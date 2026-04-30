#!/bin/bash
# Scrape CCS versions from TI website
# Returns JSON array of version objects

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v node &> /dev/null; then
    echo "Error: Node.js is required for scraping CCS versions" >&2
    exit 1
fi

# Install dependencies if needed
if [ ! -d "${SCRIPT_DIR}/node_modules" ]; then
    echo "Installing dependencies..." >&2
    cd "${SCRIPT_DIR}"
    npm install --silent > /dev/null 2>&1
    npx playwright install chromium --with-deps > /dev/null 2>&1
fi

echo "Scraping CCS versions from TI website..." >&2
if ! SCRAPED=$(node "${SCRIPT_DIR}/scrape-versions.js" 2>/dev/null) || [ -z "$SCRAPED" ]; then
    echo "Error: Failed to scrape CCS versions from TI website" >&2
    exit 1
fi

# Sort and mark latest
echo "$SCRAPED" | node "${SCRIPT_DIR}/merge-versions.js"
