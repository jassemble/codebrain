#!/usr/bin/env node
// graphbrain CLI entry — verb dispatch only. Real logic lives in scripts/.
// PRD Design Decisions #28 (npm distribution) + #32 (hooks id-prefix) + #33 (version marker).

'use strict';

const path = require('path');
const pkg = require('../package.json');

const VERB = process.argv[2];
const ARGS = process.argv.slice(3);

function printHelp() {
  console.log(`graphbrain ${pkg.version} — agent-maintained codebase wiki for Claude Code

Usage:
  graphbrain init [--global] [--force] [--dry-run]
      Scaffold .brain/ in the current repo and write /brain slash commands
      + graphbrain hooks block into .claude/. Project-local by default; use
      --global to write to ~/.claude/ instead.

  graphbrain version
      Print the installed graphbrain version.

  graphbrain update
      [Deferred to v0.2] Refresh installed templates and hooks after a graphbrain
      version bump. For now, re-run \`graphbrain init --force\`.

  graphbrain uninstall
      [Deferred to v0.2] Remove .brain/, graphbrain entries from .claude/commands/
      and .claude/settings.local.json. For now, see the message printed below.

  graphbrain hook <subcommand>
      Internal hook entry point invoked by .claude/settings.local.json
      (PreToolUse/PostToolUse). Subcommands:
        stale-detect    — PostToolUse: mark .brain/ pages STALE on source edit
        verified-guard  — PreToolUse: block writes to VERIFIED .brain/ pages
        observe         — PreToolUse: collect minimal tool-use observations
                          (only fires when /brain learn on per-project)
      Not intended for direct operator use.

  graphbrain help
      Print this message.

After \`graphbrain init\`, restart Claude Code (or open a new session) and use
\`/brain init\` to begin. See https://github.com/jassemble/graphbrain for more.`);
}

const HOOK_SUBCOMMANDS = ['stale-detect', 'verified-guard', 'observe'];

function dispatchHook(args) {
  const sub = args[0];
  if (!sub) {
    console.error('graphbrain hook: missing subcommand. Available:');
    for (const s of HOOK_SUBCOMMANDS) console.error(`  ${s}`);
    process.exit(1);
  }
  if (!HOOK_SUBCOMMANDS.includes(sub)) {
    console.error(`graphbrain hook: unknown subcommand '${sub}'. Available:`);
    for (const s of HOOK_SUBCOMMANDS) console.error(`  ${s}`);
    process.exit(1);
  }
  // Delegate to the hook script (it runs side-effects + exits itself)
  require(path.join(__dirname, '..', 'scripts', 'hooks', sub + '.js'));
}

function main() {
  switch (VERB) {
    case 'init': {
      const init = require(path.join(__dirname, '..', 'scripts', 'init.js'));
      const code = init(ARGS);
      process.exit(typeof code === 'number' ? code : 0);
    }

    case 'version':
    case '-v':
    case '--version':
      console.log(pkg.version);
      process.exit(0);

    case 'update':
      console.log(
        `graphbrain update is not yet implemented in v${pkg.version}. ` +
        `For now, re-run \`graphbrain init --force\` to refresh templates and ` +
        `hooks after upgrading graphbrain via npm.`
      );
      process.exit(0);

    case 'uninstall':
      console.log(
        `graphbrain uninstall is not yet implemented in v${pkg.version}. ` +
        `Manual removal:\n` +
        `  1. Delete \`.brain/\` from your repo.\n` +
        `  2. Remove entries with \`id\` starting \`graphbrain:\` from ` +
        `\`.claude/settings.local.json\`.\n` +
        `  3. Delete \`.claude/commands/{brain,graphbrain}.md\`.\n` +
        `  4. Remove the \`<!-- graphbrain:begin -->\` ... ` +
        `\`<!-- graphbrain:end -->\` block from \`CLAUDE.md\`.`
      );
      process.exit(0);

    case 'hook':
      // Internal — invoked by .claude/settings.local.json entries.
      // The hook script handles its own exit code.
      dispatchHook(ARGS);
      return; // dispatched script will exit; safety return if it doesn't

    case undefined:
    case 'help':
    case '-h':
    case '--help':
      printHelp();
      process.exit(0);

    default:
      console.error(`Unknown verb: ${VERB}\n`);
      printHelp();
      process.exit(1);
  }
}

main();
