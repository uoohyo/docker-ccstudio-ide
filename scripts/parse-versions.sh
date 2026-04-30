#!/bin/bash
# Parse CCS versions from TI download page
# Returns JSON array of version objects

set -euo pipefail

# Fetch TI download page and extract version
TI_URL="https://www.ti.com/tool/download/CCSTUDIO"

echo "Fetching CCS versions from ${TI_URL}..." >&2

# Extract version from download links
# Pattern: CCS_MAJOR.MINOR.PATCH.BUILD_platform.ext
VERSION=$(curl -s "${TI_URL}" | \
    grep -o 'CCS_[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+' | \
    sed 's/CCS_//' | \
    head -1)

if [ -z "$VERSION" ]; then
    echo "Error: Failed to parse CCS version" >&2
    exit 1
fi

echo "Latest version: ${VERSION}" >&2

# Parse version components
IFS='.' read -r MAJOR MINOR PATCH BUILD <<< "$VERSION"

# Output JSON array with version objects
# For now, we'll build specific supported versions
# In the future, this can be expanded to scrape multiple versions
cat << EOF
[
  {
    "version": "${VERSION}",
    "major": "${MAJOR}",
    "minor": "${MINOR}",
    "patch": "${PATCH}",
    "build": "${BUILD}",
    "is_latest": true
  }
]
EOF
