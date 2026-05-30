#!/usr/bin/env node
// graphbrain auto-refresh-prompt — UserPromptSubmit hook (v1.0.15)
//
// Fires at the start of every user prompt. Reads `.brain/.refresh-queue` —
// a list of source paths that the PostToolUse stale-detect hook recorded
// as having been edited since the last user turn. If the queue is non-empty
// AND the per-project auto-refresh toggle is on (default: on), prepends a
// short directive to the user's prompt telling Claude to refresh those
// pages via /brain:ingest BEFORE answering. Drains the queue.
//
// User-facing effect: between turns, the wiki refreshes seamlessly. The
// operator's next interaction with Claude finds .brain/ already current.
//
// Contract:
//   - Reads { prompt, ... } payload from stdin (Claude Code hook protocol).
//   - Always exits 0. Hooks must never block prompt submission.
//   - Errors silent (operator-visible noise would be worse than missed refresh).
//   - Outputs JSON `{ "additionalContext": "<directive>" }` when injection
//     applies — Claude Code's documented contract for UserPromptSubmit hooks.
//   - Silently no-ops if cwd has no .brain/ or the toggle is off.

'use strict';

const fs = require('fs');
const path = require('path');
const pageIo = require(path.join(__dirname, 'lib', 'page-io.js'));

function safe(fn) {
  try { return fn(); } catch { return null; }
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

function isToggleOn(brainRoot) {
  // .brain/.graphbrain-auto-refresh-state holds one of: "on", "off".
  // Missing or unreadable → default to "on" (v1.0.15 ships auto-refresh
  // enabled by default per the operator's explicit preference).
  const statePath = path.join(brainRoot, '.graphbrain-auto-refresh-state');
  let raw;
  try { raw = fs.readFileSync(statePath, 'utf8'); } catch { return true; }
  const trimmed = (raw || '').trim().toLowerCase();
  if (trimmed === 'off') return false;
  return true;
}

async function main() {
  // Always read+ack stdin so we don't leave the hook channel hanging.
  await readStdin();

  const cwd = process.cwd();
  const brainRoot = pageIo.findBrainRoot(cwd);
  if (!brainRoot) process.exit(0); // not a graphbrain project — pass-through

  if (!isToggleOn(brainRoot)) process.exit(0); // operator opted out

  const queuePath = path.join(brainRoot, '.refresh-queue');
  let raw;
  try { raw = fs.readFileSync(queuePath, 'utf8'); } catch { process.exit(0); }
  const paths = raw.split('\n').map(l => l.trim()).filter(Boolean);
  if (paths.length === 0) process.exit(0);

  // Drain the queue eagerly. If injection fails downstream, we don't want
  // to inject the same set again on the next prompt — that would compound.
  safe(() => fs.unlinkSync(queuePath));

  // Cap the listed paths in the directive to avoid hijacking long prompts.
  const MAX_LISTED = 12;
  const listed = paths.slice(0, MAX_LISTED);
  const overflow = paths.length - listed.length;

  const directive =
    `[graphbrain auto-refresh — ${paths.length} source file(s) edited since your last turn]\n` +
    `\n` +
    `Before responding to the user's request, refresh the wiki pages that mirror these sources:\n` +
    listed.map(p => `  - ${p}`).join('\n') +
    (overflow > 0 ? `\n  - … +${overflow} more (see .brain/code/ for the full set)` : '') +
    `\n\n` +
    `Run \`/brain:ingest\` on each path (single-file mode). For ≥3 paths under the same\n` +
    `directory, prefer the folder form: \`/brain:ingest <common-folder>\`. This refresh\n` +
    `is part of the auto-refresh contract — finish it, then proceed with the user's\n` +
    `actual request below. Skip the refresh only if the user's prompt explicitly says\n` +
    `to (e.g., "ignore the wiki" / "don't refresh"). The operator can disable this\n` +
    `mechanism per-project via \`/brain:learn auto-refresh off\`.\n`;

  // Claude Code UserPromptSubmit hook protocol: emit JSON with the field
  // `additionalContext` (or `hookSpecificOutput` containing it, depending
  // on Claude Code version). We emit both wrapper shapes for compatibility.
  const payload = {
    hookSpecificOutput: {
      hookEventName: 'UserPromptSubmit',
      additionalContext: directive,
    },
    additionalContext: directive,
  };
  process.stdout.write(JSON.stringify(payload));
  process.exit(0);
}

main().catch(() => process.exit(0));
