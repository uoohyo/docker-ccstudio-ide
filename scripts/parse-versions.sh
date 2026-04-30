#!/bin/bash
# Parse CCS versions from TI website or fallback to versions.json
# Returns JSON array of version objects

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSIONS_FILE="${SCRIPT_DIR}/../versions.json"
USE_SCRAPER="${USE_SCRAPER:-false}"

# Function to load from versions.json (fallback)
load_from_file() {
    echo "Loading CCS versions from versions.json..." >&2

    if [ ! -f "$VERSIONS_FILE" ]; then
        echo "Error: versions.json not found at ${VERSIONS_FILE}" >&2
        exit 1
    fi

    VERSIONS=$(cat "$VERSIONS_FILE")
    echo "$VERSIONS"
}

# Function to scrape from TI website
scrape_from_web() {
    echo "Scraping CCS versions from TI website (requires Node.js + Playwright)..." >&2

    # Check if Node.js is available
    if ! command -v node &> /dev/null; then
        echo "Warning: Node.js not found, falling back to versions.json" >&2
        load_from_file
        return
    fi

    # Install dependencies if needed
    if [ ! -d "${SCRIPT_DIR}/node_modules" ]; then
        echo "Installing Playwright..." >&2
        cd "${SCRIPT_DIR}"
        npm install --silent 2>&1 > /dev/null
        npx playwright install chromium --with-deps 2>&1 > /dev/null
    fi

    # Run scraper
    VERSIONS=$(node "${SCRIPT_DIR}/scrape-versions.js" 2>&1)

    if [ $? -ne 0 ] || [ -z "$VERSIONS" ]; then
        echo "Warning: Scraping failed, falling back to versions.json" >&2
        load_from_file
        return
    fi

    echo "$VERSIONS"
}

# Main logic
if [ "$USE_SCRAPER" = "true" ]; then
    scrape_from_web
else
    load_from_file
fi
