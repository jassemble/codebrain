#!/usr/bin/env node
'use strict';
//
// walk-imports <code-page-path>
//
// Given a `.brain/code/<source-path>.md` page, parses its `## Imports`
// section, resolves relative paths against the original source file's
// directory, and returns the subset whose import target is itself a
// tracked code page in `.brain/code/`.
//
// This is the **transitive-dependency walker** for the linker (v1.0.14).
// The linker uses the output to populate a concept page's `sources:`
// array with not just the primary cited sources but also the in-vault
// files those sources import from. Without this, the staleness hook
// can't propagate edits through concept pages that talk about a
// feature but don't directly wikilink every underlying file.
//
// Page Imports section format (graphbrain convention):
//
//   ## Imports
//   - from `<path>`: `<symbol>, <symbol>` — comment
//   - from `<path>`: `<symbol>` — comment
//   ...
//
// Where `<path>` is either:
//   - external package: `@nestjs/common`, `react`, `lodash`   (skipped)
//   - relative module: `./streak-bonus`, `../shared/week`     (resolved)
//
// Output (stdout): JSON
//   {
//     source: "<source-path of the code page>",
//     transitive: [
//       {
//         source_path: "server/src/modules/workers/streak-bonus.ts",
//         brain_page_path: ".brain/code/server/src/modules/workers/streak-bonus.ts.md",
//         hash: "git:<...>"  // or "sha256:<...>"
//       }
//     ],
//     unresolved: ["./missing-module", ...]   // relative paths that couldn't be mapped
//   }
//
// Exit codes: 0 on success (even if transitive is empty), 1 on usage / page missing.

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const RESOLVE_EXTS = ['.ts', '.tsx', '.js', '.jsx', '.mjs', '.cjs', '.py', '.go', '.rs', '.rb', '.java'];

function fail(msg) {
  process.stderr.write(msg + '\n');
  process.exit(1);
}

const pagePathArg = process.argv[2];
if (!pagePathArg) fail('usage: walk-imports <code-page-path>');
if (!fs.existsSync(pagePathArg)) fail(`page not found: ${pagePathArg}`);

const cwd = process.cwd();
const pageAbs = path.resolve(pagePathArg);
const pageContent = fs.readFileSync(pageAbs, 'utf8');

// Find frontmatter `source:` field — that's the canonical source path the page mirrors.
const fmMatch = pageContent.match(/^---\n([\s\S]*?)\n---\n/);
if (!fmMatch) fail(`page has no YAML frontmatter: ${pagePathArg}`);
const fm = fmMatch[1];
const sourceMatch = fm.match(/^source:\s*(.+)$/m);
if (!sourceMatch) fail(`page frontmatter missing source: field: ${pagePathArg}`);
const sourceRel = sourceMatch[1].trim();
const sourceAbs = path.resolve(cwd, sourceRel);
const sourceDir = path.dirname(sourceAbs);

// Extract Imports section.
const importsSection = pageContent.match(/\n## Imports\n([\s\S]*?)(?:\n## |\n*$)/);
const importsBody = importsSection ? importsSection[1] : '';

// Pull every backtick-quoted path-looking string out of the section. The
// page format puts paths in backticks; the LLM's exact prose varies, so
// we don't require a strict `- from \`<path>\`:` shape. We just collect
// every backticked token and filter for relative-path shape afterward.
const backtickRe = /`([^`\n]+)`/g;
const candidates = new Set();
let m;
while ((m = backtickRe.exec(importsBody)) !== null) {
  candidates.add(m[1]);
}

// Find the .brain/code/ root (caller's vault).
function findBrainRoot(fromAbs) {
  let dir = fromAbs;
  while (dir !== path.dirname(dir)) {
    const candidate = path.join(dir, '.brain');
    if (fs.existsSync(candidate) && fs.statSync(candidate).isDirectory()) {
      return candidate;
    }
    dir = path.dirname(dir);
  }
  return null;
}
const brainRoot = findBrainRoot(pageAbs);
if (!brainRoot) fail(`could not locate .brain/ from ${pageAbs}`);
const codeRoot = path.join(brainRoot, 'code');
const vaultRoot = path.dirname(brainRoot); // the project root (cwd of operator)

function tryResolveExt(absNoExt) {
  if (fs.existsSync(absNoExt) && fs.statSync(absNoExt).isFile()) {
    return absNoExt;
  }
  for (const ext of RESOLVE_EXTS) {
    const withExt = absNoExt + ext;
    if (fs.existsSync(withExt) && fs.statSync(withExt).isFile()) return withExt;
  }
  // Try index.<ext>
  if (fs.existsSync(absNoExt) && fs.statSync(absNoExt).isDirectory()) {
    for (const ext of RESOLVE_EXTS) {
      const idx = path.join(absNoExt, 'index' + ext);
      if (fs.existsSync(idx) && fs.statSync(idx).isFile()) return idx;
    }
  }
  return null;
}

function hashSource(absPath) {
  try {
    const h = execSync(`git hash-object "${absPath}"`, {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
    return `git:${h}`;
  } catch {
    try {
      const raw = execSync(`shasum -a 256 "${absPath}"`, {
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'ignore'],
      }).trim();
      return `sha256:${raw.split(/\s+/)[0]}`;
    } catch {
      return null;
    }
  }
}

const transitive = [];
const unresolved = [];
const seen = new Set();

for (const candidate of candidates) {
  // Only relative paths are tracked; external packages skip silently.
  if (!candidate.startsWith('./') && !candidate.startsWith('../')) continue;

  const resolvedNoExt = path.resolve(sourceDir, candidate);
  const sourceAbsHit = tryResolveExt(resolvedNoExt);
  if (!sourceAbsHit) {
    unresolved.push(candidate);
    continue;
  }

  // Map back to .brain/code/<rel-from-vault>.md
  const sourceRelFromVault = path.relative(vaultRoot, sourceAbsHit);
  if (sourceRelFromVault.startsWith('..')) {
    unresolved.push(candidate);
    continue;
  }
  const brainPageAbs = path.join(codeRoot, sourceRelFromVault + '.md');
  if (!fs.existsSync(brainPageAbs)) {
    // Source resolved but no brain page for it — operator hasn't ingested it yet.
    unresolved.push(candidate);
    continue;
  }

  if (seen.has(sourceRelFromVault)) continue;
  seen.add(sourceRelFromVault);

  const hash = hashSource(sourceAbsHit);
  transitive.push({
    source_path: sourceRelFromVault,
    brain_page_path: path.relative(vaultRoot, brainPageAbs),
    hash,
  });
}

process.stdout.write(JSON.stringify({
  source: sourceRel,
  transitive,
  unresolved,
}, null, 2) + '\n');
