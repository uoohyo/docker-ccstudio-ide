import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("registry", ROOT / ".github/scripts/registry-tags.py")
registry = importlib.util.module_from_spec(spec)
spec.loader.exec_module(registry)


class RegistryTests(unittest.TestCase):
    def test_pagination_and_numeric_order(self):
        pages = [{"results": [{"name": f"1.{n}.0"} for n in range(100)],
                  "next": "https://hub.docker.com/v2/repositories/test/image/tags?page=2"},
                 {"results": [{"name": "1.100.0"}, {"name": "latest"}], "next": None}]
        self.assertEqual(registry.registry_versions("test/image", 3, lambda _: pages.pop(0))[-1], "1.100.0")

    def test_fail_closed(self):
        for payload in ({}, {"results": [], "next": None}, {"results": [], "next": "https://evil.example/tags"}):
            with self.subTest(payload=payload), self.assertRaises(ValueError):
                registry.registry_versions("test/image", 3, lambda _: payload)
        with self.assertRaises(OSError):
            registry.registry_versions("test/image", 3, lambda _: (_ for _ in ()).throw(OSError("HTTP failure")))

    def test_ccs_full_versions_only(self):
        data = {"results": [{"name": n} for n in ["21.0.1.00010", "21.0.1.00009", "21.0.1", "21.0.1.00011-r2"]], "next": None}
        self.assertEqual(registry.registry_versions("test/image", 4, lambda _: data)[-1], "21.0.1.00010")


class PublishTests(unittest.TestCase):
    def test_publish_identity_and_failure(self):
        for mismatch in (False, True):
            with self.subTest(mismatch=mismatch), tempfile.TemporaryDirectory() as temp:
                tmp = Path(temp)
                docker = tmp / "docker"
                docker.write_text("""#!/bin/bash
if [ "$1" = image ]; then
  if [[ "$*" == *RepoDigests* ]]; then echo '["test/image@sha256:manifest"]';
  elif [[ "$*" == *@sha256:* && "${MISMATCH:-}" == true ]]; then echo sha256:other;
  else echo sha256:tested; fi
elif [ "$1" = buildx ]; then printf '{"digest":"sha256:%064d"}\\n' 2
elif [ "$1" = push ] || [ "$1" = pull ]; then :
else exit 99; fi
""")
                docker.chmod(0o755)
                receipt = tmp / "receipt.json"
                env = dict(os.environ, PATH=str(tmp) + ":" + os.environ["PATH"], MISMATCH=str(mismatch).lower())
                result = subprocess.run(["bash", str(ROOT / ".github/scripts/publish-tested-image.sh"), "test/image:1.0.0", str(receipt)], env=env, capture_output=True)
                self.assertEqual(result.returncode == 0, not mismatch, result.stderr.decode())
                self.assertEqual(receipt.exists(), not mismatch)

    def test_overwrite_requires_old_digest_and_retains_rollback(self):
        for valid in (False, True):
            with self.subTest(valid=valid), tempfile.TemporaryDirectory() as temp:
                tmp = Path(temp)
                docker = tmp / "docker"
                docker.write_text("""#!/bin/bash
if [ "$1" = buildx ]; then
  [ "$VALID" = True ] || exit 7
  printf '{"digest":"sha256:%064d"}\\n' 1
elif [ "$1" = image ]; then
  if [[ "$*" == *RepoDigests* ]]; then echo '["test/image@sha256:manifest"]'; else echo sha256:tested; fi
elif [ "$1" = push ]; then touch pushed
elif [ "$1" = pull ]; then :
else exit 99; fi
""")
                docker.chmod(0o755)
                env = dict(os.environ, PATH=str(tmp) + ":" + os.environ["PATH"], REQUIRE_EXISTING_IMAGE="true", VALID=str(valid))
                prepared = subprocess.run(["bash", str(ROOT / ".github/scripts/prepare-image-rollback.sh"), "test/image:1.0.0", str(tmp / "receipt.json")], cwd=tmp, env=env, capture_output=True)
                self.assertEqual(prepared.returncode == 0, valid, prepared.stderr.decode())
                result = subprocess.run(["bash", str(ROOT / ".github/scripts/publish-tested-image.sh"), "test/image:1.0.0", str(tmp / "receipt.json")], cwd=tmp, env=env, capture_output=True)
                self.assertEqual(result.returncode == 0, valid, result.stderr.decode())
                self.assertEqual((tmp / "pushed").exists(), valid)
                self.assertEqual((tmp / "rollback/receipt.json").exists(), valid)


class WorkflowTests(unittest.TestCase):
    def test_publish_is_per_version_and_never_rebuilds(self):
        text = (ROOT / ".github/workflows/build-all-versions.yml").read_text()
        self.assertNotIn("\n  push:\n    needs:", text)
        self.assertNotIn("docker buildx build", text)
        self.assertIn("Publish the tested image", text)
        self.assertIn("always() && !cancelled()", text)
        self.assertNotIn('BUILT_VERSION=', text)
        self.assertIn("push_to_registry == 'true'", text)
        self.assertNotIn("  push:\n", text.split("jobs:")[0])
        self.assertIn("org.opencontainers.image.revision", text)
        self.assertIn("existing_versions_only", text)
        self.assertIn("($tags | index($v)) != null", text)
        self.assertIn("Persist rollback metadata before overwriting", text)
        self.assertLess(text.index("Persist rollback metadata before overwriting"), text.index("Publish the tested image"))


if __name__ == "__main__":
    unittest.main()
