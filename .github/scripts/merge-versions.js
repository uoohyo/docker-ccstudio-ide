#!/usr/bin/env node
// Sort scraped versions and mark the latest

let input = '';

process.stdin.on('data', chunk => { input += chunk; });

process.stdin.on('end', () => {
  let versions;
  try {
    versions = JSON.parse(input);
  } catch (e) {
    console.error('Error parsing scraped versions:', e.message);
    process.exit(1);
  }

  versions.sort((a, b) => {
    const aVer = [a.major, a.minor, a.patch, a.build].map(Number);
    const bVer = [b.major, b.minor, b.patch, b.build].map(Number);
    for (let i = 0; i < 4; i++) {
      if (aVer[i] !== bVer[i]) return bVer[i] - aVer[i];
    }
    return 0;
  });

  if (versions.length > 0) versions[0].is_latest = true;

  console.log(JSON.stringify(versions));
});
