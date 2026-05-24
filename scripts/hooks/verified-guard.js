#!/usr/bin/env node
// codebrain verified-guard — PreToolUse hook
//
// Fires before every Edit / Write / MultiEdit tool call. If the target
// is a page under .brain/ with status: VERIFIED in its frontmatter AND
// the tool input does not contain --force, the hook blocks the operation
// (exit code 2 per Claude Code hook convention). This is the structural
// layer of codebrain's dual-layer guardrail model (PRD design decision #19).
//
// Contract:
//   - Reads tool-call payload from stdin (JSON).
//   - Exits 0 if the action is allowed.
//   - Exits 2 if blocked — Claude Code will refuse the tool call.
//   - Errors logged to stderr with [codebrain] prefix; exits 0 on error
//     (fail-open: a buggy guard should not block legitimate work).

'use strict';

const fs = require('fs');
const path = require('path');
const pageIo = require(path.join(__dirname, 'lib', 'page-io.js'));

function safe(fn) {
  try {
    return fn();
  } catch (e) {
    process.stderr.write(`[codebrain] verified-guard error: ${e.message}\n`);
    return null;
  }
}

function readStdin() {
  return new Promise(resolve => {
    let data = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', chunk => { data += chunk; });
    process.stdin.on('end', () => resolve(data));
    if (process.stdin.isTTY) resolve('');
    setTimeout(() => resolve(data), 5000);
  });
}

function extractFilePath(payload) {
  if (!payload || typeof payload !== 'object') return null;
  const ti = payload.tool_input || payload.toolInput || payload;
  return ti.file_path || ti.filePath || ti.path || ti.target || null;
}

function hasForceFlag(payload) {
  // Operator can pass --force in the slash-command arguments or in the
  // tool input itself. Check both layers defensively.
  if (!payload) return false;
  const stringified = safe(() => JSON.stringify(payload)) || '';
  return stringified.includes('--force');
}

async function main() {
  const stdinRaw = await readStdin();
  let payload = null;
  if (stdinRaw && stdinRaw.trim()) {
    payload = safe(() => JSON.parse(stdinRaw));
  }
  if (!payload) {
    // No payload — exit 0 (fail-open)
    process.exit(0);
  }

  const filePath = extractFilePath(payload);
  if (!filePath || typeof filePath !== 'string') {
    process.exit(0);
  }

  const cwd = process.cwd();
  const absTarget = path.isAbsolute(filePath) ? filePath : path.resolve(cwd, filePath);
  const relTarget = path.relative(cwd, absTarget);

  // Only guard files inside .brain/
  if (!relTarget.startsWith('.brain' + path.sep)) {
    process.exit(0);
  }

  // Target doesn't exist yet → not a guarded file (new page)
  if (!fs.existsSync(absTarget)) {
    process.exit(0);
  }

  const page = safe(() => pageIo.readPage(absTarget));
  if (!page) {
    // No frontmatter → not a guarded file
    process.exit(0);
  }

  if (page.frontmatter.status !== 'VERIFIED') {
    process.exit(0);
  }

  // status: VERIFIED. Check for --force.
  if (hasForceFlag(payload)) {
    process.exit(0);
  }

  // Block.
  process.stderr.write(
    `[codebrain] BLOCKED: refusing to overwrite VERIFIED page ${relTarget}.\n` +
    `  The operator has stamped this page as VERIFIED.\n` +
    `  To override, re-run the operation with --force in the command/argument.\n`
  );
  process.exit(2);
}

main().catch(() => process.exit(0));
