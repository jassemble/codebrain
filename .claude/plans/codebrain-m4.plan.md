# Plan: codebrain — Milestone #4 (4-tier staleness model — PostToolUse hook + PreToolUse guard)

**Source PRD**: `.claude/prds/codebrain.prd.md`
**Selected Milestone**: #4 — 4-tier staleness model
**Complexity**: Medium-to-Large — first runtime Node code, first hook scripts, extends `bin/codebrain.js` with a `hook` subcommand, extends `scripts/init.js` with non-empty `codebrainOwnedHooks`
**Status**: READY — first-draft plan with sweep findings baked in

## Summary

This milestone makes codebrain **self-maintaining**. The PostToolUse hook fires after every Edit/Write/MultiEdit; if the edited file is a tracked source, the hook flips `.brain/code/<path>.md` to `status: STALE` and walks both wikilinks AND per-source `sources:` arrays in concept pages to propagate STALE. The PreToolUse hook blocks writes to `.brain/` pages with `status: VERIFIED` (the operator's stamp) unless `--force` is passed. Together they constitute tiers 1+2 of the 4-tier staleness model (per PRD #10) and the structural layer of the dual-layer guardrail (PRD #19).

After M#4, when an operator edits `src/api/auth.ts`:
1. Hook fires → finds `.brain/code/src/api/auth.ts.md` → flips to `status: STALE` + records the source-hash that triggered the change
2. Hook walks all `.brain/**/*.md` pages → finds concept pages with `[[code/src/api/auth.ts]]` OR matching entries in their `sources:` array → flips those to STALE too
3. Operator's next `/brain query` or `/brain ingest --refresh` sees the STALE and acts (tiers 3+4 — query-time refresh lands in M#5; lint contradiction-check in M#6)

## Patterns to Mirror

| Category | Source | Pattern |
|---|---|---|
| Hook entry shape in settings.local.json | `reference/claude-code-conventions.md` (M#1 vendored canonical contract) | `{ matcher, hooks: [{ type: command, command: "...", timeout }], id: "codebrain:...", description }` — codebrain owns only entries with `id` starting `codebrain:` (PRD #32) |
| Init merges hooks via id-prefix partition | `scripts/init.js:mergeHooks` (M#1) | Read existing settings.local.json; partition each phase array into codebrain-owned + other; replace owned; preserve others — already implemented, just needs non-empty `codebrainOwnedHooks` |
| CLI verb dispatch | `bin/codebrain.js:main` (M#1) | switch on `process.argv[2]`; M#4 adds case `hook` that requires the named subcommand script from `scripts/hooks/` |
| Source-hash format | `commands/brain.md` ingest Step 3 + concept page `sources:` array (M#3b B6) | `git:<hash>` or `sha256:<hash>` — hook reads page frontmatter, extracts current source hash, compares to fresh `git hash-object` / `shasum` |
| Atomic writes for `.brain/` page mutations | `scripts/init.js:atomicWrite` (M#1) | Same `.bak → .tmp → fsync → rename` pattern; hooks should never corrupt a page mid-write |
| Exit-0-on-error for hooks (never block tool execution) | ECC convention + PRD implied (hooks must not surprise the operator) | Hook script: try/catch around everything; log errors to stderr with `[codebrain]` prefix; always `exit 0` from PostToolUse; PreToolUse `verified-guard` is the ONLY codebrain hook that can exit non-zero (to block) |
| Tests | `tests/e2e-test.sh` T1–T19 | T20: hook scripts exist + shebang + `bin/codebrain.js` has `hook` verb. T21: init.js writes the hook entries with `codebrain:` ids. T22: hook scripts behave correctly when fed mock tool inputs. |

## Sweep Findings (folded in)

Seven findings from the in-flight sweep of this first-draft plan:

- **D1 — Hook invocation path: `npx codebrain hook <subcommand>`** — solves Q1 (template/script discovery from npm-installed location, raised in M#3a/M#3c sweeps). `npx` is reliable because it resolves whichever codebrain is installed (global or project-local) and uses the package's `bin` entry. Settings.local.json entries are short, version-stable, and don't need to know absolute install paths.
- **D2 — Hook scripts read tool input from stdin** per Claude Code's hook protocol. Hook receives a JSON payload describing the tool call. Script parses, decides, exits.
- **D3 — Atomic writes for status-flip operations** — never `Edit` an existing page; always read full content, mutate frontmatter, write atomically via the same temp+rename pattern `scripts/init.js` uses. Mid-write crashes leave the original intact.
- **D4 — `verified-guard` is the only blocking hook in M#4** (PreToolUse with non-zero exit). All others (`stale-detect`) are PostToolUse with `exit 0` always — observation-only, never blocks the operator's session.
- **D5 — Hook does NOT try to determine "is this file tracked?"** by checking the filesystem state. Instead: it checks whether a `.brain/code/<path>.md` page EXISTS. If yes → tracked. If no → tracked-but-not-ingested-yet, or genuinely untracked; either way nothing to do; exit 0. Avoids guesswork.
- **D6 — Hook scope is per-repo, not per-session**: the hook script always reads `cwd/.brain/` (where the tool call originated). Operator working in multiple repos in parallel sessions: each session's `.brain/` is independent; no cross-repo interference.
- **D7 — Hook script must handle the "no .brain/ in this cwd" case gracefully**: many Claude Code sessions run in repos that don't have codebrain installed. Hook fires, sees no `.brain/`, exits 0 silently. No noise, no errors.

## Files to Change

| File | Action | Why |
|---|---|---|
| `scripts/hooks/stale-detect.js` | CREATE | PostToolUse hook on Edit/Write/MultiEdit. Reads tool input from stdin; identifies edited file; checks for matching `.brain/code/<path>.md`; if found, flips `status: STALE` + records `last_stale_at` + walks all `.brain/**/*.md` for wikilinks and concept-page `sources:` entries referencing the edited path; flips matching pages to STALE. Always exits 0. |
| `scripts/hooks/verified-guard.js` | CREATE | PreToolUse hook on Edit/Write/MultiEdit. If the target file is under `.brain/` AND has `status: VERIFIED` AND tool input does not contain `--force`: prints rejection message to stderr; exits 2 (blocks). Otherwise exits 0. |
| `scripts/hooks/lib/page-io.js` | CREATE | Shared helpers used by both hooks: read frontmatter, parse `kind`/`status`/`source`/`sources:`, mutate frontmatter atomically, walk `.brain/**/*.md` (small custom recursive walk; no Glob dep). Single source of truth for page mutation — verifier (M#6) reuses. |
| `bin/codebrain.js` | UPDATE | Extend verb dispatch: add `hook <subcommand> [...]`. Looks up `scripts/hooks/<subcommand>.js` and requires it with `process.argv.slice(3)`. Used by settings.local.json entries: `npx codebrain hook stale-detect`. Errors with help if subcommand unknown. |
| `scripts/init.js` | UPDATE | Populate `codebrainOwnedHooks` with the two entries (PreToolUse verified-guard + PostToolUse stale-detect). Existing merge logic from M#1 already handles partitioning + idempotent replacement. |
| `tests/e2e-test.sh` | UPDATE | T20: hook scripts exist + shebang + `bin/codebrain.js hook` verb dispatches. T21: a fresh `init` run now writes the two `codebrain:*` entries into `settings.local.json` (and a re-init still produces SKIPs or only a no-op merge per #32). T22: feed mock tool-input JSON to each hook script and assert correct behavior on the fixture `.brain/`. |
| `.claude/prds/codebrain.prd.md` | UPDATE | M#4 row → `in-progress` with plan link |

**Not in M#4 (deferred):**
- Tier 3 of staleness model (`/brain lint` contradiction-check) → M#6
- Tier 4 of staleness model (`/brain query` time refresh) → M#5
- Observer-agent block hook (extra PreToolUse rule preventing observer agents from writing) → M#7 (when first observer ships)

## Tasks

### Task 1: scripts/hooks/lib/page-io.js (shared helpers)

- **Action**: Create CommonJS module exporting:
  - `readPage(absolutePath)` → `{ frontmatter: { kind, status, source, source_hash, sources?, ... }, body }`. Parses YAML-ish frontmatter between leading `---`/`---` markers (we only need 4 fields — `kind`, `status`, `source`, `sources:`; full YAML parser not required). Returns `null` if file doesn't exist or has no frontmatter.
  - `writePage(absolutePath, { frontmatter, body })` → atomic write (write to `<path>.tmp`, fsync, rename). Mirrors `scripts/init.js:atomicWrite`.
  - `flipToStale(absolutePath, reason)` → reads page, sets `status: STALE`, sets `last_stale_at: <today ISO>`, optionally sets `stale_reason: <reason>`, writes atomically. Returns true if flipped, false if already STALE or page missing.
  - `walkBrainPages(brainRoot)` → generator/array of absolute paths under `<brainRoot>/{code,concepts}/**/*.md`. Small custom walk, no deps.
  - `findReferencingPages(brainRoot, sourceRelativePath)` → returns absolute paths of `.brain/**/*.md` pages whose body contains `[[code/<sourceRelativePath>]]` OR whose frontmatter `sources:` array has an entry with `path: <sourceRelativePath>`.
- **Mirror**: `scripts/init.js` (atomic write + frontmatter helper patterns)
- **Validate**: T20 — file exists + has shebang? (no shebang needed, it's a library not a script — just `module.exports`). T22 — fixture-driven assertions: write a fake page, flip it, read back, verify status: STALE.

### Task 2: scripts/hooks/stale-detect.js (PostToolUse)

- **Action**: Node CommonJS script with shebang `#!/usr/bin/env node`. Reads tool input from stdin (JSON; Claude Code hook protocol). Extracts the edited file path from tool input's `file_path`, `path`, or `target` field (handles Edit, Write, MultiEdit shapes — be defensive about field names).
  - Resolves path against cwd.
  - Checks for `cwd/.brain/.codebrain-version`. If absent → no codebrain here → exit 0 silently.
  - Computes the mirrored code-page path: `cwd/.brain/code/<relative-source-path>.md`. If it exists → flip to STALE via `lib/page-io.flipToStale`.
  - Walks `cwd/.brain/**/*.md` via `lib/page-io.walkBrainPages`; for each page, checks via `lib/page-io.findReferencingPages` logic whether it references the edited path (wikilink in body OR entry in `sources:` array). For each match → flip to STALE.
  - Updates `cwd/.brain/status.md` (the derived view): for every flipped page, refresh its row.
  - Logs to stderr with `[codebrain]` prefix on errors (never stdout — that's hook channel).
  - **ALWAYS exits 0**, even on error. Hooks must never block tool execution.
- **Mirror**: ECC `scripts/hooks/observe-runner.js` (the "exit 0 always; log to stderr" pattern; the stdin-read shape)
- **Validate**: T22 — fixture: write a fake `.brain/code/src/auth.ts.md` with `status: FRESH`. Feed the hook stdin `{"tool_input": {"file_path": "src/auth.ts"}}`. After: page status is STALE. Repeat with no `.brain/`: exit 0 silently. Repeat with non-tracked path: exit 0, page count unchanged.

### Task 3: scripts/hooks/verified-guard.js (PreToolUse)

- **Action**: Node CommonJS script with shebang. Reads tool input from stdin. Extracts the target file path.
  - If path does NOT start with `cwd/.brain/`: exit 0 (not our concern).
  - Read the existing target file. If it doesn't exist or has no frontmatter: exit 0 (new page, not guarded).
  - Parse frontmatter; if `status` is NOT `VERIFIED`: exit 0.
  - If `status: VERIFIED`: check tool input for `--force`. If present in args/content: exit 0.
  - Otherwise: print to stderr:
    ```
    [codebrain] BLOCKED: refusing to overwrite VERIFIED page <path>.
      The operator has stamped this page as VERIFIED.
      To override, re-run with --force in the command/argument.
    ```
  - Exit 2 (block).
- **Mirror**: graphbrain `scripts/hooks/guardrails.sh` (the exit-2-blocks pattern)
- **Validate**: T22 — fixture: write a fake `.brain/code/src/auth.ts.md` with `status: VERIFIED`. Feed mock Edit tool input targeting that page. Hook exits 2 + stderr matches. Same fixture with `--force` in input: hook exits 0. Fixture with `status: FRESH`: hook exits 0.

### Task 4: Extend bin/codebrain.js with `hook` verb

- **Action**: Add `case 'hook'` to the main switch. Subcommand dispatch:
  ```
  codebrain hook <subcommand> [...]   → require('../scripts/hooks/<subcommand>.js') with process.argv.slice(3)
  ```
  - Known subcommands at v0.1: `stale-detect`, `verified-guard`.
  - Unknown subcommand: print available subcommands and exit 1.
  - When loaded, the hook script's `module.exports` is called with the remaining argv (or the script just runs side-effects via shebang — depending on style; consistent with M#4's choice).

  Update the help text in `printHelp()` to mention:
  ```
  codebrain hook <subcommand>
      Internal hook entry point invoked by .claude/settings.local.json
      (PreToolUse/PostToolUse). Subcommands:
        stale-detect    — PostToolUse: mark .brain/ pages STALE on source edit
        verified-guard  — PreToolUse: block writes to VERIFIED .brain/ pages
      Not intended for direct operator use.
  ```
- **Mirror**: `bin/codebrain.js:main` (existing verb dispatch shape)
- **Validate**: T20 — `node bin/codebrain.js hook` prints subcommand list. `node bin/codebrain.js hook bogus` exits 1. `echo '{}' | node bin/codebrain.js hook stale-detect` exits 0 in a directory without `.brain/`.

### Task 5: Update scripts/init.js — populate codebrainOwnedHooks

- **Action**: Edit the `mergeHooks()` function in `scripts/init.js`. The existing `codebrainOwnedHooks` object is empty (`{}`); replace with the two entries:
  ```js
  const codebrainOwnedHooks = {
    PreToolUse: [{
      matcher: 'Edit|Write|MultiEdit',
      hooks: [{
        type: 'command',
        command: 'npx codebrain hook verified-guard',
        timeout: 5
      }],
      id: 'codebrain:pre:verified-guard',
      description: 'Block writes to VERIFIED .brain/ pages without --force'
    }],
    PostToolUse: [{
      matcher: 'Edit|Write|MultiEdit',
      hooks: [{
        type: 'command',
        command: 'npx codebrain hook stale-detect',
        timeout: 10
      }],
      id: 'codebrain:post:stale-detect',
      description: 'Mark .brain/ pages STALE when their source file is edited'
    }]
  };
  ```
- The merge logic from M#1 already partitions by `id` prefix and idempotently replaces. No other change needed.
- **Mirror**: M#1 `scripts/init.js:mergeHooks` (the existing merge — unchanged structure)
- **Validate**: T21 — run `npx codebrain init` in a tmpdir; assert `settings.local.json` has both `codebrain:` entries with correct `matcher`/`command`/`id`/`description`. Re-run: same content (no duplication).

### Task 6: tests/e2e-test.sh — T20 + T21 + T22

- **Action**: Three new test sections.

  **T20 — Hook scripts exist + CLI verb dispatches:**
  - `scripts/hooks/stale-detect.js` exists + has `#!/usr/bin/env node` shebang
  - `scripts/hooks/verified-guard.js` exists + has shebang
  - `scripts/hooks/lib/page-io.js` exists (no shebang — library)
  - `node bin/codebrain.js hook` prints both subcommands in help
  - `node bin/codebrain.js hook bogus-name` exits 1
  - npm pack includes all three new hook files

  **T21 — init.js writes the codebrain hook entries:**
  - In an existing test fixture dir, run `init`; assert `settings.local.json` has `hooks.PreToolUse` and `hooks.PostToolUse` arrays each containing an entry with `id` starting `codebrain:`
  - Assert the `command` field references `npx codebrain hook <subcommand>`
  - Re-run init; count of `codebrain:*` entries unchanged (idempotent)
  - Seed settings.local.json with a user hook (id `user:foo`) + a stale codebrain entry (id `codebrain:old`); run init; assert `user:foo` preserved + `codebrain:old` removed + new entries added (extends T2/T3 from M#1)

  **T22 — Hook script behavior on fixture .brain/:**
  - Set up tmpdir with `.brain/{code,concepts}/`, `.brain/.codebrain-version`, and one fake `.brain/code/src/auth.ts.md` with `status: FRESH` + matching `source: src/auth.ts`
  - Feed `stale-detect` mock tool input `{"tool_input": {"file_path": "src/auth.ts"}}`; assert exit 0 + page now has `status: STALE` + new `last_stale_at:` field
  - Feed `stale-detect` mock for a path NOT tracked (no matching page); assert exit 0 + no page changes
  - In a dir with no `.brain/`, feed `stale-detect` any input; assert exit 0 silently
  - For `verified-guard`: page with `status: VERIFIED`, mock Edit on it without `--force`: exit 2 + stderr has BLOCKED message
  - Same with `--force` in input: exit 0
  - For `verified-guard`: target file outside `.brain/`: exit 0 (not our concern)
  - For a concept page with `sources: [{path: src/auth.ts, hash: git:abc}]`: `stale-detect` flips it to STALE when src/auth.ts is edited
  - For a code page A with `[[code/src/auth.ts]]` in its body: `stale-detect` flips A to STALE when src/auth.ts is edited
- **Mirror**: existing T1–T19 shape; T22 introduces fixture-driven hook tests
- **Validate**: `bash tests/e2e-test.sh` exits 0; total ~260 (216 + ~45 new); runtime still <5s

### Task 7: PRD update — M#4 → in-progress

- **Action**: Edit `.claude/prds/codebrain.prd.md`: M#4 row `pending` → `in-progress`; Plan → link to this file.
- **Validate**: `grep "4-tier staleness" .claude/prds/codebrain.prd.md` shows updated row.

## Validation

```bash
# 1. E2E (combined M#1+M#2+M#3a/b/c+M#4 surface)
bash tests/e2e-test.sh
# Expect: ~260 passes, 0 failures, <5s

# 2. Hook scripts exist + executable
test -f scripts/hooks/stale-detect.js
test -f scripts/hooks/verified-guard.js
test -f scripts/hooks/lib/page-io.js
head -1 scripts/hooks/stale-detect.js | grep -q '^#!/usr/bin/env node'
head -1 scripts/hooks/verified-guard.js | grep -q '^#!/usr/bin/env node'

# 3. CLI verb wired
node bin/codebrain.js hook 2>&1 | grep -q 'stale-detect'
node bin/codebrain.js hook 2>&1 | grep -q 'verified-guard'

# 4. init.js merges the codebrain entries
node -e "
const init = require('./scripts/init.js');
process.chdir(require('os').tmpdir() + '/cb-test-' + Date.now());
require('fs').mkdirSync('.git');
init([]);
const s = require(process.cwd() + '/.claude/settings.local.json');
const pre = (s.hooks.PreToolUse || []).find(e => e.id === 'codebrain:pre:verified-guard');
const post = (s.hooks.PostToolUse || []).find(e => e.id === 'codebrain:post:stale-detect');
if (!pre || !post) { console.error('hook entries missing'); process.exit(1); }
"

# 5. npm pack includes new hook files
npm pack --dry-run | grep -E 'scripts/hooks/(stale-detect|verified-guard|lib/page-io)\.js'

# 6. Manual smoke (post-commit; in a real repo with codebrain init done):
#   /brain ingest src/some-file.ts                 → page FRESH
#   <operator edits src/some-file.ts via Edit>     → hook fires; page STALE
#   /brain ingest src/some-file.ts                 → re-ingest; page FRESH again
#   <operator stamps a page status: VERIFIED>      → page VERIFIED
#   /brain ingest src/some-file.ts                 → SKIP (per M#3a) OR <attempt to Edit the page> → guard blocks
```

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Hook script crashes mid-write → corrupts a `.brain/` page | Med | Atomic write via temp+rename in lib/page-io; never edit in place; on crash, original page intact |
| Hook fires in a non-codebrain repo and emits errors | High if unguarded | D7 — first thing the hook does is check for `.brain/.codebrain-version`; if absent, exit 0 silently |
| `npx codebrain hook ...` is slow on first invocation (npx cold-start) | Med | npx caches the package; subsequent invocations are fast. Document in CLAUDE.md that the first edit after `npx codebrain init` may have a brief pause. M#4+ can investigate using `node_modules/.bin/codebrain hook ...` if cold-start is annoying. |
| Claude Code hook protocol changes (the JSON shape passed on stdin) | Low | Single source of truth for parsing: `lib/page-io` exports a helper. If the protocol changes, update one place. |
| `verified-guard` blocks operator's own legitimate edits to a brain page | Med | Operator can always pass `--force`; OR manually downgrade `status: VERIFIED` to `FRESH` before editing; OR set `CODEBRAIN_DISABLED_HOOKS=codebrain:pre:verified-guard` for the session (per PRD #24 env-gate, which lands when scripts/init.js wires it — not strictly required for M#4 but easy to add) |
| Walking `.brain/**/*.md` is slow on a large brain | Low | Walk is bounded by `.brain/` size (small); typical brains have <100 pages; <50ms for any reasonable case |
| Per-source-hash check on concept pages requires re-hashing the source for every edit | Low for M#4 | M#4's stale-detect doesn't compare hashes — it just marks STALE on any edit of a referenced source. Hash comparison is for *resolving* STALE (M#5's query-time refresh decides whether to re-ingest based on whether hash actually changed). Cheap. |
| `lib/page-io` becomes a fragile YAML parser | Low | Only 4 fields needed (`kind`, `status`, `source`, `sources:`); custom parser handles them; if codebrain ever needs full YAML, vendor a tiny one — but not today |
| User runs `npm pack` then `npm install` of the tarball in CI; `scripts/hooks/` doesn't get the executable bit | Med | The `files:` whitelist in package.json includes `scripts/`; the shebang is enough — npm install preserves shebangs, and `npx codebrain hook ...` invokes via node anyway, not via the shebang. So executable bit doesn't matter. |
| Alias parity between brain.md and codebrain.md not relevant for M#4 (no slash-command body changes) | N/A | M#4 doesn't touch commands/*.md |

## Acceptance

- [ ] All 7 tasks complete
- [ ] Validation §1 (e2e ~260) passes; <5s
- [ ] Validation §2–§5 pass
- [ ] Hook scripts behave correctly on fixture inputs (T22)
- [ ] init.js produces correct hook entries (T21); idempotent on re-run
- [ ] PRD M#4 row → in-progress with plan link
- [ ] Patterns mirrored from M#1 hook-merge + M#3a/b/c file conventions — not reinvented
- [ ] No regression: 216 prior tests still pass; total ~260 after T20+T21+T22 added (~45 new)
- [ ] (Optional) Manual smoke test: edit a tracked source file in a codebrain-initialized repo; verify the corresponding `.brain/code/` page status flips to STALE
