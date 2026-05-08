#!/usr/bin/env node
/**
 * Scrape CCS versions from the TI download page.
 *
 * Strategy (no headless browser needed):
 *   1. Fetch the main TI download page — the full version list is in the
 *      server-rendered HTML (CCSTUDIO/X.Y.Z.BUILD or CCSTUDIO/X.Y.Z paths).
 *   2. For every version, fetch its TI per-version page to locate the Linux
 *      installer link and extract the full 4-part build version.
 *      - v4–v11: use the 4-part version path already known from the main page.
 *      - v12+:   use the 3-part path; build number only appears on the version page.
 *   3. linux_supported: true when TI's own page lists a Linux installer link.
 *      URL accessibility is NOT checked here — that is validate-urls.js's job.
 *
 * URL patterns seen on TI pages:
 *   v7–v20: dr-download.ti.com/[secure/]software-development/.../CCS..._linux...
 *   v5–v6:  software-dl.ti.com self-cert form  (prod_no=CCS..._linux...)
 *   v4:     unknown / no Linux link
 */

const TI_BASE = 'https://www.ti.com/tool/download/CCSTUDIO';
const HEADERS  = { 'User-Agent': 'curl/7.81.0', Accept: '*/*' };

// Matches the 4-part build version inside any CCS Linux filename.
//   CCS_20.5.0.00028_linux  →  '20.5.0.00028'
//   CCS12.8.1.00007_linux   →  '12.8.1.00007'
//   CCS5.5.0.00077_linux    →  '5.5.0.00077'
const LINUX_VERSION_RE = /CCS[_]?(\d+\.\d+\.\d+\.\d+)[_-]?linux/gi;

function extractLinuxVersion(html) {
  LINUX_VERSION_RE.lastIndex = 0;
  const m = LINUX_VERSION_RE.exec(html);
  return m ? m[1] : null;
}

function hasLinuxLink(html) {
  // Check for direct CDN download links (public or /secure/) with a Linux filename.
  if (/dr-download\.ti\.com[^"'<>\s]*CCS[^"'<>\s]*linux/i.test(html)) return true;
  // Check for self-cert export form links that reference a Linux installer.
  if (/self_cert_export[^"'<>\s]*prod_no=CCS[^"'<>\s]*linux/i.test(html)) return true;
  return false;
}

// Construct the URL the Dockerfile would use for this version.
// public_download is verified by actually checking this URL (HEAD request).
function buildDownloadUrl(v) {
  const CDN = 'https://dr-download.ti.com/software-development/ide-configuration-compiler-or-debugger/MD-J1VdearkvK/';
  const major = parseInt(v.major);
  if (major >= 20) return `${CDN}${v.major}.${v.minor}.${v.patch}/CCS_${v.version}_linux.zip`;
  if (major >= 12) return `${CDN}${v.major}.${v.minor}.${v.patch}/CCS${v.version}_linux-x64.tar.gz`;
  return `${CDN}${v.version}/CCS${v.version}_linux-x64.tar.gz`;
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

async function fetchText(url, timeoutMs = 30000) {
  const ctrl  = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const res = await fetch(url, { headers: HEADERS, signal: ctrl.signal });
    return await res.text();
  } finally {
    clearTimeout(timer);
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

  // ── Step 2: fetch each version's TI page to get Linux info ─────────────────
  // v4–v11: use the full 4-part version path (already known).
  // v12+:   use the 3-part path (build number comes from the page).
  const CONCURRENCY = 5;
  const entries = [...seen.values()];
  const resolved = new Map(); // key → { fullVersion, linuxSupported }

  for (let i = 0; i < entries.length; i += CONCURRENCY) {
    const batch = entries.slice(i, i + CONCURRENCY);
    await Promise.all(batch.map(async v => {
      const key       = `${v.major}.${v.minor}.${v.patch}`;
      const tiPath    = v.build !== null ? `${key}.${v.build}` : key;
      try {
        const html        = await fetchText(`${TI_BASE}/${tiPath}`);
        const fullVersion = extractLinuxVersion(html);
        const linuxFound  = fullVersion !== null || hasLinuxLink(html);

        if (fullVersion) {
          resolved.set(key, { fullVersion, linuxSupported: true });
          console.error(`  ${tiPath.padEnd(24)} → ${fullVersion}`);
        } else if (linuxFound) {
          const fallback = v.build !== null
            ? `${v.major}.${v.minor}.${v.patch}.${v.build}`
            : null;
          resolved.set(key, { fullVersion: fallback, linuxSupported: true });
          console.error(`  ${tiPath.padEnd(24)} → linux link found (version unparsed)`);
        } else {
          resolved.set(key, { fullVersion: null, linuxSupported: false });
          console.error(`  ${tiPath.padEnd(24)} → no Linux link`);
        }
      } catch (e) {
        resolved.set(key, { fullVersion: null, linuxSupported: false });
        console.error(`  ${tiPath.padEnd(24)} → fetch error: ${e.message}`);
      }
    }));
  }

  // ── Step 3: verify Dockerfile download URLs for linux_supported versions ──
  // public_download: true only when the URL the Dockerfile would construct
  // is actually reachable. This correctly excludes v6 (/secure/) and v5
  // (different CDN / self-cert) even if TI's page lists them as Linux-supported.
  console.error('\nVerifying download URLs...');
  const urlCache = new Map(); // key → boolean

  const linuxCandidates = [...seen.entries()]
    .map(([key, v]) => ({ key, v, info: resolved.get(key) }))
    .filter(({ info }) => info && info.linuxSupported && info.fullVersion);

  for (let i = 0; i < linuxCandidates.length; i += CONCURRENCY) {
    const batch = linuxCandidates.slice(i, i + CONCURRENCY);
    await Promise.all(batch.map(async ({ key, info }) => {
      const parts = info.fullVersion.split('.');
      const vObj  = { version: info.fullVersion, major: parts[0], minor: parts[1], patch: parts[2], build: parts[3] };
      const url   = buildDownloadUrl(vObj);
      const ok    = await checkUrl(url);
      urlCache.set(key, ok);
      console.error(`  ${info.fullVersion.padEnd(22)} ${ok ? '✓' : '✗'}`);
    }));
  }

  // ── Step 4: build the final version list ──────────────────────────────────
  // Exclusions: versions with known installation issues
  const EXCLUDED_VERSIONS = [
    '7.0.0.00043', // Requires X11 display even with --unattendedmodeui none
  ];

  const versionList = [];
  for (const [key, v] of seen.entries()) {
    const info        = resolved.get(key) || { fullVersion: null, linuxSupported: false };
    const fullVersion = info.fullVersion;
    const parts       = fullVersion
      ? fullVersion.split('.')
      : [v.major, v.minor, v.patch, v.build ?? '0'];

    const version = fullVersion || `${v.major}.${v.minor}.${v.patch}.${v.build ?? '0'}`;

    // Skip excluded versions
    if (EXCLUDED_VERSIONS.includes(version)) {
      console.error(`  Excluding ${version} (known installation issues)`);
      continue;
    }

    versionList.push({
      version:         version,
      major:           parts[0],
      minor:           parts[1],
      patch:           parts[2],
      build:           parts[3],
      linux_supported: info.linuxSupported,
      public_download: urlCache.get(key) === true,
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
  console.error(`\nDone: ${versionList.length} versions total, ${linuxCount} with Linux support`);

  console.log(JSON.stringify(versionList));
}

scrapeVersions().catch(e => {
  console.error('Fatal error:', e);
  process.exit(1);
});
