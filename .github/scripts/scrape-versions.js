#!/usr/bin/env node
/**
 * Scrape CCS versions from the TI download page and verify download URLs.
 *
 * Strategy (no headless browser needed):
 *   1. Fetch the main TI download page — the full version list is in the
 *      server-rendered HTML (CCSTUDIO/X.Y.Z.BUILD or CCSTUDIO/X.Y.Z paths).
 *   2. v4–v11: the 4-part version is already in the path, no further fetch.
 *   3. v12+:   only 3-part path; fetch the per-version page to read the Linux
 *      installer filename and extract the build number.
 *   4. Verify every candidate download URL is reachable.
 *      linux_supported: true only when the CDN URL returns HTTP 200/206.
 */

const TI_BASE   = 'https://www.ti.com/tool/download/CCSTUDIO';
const CDN_BASE  = 'https://dr-download.ti.com/software-development/ide-configuration-compiler-or-debugger/MD-J1VdearkvK/';
const HEADERS   = { 'User-Agent': 'curl/7.81.0', Accept: '*/*' };

// Match CCS Linux installer filenames in HTML:
//   v20+:   CCS_20.5.0.00028_linux  → group 1 = '20.5.0.00028'
//   v4–v19: CCS12.8.1.00007_linux   → group 1 = '12.8.1.00007'
const LINUX_RE = /CCS[_]?(\d+\.\d+\.\d+\.\d+)_linux/g;

function parseLinuxVersion(html) {
  LINUX_RE.lastIndex = 0;
  const m = LINUX_RE.exec(html);
  return m ? m[1] : null;
}

function buildDownloadUrl(v) {
  const major = parseInt(v.major);
  if (major >= 20) return `${CDN_BASE}${v.major}.${v.minor}.${v.patch}/CCS_${v.version}_linux.zip`;
  if (major >= 12) return `${CDN_BASE}${v.major}.${v.minor}.${v.patch}/CCS${v.version}_linux-x64.tar.gz`;
  return `${CDN_BASE}${v.version}/CCS${v.version}_linux-x64.tar.gz`;
}

async function fetchText(url, timeoutMs = 30000) {
  const ctrl  = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const res  = await fetch(url, { headers: HEADERS, signal: ctrl.signal });
    return await res.text();
  } finally {
    clearTimeout(timer);
  }
}

async function checkUrl(url, timeoutMs = 20000) {
  const ctrl  = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    let res = await fetch(url, { method: 'HEAD', headers: HEADERS, signal: ctrl.signal, redirect: 'follow' });
    clearTimeout(timer);
    if (res.status === 405 || res.status === 403) {
      const ctrl2  = new AbortController();
      const timer2 = setTimeout(() => ctrl2.abort(), timeoutMs);
      res = await fetch(url, {
        method: 'GET',
        headers: { ...HEADERS, Range: 'bytes=0-0' },
        signal: ctrl2.signal,
        redirect: 'follow',
      });
      clearTimeout(timer2);
      return res.ok || res.status === 206;
    }
    return res.ok;
  } catch (_) {
    clearTimeout(timer);
    return false;
  }
}

async function scrapeVersions() {
  // ── Step 1: fetch main page and extract all version paths ─────────────────
  console.error(`Fetching ${TI_BASE}...`);
  const mainHtml = await fetchText(TI_BASE);

  const pathRe = /CCSTUDIO\/(\d+)\.(\d+)\.(\d+)(?:\.(\d+))?/g;
  const seen   = new Map(); // 'MA.MI.PA' → {major, minor, patch, build|null}
  for (const m of mainHtml.matchAll(pathRe)) {
    const [ma, mi, pa, bu] = [m[1], m[2], m[3], m[4] ?? null];
    if (parseInt(ma) < 4) continue;
    const key = `${ma}.${mi}.${pa}`;
    if (!seen.has(key)) seen.set(key, { major: ma, minor: mi, patch: pa, build: bu });
  }
  console.error(`Found ${seen.size} unique versions (major >= 4) in main page`);

  // ── Step 2: for v12+ (3-part only), fetch per-version page in parallel ────
  const needsFetch = [...seen.values()].filter(v => v.build === null);
  console.error(`Fetching build numbers for ${needsFetch.length} v12+ versions...`);

  const resolved = new Map();

  // Pre-resolve v4–v11 (build already known).
  for (const v of seen.values()) {
    if (v.build !== null) {
      resolved.set(`${v.major}.${v.minor}.${v.patch}`, `${v.major}.${v.minor}.${v.patch}.${v.build}`);
    }
  }

  const CONCURRENCY = 5;
  for (let i = 0; i < needsFetch.length; i += CONCURRENCY) {
    const batch = needsFetch.slice(i, i + CONCURRENCY);
    await Promise.all(batch.map(async v => {
      const key = `${v.major}.${v.minor}.${v.patch}`;
      try {
        const html = await fetchText(`${TI_BASE}/${key}`);
        const full = parseLinuxVersion(html);
        if (full) {
          resolved.set(key, full);
          console.error(`  ${key} → ${full}`);
        } else {
          console.error(`  ${key} → no Linux link found`);
        }
      } catch (e) {
        console.error(`  ${key} → fetch error: ${e.message}`);
      }
    }));
  }

  // ── Step 3: build candidate list ──────────────────────────────────────────
  const candidates = [];
  for (const [key, v] of seen.entries()) {
    const fullVersion = resolved.get(key);
    if (!fullVersion) continue; // no Linux link found on TI page

    const parts = fullVersion.split('.');
    candidates.push({
      version:  fullVersion,
      major:    parts[0],
      minor:    parts[1],
      patch:    parts[2],
      build:    parts[3],
    });
  }

  // ── Step 4: verify download URLs in parallel ───────────────────────────────
  console.error(`\nVerifying ${candidates.length} download URL(s)...`);
  const versionList = [];

  for (let i = 0; i < candidates.length; i += CONCURRENCY) {
    const batch = candidates.slice(i, i + CONCURRENCY);
    const results = await Promise.all(batch.map(async v => {
      const url = buildDownloadUrl(v);
      const ok  = await checkUrl(url);
      console.error(`  ${v.version.padEnd(20)} ${ok ? '✓' : '✗'}  ${url}`);
      return { ...v, linux_supported: ok };
    }));
    versionList.push(...results);
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
  console.error(`\nDone: ${versionList.length} versions total, ${linuxCount} with Linux support`);

  console.log(JSON.stringify(versionList));
}

scrapeVersions().catch(e => {
  console.error('Fatal error:', e);
  process.exit(1);
});
