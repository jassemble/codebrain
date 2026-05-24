// codebrain init — scaffold .brain/ + wire slash commands and hooks into .claude/.
//
// Load-bearing for Milestone #1. Respect these contracts:
//   - PRD #28: npm-only distribution; this script is the install path.
//   - PRD #31: project-local default; --global opts into ~/.claude/.
//   - PRD #32: hooks ownership via `id:` prefix `codebrain:*`.
//             Partition existing entries; replace own; preserve others.
//   - PRD #33: ship `.brain/.codebrain-version` so upgrade detection works.
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

const VERSION_MARKER = `<!-- codebrain v${CODEBRAIN_VERSION} -->`;
const CLAUDE_MD_BEGIN = '<!-- codebrain:begin -->';
const CLAUDE_MD_END = '<!-- codebrain:end -->';

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
  console.log(`codebrain init — scaffold .brain/ + wire /brain commands and hooks

Usage:
  codebrain init                   Project-local install in the current repo
  codebrain init --global          Write to ~/.claude/ instead of <cwd>/.claude/
  codebrain init --force           Overwrite existing files (still writes .bak)
  codebrain init --dry-run         Print plan, write nothing

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

  // .codebrain-version marker — PRD Design Decision #33
  const versionFile = path.join(brain, '.codebrain-version');
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
      + '\n# Index\n\nPage catalog. Populated by Milestone #2 init skill and updated on every ingest.\n',
    'log.md': frontmatter({ kind: 'log', status: 'UNENRICHED', created: today })
      + '\n# Log\n\n## Recent Patterns\n\n<!-- Promoted recurring patterns from activity history. -->\n\n## Activity History\n\n<!-- Append-only per-event entries. Format: ## [YYYY-MM-DD] <op> | <subject> -->\n\n'
      + `## [${today}] init | codebrain v${CODEBRAIN_VERSION} scaffolded .brain/\n`,
    'overview.md': frontmatter({ kind: 'overview', status: 'UNENRICHED', created: today })
      + '\n# Overview\n\n## Project Purpose\n\n## Codebase Structure\n\n## Key Patterns\n\n## Active State\n\n## Recent Activity\n',
    'decisions.md': frontmatter({ kind: 'decisions-index', status: 'UNENRICHED', created: today })
      + '\n# Decisions\n\n## Active Decisions\n\n## Superseded Decisions\n',
    'status.md': frontmatter({ kind: 'status', status: 'UNENRICHED', created: today })
      + '\n# Status — Page Lifecycle Tracker\n\nDerived view; regenerated from per-page frontmatter.\n\n| Page | Status | Last Sync | Source Hash |\n|------|--------|-----------|-------------|\n',
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
  const block = `${CLAUDE_MD_BEGIN}\n## codebrain\n_placeholder schema block — populated by Milestone #2 init skill_\n${CLAUDE_MD_END}\n`;

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
  // Milestone #1 ships an EMPTY codebrain hooks set — Milestone #4 fills these in.
  const target = path.join(targetDir, 'settings.local.json');
  const codebrainOwnedHooks = {
    // Milestone #4 will populate this: e.g.,
    //   PreToolUse: [{ matcher: 'Edit|Write|MultiEdit', hooks: [...], id: 'codebrain:pre:edit-write:stale-detect', description: '...' }]
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
    const nonCodebrain = arr.filter(e => !(e && typeof e.id === 'string' && e.id.startsWith('codebrain:')));
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

  console.log(`codebrain v${CODEBRAIN_VERSION} — init${opts.dryRun ? ' --dry-run' : ''}${opts.force ? ' --force' : ''}${isGlobal ? ' --global' : ''}`);
  console.log(`  cwd:        ${cwd}`);
  console.log(`  target:     ${claudeDir}`);
  console.log(`  vault:      ${path.join(cwd, '.brain')}\n`);

  // Project-dir guard (Design Decision: refuse in random cwd without --global).
  if (!isGlobal && !isProjectDir(cwd)) {
    console.error(`error: cwd does not look like a project root (no ${PROJECT_SIGNALS.join(', no ')}).`);
    console.error('To install codebrain commands globally, re-run with --global.');
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
  copyTemplate('commands/brain.md', path.join(claudeDir, 'commands', 'brain.md'), opts);
  copyTemplate('commands/codebrain.md', path.join(claudeDir, 'commands', 'codebrain.md'), opts);

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
    console.log(`Try \`/brain init\` to see Milestone #2 status.`);
  } else {
    console.log(`\nDry run — no files written.`);
  }
  return 0;
}

module.exports = init;
