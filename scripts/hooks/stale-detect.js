#!/usr/bin/env node
// codebrain stale-detect — PostToolUse hook
//
// Fires after every Edit / Write / MultiEdit tool call. If the edited file
// is a tracked source (has a corresponding .brain/code/<path>.md page), flips
// that page to status: STALE. Then walks all .brain/**/*.md pages to find
// concept pages with wikilinks or sources: entries referencing the edited
// path; flips matching pages STALE too. This is tier 1 of the 4-tier
// staleness model (PRD design decision #10).
//
// Contract:
//   - Reads tool-call payload from stdin (Claude Code hook protocol — JSON).
//   - Always exits 0. Hooks must never block tool execution.
//   - Errors logged to stderr with [codebrain] prefix; never stdout.
//   - Silently no-ops if cwd has no .brain/ (per sweep finding D7).

'use strict';

const path = require('path');
const pageIo = require(path.join(__dirname, 'lib', 'page-io.js'));

function safe(fn) {
  try {
    return fn();
  } catch (e) {
    process.stderr.write(`[codebrain] stale-detect error: ${e.message}\n`);
    return null;
  }
}

function readStdin() {
  return new Promise(resolve => {
    let data = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', chunk => { data += chunk; });
    process.stdin.on('end', () => resolve(data));
    // If stdin is a TTY (no piped input), resolve immediately
    if (process.stdin.isTTY) resolve('');
    // Belt-and-suspenders timeout — never hang
    setTimeout(() => resolve(data), 8000);
  });
}

function extractFilePath(payload) {
  // Be defensive about field names — Claude Code's hook protocol varies
  // across tool shapes (Edit, Write, MultiEdit). Try common shapes.
  if (!payload || typeof payload !== 'object') return null;
  const ti = payload.tool_input || payload.toolInput || payload;
  return ti.file_path || ti.filePath || ti.path || ti.target || null;
}

async function main() {
  const stdinRaw = await readStdin();
  let payload = null;
  if (stdinRaw && stdinRaw.trim()) {
    payload = safe(() => JSON.parse(stdinRaw));
  }
  if (!payload) {
    // No payload or unparseable — exit silently per D4
    process.exit(0);
  }

  const filePath = extractFilePath(payload);
  if (!filePath || typeof filePath !== 'string') {
    process.exit(0);
  }

  const cwd = process.cwd();
  const brainRoot = pageIo.findBrainRoot(cwd);
  if (!brainRoot) {
    // No codebrain in this repo — exit silently per D7
    process.exit(0);
  }

  // Resolve the edited file path against cwd; if it's absolute and inside
  // cwd, derive the relative path. If it's outside cwd, nothing to do.
  const absEdited = path.isAbsolute(filePath) ? filePath : path.resolve(cwd, filePath);
  const relEdited = path.relative(cwd, absEdited);
  if (relEdited.startsWith('..') || path.isAbsolute(relEdited)) {
    // Edited file is outside cwd; can't be a tracked source
    process.exit(0);
  }

  // Skip if the edited file is INSIDE .brain/ itself (no self-tracking)
  if (relEdited.startsWith('.brain' + path.sep) || relEdited === '.brain') {
    process.exit(0);
  }

  const flipped = [];

  // (1) Flip the mirrored code page if it exists
  const codePagePath = path.join(brainRoot, 'code', relEdited + '.md');
  if (safe(() => pageIo.flipToStale(codePagePath, `source edited: ${relEdited}`))) {
    flipped.push(codePagePath);
  }

  // (2) Walk all .brain/ pages; flip any that reference the edited path
  //     via wikilink in body OR via sources: array entry in frontmatter
  const referencing = safe(() => pageIo.findReferencingPages(brainRoot, relEdited)) || [];
  for (const ref of referencing) {
    if (ref === codePagePath) continue; // already flipped above
    if (safe(() => pageIo.flipToStale(ref, `referenced source edited: ${relEdited}`))) {
      flipped.push(ref);
    }
  }

  // Non-blocking: never write to stdout (hook channel). If there's something
  // to report, write to stderr with the [codebrain] prefix so it's visible
  // in tool-call logs but doesn't interfere with Claude Code's tool flow.
  if (flipped.length > 0) {
    process.stderr.write(`[codebrain] stale-detect: flipped ${flipped.length} page(s) STALE for edit of ${relEdited}\n`);
  }

  process.exit(0);
}

main().catch(() => process.exit(0));
