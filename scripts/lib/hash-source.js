#!/usr/bin/env node
'use strict';
//
// hash-source <path>
//
// Returns a content hash of <path>. Prefers `git hash-object` (so .brain
// hashes match git's stable object identity, which is what /brain:lint
// compares against). Falls back to sha256 when git is unavailable.
//
// Output (stdout): JSON { hash, prefix, formatted }
//   prefix: "git" | "sha256"
//   formatted: "<prefix>:<hash>"  — the form persisted in page frontmatter
//
// Exit codes: 0 on success, 1 on usage / file-not-found / both hashers failed.
//
// Replaces a single Bash sequence in /brain:ingest Step 3, but bundling it
// into a named helper makes the slash-command body a 1-liner.

const fs = require('fs');
const { execSync } = require('child_process');

const p = process.argv[2];
if (!p) {
  process.stderr.write('usage: hash-source <path>\n');
  process.exit(1);
}
if (!fs.existsSync(p)) {
  process.stderr.write(`not found: ${p}\n`);
  process.exit(1);
}

let hash, prefix;
try {
  hash = execSync(`git hash-object "${p}"`, {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'ignore'],
  }).trim();
  prefix = 'git';
} catch {
  try {
    const raw = execSync(`shasum -a 256 "${p}"`, {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
    hash = raw.split(/\s+/)[0];
    prefix = 'sha256';
  } catch {
    process.stderr.write(`could not hash ${p}: neither git nor shasum available\n`);
    process.exit(1);
  }
}

process.stdout.write(JSON.stringify({
  hash,
  prefix,
  formatted: `${prefix}:${hash}`,
}) + '\n');
