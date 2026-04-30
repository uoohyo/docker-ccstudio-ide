#!/usr/bin/env node
/**
 * Merge scraped versions with manually defined versions
 * Ensures important versions (like v12) are included even if missing from web
 */

const fs = require('fs');
const path = require('path');

// Read scraped versions from stdin
let scrapedVersions = [];
let input = '';

process.stdin.on('data', (chunk) => {
  input += chunk;
});

process.stdin.on('end', () => {
  try {
    scrapedVersions = JSON.parse(input);
  } catch (e) {
    console.error('Error parsing scraped versions:', e.message);
    process.exit(1);
  }

  // Read manual versions from versions.json
  const versionsFile = path.join(__dirname, '..', 'versions.json');
  const manualVersions = JSON.parse(fs.readFileSync(versionsFile, 'utf8'));

  // Create a map of all versions (scraped + manual)
  const versionMap = new Map();

  // Add manual versions first (they have descriptions)
  for (const v of manualVersions) {
    versionMap.set(v.version, {
      version: v.version,
      major: v.major,
      minor: v.minor,
      patch: v.patch,
      build: v.build,
      description: v.description,
      source: 'manual'
    });
  }

  // Add scraped versions (newer versions might not be in manual list)
  for (const v of scrapedVersions) {
    if (!versionMap.has(v.version)) {
      versionMap.set(v.version, {
        version: v.version,
        major: v.major,
        minor: v.minor,
        patch: v.patch,
        build: v.build,
        description: `Auto-detected from web`,
        source: 'scraped'
      });
    }
  }

  // Convert to array and sort by version (newest first)
  const mergedVersions = Array.from(versionMap.values());
  mergedVersions.sort((a, b) => {
    const aVer = [a.major, a.minor, a.patch, a.build].map(Number);
    const bVer = [b.major, b.minor, b.patch, b.build].map(Number);

    for (let i = 0; i < 4; i++) {
      if (aVer[i] !== bVer[i]) return bVer[i] - aVer[i];
    }
    return 0;
  });

  // Mark latest
  if (mergedVersions.length > 0) {
    mergedVersions[0].is_latest = true;
  }

  // Remove source field before output
  const output = mergedVersions.map(v => {
    const { source, ...rest } = v;
    return rest;
  });

  console.error(`Merged ${scrapedVersions.length} scraped + ${manualVersions.length} manual versions = ${output.length} total`);
  console.log(JSON.stringify(output, null, 2));
});
