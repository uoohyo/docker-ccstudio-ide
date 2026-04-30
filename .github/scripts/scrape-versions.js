#!/usr/bin/env node
/**
 * Scrape CCS versions from the TI download page.
 *
 * For every version with major >= 4 the canonical full version (including
 * build number) is read from the Linux installer filename shown on the TI
 * page when that version is selected in the filter.  Clicking each entry
 * triggers an AJAX update; a network-response interceptor and page-content
 * scan then capture the filename (e.g. CCS_20.5.0.00028_linux.zip or
 * CCS12.8.1.00007_linux-x64.tar.gz).
 *
 * Versions with major < 4 are skipped (no Linux builds ever existed).
 * Versions that have no Linux download link are included but flagged
 * linux_supported: false and excluded from Docker builds.
 */

const { chromium } = require('playwright');

const TI_URL = 'https://www.ti.com/tool/download/CCSTUDIO';

// Match CCS Linux installer filenames:
//   v20+:   CCS_20.5.0.00028_linux  → capture group 1 = '20.5.0.00028'
//   v4–v19: CCS12.8.1.00007_linux   → capture group 1 = '12.8.1.00007'
const LINUX_PATTERNS = [
  /CCS_(\d+\.\d+\.\d+\.\d+)_linux/g,
  /CCS(\d+\.\d+\.\d+\.\d+)_linux/g,
];

function scanText(text, map) {
  for (const re of LINUX_PATTERNS) {
    re.lastIndex = 0;
    for (const m of text.matchAll(re)) {
      const [ma, mi, pa, bu] = m[1].split('.');
      const key = `${ma}.${mi}.${pa}`;
      if (!map.has(key)) {
        map.set(key, m[1]);
        console.error(`  resolved ${key} → ${m[1]}`);
      }
    }
  }
}

async function scrapeVersions() {
  console.error('Launching headless browser...');
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage();

  // Intercept every network response to capture Linux filenames from AJAX.
  const resolved = new Map(); // 'MA.MI.PA' → 'MA.MI.PA.BUILD'
  page.on('response', async (res) => {
    try {
      if (res.status() !== 200) return;
      const text = await res.text().catch(() => '');
      scanText(text, resolved);
    } catch (_) {}
  });

  console.error(`Navigating to ${TI_URL}...`);
  await page.goto(TI_URL, { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(3000);

  // Dismiss cookie / consent dialog if present.
  try {
    const btn = page.locator('button:has-text("Accept"), button:has-text("Agree"), button:has-text("OK")').first();
    if (await btn.count() > 0) {
      await btn.click({ timeout: 5000 });
      await page.waitForTimeout(1000);
    }
  } catch (_) {}

  // ── Phase 1: collect version list from ti-filter-list ─────────────────────
  // We only need (major, minor, patch) here — the build number comes from the
  // Linux download link, not from the filter path.
  const filterVersions = []; // [{major, minor, patch, ccValue}]

  console.error('Reading ti-filter-list...');
  try {
    const fl = page.locator('ti-filter-list').first();
    if (await fl.count() > 0) {
      const raw = await fl.getAttribute('items');
      if (raw) {
        for (const group of JSON.parse(raw)) {
          for (const item of group.children || []) {
            const m = (item.value || '').match(/CCSTUDIO\/(\d+)\.(\d+)\.(\d+)/);
            if (m && parseInt(m[1]) >= 4) {
              filterVersions.push({ major: m[1], minor: m[2], patch: m[3], ccValue: item.value });
            }
          }
        }
        console.error(`Filter list: ${filterVersions.length} entries (major >= 4)`);
      }
    }
  } catch (e) {
    console.error(`Filter list error: ${e.message}`);
  }

  // ── Phase 2: scan initial page content ────────────────────────────────────
  // The currently-selected version's download link is already in the HTML.
  console.error('Scanning initial page content...');
  try {
    scanText(await page.content(), resolved);
  } catch (e) {
    console.error(`Initial scan error: ${e.message}`);
  }

  // ── Phase 3: click through every unresolved version ───────────────────────
  // Clicking triggers an AJAX update of the download section; the network
  // interceptor and subsequent page scan capture the Linux filename.
  const unresolved = filterVersions.filter(v => !resolved.has(`${v.major}.${v.minor}.${v.patch}`));
  console.error(`Clicking through ${unresolved.length} unresolved versions...`);

  for (const v of unresolved) {
    const key = `${v.major}.${v.minor}.${v.patch}`;
    if (resolved.has(key)) continue; // resolved by a prior network event

    console.error(`  → ${v.ccValue}`);
    try {
      await page.evaluate((ccValue, path) => {
        function trigger(el) {
          if (!el) return false;
          el.click();
          el.dispatchEvent(new Event('change', { bubbles: true }));
          return true;
        }

        const fl = document.querySelector('ti-filter-list');
        if (!fl) return false;

        // A: shadow DOM
        if (fl.shadowRoot) {
          for (const sel of [`[value="${ccValue}"]`, `[value*="${path}"]`]) {
            if (trigger(fl.shadowRoot.querySelector(sel))) return true;
          }
        }
        // B: light DOM children
        for (const sel of [`[value="${ccValue}"]`, `[value*="${path}"]`]) {
          if (trigger(fl.querySelector(sel))) return true;
        }
        // C: set component value property directly
        try {
          fl.value = [ccValue];
          fl.dispatchEvent(new CustomEvent('valueChange', { detail: { value: [ccValue] }, bubbles: true }));
          fl.dispatchEvent(new Event('change', { bubbles: true }));
          return true;
        } catch (_) {}

        return false;
      }, v.ccValue, key);

      // Wait for AJAX to settle, then scan.
      await page.waitForTimeout(2500);
      scanText(await page.content(), resolved);
    } catch (e) {
      console.error(`    click error: ${e.message}`);
    }
  }

  await browser.close();

  // ── Phase 4: build the final version list ─────────────────────────────────
  const seen = new Set();
  const versionList = [];

  for (const fv of filterVersions) {
    const key = `${fv.major}.${fv.minor}.${fv.patch}`;
    if (seen.has(key)) continue;
    seen.add(key);

    const fullVersion = resolved.get(key);
    const linuxSupported = !!fullVersion;
    const parts = fullVersion ? fullVersion.split('.') : [fv.major, fv.minor, fv.patch, '0'];

    versionList.push({
      version: fullVersion || `${fv.major}.${fv.minor}.${fv.patch}.0`,
      major: parts[0],
      minor: parts[1],
      patch: parts[2],
      build: parts[3],
      linux_supported: linuxSupported,
    });
  }

  // Sort newest-first.
  versionList.sort((a, b) => {
    const av = [a.major, a.minor, a.patch, a.build].map(Number);
    const bv = [b.major, b.minor, b.patch, b.build].map(Number);
    for (let i = 0; i < 4; i++) if (av[i] !== bv[i]) return bv[i] - av[i];
    return 0;
  });

  // Mark the newest linux-supported entry as is_latest.
  const latestLinux = versionList.find(v => v.linux_supported);
  if (latestLinux) latestLinux.is_latest = true;

  const linuxCount = versionList.filter(v => v.linux_supported).length;
  console.error(`Done: ${versionList.length} versions total, ${linuxCount} with Linux support`);

  console.log(JSON.stringify(versionList));
}

scrapeVersions().catch(e => {
  console.error('Fatal error:', e);
  process.exit(1);
});
