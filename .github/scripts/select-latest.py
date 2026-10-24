#!/usr/bin/env python3
"""Select latest without promoting an attempted but unverified publication."""
import importlib.util
import json
import os
from pathlib import Path
import re
import sys

spec = importlib.util.spec_from_file_location("registry_tags", Path(__file__).with_name("registry-tags.py"))
registry = importlib.util.module_from_spec(spec)
spec.loader.exec_module(registry)


def select_latest(repository, versions, attempted, receipts, revision):
    if not receipts:
        raise ValueError("No verified publications")
    published = {}
    for receipt in receipts:
        image, digest, image_id = (receipt.get(key, "") for key in ("image", "repository_digest", "image_id"))
        if receipt.get("source_revision") != revision or not image.startswith(repository + ":"):
            raise ValueError("Publication receipt revision/repository mismatch")
        if not re.fullmatch(re.escape(repository) + r"@sha256:[0-9a-f]{64}", digest):
            raise ValueError("Invalid published digest")
        if not re.fullmatch(r"sha256:[0-9a-f]{64}", image_id):
            raise ValueError("Invalid image ID")
        version = image[len(repository) + 1:]
        if version not in attempted or version in published:
            raise ValueError("Unexpected/duplicate publication receipt")
        published[version] = digest
    latest = versions[-1]
    if latest in attempted and latest not in published:
        raise ValueError("Highest registry version was attempted but not verified; latest unchanged")
    return published.get(latest, repository + ":" + latest)


if __name__ == "__main__":
    try:
        repository, parts, directory = sys.argv[1:]
        versions = registry.registry_versions(repository, int(parts))
        attempted = {item["version"] for item in json.loads(os.environ["ATTEMPTED_VERSIONS"])}
        receipts = [json.loads(path.read_text()) for path in Path(directory).glob("*.json")]
        print(select_latest(repository, versions, attempted, receipts, os.environ["EXPECTED_REVISION"]))
    except Exception as error:
        sys.exit(f"Latest selection failed: {error}")
