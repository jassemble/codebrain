#!/usr/bin/env node
// graphbrain observe — PreToolUse hook for the continuous-learning observer (M#7)
//
// Fires before every tool call when /brain learn is toggled `on` for the
// current project. Appends a MINIMAL observation record to the XDG store:
//   { ts, tool, path?, status }
//
// Privacy by design:
//   - NEVER captures tool output
//   - NEVER captures user prompts
//   - NEVER captures file content
//   - NEVER captures stderr/stdout
//   - Only the four fields above; whitelist-enforced in lib/observations
//
// Contract:
//   - Reads stdin JSON (Claude Code hook payload)
//   - Async, fast (<100ms)
//   - Always exits 0 — observations must never block tool execution
//   - Silently no-ops if .brain/.graphbrain-learn-state is missing OR set to "off"
//   - Silently no-ops if cwd has no .brain/ at all (per M#4 D7 — works safely in every repo)

'use strict';

const fs = require('fs');
const path = require('path');
const obs = require(path.join(__dirname, 'lib', 'observations.js'));

function safe(fn) {
  try {
    return fn();
  } catch (e) {
    process.stderr.write(`[graphbrain] observe error: ${e.message}\n`);
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
    setTimeout(() => resolve(data), 8000);
  });
}

function extractFilePath(payload) {
  if (!payload || typeof payload !== 'object') return null;
  const ti = payload.tool_input || payload.toolInput || payload;
  return ti.file_path || ti.filePath || ti.path || ti.target || null;
}

function extractToolName(payload) {
  if (!payload || typeof payload !== 'object') return 'unknown';
  return payload.tool_name || payload.toolName || payload.tool || 'unknown';
}

async function main() {
  const cwd = process.cwd();

  // Fast bail-out 1: no .brain/ → not a graphbrain project → exit 0 silently
  if (!fs.existsSync(path.join(cwd, '.brain'))) {
    process.exit(0);
  }

  // Fast bail-out 2: toggle is off or missing → exit 0 silently
  const state = safe(() => obs.learnToggleState(cwd));
  if (state !== 'on') {
    process.exit(0);
  }

  // Read the hook payload
  const stdinRaw = await readStdin();
  let payload = null;
  if (stdinRaw && stdinRaw.trim()) {
    payload = safe(() => JSON.parse(stdinRaw));
  }
  if (!payload) {
    process.exit(0);
  }

  const record = {
    ts: Date.now(),
    tool: extractToolName(payload),
    path: extractFilePath(payload),
    status: 'ok',
  };

  // Privacy guard (belt-and-suspenders — lib/observations also whitelists):
  // strip the path if it looks like an absolute system path outside cwd
  if (record.path && path.isAbsolute(record.path)) {
    const rel = path.relative(cwd, record.path);
    if (rel.startsWith('..') || path.isAbsolute(rel)) {
      record.path = null;
    } else {
      record.path = rel;
    }
  }

  safe(() => obs.appendObservation(cwd, record));

  process.exit(0);
}

main().catch(() => process.exit(0));
