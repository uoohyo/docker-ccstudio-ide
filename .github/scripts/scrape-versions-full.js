#!/usr/bin/env node
/**
 * Scrape full CCS version numbers by visiting each version's download page
 * Extracts accurate build numbers from download links
 */

const { chromium } = require('playwright');

const TI_BASE_URL = 'https://www.ti.com/tool/download/CCSTUDIO';

async function scrapeFullVersions() {
  console.error('Launching headless browser...');
  let browser = await chromium.launch({ headless: true });
  let page = await browser.newPage();

  console.error(`Navigating to ${TI_BASE_URL}...`);
  await page.goto(TI_BASE_URL, { waitUntil: 'networkidle', timeout: 30000 });

  // Wait for page to fully load
  await page.waitForTimeout(5000);

  console.error('Extracting version list from ti-filter-list...');

  // Extract all versions from ti-filter-list items attribute
  const filterList = page.locator('ti-filter-list').first();
  const itemsAttr = await filterList.getAttribute('items');

  if (!itemsAttr) {
    console.error('Error: Could not find ti-filter-list items attribute');
    process.exit(1);
  }

  const items = JSON.parse(itemsAttr);
  const versionPaths = [];

  // Extract version paths from all groups
  for (const group of items) {
    if (group.children && Array.isArray(group.children)) {
      for (const item of group.children) {
        versionPaths.push(item.value); // e.g., "CCSTUDIO/20.5.0"
      }
    }
  }

  console.error(`Found ${versionPaths.length} version paths`);

  // Visit each version page and extract full version from download link
  const fullVersions = [];
  const BATCH_SIZE = 10; // Restart browser every 10 pages to avoid crashes

  for (let i = 0; i < versionPaths.length; i++) {
    // Restart browser every BATCH_SIZE pages
    if (i > 0 && i % BATCH_SIZE === 0) {
      console.error(`Restarting browser after ${i} pages...`);
      await page.close();
      await browser.close();

      const newBrowser = await chromium.launch({ headless: true });
      const newPage = newBrowser.newPage();

      // Replace references
      browser = newBrowser;
      page = await newPage;

      await page.waitForTimeout(2000);
    }

    const versionPath = versionPaths[i];
    const url = `https://www.ti.com/tool/download/${versionPath}`;

    console.error(`[${i + 1}/${versionPaths.length}] Checking ${versionPath}...`);

    try {
      await page.goto(url, { waitUntil: 'load', timeout: 30000 });
      await page.waitForTimeout(1500);

      // Look for Linux download link
      const downloadLinks = await page.locator('a[href*="CCS"]').all();

      for (const link of downloadLinks) {
        const href = await link.getAttribute('href');
        if (href && (href.includes('linux') || href.includes('Linux'))) {
          // Extract version from filename: CCS_20.5.0.00028_linux.zip
          const match = href.match(/CCS[_-]?(\d+\.\d+\.\d+\.\d+)/i);
          if (match) {
            const fullVersion = match[1];
            const parts = fullVersion.split('.');

            fullVersions.push({
              version: fullVersion,
              major: parts[0],
              minor: parts[1],
              patch: parts[2],
              build: parts[3],
              path: versionPath,
              downloadUrl: href
            });

            console.error(`  ✓ Found: ${fullVersion}`);
            break;
          }
        }
      }
    } catch (e) {
      console.error(`  ✗ Error: ${e.message.split('\n')[0]}`);

      // If page crashed, restart browser immediately
      if (e.message.includes('crashed') || e.message.includes('closed')) {
        console.error(`Browser crashed, restarting...`);
        try {
          await browser.close();
        } catch {}

        browser = await chromium.launch({ headless: true });
        page = await browser.newPage();
        await page.waitForTimeout(2000);
      }
    }

    // Rate limiting - wait between requests
    if (i < versionPaths.length - 1) {
      await page.waitForTimeout(500);
    }
  }

  await browser.close();

  // Deduplicate versions
  const uniqueVersions = Array.from(
    new Map(fullVersions.map(v => [v.version, v])).values()
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

  console.error(`\nExtracted ${uniqueVersions.length} full versions`);

  // Output JSON (without downloadUrl in final output)
  const output = uniqueVersions.map(v => ({
    version: v.version,
    major: v.major,
    minor: v.minor,
    patch: v.patch,
    build: v.build,
    is_latest: v.is_latest || false
  }));

  console.log(JSON.stringify(output, null, 2));
}

scrapeFullVersions().catch(error => {
  console.error('Error scraping versions:', error);
  process.exit(1);
});
