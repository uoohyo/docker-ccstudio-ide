#!/usr/bin/env node
/**
 * Scrape CCS versions from TI download page using Playwright
 * Handles JavaScript-rendered content
 */

const { chromium } = require('playwright');

const TI_URL = 'https://www.ti.com/tool/download/CCSTUDIO';

async function scrapeVersions() {
  console.error('Launching headless browser...');
  const browser = await chromium.launch();
  const page = await browser.newPage();

  console.error(`Navigating to ${TI_URL}...`);
  await page.goto(TI_URL, { waitUntil: 'networkidle' });

  // Wait for version selector to load
  console.error('Waiting for version selector...');
  await page.waitForSelector('[data-testid="version-selector"]', { timeout: 10000 })
    .catch(() => page.waitForSelector('.version-select', { timeout: 10000 }))
    .catch(() => console.error('Version selector not found, proceeding anyway...'));

  // Extract version list
  console.error('Extracting versions...');
  const versions = await page.evaluate(() => {
    const versionElements = Array.from(document.querySelectorAll('[data-version], .version-item, option[value*="."]'));

    return versionElements
      .map(el => {
        // Try different attributes/text content
        const text = el.getAttribute('data-version') ||
                     el.getAttribute('value') ||
                     el.textContent.trim();

        // Match version pattern: X.X.X.XXXXX
        const match = text.match(/(\d+)\.(\d+)\.(\d+)\.(\d+)/);
        if (match) {
          return {
            version: `${match[1]}.${match[2]}.${match[3]}.${match[4]}`,
            major: match[1],
            minor: match[2],
            patch: match[3],
            build: match[4]
          };
        }
        return null;
      })
      .filter(v => v !== null);
  });

  // Also try to extract from links
  const linkVersions = await page.evaluate(() => {
    const links = Array.from(document.querySelectorAll('a[href*="CCS"]'));

    return links
      .map(link => {
        const href = link.href;
        const match = href.match(/CCS_?(\d+)\.(\d+)\.(\d+)\.(\d+)/);
        if (match) {
          return {
            version: `${match[1]}.${match[2]}.${match[3]}.${match[4]}`,
            major: match[1],
            minor: match[2],
            patch: match[3],
            build: match[4]
          };
        }
        return null;
      })
      .filter(v => v !== null);
  });

  await browser.close();

  // Combine and deduplicate
  const allVersions = [...versions, ...linkVersions];
  const uniqueVersions = Array.from(
    new Map(allVersions.map(v => [v.version, v])).values()
  );

  // Sort by version (newest first)
  uniqueVersions.sort((a, b) => {
    const aVer = [a.major, a.minor, a.patch, a.build].map(Number);
    const bVer = [b.major, b.minor, b.patch, b.build].map(Number);

    for (let i = 0; i < 4; i++) {
      if (aVer[i] !== bVer[i]) return bVer[i] - aVer[i];
    }
    return 0;
  });

  // Mark latest
  if (uniqueVersions.length > 0) {
    uniqueVersions[0].is_latest = true;
  }

  console.error(`Found ${uniqueVersions.length} unique versions`);

  // Output JSON
  console.log(JSON.stringify(uniqueVersions, null, 2));
}

scrapeVersions().catch(error => {
  console.error('Error scraping versions:', error);
  process.exit(1);
});
