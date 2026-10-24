"""Registry eventual consistency must not change which pushed image is verified."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
OLD = 'sha256:' + '1' * 64
NEW = 'sha256:' + '2' * 64
OTHER = 'sha256:' + '3' * 64
TESTED = 'sha256:' + '4' * 64
MOCK = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
path = Path(os.environ['MOCK_STATE'])
state = json.loads(path.read_text())
args = sys.argv[1:]
state['calls'].append(args)
mode = state['mode']
old, new, other, tested = ['sha256:' + c * 64 for c in '1234']
code = 0
if args[:2] == ['image', 'inspect']:
    print(other if '@' in args[-1] and mode == 'pull-mismatch' else tested)
elif args[0] == 'push':
    state['pushes'] += 1
    fail = mode == 'push-fail' or (mode == 'retry' and state['pushes'] < 3)
    summary = args[-1].rsplit(':', 1)[-1] + ': digest: ' + (old if fail else new) + ' size: 1234'
    if fail:
        print(summary)
        print('push transport failure', file=sys.stderr)
        code = 9
    elif mode == 'missing':
        print('layers already exist')
    elif mode == 'malformed':
        print(summary.replace(new, 'sha256:invalid'))
    elif mode == 'wrong-tag':
        print('different-tag: digest: ' + new + ' size: 1234')
    elif mode == 'duplicate':
        print(summary + '\n' + summary)
    else:
        print(summary, file=sys.stderr if mode == 'stderr' else sys.stdout)
elif args[0] == 'pull':
    if mode == 'pull-fail': code = 7
elif args[0] == 'buildx':
    if state['pushes'] == 0:
        print(json.dumps({'digest': other if mode == 'guard-changed' else old}))
    else:
        state['post_inspects'] += 1
        if mode == 'tag-api-fail':
            code = 7
        elif mode == 'tag-malformed':
            print('{}')
        else:
            stale = mode == 'stale-forever' or (mode == 'stale-then-new' and state['post_inspects'] < 3)
            print(json.dumps({'digest': old if stale else (other if mode == 'unrelated' else new)}))
else:
    raise AssertionError(args)
path.write_text(json.dumps(state))
sys.exit(code)
'''


class PushDigestTests(unittest.TestCase):
    def run_publish(self, mode='success', require_existing=True, image='test/image:1.0.0', tee_failure=False):
        with tempfile.TemporaryDirectory() as temporary:
            work = Path(temporary)
            state_path = work / 'state.json'
            state_path.write_text(json.dumps({'mode': mode, 'calls': [], 'pushes': 0, 'post_inspects': 0}))
            (work / 'docker').write_text(MOCK)
            (work / 'docker').chmod(0o755)
            (work / 'sleep').write_text('#!/bin/sh\nexit 0\n')
            (work / 'sleep').chmod(0o755)
            if tee_failure:
                (work / 'tee').write_text('#!/bin/sh\ncat >/dev/null\nexit 1\n')
                (work / 'tee').chmod(0o755)
            receipt = work / 'receipt.json'
            (work / 'rollback').mkdir()
            ledger = {'image': image, 'proposed_image_id': TESTED, 'previous_repository_digest': image.rsplit(':', 1)[0]+'@'+OLD}
            (work / 'rollback/receipt.json').write_text(json.dumps(ledger))
            env = dict(os.environ, PATH=f"{work}:{os.environ['PATH']}", MOCK_STATE=str(state_path), REQUIRE_EXISTING_IMAGE=str(require_existing).lower(), GITHUB_SHA='fixture-revision')
            result = subprocess.run(['bash', str(ROOT / '.github/scripts/publish-tested-image.sh'), image, str(receipt)], cwd=work, env=env, capture_output=True, text=True)
            state = json.loads(state_path.read_text())
            return result, state, json.loads(receipt.read_text()) if receipt.exists() else None

    def test_push_digest_is_authoritative_while_old_tag_converges(self):
        result, state, receipt = self.run_publish('stale-then-new')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(state['pushes'], 1)
        self.assertEqual(state['post_inspects'], 3)
        self.assertEqual([c for c in state['calls'] if c[0] == 'pull'], [['pull', 'test/image@'+NEW]])
        self.assertEqual(receipt['repository_digest'], 'test/image@'+NEW)
        self.assertEqual(receipt['previous_digest'], OLD)

    def test_success_summary_can_be_on_stderr_and_host_can_have_port(self):
        result, state, receipt = self.run_publish('stderr', image='registry.example:5000/team/image:1.0.0')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(receipt['repository_digest'], 'registry.example:5000/team/image@'+NEW)
        self.assertIn('digest: '+NEW, result.stdout)

    def test_failed_push_retries_but_uses_only_successful_attempt_summary(self):
        result, state, receipt = self.run_publish('retry')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(state['pushes'], 3)
        self.assertEqual(receipt['repository_digest'], 'test/image@'+NEW)
        self.assertIn('push transport failure', result.stdout)

    def test_all_failed_pushes_do_not_pull_or_create_receipt(self):
        result, state, receipt = self.run_publish('push-fail')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(state['pushes'], 3)
        self.assertFalse(any(c[0] == 'pull' for c in state['calls']))
        self.assertIsNone(receipt)

    def test_invalid_summary_never_queries_or_pulls_an_unverified_digest(self):
        for mode in ['missing', 'malformed', 'duplicate', 'wrong-tag']:
            with self.subTest(mode=mode):
                result, state, receipt = self.run_publish(mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(state['pushes'], 1)
                self.assertEqual(state['post_inspects'], 0)
                self.assertFalse(any(c[0] == 'pull' for c in state['calls']))
                self.assertIsNone(receipt)

    def test_verification_failure_never_repushes_or_writes_receipt(self):
        for mode in ['unrelated', 'stale-forever', 'pull-mismatch', 'pull-fail', 'tag-api-fail', 'tag-malformed']:
            with self.subTest(mode=mode):
                result, state, receipt = self.run_publish(mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(state['pushes'], 1)
                self.assertIsNone(receipt)
                if mode == 'stale-forever':
                    self.assertEqual(state['post_inspects'], 6)
                elif mode == 'unrelated':
                    self.assertEqual(state['post_inspects'], 1)

    def test_tee_failure_after_successful_push_does_not_repush(self):
        result, state, receipt = self.run_publish(tee_failure=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(state['pushes'], 1)
        self.assertIsNone(receipt)
        self.assertIn('Push succeeded', result.stderr)

    def test_pre_push_rollback_guard_still_rejects_changed_release(self):
        result, state, receipt = self.run_publish('guard-changed')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(state['pushes'], 0)
        self.assertIsNone(receipt)

    def test_new_tag_requires_exact_convergence_without_unknown_stale_allowance(self):
        result, state, receipt = self.run_publish(require_existing=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(receipt['previous_digest'], '')
        result, state, receipt = self.run_publish('stale-then-new', require_existing=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(state['post_inspects'], 1)
        self.assertIsNone(receipt)


if __name__ == '__main__':
    unittest.main()
