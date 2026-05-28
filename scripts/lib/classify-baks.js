#!/usr/bin/env node
'use strict';
//
// classify-baks [cwd]
//
// Walks cwd for `*.bak` files left by `npx graphbrain init` upgrades and
// pre-classifies each into structured diff data. The LLM does the final
// classification + action choice from this output — the helper just gives
// it deterministic facts about which lines moved where.
//
// Two safe classes are RESOLVED here (no LLM judgment needed):
//   - identical        — bytes equal; the .bak is pure noise
//   - whitespace-only  — only EOL / trailing-whitespace / final-newline diff
//
// All other diffs get classification: "needs-llm-review" with structured
// fields the LLM can use:
//   {
//     added_in_current: { count, version_only, preview: [first 10 lines] },
//     removed_from_current: { count, version_only, preview: [first 10 lines] },
//   }
// "version_only" means every changed line matched one of the version /
// date / hash patterns — i.e., this is a graphbrain-version-bump diff
// with no semantic content, and the LLM can auto-delete the .bak.
//
// Output (stdout): JSON
//   {
//     count: <total .bak files>,
//     files: [
//       { path, current_exists, bak_exists, classification, version_only, summary, diff?: {...} }
//     ]
//   }
//
// Exit codes: 0 on success (even when count is 0), 1 on usage error.
//
// Replaces ~30 lines of LLM-side procedure in /brain:init Step 1b-A/1b-B.

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const cwd = path.resolve(process.argv[2] || '.');

// Detect via find. Mirror the slash-command body's blocklist.
function listBaks() {
  try {
    const out = execSync(
      `find . -name "*.bak" -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null`,
      { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }
    );
    return out.split('\n').filter(Boolean).map(p => p.replace(/^\.\//, ''));
  } catch {
    return [];
  }
}

const VERSION_PATTERNS = [
  /^\s*$/,                              // blank
  /v?\d+\.\d+\.\d+/,                    // semver anywhere on the line
  /\d{4}-\d{2}-\d{2}/,                  // ISO date
  /git:[a-f0-9]+/i,                     // git hash ref
  /sha256:[a-f0-9]+/i,                  // sha256 ref
  /"version"\s*:\s*"[^"]+"/,            // JSON version field
  /^\s*#?\s*graphbrain v\d+\.\d+\.\d+/, // graphbrain header line
];

function isVersionOnly(lines) {
  if (lines.length === 0) return true;
  return lines.every(l => VERSION_PATTERNS.some(re => re.test(l)));
}

function classifyOne(bakRel) {
  const bakAbs = path.join(cwd, bakRel);
  const currentRel = bakRel.replace(/\.bak$/, '');
  const currentAbs = path.join(cwd, currentRel);

  const current_exists = fs.existsSync(currentAbs);
  const bak_exists = fs.existsSync(bakAbs);

  if (!bak_exists) {
    return { path: currentRel, current_exists, bak_exists, classification: 'no-bak', summary: 'no .bak file' };
  }
  if (!current_exists) {
    return {
      path: currentRel, current_exists, bak_exists,
      classification: 'orphaned',
      summary: 'current file missing; .bak is orphaned',
    };
  }

  const cur = fs.readFileSync(currentAbs, 'utf8');
  const old = fs.readFileSync(bakAbs, 'utf8');

  if (cur === old) {
    return {
      path: currentRel, current_exists, bak_exists,
      classification: 'identical',
      version_only: true,
      summary: 'byte-identical',
    };
  }
  if (cur.replace(/\s+/g, '') === old.replace(/\s+/g, '')) {
    return {
      path: currentRel, current_exists, bak_exists,
      classification: 'whitespace-only',
      version_only: true,
      summary: 'whitespace / EOL / final-newline differences only',
    };
  }

  const curLines = cur.split('\n');
  const oldLines = old.split('\n');
  const curSet = new Set(curLines);
  const oldSet = new Set(oldLines);

  // added_in_current  = lines graphbrain just wrote that weren't there before
  // removed_from_current = lines from the .bak (pre-write) that aren't in current
  //                        — these are the operator's "additions" we'd preserve
  const added_in_current = curLines.filter(l => !oldSet.has(l));
  const removed_from_current = oldLines.filter(l => !curSet.has(l));

  const addedVO = isVersionOnly(added_in_current);
  const removedVO = isVersionOnly(removed_from_current);

  return {
    path: currentRel, current_exists, bak_exists,
    classification: 'needs-llm-review',
    version_only: addedVO && removedVO,
    summary:
      addedVO && removedVO
        ? 'version-stamp / date / hash differences only — no semantic content at risk'
        : `${removed_from_current.length} operator line(s), ${added_in_current.length} graphbrain line(s) changed`,
    diff: {
      added_in_current: {
        count: added_in_current.length,
        version_only: addedVO,
        preview: added_in_current.slice(0, 10),
      },
      removed_from_current: {
        count: removed_from_current.length,
        version_only: removedVO,
        preview: removed_from_current.slice(0, 10),
      },
    },
  };
}

const bakList = listBaks();
const files = bakList.map(classifyOne);

process.stdout.write(JSON.stringify({
  count: files.length,
  files,
}, null, 2) + '\n');
