import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("latest", ROOT / ".github/scripts/select-latest.py")
latest = importlib.util.module_from_spec(spec)
spec.loader.exec_module(latest)


class ReceiptTests(unittest.TestCase):
    def receipt(self, version):
        return {"image": "test/image:" + version, "repository_digest": "test/image@sha256:" + "a" * 64,
                "image_id": "sha256:" + "b" * 64, "source_revision": "revision"}

    def test_unverified_higher_push_never_promoted(self):
        with self.assertRaises(ValueError):
            latest.select_latest("test/image", ["1.0.0", "2.0.0"], {"1.0.0", "2.0.0"}, [self.receipt("1.0.0")], "revision")

    def test_verified_current_version_is_digest_pinned(self):
        result = latest.select_latest("test/image", ["1.0.0"], {"1.0.0"}, [self.receipt("1.0.0")], "revision")
        self.assertEqual(result, "test/image@sha256:" + "a" * 64)

    def test_older_rebuild_does_not_downgrade_latest(self):
        self.assertEqual(latest.select_latest("test/image", ["1.0.0", "2.0.0"], {"1.0.0"}, [self.receipt("1.0.0")], "revision"), "test/image:2.0.0")

    def test_wrong_revision_fails(self):
        with self.assertRaises(ValueError):
            latest.select_latest("test/image", ["1.0.0"], {"1.0.0"}, [self.receipt("1.0.0")], "other")
