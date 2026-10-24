"""Offline contracts for the real same-container lifecycle smoke test."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / '.github/scripts/smoke-ccs-lifecycle.sh'
MOCK = '''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
state = Path(os.environ['MOCK_STATE'])
data = json.loads(state.read_text()) if state.exists() else {'starts':0, 'calls':[]}
args = sys.argv[1:]
data['calls'].append(args)
mode = os.environ.get('MOCK_MODE', '')
command = args[0]
if command == 'create':
    print('same-container-id')
elif command == 'start':
    assert args[1] == 'same-container-id'
    data['starts'] += 1
elif command == 'wait':
    assert args[1] == 'same-container-id'
    print('42' if mode == 'first-failure' or (mode == 'restart-failure' and data['starts'] == 2) else '0')
elif command == 'inspect':
    print('exited')
elif command == 'logs':
    print('=== CCS 21.0.1.00010 is ready. ===')
    if data['starts'] == 2:
        if mode == 'reinstall': print('=== CCS 21.0.1.00010 is ready. ===')
        if mode != 'no-reuse': print('>>> Reusing verified CCS 21.0.1.00010 installation.')
elif command == 'cp':
    assert args[1].startswith('same-container-id:')
    value = '21.0.1.00010\\nPF_C28\\n'
    if mode == 'changed-marker' and data['starts'] == 2: value = 'changed\\n'
    Path(args[2]).write_text(value)
elif command == 'rm':
    assert args[1:] == ['-f', 'same-container-id']
else:
    raise AssertionError(args)
state.write_text(json.dumps(data))
'''


class LifecycleTests(unittest.TestCase):
    def run_mock(self, mode=''):
        with tempfile.TemporaryDirectory() as temp:
            work = Path(temp)
            docker = work / 'docker'
            docker.write_text(MOCK)
            docker.chmod(0o755)
            state = work / 'state.json'
            env = dict(os.environ, PATH=f"{work}:{os.environ['PATH']}", MOCK_STATE=str(state), MOCK_MODE=mode)
            result = subprocess.run(['bash', str(SCRIPT), 'uoohyo/ccstudio-ide:21.0.1.00010', '21.0.1.00010', '21'], env=env, capture_output=True, text=True)
            return result, json.loads(state.read_text())

    def test_first_install_and_restart_use_one_container_then_cleanup(self):
        result, state = self.run_mock()
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = state['calls']
        self.assertEqual(sum(call[0] == 'create' for call in calls), 1)
        self.assertEqual(sum(call[0] == 'start' for call in calls), 2)
        self.assertEqual(calls[-1], ['rm', '-f', 'same-container-id'])
        create = calls[0]
        self.assertNotIn('--rm', create)
        self.assertIn('--name', create)
        self.assertIn('COMPONENTS=PF_C28', create)
        self.assertEqual(create[create.index('bash'):create.index('bash')+4], ['bash', '-euo', 'pipefail', '-c'])
        self.assertIn('PASS:', result.stdout)

    def test_failure_reinstall_and_marker_change_never_pass(self):
        for mode in ['first-failure', 'restart-failure', 'reinstall', 'no-reuse', 'changed-marker']:
            with self.subTest(mode=mode):
                result, state = self.run_mock(mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('PASS:', result.stdout)
                self.assertEqual(state['calls'][-1], ['rm', '-f', 'same-container-id'])

    def test_payload_checks_cli_exit_even_with_success_text(self):
        source = SCRIPT.read_text()
        payload = source.split("cat <<'VALIDATION'\n", 1)[1].split('\nVALIDATION', 1)[0]
        for major in [8, 12, 21]:
            for exit_code in [0, 7]:
                with self.subTest(major=major, exit_code=exit_code), tempfile.TemporaryDirectory() as temp:
                    work = Path(temp)
                    ti = work / 'ti'
                    eclipse = ti / ('ccs' if major >= 9 else f'ccsv{major}') / 'eclipse'
                    eclipse.mkdir(parents=True)
                    version = f'{major}.0.0.00001'
                    (ti / '.ccs-install-complete').write_text(version+'\nPF_C28\n')
                    executable = eclipse / ('ccs-server-cli.sh' if major >= 20 else 'eclipse')
                    executable.write_text(f"#!/bin/bash\necho 'Usage: Eclipse'\nexit {exit_code}\n")
                    executable.chmod(0o755)
                    script = payload.replace('/opt/ti', str(ti)).replace('/opt/ccs-installer', str(work / 'removed-installer')).replace('/tmp/ccs_verify', str(work / 'verify'))
                    result = subprocess.run(['bash', '-euo', 'pipefail', '-c', script, '--', version, str(major), 'PF_C28'], capture_output=True, text=True)
                    self.assertEqual(result.returncode, exit_code)

    def test_workflow_calls_lifecycle_before_publication(self):
        workflow = (ROOT / '.github/workflows/build-all-versions.yml').read_text()
        self.assertIn('bash .github/scripts/smoke-ccs-lifecycle.sh', workflow)
        self.assertLess(workflow.index('bash .github/scripts/smoke-ccs-lifecycle.sh'), workflow.index('- name: Log in to Docker Hub'))
        self.assertNotIn('sleep infinity', workflow)


if __name__ == '__main__':
    unittest.main()
