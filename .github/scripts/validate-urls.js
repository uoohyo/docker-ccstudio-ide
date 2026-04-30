#!/usr/bin/env node
/**
 * Validate CCS download URLs.
 *
 * Reads the version JSON array from stdin, constructs a download URL for
 * every linux-supported version using the same logic as the Dockerfile,
 * and verifies each URL is reachable.
 *
 * URL construction rules (mirrors Dockerfile download logic):
 *   major >= 20 → https://…/MAJOR.MINOR.PATCH/CCS_VERSION_linux.zip
 *   major 12–19 → https://…/MAJOR.MINOR.PATCH/CSSVERSION_linux-x64.tar.gz
 *   major  4–11 → https://…/VERSION/CSSVERSION_linux-x64.tar.gz
 *
 * Exits 0 if all URLs are reachable, 1 otherwise.
 */

const BASE = 'https://dr-download.ti.com/software-development/ide-configuration-compiler-or-debugger/MD-J1VdearkvK/';

function buildUrl(v) {
  const major = parseInt(v.major);
  if (major >= 20) {
    return `${BASE}${v.major}.${v.minor}.${v.patch}/CCS_${v.version}_linux.zip`;
  }
  if (major >= 12) {
    return `${BASE}${v.major}.${v.minor}.${v.patch}/CCS${v.version}_linux-x64.tar.gz`;
  }
  return `${BASE}${v.version}/CCS${v.version}_linux-x64.tar.gz`;
}

async function checkUrl(url, timeoutMs = 20000) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  const headers = { 'User-Agent': 'curl/7.81.0', 'Accept': '*/*' };

  try {
    // Try HEAD first (no body transfer).
    let res = await fetch(url, { method: 'HEAD', headers, signal: ctrl.signal, redirect: 'follow' });
    clearTimeout(timer);

    // Some servers reject HEAD with 405; fall back to a 1-byte range GET.
    if (res.status === 405 || res.status === 403) {
      const ctrl2 = new AbortController();
      const timer2 = setTimeout(() => ctrl2.abort(), timeoutMs);
      res = await fetch(url, {
        method: 'GET',
        headers: { ...headers, Range: 'bytes=0-0' },
        signal: ctrl2.signal,
        redirect: 'follow',
      });
      clearTimeout(timer2);
      // 206 Partial Content is success for range request.
      return { ok: res.ok || res.status === 206, status: res.status };
    }

    return { ok: res.ok, status: res.status };
  } catch (e) {
    clearTimeout(timer);
    return { ok: false, error: e.name === 'AbortError' ? 'timeout' : e.message };
  }
}

async function main() {
  let input = '';
  for await (const chunk of process.stdin) input += chunk;

  let versions;
  try {
    versions = JSON.parse(input.trim());
  } catch (e) {
    console.error('Failed to parse version JSON:', e.message);
    process.exit(1);
  }

  const targets = versions.filter(v => v.public_download === true);
  if (targets.length === 0) {
    console.log('No linux-supported versions to validate.');
    process.exit(0);
  }

  console.log(`Validating ${targets.length} download URL(s)...\n`);

  const failures = [];
  for (const v of targets) {
    const url = buildUrl(v);
    process.stdout.write(`  ${v.version.padEnd(20)} `);

    const r = await checkUrl(url);
    if (r.ok) {
      console.log(`✓  HTTP ${r.status}`);
    } else {
      const reason = r.error || `HTTP ${r.status}`;
      console.log(`✗  ${reason}`);
      console.log(`     ${url}`);
      failures.push({ version: v.version, url, reason });
    }
  }

  console.log('');

  if (failures.length > 0) {
    console.error(`❌  ${failures.length} URL(s) failed:\n`);
    for (const f of failures) console.error(`  • ${f.version}: ${f.reason}\n    ${f.url}`);
    process.exit(1);
  }

  console.log(`✅  All ${targets.length} URLs are valid.`);
}

main();
