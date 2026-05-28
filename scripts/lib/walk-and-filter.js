#!/usr/bin/env node
'use strict';
//
// walk-and-filter <folder>
//
// Lists ingest-eligible files under <folder>, relative to cwd.
// Strategy: try `git ls-files <folder>` first (respects .gitignore); fall back
// to recursive walk with the standard exclude-dir blocklist.
//
// Filters (matches the in-prompt blocklists graphbrain shipped pre-v1.0.13):
//   - Binary extensions  (.png, .jpg, .pdf, .so, .zip, .mp4, ...)
//   - Lockfiles          (package-lock.json, yarn.lock, ...)
//   - Minified/generated (*.min.js, *.bundle.js, *.map)
//
// Output (stdout): JSON
//   {
//     total: <pre-filter count>,
//     files: [...rel-paths kept],
//     skipped_binary: [...],
//     skipped_lock: [...],
//     skipped_minified: [...],
//     by_ext: { ".ts": N, ... }
//   }
//
// Exit codes: 0 on success, 1 on usage error / folder not found.
//
// This helper replaces ~30 lines of LLM-side procedure in /brain:ingest
// folder Steps 2-3. The LLM still decides what to do with the results.

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const BINARY_EXTS = new Set([
  '.png', '.jpg', '.jpeg', '.gif', '.webp', '.pdf',
  '.exe', '.bin', '.so', '.dylib', '.o', '.a',
  '.zip', '.tar', '.tgz', '.gz', '.mp4', '.mp3', '.wav',
  '.ico', '.ttf', '.woff', '.woff2',
]);

const LOCKFILES = new Set([
  'package-lock.json', 'yarn.lock', 'pnpm-lock.yaml',
  'poetry.lock', 'Cargo.lock', 'go.sum', 'composer.lock', 'Pipfile.lock',
]);

const MINIFIED_RE = /\.(min\.js|min\.css|bundle\.js|map)$/i;

const EXCLUDE_DIRS = new Set([
  '.git', 'node_modules', '.brain', '.claude', 'dist', 'build',
  'coverage', '.venv', '__pycache__', 'target', '.next', '.nuxt',
  '.cache', 'vendor',
]);

function fail(msg) {
  process.stderr.write(msg + '\n');
  process.exit(1);
}

function listGit(folder) {
  try {
    const out = execSync(`git ls-files -- "${folder}"`, {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    });
    return out.split('\n').filter(Boolean);
  } catch {
    return null;
  }
}

function walk(absDir, baseAbs) {
  const out = [];
  let entries;
  try {
    entries = fs.readdirSync(absDir, { withFileTypes: true });
  } catch {
    return out;
  }
  for (const entry of entries) {
    if (EXCLUDE_DIRS.has(entry.name)) continue;
    const full = path.join(absDir, entry.name);
    if (entry.isDirectory()) {
      out.push(...walk(full, baseAbs));
    } else if (entry.isFile()) {
      out.push(path.relative(baseAbs, full));
    }
  }
  return out;
}

const folder = process.argv[2];
if (!folder) fail('usage: walk-and-filter <folder>');
if (!fs.existsSync(folder)) fail(`folder not found: ${folder}`);

const cwd = process.cwd();
let all = listGit(folder);
if (all === null) {
  all = walk(path.resolve(folder), cwd);
}

const files = [];
const skipped_binary = [];
const skipped_lock = [];
const skipped_minified = [];
const by_ext = {};

for (const f of all) {
  const base = path.basename(f);
  const ext = path.extname(f).toLowerCase();
  if (BINARY_EXTS.has(ext)) { skipped_binary.push(f); continue; }
  if (LOCKFILES.has(base)) { skipped_lock.push(f); continue; }
  if (MINIFIED_RE.test(f)) { skipped_minified.push(f); continue; }
  files.push(f);
  const key = ext || '(no-ext)';
  by_ext[key] = (by_ext[key] || 0) + 1;
}

process.stdout.write(JSON.stringify({
  total: all.length,
  files,
  skipped_binary,
  skipped_lock,
  skipped_minified,
  by_ext,
}, null, 2) + '\n');
