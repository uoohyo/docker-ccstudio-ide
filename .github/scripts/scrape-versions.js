#!/usr/bin/env node
/**
 * Scrape CCS versions from TI download page using Playwright
 * Handles JavaScript-rendered content and interactive elements
 */

const { chromium } = require('playwright');

const TI_URL = 'https://www.ti.com/tool/download/CCSTUDIO';

async function scrapeVersions() {
  console.error('Launching headless browser...');
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage();

  console.error(`Navigating to ${TI_URL}...`);
  await page.goto(TI_URL, { waitUntil: 'networkidle', timeout: 30000 });

  // Handle cookie consent if present
  try {
    const cookieButton = page.locator('button:has-text("Accept"), button:has-text("Agree"), button:has-text("OK")').first();
    if (await cookieButton.count() > 0) {
      console.error('Accepting cookies...');
      await cookieButton.click({ timeout: 5000 });
      await page.waitForTimeout(1000);
    }
  } catch (e) {
    // No cookie dialog, continue
  }

  // Wait for page to fully load
  await page.waitForTimeout(5000);

  // Scroll to make version selector visible
  console.error('Scrolling to version selector...');
  await page.evaluate(() => {
    const selector = document.querySelector('input[placeholder*="version" i], input[placeholder*="filter" i]');
    if (selector) {
      selector.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }
  });
  await page.waitForTimeout(2000);

  console.error('Looking for ti-filter-list element...');

  let versionList = [];

  // Strategy 1: Extract from ti-filter-list items attribute (most reliable)
  try {
    console.error('Strategy 1: Parsing ti-filter-list items attribute...');

    const filterList = page.locator('ti-filter-list').first();
    if (await filterList.count() > 0) {
      const itemsAttr = await filterList.getAttribute('items');
      if (itemsAttr) {
        console.error('Found items attribute, parsing JSON...');
        const items = JSON.parse(itemsAttr);

        // Parse version groups
        for (const group of items) {
          if (group.children && Array.isArray(group.children)) {
            for (const item of group.children) {
              // Extract version from value (e.g., "CCSTUDIO/20.5.0" or "CCSTUDIO/11.2.0.00007")
              const valueMatch = item.value.match(/CCSTUDIO\/(\d+\.\d+\.\d+(?:\.\d+)?)/);
              if (valueMatch) {
                const versionStr = valueMatch[1];
                const parts = versionStr.split('.');

                // Ensure 4-part version (add .0 if needed for v12 and below)
                const major = parts[0];
                const minor = parts[1] || '0';
                const patch = parts[2] || '0';
                const build = parts[3] || '0';

                versionList.push({
                  version: `${major}.${minor}.${patch}.${build}`,
                  major,
                  minor,
                  patch,
                  build
                });
              }
            }
          }
        }

        console.error(`Extracted ${versionList.length} versions from ti-filter-list`);
      }
    }
  } catch (e) {
    console.error(`Strategy 1 error: ${e.message}`);
  }

  // Strategy 2: Always scan page content for full 4-part versions.
  // This augments Strategy 1 when v20+ filter-list items only expose a 3-part path
  // (e.g. "CCSTUDIO/20.5.0") and the real build number lives in download URLs.
  try {
    console.error('Strategy 2: Scanning page content for 4-part version numbers...');
    const pageContent = await page.content();
    const versionMatches = pageContent.matchAll(/(\d+)\.(\d+)\.(\d+)\.(\d+)/g);

    for (const match of versionMatches) {
      const major = parseInt(match[1]);
      if (major >= 7 && major <= 30) {
        versionList.push({
          version: `${match[1]}.${match[2]}.${match[3]}.${match[4]}`,
          major: match[1],
          minor: match[2],
          patch: match[3],
          build: match[4]
        });
      }
    }
  } catch (e) {
    console.error(`Strategy 2 error: ${e.message}`);
  }

  await browser.close();

  // Deduplicate by major.minor.patch, preferring entries with a real build number
  // over placeholder '0' added when the filter list only exposed a 3-part path.
  const versionMap = new Map();
  for (const v of versionList) {
    const key = `${v.major}.${v.minor}.${v.patch}`;
    const existing = versionMap.get(key);
    if (!existing || (existing.build === '0' && v.build !== '0')) {
      versionMap.set(key, v);
    }
  }
  const uniqueVersions = Array.from(versionMap.values());

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

  if (uniqueVersions.length > 0) {
    console.error('Versions:', uniqueVersions.map(v => v.version).join(', '));
  }

  // Output JSON
  console.log(JSON.stringify(uniqueVersions, null, 2));
}

scrapeVersions().catch(error => {
  console.error('Error scraping versions:', error);
  process.exit(1);
});
