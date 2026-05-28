#!/usr/bin/env node
'use strict';
//
// detect-stacks [cwd]
//
// Walks the cwd ROOT subtree + every immediate subdir (excluded list below),
// runs `stack-detection.json` signal match per subtree, persists
// `<cwd>/.brain/.graphbrain-stacks.json` (the load-bearing map read by
// /brain:ingest for per-file template routing).
//
// Output (stdout): the same JSON written to .graphbrain-stacks.json.
//
// Catalog resolution: looks in
//   1. <cwd>/.claude/plugins/graphbrain/skills/core/init/templates/stack-detection.json
//   2. $HOME/.claude/plugins/graphbrain/skills/core/init/templates/stack-detection.json
//
// Exit codes:
//   0 — success
//   1 — usage / catalog / .brain missing
//
// Replaces ~50 lines of LLM-side procedure in /brain:init Step 4a/4b/4c.

const fs = require('fs');
const path = require('path');

const EXCLUDE_DIRS = new Set([
  '.git', 'node_modules', '.venv', '__pycache__', 'dist', 'build',
  '.brain', '.claude', '.next', 'target', 'vendor', '.cache',
]);

const MAX_SUBTREES = 16;

function fail(msg) {
  process.stderr.write(msg + '\n');
  process.exit(1);
}

const cwd = path.resolve(process.argv[2] || '.');

const catalogCandidates = [
  path.join(cwd, '.claude', 'plugins', 'graphbrain', 'skills', 'core', 'init', 'templates', 'stack-detection.json'),
  path.join(process.env.HOME || '', '.claude', 'plugins', 'graphbrain', 'skills', 'core', 'init', 'templates', 'stack-detection.json'),
];
let catalogPath = null;
for (const p of catalogCandidates) {
  if (p && fs.existsSync(p)) { catalogPath = p; break; }
}
if (!catalogPath) fail(`stack-detection.json not found. Looked in:\n  ${catalogCandidates.join('\n  ')}`);

let catalog;
try {
  catalog = JSON.parse(fs.readFileSync(catalogPath, 'utf8'));
} catch (e) {
  fail(`stack-detection.json unparseable: ${e.message}`);
}

// Minimal glob: supports `*.<ext>` (shallow, root-only) and exact names.
// Anything more elaborate returns false; widen the matcher when the catalog needs it.
function globMatches(subroot, pattern) {
  if (!pattern.includes('*') && !pattern.includes('?')) {
    return fs.existsSync(path.join(subroot, pattern));
  }
  const starExt = pattern.match(/^\*(\.[A-Za-z0-9]+)$/);
  if (starExt) {
    const ext = starExt[1];
    let entries;
    try {
      entries = fs.readdirSync(subroot, { withFileTypes: true });
    } catch {
      return false;
    }
    return entries.some(e => e.isFile() && e.name.toLowerCase().endsWith(ext.toLowerCase()));
  }
  return false;
}

function signalMatches(subroot, sig) {
  if (sig.file_exists) {
    const target = path.join(subroot, sig.file_exists);
    let st;
    try { st = fs.statSync(target); } catch { return false; }
    if (!st.isFile()) return false;
    if (sig.contains) {
      let content;
      try { content = fs.readFileSync(target, 'utf8'); } catch { return false; }
      return content.includes(sig.contains);
    }
    return true;
  }
  if (sig.dir_exists) {
    const target = path.join(subroot, sig.dir_exists);
    try { return fs.statSync(target).isDirectory(); } catch { return false; }
  }
  if (sig.glob) {
    return globMatches(subroot, sig.glob);
  }
  return false;
}

function detectFor(subroot) {
  const matched = [];
  for (const stack of catalog.stacks || []) {
    const signals = stack.signals || [];
    if (signals.length === 0) continue;
    const all = signals.every(s => signalMatches(subroot, s));
    if (all) matched.push(stack.name);
  }
  return Array.from(new Set(matched));
}

// 4a — Enumerate subtrees (cwd root + each immediate subdir not excluded).
const subtrees = [];
const rootStacks = detectFor(cwd);
subtrees.push({ path: '', stacks: rootStacks });

let entries;
try {
  entries = fs.readdirSync(cwd, { withFileTypes: true });
} catch (e) {
  fail(`could not read cwd ${cwd}: ${e.message}`);
}
entries.sort((a, b) => a.name.localeCompare(b.name));

let warning_truncated = false;
let added = 0;
for (const entry of entries) {
  if (!entry.isDirectory()) continue;
  if (EXCLUDE_DIRS.has(entry.name)) continue;
  if (added >= MAX_SUBTREES) { warning_truncated = true; break; }
  const stacks = detectFor(path.join(cwd, entry.name));
  if (stacks.length > 0) {
    subtrees.push({ path: entry.name, stacks });
    added++;
  }
}

const result = {
  version: '1.0.13',
  generated: new Date().toISOString().slice(0, 10),
  subtrees,
};
if (warning_truncated) {
  result.warning = `more than ${MAX_SUBTREES} subdirs; truncated to first ${MAX_SUBTREES} alphabetically`;
}

// 4c — Persist.
const brainDir = path.join(cwd, '.brain');
if (!fs.existsSync(brainDir)) {
  fail(`.brain/ does not exist in ${cwd} — run npx graphbrain init first`);
}
const outFile = path.join(brainDir, '.graphbrain-stacks.json');
fs.writeFileSync(outFile, JSON.stringify(result, null, 2) + '\n');

process.stdout.write(JSON.stringify(result, null, 2) + '\n');
