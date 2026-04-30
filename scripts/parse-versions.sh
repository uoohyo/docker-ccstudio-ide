#!/bin/bash
# Parse CCS versions from versions.json
# Returns JSON array of version objects

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSIONS_FILE="${SCRIPT_DIR}/../versions.json"

# Check if versions.json exists
if [ ! -f "$VERSIONS_FILE" ]; then
    echo "Error: versions.json not found at ${VERSIONS_FILE}" >&2
    exit 1
fi

echo "Loading supported CCS versions from versions.json..." >&2

# Read and output versions.json
VERSIONS=$(cat "$VERSIONS_FILE")

# Count versions
COUNT=$(echo "$VERSIONS" | jq '. | length')
echo "Found ${COUNT} supported versions:" >&2
echo "$VERSIONS" | jq -r '.[] | "  - \(.version) (\(.description))"' >&2

# Output JSON
echo "$VERSIONS"
