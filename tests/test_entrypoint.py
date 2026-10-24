import os
import re
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class EntrypointTests(unittest.TestCase):
    def test_install_restart_and_failure_paths(self):
        for status in (0, 7, 143):
            with self.subTest(status=status), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                # Sandbox the real entrypoint's absolute paths; no host system changes.
                source = (ROOT / "entrypoint.sh").read_text()
                source = re.sub(r"/(?:ccs_install|opt|root|tmp|home|sbin|etc|run|lib/modules|usr/local)(?=/|[\" \n])", lambda match: str(root) + match.group(), source)
                script = root / "entrypoint.sh"
                script.write_text(source)
                for folder in ("home", "tmp", "usr/local/bin"):
                    (root / folder).mkdir(parents=True, exist_ok=True)
                installer = root / "opt/ccs-installer/CCS12.7.0.00007_linux-x64/ccs_setup_12.7.0.00007.run"
                installer.parent.mkdir(parents=True)
                executable = root / "opt/ti/ccs/eclipse/eclipse"
                installer.write_text(f"#!/bin/bash\nmkdir -p '{executable.parent}'\nprintf '#!/bin/bash\\nexit 0\\n' > '{executable}'\nchmod +x '{executable}'\necho installer-log\nexit {status}\n")
                installer.chmod(0o755)
                env = dict(os.environ, MAJOR_VER="12", MINOR_VER="7", PATCH_VER="0", BUILD_VER="00007", CCS_VERSION="12.7.0.00007", COMPONENTS="PF_C28")
                result = subprocess.run(["bash", str(script), "true"], env=env, capture_output=True)
                self.assertEqual(result.returncode, status, result.stderr.decode())
                marker = root / "opt/ti/.ccs-install-complete"
                self.assertEqual(marker.exists(), status == 0)
                if status == 0:
                    self.assertFalse(installer.exists())
                    second = subprocess.run(["bash", str(script), "true"], env=env, capture_output=True)
                    self.assertEqual(second.returncode, 0, second.stderr.decode())
                    self.assertIn(b"Reusing verified", second.stdout)
                    changed = subprocess.run(["bash", str(script), "true"], env=dict(env, COMPONENTS="PF_MSP430"), capture_output=True)
                    self.assertNotEqual(changed.returncode, 0)
                    executable.unlink()
                    broken = subprocess.run(["bash", str(script), "true"], env=env, capture_output=True)
                    self.assertNotEqual(broken.returncode, 0)


if __name__ == "__main__":
    unittest.main()
