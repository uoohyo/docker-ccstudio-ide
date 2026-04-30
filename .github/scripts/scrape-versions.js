#!/usr/bin/env node
/**
 * Scrape CCS versions from TI download page using Playwright.
 *
 * Strategy overview:
 *   1. Parse the ti-filter-list items attribute for the version list.
 *      v11 and below include the full 4-part version in the path value.
 *      v12+ only expose a 3-part path (e.g. "CCSTUDIO/12.8.1"), so the
 *      build number must be resolved separately.
 *   2. Intercept every network response throughout the session to capture
 *      CCS Linux filenames (e.g. CCS12.8.1.00007_linux-x64.tar.gz).
 *      This resolves the currently-visible version immediately.
 *   3. For each v12+ version still missing a build number, click it in the
 *      filter UI to trigger the AJAX download-link update, then re-scan.
 *
 * linux_supported field:
 *   major >= 7 → true  (Linux installers available)
 *   major <  7 → false (Windows-only releases; list but do not build)
 */

const { chromium } = require('playwright');

const TI_URL = 'https://www.ti.com/tool/download/CCSTUDIO';
const LINUX_MIN_MAJOR = 7;

// Regex patterns that match a CCS Linux installer filename regardless of
// whether the CCS_ prefix is present (format changed between versions).
const LINUX_FILENAME_RE = /CCS_?(\d+)\.(\d+)\.(\d+)\.(\d+)_linux/g;

async function scrapeVersions() {
  console.error('Launching headless browser...');
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage();

  // Intercept ALL network responses to capture download link build numbers
  // before and after any filter interaction.
  const resolvedBuilds = new Map(); // 'MAJOR.MINOR.PATCH' -> 'BUILD'
  page.on('response', async (response) => {
    try {
      if (response.status() !== 200) return;
      const text = await response.text().catch(() => '');
      for (const m of text.matchAll(LINUX_FILENAME_RE)) {
        const key = `${m[1]}.${m[2]}.${m[3]}`;
        if (!resolvedBuilds.has(key)) {
          resolvedBuilds.set(key, m[4]);
          console.error(`Network: resolved ${key} → build ${m[4]}`);
        }
      }
    } catch (_) {}
  });

  console.error(`Navigating to ${TI_URL}...`);
  await page.goto(TI_URL, { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(3000);

  // Handle cookie / consent dialog
  try {
    const btn = page.locator('button:has-text("Accept"), button:has-text("Agree"), button:has-text("OK")').first();
    if (await btn.count() > 0) {
      await btn.click({ timeout: 5000 });
      await page.waitForTimeout(1000);
    }
  } catch (_) {}

  // ── Strategy 1: Parse ti-filter-list items attribute ──────────────────────
  const versionList = [];
  const versionsNeedingBuild = []; // versions with build='0' AND linux_supported

  console.error('Strategy 1: Parsing ti-filter-list items...');
  try {
    const filterList = page.locator('ti-filter-list').first();
    if (await filterList.count() > 0) {
      const itemsAttr = await filterList.getAttribute('items');
      if (itemsAttr) {
        const groups = JSON.parse(itemsAttr);
        for (const group of groups) {
          if (!Array.isArray(group.children)) continue;
          for (const item of group.children) {
            const m = (item.value || '').match(/CCSTUDIO\/(\d+\.\d+\.\d+(?:\.\d+)?)/);
            if (!m) continue;

            const parts = m[1].split('.');
            const [major, minor, patch, build] = [
              parts[0],
              parts[1] || '0',
              parts[2] || '0',
              parts[3] || '0',
            ];
            const linuxSupported = parseInt(major) >= LINUX_MIN_MAJOR;
            versionList.push({ version: `${major}.${minor}.${patch}.${build}`, major, minor, patch, build, linux_supported: linuxSupported });

            if (build === '0' && linuxSupported) {
              versionsNeedingBuild.push({ major, minor, patch });
            }
          }
        }
        console.error(`Strategy 1: ${versionList.length} versions (${versionsNeedingBuild.length} need build number)`);
      }
    }
  } catch (e) {
    console.error(`Strategy 1 error: ${e.message}`);
  }

  // ── Strategy 2: Scan current page content for CCS Linux filenames ─────────
  // This immediately resolves whatever version is currently selected (usually
  // the latest), without any UI interaction.
  console.error('Strategy 2: Scanning page content for CCS Linux filenames...');
  try {
    const html = await page.content();
    for (const m of html.matchAll(LINUX_FILENAME_RE)) {
      const key = `${m[1]}.${m[2]}.${m[3]}`;
      if (!resolvedBuilds.has(key)) {
        resolvedBuilds.set(key, m[4]);
        console.error(`Strategy 2: resolved ${key} → build ${m[4]}`);
      }
    }
  } catch (e) {
    console.error(`Strategy 2 error: ${e.message}`);
  }

  // ── Strategy 3: Click each unresolved v12+ version to trigger AJAX ────────
  const stillMissing = versionsNeedingBuild.filter(
    v => !resolvedBuilds.has(`${v.major}.${v.minor}.${v.patch}`)
  );

  if (stillMissing.length > 0) {
    console.error(`Strategy 3: clicking through ${stillMissing.length} versions to get build numbers...`);

    for (const v of stillMissing) {
      const versionPath = `${v.major}.${v.minor}.${v.patch}`;
      const ccstudioPath = `CCSTUDIO/${versionPath}`;

      try {
        // Try multiple ways to select the version in the filter component.
        const clicked = await page.evaluate((path, ccPath) => {
          // Helper: fire a click + change event on an element
          function triggerClick(el) {
            el.click();
            el.dispatchEvent(new Event('change', { bubbles: true }));
            return true;
          }

          const filterList = document.querySelector('ti-filter-list');
          if (!filterList) return false;

          // 1. Try shadow DOM
          const root = filterList.shadowRoot;
          if (root) {
            for (const sel of [
              `[value="${ccPath}"]`, `[value*="${path}"]`, `input[value*="${path}"]`
            ]) {
              const el = root.querySelector(sel);
              if (el) return triggerClick(el);
            }
          }

          // 2. Try light DOM inside filter
          for (const sel of [
            `[value="${ccPath}"]`, `[value*="${path}"]`
          ]) {
            const el = filterList.querySelector(sel);
            if (el) return triggerClick(el);
          }

          // 3. Try setting the component's value property directly
          if (Array.isArray(filterList.value) || typeof filterList.value === 'string') {
            filterList.value = [ccPath];
            filterList.dispatchEvent(new CustomEvent('valueChange', {
              detail: { value: [ccPath] }, bubbles: true
            }));
            filterList.dispatchEvent(new Event('change', { bubbles: true }));
            return true;
          }

          return false;
        }, versionPath, ccstudioPath);

        if (clicked) {
          // Wait for the download section to update via AJAX
          await page.waitForTimeout(2500);

          // Scan updated page content
          const html = await page.content();
          for (const m of html.matchAll(LINUX_FILENAME_RE)) {
            const key = `${m[1]}.${m[2]}.${m[3]}`;
            if (!resolvedBuilds.has(key)) {
              resolvedBuilds.set(key, m[4]);
              console.error(`Strategy 3: resolved ${key} → build ${m[4]}`);
            }
          }
        } else {
          console.error(`Strategy 3: could not click version ${versionPath}`);
        }
      } catch (e) {
        console.error(`Strategy 3 error (${versionPath}): ${e.message}`);
      }
    }
  }

  await browser.close();

  // ── Apply resolved build numbers ───────────────────────────────────────────
  for (const v of versionList) {
    if (v.build === '0') {
      const resolved = resolvedBuilds.get(`${v.major}.${v.minor}.${v.patch}`);
      if (resolved) {
        v.build = resolved;
        v.version = `${v.major}.${v.minor}.${v.patch}.${v.build}`;
      }
    }
  }

  // Also add any versions found by content/network scans but not in the filter
  for (const [key, build] of resolvedBuilds) {
    const [major, minor, patch] = key.split('.');
    const exists = versionList.some(
      v => v.major === major && v.minor === minor && v.patch === patch
    );
    if (!exists) {
      const linuxSupported = parseInt(major) >= LINUX_MIN_MAJOR;
      versionList.push({ version: `${major}.${minor}.${patch}.${build}`, major, minor, patch, build, linux_supported: linuxSupported });
    }
  }

  // ── Deduplicate by major.minor.patch, prefer non-zero build ───────────────
  const versionMap = new Map();
  for (const v of versionList) {
    const key = `${v.major}.${v.minor}.${v.patch}`;
    const existing = versionMap.get(key);
    if (!existing || (existing.build === '0' && v.build !== '0')) {
      versionMap.set(key, v);
    }
  }
  const uniqueVersions = Array.from(versionMap.values());

  // ── Sort newest first ──────────────────────────────────────────────────────
  uniqueVersions.sort((a, b) => {
    const av = [a.major, a.minor, a.patch, a.build].map(Number);
    const bv = [b.major, b.minor, b.patch, b.build].map(Number);
    for (let i = 0; i < 4; i++) {
      if (av[i] !== bv[i]) return bv[i] - av[i];
    }
    return 0;
  });

  // Mark latest linux-supported version
  const latestLinux = uniqueVersions.find(v => v.linux_supported !== false);
  if (latestLinux) latestLinux.is_latest = true;

  const linuxCount = uniqueVersions.filter(v => v.linux_supported !== false).length;
  console.error(`Found ${uniqueVersions.length} versions total (${linuxCount} with Linux support)`);
  console.error('Versions:', uniqueVersions.map(v =>
    `${v.version}${v.linux_supported === false ? '[no-linux]' : ''}`
  ).join(', '));

  console.log(JSON.stringify(uniqueVersions));
}

scrapeVersions().catch(error => {
  console.error('Error scraping versions:', error);
  process.exit(1);
});
