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

  console.error('Looking for version selector...');

  // Try multiple strategies to find and interact with version selector
  let versionList = [];

  // Strategy 1: Look for and click version filter/dropdown
  try {
    console.error('Strategy 1: Clicking version filter...');

    // Try to click on "Select a version" text or nearby element
    const versionDropdown = page.locator('text="Select a version"').first();
    if (await versionDropdown.isVisible({ timeout: 5000 })) {
      console.error('Found "Select a version", clicking...');
      await versionDropdown.click({ force: true });
      await page.waitForTimeout(2000);
    }

    // Also try clicking the filter input
    const filterInput = page.locator('input[placeholder*="version" i], input[placeholder*="filter" i]').first();
    if (await filterInput.count() > 0) {
      console.error('Found filter input, scrolling and clicking...');

      // Scroll into view and click with force
      await filterInput.scrollIntoViewIfNeeded();
      await page.waitForTimeout(500);
      await filterInput.click({ force: true });
      await page.waitForTimeout(2000);

      // Try typing to trigger dropdown
      await filterInput.fill('');
      await page.waitForTimeout(1000);
    }
  } catch (e) {
    console.error(`Strategy 1 error: ${e.message}`);
  }

  // Strategy 2: Look for version list items
  try {
    console.error('Strategy 2: Extracting version list items...');

    // Common selectors for version lists
    const selectors = [
      '[class*="version"] a',
      '[class*="version"] button',
      'li[class*="version"]',
      '[data-version]',
      'a[href*="20."], a[href*="12."], a[href*="11."]'
    ];

    for (const selector of selectors) {
      const elements = await page.locator(selector).all();
      if (elements.length > 0) {
        console.error(`Found ${elements.length} elements with selector: ${selector}`);

        for (const el of elements) {
          const text = await el.textContent();
          const match = text.match(/(\d+)\.(\d+)\.(\d+)\.(\d+)/);
          if (match) {
            versionList.push({
              version: `${match[1]}.${match[2]}.${match[3]}.${match[4]}`,
              major: match[1],
              minor: match[2],
              patch: match[3],
              build: match[4]
            });
          }
        }

        if (versionList.length > 0) break;
      }
    }
  } catch (e) {
    console.error('Version list extraction failed:', e.message);
  }

  // Strategy 3: Extract from page content directly
  console.error('Strategy 3: Extracting from page text content...');
  const pageContent = await page.content();
  const versionMatches = pageContent.matchAll(/(\d+)\.(\d+)\.(\d+)\.(\d+)/g);

  for (const match of versionMatches) {
    const major = parseInt(match[1]);
    // Filter out non-version numbers (e.g., dates, random numbers)
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

  // Strategy 4: Check download links
  console.error('Strategy 4: Checking download links...');
  const links = await page.locator('a[href*="CCS"]').all();

  for (const link of links) {
    const href = await link.getAttribute('href');
    if (href) {
      const match = href.match(/CCS_?(\d+)\.(\d+)\.(\d+)\.(\d+)/);
      if (match) {
        versionList.push({
          version: `${match[1]}.${match[2]}.${match[3]}.${match[4]}`,
          major: match[1],
          minor: match[2],
          patch: match[3],
          build: match[4]
        });
      }
    }
  }

  await browser.close();

  // Deduplicate versions
  const uniqueVersions = Array.from(
    new Map(versionList.map(v => [v.version, v])).values()
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
