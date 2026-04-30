#!/bin/bash
# Scrape CCS versions from TI website
# Returns JSON array of version objects

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v node &> /dev/null; then
    echo "Error: Node.js is required for scraping CCS versions" >&2
    exit 1
fi

# No external dependencies required (uses built-in Node.js fetch)

echo "Scraping CCS versions from TI website..." >&2
if ! SCRAPED=$(node "${SCRIPT_DIR}/scrape-versions.js" 2>/dev/null) || [ -z "$SCRAPED" ]; then
    echo "Error: Failed to scrape CCS versions from TI website" >&2
    exit 1
fi

# Sort and mark latest
echo "$SCRAPED" | node "${SCRIPT_DIR}/merge-versions.js"
