// Shared page I/O helpers for graphbrain hooks.
// Single source of truth for reading + mutating .brain/ pages.
//
// Used by:
//   scripts/hooks/stale-detect.js  (PostToolUse — flip pages to STALE)
//   scripts/hooks/verified-guard.js (PreToolUse — check status: VERIFIED)
// Future:
//   M#6 verifier agent — reuses these helpers for lint
//
// PRD design decisions in scope:
//   #7  page-cap (not enforced here; just parsed)
//   #10 4-tier staleness model (tier 1 hook reverse-lookup)
//   #19 dual-layer guardrails (structural layer)
//   #32 hooks ownership via id-prefix (not relevant here — that's settings.local.json merge)

'use strict';

const fs = require('fs');
const path = require('path');

// --- Frontmatter parsing -----------------------------------------------------
// Custom parser — only handles the 4 fields hooks care about:
//   kind, status, source, sources (array of objects with path + hash)
// Not a full YAML parser; intentionally narrow.

function readPage(absolutePath) {
  if (!fs.existsSync(absolutePath)) return null;
  let raw;
  try {
    raw = fs.readFileSync(absolutePath, 'utf8');
  } catch {
    return null;
  }

  if (!raw.startsWith('---\n')) return null;
  const end = raw.indexOf('\n---\n', 4);
  if (end === -1) return null;

  const headerText = raw.slice(4, end);
  const body = raw.slice(end + 5);

  // Detect version-marker comment as the first line of the body and skip it
  // (M#1 ships <!-- graphbrain v0.1.0 --> as line 1 of slash-command templates,
  // but pages from M#3a+ don't have it. Tolerant either way.)

  const frontmatter = {};
  const lines = headerText.split('\n');
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    if (line === '' || /^\s*#/.test(line)) {
      i++;
      continue;
    }
    const flatMatch = line.match(/^([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(.*)$/);
    if (!flatMatch) {
      i++;
      continue;
    }
    const key = flatMatch[1];
    const value = flatMatch[2].trim();

    if (value === '') {
      // Could be a nested list (e.g., sources:). Collect indented list items.
      const items = [];
      let j = i + 1;
      while (j < lines.length) {
        const sub = lines[j];
        if (/^\s+-\s+/.test(sub)) {
          // Start of a list item; collect indented continuation lines too
          const item = { _raw: sub };
          // Parse `key: value` inside the item's continuation lines
          const itemKeyMatch = sub.match(/^\s+-\s+(?:([A-Za-z_][A-Za-z0-9_]*)\s*:\s*)?(.*)$/);
          if (itemKeyMatch && itemKeyMatch[1]) {
            item[itemKeyMatch[1]] = itemKeyMatch[2].trim();
          }
          let k = j + 1;
          while (k < lines.length && /^\s{4,}/.test(lines[k]) && !/^\s+-\s+/.test(lines[k])) {
            const sub2 = lines[k];
            const sub2Match = sub2.match(/^\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(.*)$/);
            if (sub2Match) {
              item[sub2Match[1]] = sub2Match[2].trim();
            }
            k++;
          }
          items.push(item);
          j = k;
        } else if (sub === '' || /^\s*#/.test(sub)) {
          j++;
        } else {
          break;
        }
      }
      if (items.length) {
        frontmatter[key] = items;
        i = j;
        continue;
      }
    }
    frontmatter[key] = value;
    i++;
  }

  return { frontmatter, body, raw, headerText };
}

// --- Frontmatter serialization ----------------------------------------------
// Round-trip-safe enough for our needs: rewrite the frontmatter from the
// parsed object, preserving the body verbatim.

function serializeFrontmatter(frontmatter) {
  const lines = [];
  for (const [key, value] of Object.entries(frontmatter)) {
    if (Array.isArray(value)) {
      lines.push(`${key}:`);
      for (const item of value) {
        const itemKeys = Object.keys(item).filter(k => k !== '_raw');
        if (itemKeys.length === 0) continue;
        // First key after the dash
        const firstKey = itemKeys[0];
        lines.push(`  - ${firstKey}: ${item[firstKey]}`);
        for (let k = 1; k < itemKeys.length; k++) {
          const subKey = itemKeys[k];
          lines.push(`    ${subKey}: ${item[subKey]}`);
        }
      }
    } else {
      lines.push(`${key}: ${value}`);
    }
  }
  return lines.join('\n');
}

// --- Atomic write -----------------------------------------------------------
// Mirrors scripts/init.js:atomicWrite (write to .tmp, fsync, rename).

function writePage(absolutePath, { frontmatter, body }) {
  const headerText = serializeFrontmatter(frontmatter);
  const content = `---\n${headerText}\n---\n${body}`;
  const tmp = `${absolutePath}.tmp`;
  fs.mkdirSync(path.dirname(absolutePath), { recursive: true });
  const fd = fs.openSync(tmp, 'w');
  try {
    fs.writeSync(fd, content);
    fs.fsyncSync(fd);
  } finally {
    fs.closeSync(fd);
  }
  fs.renameSync(tmp, absolutePath);
}

// --- Page mutations ---------------------------------------------------------

function flipToStale(absolutePath, reason) {
  const page = readPage(absolutePath);
  if (!page) return false;
  if (page.frontmatter.status === 'STALE') return false; // already stale

  page.frontmatter.status = 'STALE';
  page.frontmatter.last_stale_at = new Date().toISOString().slice(0, 10);
  if (reason) page.frontmatter.stale_reason = reason;

  writePage(absolutePath, { frontmatter: page.frontmatter, body: page.body });
  return true;
}

// --- Walking + finding ------------------------------------------------------

function walkBrainPages(brainRoot) {
  const out = [];
  function walk(dir) {
    let entries;
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of entries) {
      const p = path.join(dir, e.name);
      if (e.isDirectory()) {
        if (e.name === 'node_modules' || e.name === '.git') continue;
        walk(p);
      } else if (e.isFile() && e.name.endsWith('.md')) {
        out.push(p);
      }
    }
  }
  const codeDir = path.join(brainRoot, 'code');
  const conceptsDir = path.join(brainRoot, 'concepts');
  if (fs.existsSync(codeDir)) walk(codeDir);
  if (fs.existsSync(conceptsDir)) walk(conceptsDir);
  return out;
}

function findReferencingPages(brainRoot, sourceRelativePath) {
  const wikilinkPattern = `[[code/${sourceRelativePath}]]`;
  const matches = [];
  for (const pagePath of walkBrainPages(brainRoot)) {
    const page = readPage(pagePath);
    if (!page) continue;

    // (a) wikilink in body
    if (page.body && page.body.includes(wikilinkPattern)) {
      matches.push(pagePath);
      continue;
    }
    // (b) sources: array entry with matching path
    if (Array.isArray(page.frontmatter.sources)) {
      for (const entry of page.frontmatter.sources) {
        if (entry && entry.path === sourceRelativePath) {
          matches.push(pagePath);
          break;
        }
      }
    }
  }
  return matches;
}

// --- Brain root discovery ---------------------------------------------------

function findBrainRoot(cwd) {
  // Hook runs in cwd; .brain/ should be at cwd or refuse to act.
  const candidate = path.join(cwd, '.brain');
  if (!fs.existsSync(candidate)) return null;
  if (!fs.existsSync(path.join(candidate, '.graphbrain-version'))) return null;
  return candidate;
}

module.exports = {
  readPage,
  writePage,
  flipToStale,
  walkBrainPages,
  findReferencingPages,
  findBrainRoot,
};
