#!/usr/bin/env python3
"""List strict toolchain versions from every Docker Hub page, failing closed."""
import json
import re
import sys
from urllib.parse import urlsplit
from urllib.request import urlopen


def registry_versions(repository, parts, fetch=None):
    if not re.fullmatch(r"[a-z0-9_-]+/[a-z0-9_-]+", repository):
        raise ValueError("Invalid Docker Hub repository")
    prefix = f"https://hub.docker.com/v2/repositories/{repository}/tags"
    url = prefix + "?page_size=100"
    seen, versions = set(), set()
    pattern = re.compile(r"[0-9]+(?:\.[0-9]+){%d}" % (parts - 1))
    fetch = fetch or fetch_json
    while url:
        parsed = urlsplit(url)
        if parsed.scheme != "https" or parsed.netloc != "hub.docker.com" or parsed.path.rstrip("/") != urlsplit(prefix).path:
            raise ValueError("Unexpected pagination URL")
        if url in seen:
            raise ValueError("Pagination loop")
        seen.add(url)
        data = fetch(url)
        if not isinstance(data, dict) or not isinstance(data.get("results"), list) or "next" not in data:
            raise ValueError("Invalid tag response")
        for tag in data["results"]:
            if not isinstance(tag, dict) or not isinstance(tag.get("name"), str):
                raise ValueError("Invalid tag entry")
            if pattern.fullmatch(tag["name"]):
                versions.add(tag["name"])
        url = data["next"]
        if url is not None and (not isinstance(url, str) or not url):
            raise ValueError("Invalid next page")
    if not versions:
        raise ValueError("No published toolchain versions; refusing to update latest")
    return sorted(versions, key=lambda version: tuple(map(int, version.split("."))))


def fetch_json(url):
    with urlopen(url, timeout=30) as response:
        return json.load(response)


if __name__ == "__main__":
    try:
        print(registry_versions(sys.argv[1], int(sys.argv[2]))[-1])
    except Exception as error:
        sys.exit(f"Registry lookup failed: {error}")
