// Shared helpers for the continuous-learning observer (Milestone #7).
// Single source of truth for: per-project hash, XDG path resolution,
// learn-toggle state file, and atomic append/read for the two jsonl
// stores (observations.jsonl, instincts.jsonl).
//
// Used by:
//   scripts/hooks/observe.js              (writes observations)
//   agents/observers/observer.md          (reads observations, writes instincts)
//   commands/brain.md learn procedure     (reads toggle, writes toggle, reads counts)
//
// Privacy by design: callers pass in only what they want recorded; this
// module does not extract or transform any data beyond what the caller
// provides. NEVER captures tool output, prompts, or file content.

'use strict';

const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');
const { execSync } = require('child_process');

const TOGGLE_FILENAME = '.codebrain-learn-state';
const OBS_FILENAME = 'observations.jsonl';
const INST_FILENAME = 'instincts.jsonl';

// --- Project hash (same scheme as ECC v2.1) ---------------------------------

function projectHash(cwd) {
  let basis;
  try {
    basis = execSync('git remote get-url origin', { cwd, stdio: ['pipe', 'pipe', 'ignore'] })
      .toString().trim();
    if (!basis) basis = cwd;
  } catch {
    basis = cwd;
  }
  return crypto.createHash('sha256').update(basis).digest('hex').slice(0, 12);
}

// --- XDG path resolution ----------------------------------------------------

function xdgDataHome() {
  return process.env.XDG_DATA_HOME || path.join(os.homedir(), '.local', 'share');
}

function xdgProjectDir(cwd) {
  const dir = path.join(xdgDataHome(), 'codebrain', 'projects', projectHash(cwd));
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

function observationsPath(cwd) {
  return path.join(xdgProjectDir(cwd), OBS_FILENAME);
}

function instinctsPath(cwd) {
  return path.join(xdgProjectDir(cwd), INST_FILENAME);
}

// --- Toggle state -----------------------------------------------------------

function toggleFilePath(cwd) {
  return path.join(cwd, '.brain', TOGGLE_FILENAME);
}

function learnToggleState(cwd) {
  const f = toggleFilePath(cwd);
  if (!fs.existsSync(f)) return 'missing';
  const raw = fs.readFileSync(f, 'utf8').trim();
  if (raw === 'on') return 'on';
  if (raw === 'off') return 'off';
  return 'missing';
}

function setLearnState(cwd, state) {
  if (state !== 'on' && state !== 'off') {
    throw new Error(`invalid toggle state: ${state}`);
  }
  const f = toggleFilePath(cwd);
  // Atomic write mirroring lib/page-io
  fs.mkdirSync(path.dirname(f), { recursive: true });
  const tmp = `${f}.tmp`;
  const fd = fs.openSync(tmp, 'w');
  try {
    fs.writeSync(fd, state + '\n');
    fs.fsyncSync(fd);
  } finally {
    fs.closeSync(fd);
  }
  fs.renameSync(tmp, f);
}

// --- jsonl I/O --------------------------------------------------------------

function appendJsonl(filePath, record) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  const line = JSON.stringify(record) + '\n';
  // Append-only — no temp+rename. fs.appendFileSync is atomic enough
  // for line-by-line records on POSIX (kernel write of short bytes is
  // atomic up to PIPE_BUF / 4096 bytes; jsonl records are well under).
  fs.appendFileSync(filePath, line);
}

function readJsonl(filePath) {
  if (!fs.existsSync(filePath)) return [];
  const raw = fs.readFileSync(filePath, 'utf8');
  const out = [];
  for (const line of raw.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    try {
      out.push(JSON.parse(trimmed));
    } catch {
      // Skip malformed lines — never crash on bad data
    }
  }
  return out;
}

// --- Observation + instinct convenience -------------------------------------

function appendObservation(cwd, record) {
  // Whitelist allowed fields — defense in depth against accidental PII capture
  const safe = {
    ts: record.ts || Date.now(),
    tool: typeof record.tool === 'string' ? record.tool : 'unknown',
    path: typeof record.path === 'string' ? record.path : null,
    status: record.status === undefined ? 'ok' : record.status,
  };
  appendJsonl(observationsPath(cwd), safe);
}

function readObservations(cwd) {
  return readJsonl(observationsPath(cwd));
}

function appendInstinct(cwd, instinct) {
  const safe = {
    id: instinct.id,
    pattern: instinct.pattern,
    frequency: instinct.frequency,
    confidence: instinct.confidence,
    first_seen: instinct.first_seen,
    last_seen: instinct.last_seen,
  };
  appendJsonl(instinctsPath(cwd), safe);
}

function readInstincts(cwd) {
  return readJsonl(instinctsPath(cwd));
}

module.exports = {
  projectHash,
  xdgDataHome,
  xdgProjectDir,
  observationsPath,
  instinctsPath,
  toggleFilePath,
  learnToggleState,
  setLearnState,
  appendObservation,
  readObservations,
  appendInstinct,
  readInstincts,
};
