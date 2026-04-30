#!/usr/bin/env node
/**
 * Debug version of scraper - saves screenshots and HTML
 */

const { chromium } = require('playwright');
const fs = require('fs');

const TI_URL = 'https://www.ti.com/tool/download/CCSTUDIO';

async function debugScrape() {
  console.error('Launching browser (headed for debugging)...');
  const browser = await chromium.launch({ headless: false, slowMo: 1000 });
  const page = await browser.newPage();

  console.error(`Navigating to ${TI_URL}...`);
  await page.goto(TI_URL, { waitUntil: 'networkidle', timeout: 30000 });

  // Screenshot 1: Initial load
  await page.screenshot({ path: '/tmp/screenshot-1-initial.png', fullPage: true });
  console.error('Screenshot 1: Initial page load');

  // Wait for page to settle
  await page.waitForTimeout(3000);

  // Screenshot 2: After wait
  await page.screenshot({ path: '/tmp/screenshot-2-after-wait.png', fullPage: true });
  console.error('Screenshot 2: After 3s wait');

  // Try to find and click version selector
  console.error('\n=== Searching for version selector ===');

  // Get all elements that might be the version selector
  const selectors = [
    'input[placeholder*="version" i]',
    'input[placeholder*="filter" i]',
    '[class*="version-select"]',
    '[class*="version-filter"]',
    'select',
    '[role="combobox"]',
    '[role="listbox"]'
  ];

  for (const selector of selectors) {
    const count = await page.locator(selector).count();
    if (count > 0) {
      console.error(`✓ Found ${count} elements: ${selector}`);

      // Try to interact
      try {
        const element = page.locator(selector).first();
        const text = await element.textContent().catch(() => '');
        const placeholder = await element.getAttribute('placeholder').catch(() => '');
        console.error(`  Text: "${text}", Placeholder: "${placeholder}"`);

        // Click it
        await element.click();
        console.error(`  Clicked!`);
        await page.waitForTimeout(2000);

        // Screenshot after click
        await page.screenshot({ path: `/tmp/screenshot-clicked-${selector.replace(/[^a-z0-9]/gi, '_')}.png`, fullPage: true });
      } catch (e) {
        console.error(`  Error interacting: ${e.message}`);
      }
    }
  }

  // Look for version list items
  console.error('\n=== Searching for version items ===');

  const versionSelectors = [
    '[class*="v20"]',
    '[class*="v12"]',
    '[class*="v11"]',
    'li:has-text("v20")',
    'li:has-text("v12")',
    'div:has-text("20.")',
    'div:has-text("12.")'
  ];

  for (const selector of versionSelectors) {
    const count = await page.locator(selector).count();
    if (count > 0) {
      console.error(`✓ Found ${count} elements: ${selector}`);
      const elements = await page.locator(selector).all();
      for (let i = 0; i < Math.min(3, elements.length); i++) {
        const text = await elements[i].textContent();
        console.error(`  [${i}]: ${text.substring(0, 100)}`);
      }
    }
  }

  // Save HTML
  const html = await page.content();
  fs.writeFileSync('/tmp/page.html', html);
  console.error('\nHTML saved to /tmp/page.html');

  // Extract all text containing version patterns
  console.error('\n=== Version patterns in page ===');
  const allText = await page.evaluate(() => document.body.innerText);
  const versionLines = allText.split('\n').filter(line =>
    /v?\d+\.\d+\.\d+/.test(line) || /v\d+x/.test(line.toLowerCase())
  );

  console.error('Lines with version patterns:');
  versionLines.slice(0, 20).forEach(line => {
    console.error(`  ${line.trim()}`);
  });

  // Try scrolling
  console.error('\n=== Trying to scroll ===');
  await page.evaluate(() => window.scrollBy(0, 500));
  await page.waitForTimeout(1000);
  await page.screenshot({ path: '/tmp/screenshot-3-scrolled.png', fullPage: true });

  console.error('\nWaiting 5 seconds before closing...');
  await page.waitForTimeout(5000);

  await browser.close();
  console.error('\nDebug complete. Check screenshots in /tmp/');
}

debugScrape().catch(error => {
  console.error('Error:', error);
  process.exit(1);
});
