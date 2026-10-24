"""Offline acceptance tests: recovery cannot publish or execute an image."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / '.github/scripts/verify-ccs-12-1-recovery.sh'
VERSION = '12.1.0.00007'
SHA = 'f9e499f1901fef71cc4590f2d8ffed485fd7acc2'
OLD = 'sha256:fc22534fd50281274ce8c52d9a5efa3737bb93507ab668356c370e9651f5f729'
NEW = 'sha256:4de950059c533d47000cf98a480744da270398a4127af6cdc668a44abfbdb7fe'
TESTED = 'sha256:26f6da4c102ceb503bc4ddbb51ab974caa2f7e1cd32d89eeb3b36e7350322027'
IMAGE = f'uoohyo/ccstudio-ide:{VERSION}'


class RecoveryTests(unittest.TestCase):
    def run_case(self, mode='success', corrupt=None):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            rollback = root / 'original-rollback'
            rollback.mkdir()
            files = {
                'original-run.json': {'id': 40126099529, 'head_sha': SHA,
                    'repository': {'full_name': 'uoohyo/docker-ccstudio-ide'},
                    'head_repository': {'full_name': 'uoohyo/docker-ccstudio-ide'},
                    'path': '.github/workflows/build-all-versions.yml',
                    'event': 'workflow_dispatch', 'status': 'completed'},
                'original-artifact.json': {'id': 12573379312, 'name': f'rollback-{VERSION}',
                    'expired': False, 'workflow_run': {'id': 40126099529, 'head_sha': SHA}},
                f'original-rollback/{VERSION}.json': {'image': IMAGE,
                    'source_revision': SHA, 'proposed_image_id': TESTED,
                    'previous_repository_digest': f'uoohyo/ccstudio-ide@{OLD}'},
                f'original-rollback/{VERSION}.manifest.json': {'digest': OLD},
                f'original-rollback/{VERSION}.raw-manifest.json': {'schemaVersion': 2},
            }
            if corrupt:
                filename, key, value = corrupt
                files[filename][key] = value
            for name, value in files.items():
                (root / name).write_text(json.dumps(value))
            bin_dir = root / 'bin'
            bin_dir.mkdir()
            docker = bin_dir / 'docker'
            docker.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args=sys.argv[1:]
with open('calls.jsonl','a') as f: f.write(json.dumps(args)+'\\n')
mode=os.environ['MODE']
if args[0]=='pull':
    assert args == ['pull', 'uoohyo/ccstudio-ide@'+os.environ['NEW']]
    sys.exit(1 if mode=='pullfail' else 0)
if args[:2]==['image','inspect']:
    assert args[-1]=='uoohyo/ccstudio-ide@'+os.environ['NEW']
    print('sha256:'+'0'*64 if mode=='idfail' else os.environ['TESTED'])
elif args[:3]==['buildx','imagetools','inspect']:
    assert args[3]==os.environ['IMAGE']
    p=Path('count'); n=int(p.read_text())+1 if p.exists() else 1; p.write_text(str(n))
    if mode=='api': sys.exit(2)
    digest = os.environ['NEW']
    if mode=='stale' or (mode=='success' and n<3): digest=os.environ['OLD']
    if mode=='unrelated': digest='sha256:'+'0'*64
    if mode=='malformed': digest='bad'
    print(json.dumps({'digest':digest}))
else:
    raise AssertionError('Forbidden Docker operation: '+str(args))
''')
            docker.chmod(0o755)
            (bin_dir / 'sleep').write_text('#!/bin/sh\nexit 0\n')
            (bin_dir / 'sleep').chmod(0o755)
            env = dict(os.environ, PATH=str(bin_dir)+':'+os.environ['PATH'], MODE=mode,
                       NEW=NEW, OLD=OLD, TESTED=TESTED, IMAGE=IMAGE,
                       GITHUB_REPOSITORY='uoohyo/docker-ccstudio-ide', GITHUB_SHA='a'*40,
                       GITHUB_RUN_ID='99999999999', GITHUB_RUN_ATTEMPT='1')
            result = subprocess.run(['bash', str(SCRIPT)], cwd=root, env=env,
                                    capture_output=True, text=True)
            calls = [json.loads(s) for s in (root/'calls.jsonl').read_text().splitlines()] if (root/'calls.jsonl').exists() else []
            receipt_path = root / f'recovery/{VERSION}.json'
            receipt = json.loads(receipt_path.read_text()) if receipt_path.exists() else None
            if receipt:
                for name in files:
                    self.assertEqual((root/name).read_bytes(), (root/'recovery'/name).read_bytes())
            return result, calls, receipt

    def test_readonly_success_preserves_provenance(self):
        result, calls, receipt = self.run_case()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(receipt['source_revision'], SHA)
        self.assertEqual(receipt['validation_code_revision'], 'a'*40)
        self.assertEqual(receipt['original_run_id'], '40126099529')
        self.assertEqual(receipt['validation_run_id'], '99999999999')
        self.assertEqual(receipt['repository_digest'], f'uoohyo/ccstudio-ide@{NEW}')
        self.assertEqual([c[0] for c in calls], ['pull', 'image', 'buildx', 'buildx', 'buildx'])

    def test_verification_failures_never_make_receipt_or_mutate(self):
        for mode in ['pullfail', 'idfail', 'stale', 'unrelated', 'api', 'malformed']:
            with self.subTest(mode=mode):
                result, calls, receipt = self.run_case(mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertIsNone(receipt)
                self.assertTrue(all(c[0] in ['pull', 'image', 'buildx'] for c in calls))
                if mode == 'stale':
                    self.assertEqual(sum(c[0]=='buildx' for c in calls), 6)

    def test_bad_original_evidence_fails_before_docker(self):
        cases = [('original-run.json', 'id', 123), ('original-run.json', 'head_sha', 'b'*40),
                 ('original-run.json', 'path', '.github/workflows/other.yml'),
                 ('original-artifact.json', 'id', 123), ('original-artifact.json', 'expired', True),
                 ('original-artifact.json', 'workflow_run', {'id':123, 'head_sha':SHA}),
                 (f'original-rollback/{VERSION}.json', 'proposed_image_id', 'sha256:'+'0'*64),
                 (f'original-rollback/{VERSION}.json', 'image', 'attacker/repo:1'),
                 (f'original-rollback/{VERSION}.json', 'source_revision', 'b'*40),
                 (f'original-rollback/{VERSION}.json', 'previous_repository_digest', 'uoohyo/ccstudio-ide@'+NEW)]
        for case in cases:
            with self.subTest(case=case):
                result, calls, receipt = self.run_case(corrupt=case)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(calls, [])
                self.assertIsNone(receipt)

    def test_workflow_is_fixed_scope_readonly(self):
        workflow = (ROOT/'.github/workflows/verify-ccs-12-1-recovery.yml').read_text()
        self.assertIn('actions: read', workflow)
        self.assertIn("artifact-ids: '12573379312'", workflow)
        self.assertIn("run-id: '40126099529'", workflow)
        self.assertNotIn('inputs:', workflow)
        for forbidden in ['docker/login', 'docker push', 'docker build', 'docker tag', 'secrets.DOCKER', ': write']:
            self.assertNotIn(forbidden, workflow)
