// graphbrain init — scaffold .brain/ + wire slash commands and hooks into .claude/.
//
// Load-bearing for Milestone #1. Respect these contracts:
//   - PRD #28: npm-only distribution; this script is the install path.
//   - PRD #31: project-local default; --global opts into ~/.claude/.
//   - PRD #32: hooks ownership via `id:` prefix `graphbrain:*`.
//             Partition existing entries; replace own; preserve others.
//   - PRD #33: ship `.brain/.graphbrain-version` so upgrade detection works.
//   - Idempotent: re-running with the same version produces no diff.
//   - Atomic-write: temp + fsync + rename; .bak before destructive edit.
//   - Project-dir guard: refuse to run in random cwd without --global.

'use strict';

const fs = require('fs');
const path = require('path');
const os = require('os');

const pkg = require(path.join(__dirname, '..', 'package.json'));
const CODEBRAIN_VERSION = pkg.version;
const ROOT = path.join(__dirname, '..');

const VERSION_MARKER = `<!-- graphbrain v${CODEBRAIN_VERSION} -->`;
const CLAUDE_MD_BEGIN = '<!-- graphbrain:begin -->';
const CLAUDE_MD_END = '<!-- graphbrain:end -->';

const PROJECT_SIGNALS = ['.git', 'package.json', 'pyproject.toml', 'go.mod', 'Cargo.toml'];

function parseFlags(argv) {
  return {
    global: argv.includes('--global'),
    force: argv.includes('--force'),
    dryRun: argv.includes('--dry-run'),
    help: argv.includes('--help') || argv.includes('-h'),
  };
}

function printInitHelp() {
  console.log(`graphbrain init — scaffold .brain/ + wire /brain commands and hooks

Usage:
  graphbrain init                   Project-local install in the current repo
  graphbrain init --global          Write to ~/.claude/ instead of <cwd>/.claude/
  graphbrain init --force           Overwrite existing files (still writes .bak)
  graphbrain init --dry-run         Print plan, write nothing

Default mode requires the cwd to look like a project (one of: .git/, package.json,
pyproject.toml, go.mod, Cargo.toml). Use --global to install slash commands and
hooks globally; .brain/ is always written to cwd because the vault is per-repo.`);
}

function isProjectDir(cwd) {
  return PROJECT_SIGNALS.some(s => fs.existsSync(path.join(cwd, s)));
}

const report = {
  ok: 0, skip: 0, warn: 0, fail: 0,
  log(kind, file, note) {
    this[kind.toLowerCase()]++;
    const prefix = kind.padEnd(4);
    console.log(`  ${prefix} ${file}${note ? ` (${note})` : ''}`);
  },
};

// --- Atomic write helpers ---------------------------------------------------

function atomicWrite(target, content, opts) {
  // PRD: write `.bak` if target exists; write to .tmp; fsync; rename.
  // On --dry-run, log intent and return.
  const dryRun = opts && opts.dryRun;
  if (dryRun) return;

  if (fs.existsSync(target)) {
    const bak = `${target}.bak`;
    fs.copyFileSync(target, bak);
  }

  const tmp = `${target}.tmp`;
  const fd = fs.openSync(tmp, 'w');
  try {
    fs.writeSync(fd, content);
    fs.fsyncSync(fd);
  } finally {
    fs.closeSync(fd);
  }
  fs.renameSync(tmp, target);
}

function ensureDir(p, opts) {
  if (opts && opts.dryRun) return;
  fs.mkdirSync(p, { recursive: true });
}

function readJsonOrEmpty(target) {
  if (!fs.existsSync(target)) return {};
  const raw = fs.readFileSync(target, 'utf8').trim();
  if (raw === '') return {};
  return JSON.parse(raw); // throws on malformed — caller decides what to do
}

// --- Operations -------------------------------------------------------------

function copyTemplate(srcRel, destAbs, opts) {
  const src = path.join(ROOT, srcRel);
  const content = fs.readFileSync(src, 'utf8');
  if (fs.existsSync(destAbs)) {
    if (!opts.force && fs.readFileSync(destAbs, 'utf8') === content) {
      report.log('SKIP', destAbs, 'already current');
      return;
    }
  }
  atomicWrite(destAbs, content, opts);
  report.log('OK', destAbs);
}

// Recursively copy a directory of templates. Used by M#12 to ship the
// per-verb slash-command files under commands/brain/ and commands/graphbrain/.
// Atomicity, .bak, and idempotency are inherited from copyTemplate — one
// atomic write per file. Subdirectories are mkdir'd before each file write.
function copyDir(srcRel, destAbs, opts) {
  const srcAbs = path.join(ROOT, srcRel);
  if (!fs.existsSync(srcAbs)) {
    report.log('FAIL', srcAbs, 'source directory missing');
    return;
  }
  ensureDir(destAbs, opts);
  for (const entry of fs.readdirSync(srcAbs, { withFileTypes: true })) {
    const childSrcRel = path.join(srcRel, entry.name);
    const childDest = path.join(destAbs, entry.name);
    if (entry.isDirectory()) {
      copyDir(childSrcRel, childDest, opts);
    } else if (entry.isFile()) {
      copyTemplate(childSrcRel, childDest, opts);
    }
    // symlinks + other types: skip silently — graphbrain templates are plain files
  }
}

function scaffoldBrainDir(cwd, opts) {
  const brain = path.join(cwd, '.brain');
  const dirs = ['code', 'concepts', 'decisions'];

  if (fs.existsSync(brain) && !opts.force) {
    report.log('SKIP', brain, 'exists');
  } else {
    ensureDir(brain, opts);
    report.log('OK', brain);
  }

  for (const d of dirs) {
    const p = path.join(brain, d);
    ensureDir(p, opts);
    const keep = path.join(p, '.keep');
    if (!fs.existsSync(keep)) {
      atomicWrite(keep, '', opts);
    }
  }

  // .graphbrain-version marker — PRD Design Decision #33
  const versionFile = path.join(brain, '.graphbrain-version');
  const versionContent = `${CODEBRAIN_VERSION}\n`;
  if (fs.existsSync(versionFile) && fs.readFileSync(versionFile, 'utf8') === versionContent) {
    report.log('SKIP', versionFile, 'already current');
  } else {
    atomicWrite(versionFile, versionContent, opts);
    report.log('OK', versionFile);
  }

  // Top-level markdown files with minimal valid frontmatter
  const today = new Date().toISOString().slice(0, 10);
  const files = {
    'index.md': frontmatter({ kind: 'index', status: 'UNENRICHED', created: today })
      + '\n# Index\n\nPage catalog. Populated by `/brain:init` and updated on every `/brain:ingest`.\n',
    'log.md': frontmatter({ kind: 'log', status: 'UNENRICHED', created: today })
      + '\n# Log\n\n## Recent Patterns\n\n<!-- Promoted recurring patterns from activity history. -->\n\n## Activity History\n\n<!-- Append-only per-event entries. Format: ## [YYYY-MM-DD] <op> | <subject> -->\n\n'
      + `## [${today}] init | graphbrain v${CODEBRAIN_VERSION} scaffolded .brain/\n`,
    'overview.md': frontmatter({ kind: 'overview', status: 'UNENRICHED', created: today })
      + '\n# Overview\n\n## Project Purpose\n\n## Codebase Structure\n\n## Key Patterns\n\n## Active State\n\n## Recent Activity\n',
    'decisions.md': frontmatter({ kind: 'decisions-index', status: 'UNENRICHED', created: today })
      + '\n# Decisions\n\n## Active Decisions\n\n## Superseded Decisions\n',
    'status.md': frontmatter({ kind: 'status', status: 'UNENRICHED', created: today })
      + '\n# Status — Page Lifecycle Tracker\n\nDerived view; regenerated from per-page frontmatter.\n\n| Page | Status | Last Sync | Source Hash |\n|------|--------|-----------|-------------|\n',
    'CHANGELOG.md': frontmatter({ kind: 'changelog', status: 'UNENRICHED', created: today })
      + `\n# CHANGELOG — what the brain learned\n\n`
      + `Append-only narrative of compound learning. Reverse-chronological by month.\n`
      + `Each entry shape: \`- YYYY-MM-DD: <narrative summary of what changed and why>\`\n`
      + `\n`
      + `## ${today.slice(0, 7)}\n\n`
      + `- ${today}: graphbrain v${CODEBRAIN_VERSION} scaffolded \`.brain/\` in this project.\n`,
    'llms.txt': `# .brain — graphbrain wiki\n`
      + `# llms.txt — agent-readable site map (https://llmstxt.org / AEO convention)\n`
      + `# Last refreshed: ${today}\n`
      + `# graphbrain v${CODEBRAIN_VERSION}\n`
      + `# Pages: 0, estimated tokens: ~0\n`
      + `\n`
      + `> .brain is a folder-mirrored markdown wiki of this codebase, maintained by graphbrain.\n`
      + `> Each page is generated from a real source file (code/), an extracted concept (concepts/),\n`
      + `> or a recorded architectural decision (decisions/). Pages are addressable as wikilinks:\n`
      + `> [[code/<path>]], [[concepts/<slug>]], [[decisions/<adr>]].\n`
      + `\n`
      + `## Top-level\n`
      + `- [overview.md](overview.md) — Project purpose, codebase structure, key patterns, active state\n`
      + `- [index.md](index.md) — Page catalog (code, concepts, decisions)\n`
      + `- [log.md](log.md) — Activity history + promoted recurring patterns\n`
      + `- [status.md](status.md) — Page lifecycle tracker (FRESH/STALE/RESYNCED)\n`
      + `- [decisions.md](decisions.md) — ADR index\n`
      + `- [CHANGELOG.md](CHANGELOG.md) — Compound-learning narrative: what the brain learned, when, why\n`
      + `\n`
      + `## Code pages (0)\n`
      + `_(no pages yet — run \`/brain ingest <file>\` or \`/brain ingest <folder>\`)_\n`
      + `\n`
      + `## Concept pages (0)\n`
      + `_(no pages yet — concepts are auto-extracted by the linker during folder ingest)_\n`
      + `\n`
      + `## Decision pages (0)\n`
      + `_(no pages yet — manually record ADRs under decisions/ as your project evolves)_\n`,
  };

  for (const [name, content] of Object.entries(files)) {
    const target = path.join(brain, name);
    if (fs.existsSync(target) && !opts.force) {
      report.log('SKIP', target, 'exists');
      continue;
    }
    atomicWrite(target, content, opts);
    report.log('OK', target);
  }
}

function frontmatter(fields) {
  const lines = ['---'];
  for (const [k, v] of Object.entries(fields)) {
    lines.push(`${k}: ${v}`);
  }
  lines.push('---');
  return lines.join('\n');
}

function appendClaudeMdManagedRegion(cwd, opts) {
  const target = path.join(cwd, 'CLAUDE.md');
  const block = `${CLAUDE_MD_BEGIN}\n## graphbrain\n\n_This block is a placeholder. Run \`/brain:init\` inside Claude Code to populate it with the full graphbrain schema (~120 lines: what \`.brain/\` is, how to navigate it, what each \`/brain:<verb>\` does). The block is co-evolved by the operator and the agent; edits between the markers above are preserved across \`npx graphbrain init\` runs._\n${CLAUDE_MD_END}\n`;

  if (!fs.existsSync(target)) {
    atomicWrite(target, `# CLAUDE.md\n\n${block}`, opts);
    report.log('OK', target);
    return;
  }

  const existing = fs.readFileSync(target, 'utf8');
  if (existing.includes(CLAUDE_MD_BEGIN)) {
    if (!opts.force) {
      report.log('SKIP', target, 'managed region present');
      return;
    }
    // --force: refresh the managed region in place
    const beginIdx = existing.indexOf(CLAUDE_MD_BEGIN);
    const endIdx = existing.indexOf(CLAUDE_MD_END);
    if (endIdx === -1) {
      report.log('FAIL', target, 'begin marker without end marker — manual fix required');
      return;
    }
    const before = existing.slice(0, beginIdx);
    const after = existing.slice(endIdx + CLAUDE_MD_END.length);
    atomicWrite(target, before + block + after, opts);
    report.log('OK', target, 'refreshed');
    return;
  }

  // Append at end
  const sep = existing.endsWith('\n') ? '\n' : '\n\n';
  atomicWrite(target, existing + sep + block, opts);
  report.log('OK', target, 'appended managed region');
}

function mergeHooks(targetDir, opts) {
  // PRD Design Decision #32: partition existing entries; replace own; preserve others.
  // Milestone #4 populated this with the two hook entries below; entries are keyed
  // by their `id:` field — graphbrain owns only ids starting `graphbrain:`.
  const target = path.join(targetDir, 'settings.local.json');
  const codebrainOwnedHooks = {
    PreToolUse: [
      {
        matcher: 'Edit|Write|MultiEdit',
        hooks: [
          {
            type: 'command',
            command: 'npx graphbrain hook verified-guard',
            timeout: 5,
          },
        ],
        id: 'graphbrain:pre:verified-guard',
        description: 'Block writes to .brain/ pages with status: VERIFIED unless --force is passed',
      },
      {
        matcher: '*',
        hooks: [
          {
            type: 'command',
            command: 'npx graphbrain hook observe',
            async: true,
            timeout: 10,
          },
        ],
        id: 'graphbrain:pre:observe',
        description: 'Continuous-learning observer: append minimal tool-use observations to XDG store when /brain learn is on (opt-in per-project; privacy by design — captures only tool name + path + timestamp, never content)',
      },
    ],
    PostToolUse: [
      {
        matcher: 'Edit|Write|MultiEdit',
        hooks: [
          {
            type: 'command',
            command: 'npx graphbrain hook stale-detect',
            timeout: 10,
          },
        ],
        id: 'graphbrain:post:stale-detect',
        description: 'Mark .brain/ pages STALE when their source file is edited (4-tier staleness model tier 1)',
      },
    ],
  };

  let existing;
  try {
    existing = readJsonOrEmpty(target);
  } catch (e) {
    report.log('FAIL', target, `unparseable JSON — manual fix required (${e.message})`);
    return;
  }

  if (!existing.hooks) existing.hooks = {};
  const phases = ['PreToolUse', 'PostToolUse', 'SessionStart', 'SessionEnd', 'Stop', 'PreCompact', 'UserPromptSubmit'];
  let changed = false;

  for (const phase of phases) {
    const arr = Array.isArray(existing.hooks[phase]) ? existing.hooks[phase] : [];
    const nonCodebrain = arr.filter(e => !(e && typeof e.id === 'string' && e.id.startsWith('graphbrain:')));
    const ours = codebrainOwnedHooks[phase] || [];

    const newArr = nonCodebrain.concat(ours);
    const beforeStr = JSON.stringify(arr);
    const afterStr = JSON.stringify(newArr);
    if (beforeStr !== afterStr) changed = true;

    if (newArr.length === 0) {
      if (existing.hooks[phase] !== undefined) {
        delete existing.hooks[phase];
        changed = true;
      }
    } else {
      existing.hooks[phase] = newArr;
    }
  }

  if (!changed && fs.existsSync(target)) {
    report.log('SKIP', target, 'hooks already current');
    return;
  }

  ensureDir(targetDir, opts);
  atomicWrite(target, JSON.stringify(existing, null, 2) + '\n', opts);
  report.log('OK', target);
}

// --- Main -------------------------------------------------------------------

function init(argv) {
  const opts = parseFlags(argv);
  if (opts.help) {
    printInitHelp();
    return 0;
  }

  const cwd = process.cwd();
  const isGlobal = opts.global;
  const claudeDir = isGlobal ? path.join(os.homedir(), '.claude') : path.join(cwd, '.claude');

  console.log(`graphbrain v${CODEBRAIN_VERSION} — init${opts.dryRun ? ' --dry-run' : ''}${opts.force ? ' --force' : ''}${isGlobal ? ' --global' : ''}`);
  console.log(`  cwd:        ${cwd}`);
  console.log(`  target:     ${claudeDir}`);
  console.log(`  vault:      ${path.join(cwd, '.brain')}\n`);

  // Project-dir guard (Design Decision: refuse in random cwd without --global).
  if (!isGlobal && !isProjectDir(cwd)) {
    console.error(`error: cwd does not look like a project root (no ${PROJECT_SIGNALS.join(', no ')}).`);
    console.error('To install graphbrain commands globally, re-run with --global.');
    console.error('Otherwise, cd into a project repo and re-run.');
    return 1;
  }

  // Claude Code presence soft-check.
  const homeClaude = path.join(os.homedir(), '.claude');
  if (!fs.existsSync(homeClaude)) {
    report.log('WARN', homeClaude, "Claude Code not detected; /brain commands won't work until Claude Code is installed");
  }

  // Create the target .claude/ dir + commands subdir.
  ensureDir(path.join(claudeDir, 'commands'), opts);

  // Copy slash-command templates into target.
  // Top-level dispatcher + per-verb namespaced files (M#12b layout).
  // v0.2: only /brain — the /graphbrain alias was dropped (see v0.2.0 changelog).
  copyTemplate('commands/brain.md', path.join(claudeDir, 'commands', 'brain.md'), opts);
  copyDir('commands/brain', path.join(claudeDir, 'commands', 'brain'), opts);

  // Copy skills + agents into .claude/plugins/graphbrain/ so they're visible
  // in the operator's repo (not buried in node_modules) AND discoverable by
  // Claude Code's plugin convention. Matches the bridge-probe path used by
  // /brain:ingest Step 4b.3 + /brain:spec Sp1 for finding ECC's skills.
  // Operators can edit installed copies; `npx graphbrain init --force` refreshes
  // them (with .bak backups of any local edits).
  copyDir('skills', path.join(claudeDir, 'plugins', 'graphbrain', 'skills'), opts);
  copyDir('agents', path.join(claudeDir, 'plugins', 'graphbrain', 'agents'), opts);

  // Merge hooks into settings.local.json.
  mergeHooks(claudeDir, opts);

  // Scaffold .brain/ in cwd (always cwd, even with --global).
  scaffoldBrainDir(cwd, opts);

  // Append/refresh CLAUDE.md managed region.
  appendClaudeMdManagedRegion(cwd, opts);

  // Summary.
  console.log(`\n${report.ok} OK · ${report.skip} SKIP · ${report.warn} WARN · ${report.fail} FAIL`);

  if (report.fail > 0) {
    return 1;
  }

  if (!opts.dryRun) {
    console.log(`\nDone. Restart Claude Code or open a new session to use /brain commands.`);
    console.log(`Try \`/brain:init\` to populate .brain/overview.md + the CLAUDE.md schema block.`);
    console.log(`\nOr run non-interactively from the shell:`);
    console.log(`  claude -p '/brain:init' --dangerously-skip-permissions`);
    console.log(`(the --dangerously-skip-permissions flag auto-approves the file writes /brain:init needs;`);
    console.log(` only use it for trusted commands like /brain:* and only in repos you control.)`);
  } else {
    console.log(`\nDry run — no files written.`);
  }
  return 0;
}

module.exports = init;
