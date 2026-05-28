# Plan: graphbrain — Milestone #1 (npm package skeleton + init)

**Source PRD**: `.claude/prds/graphbrain.prd.md`
**Selected Milestone**: #1 — npm package skeleton + init
**Complexity**: Small-to-Medium (was Small; the `init` script adds real logic — JSON-aware settings merge, idempotent guard, project-local-vs-global target detection)

## Summary

Bootstrap graphbrain as a publishable npm package. After `npx graphbrain init`, the user has `.brain/` scaffolded in their cwd, `/brain *` slash commands available in Claude Code (project-local under `<cwd>/.claude/commands/` by default; `~/.claude/commands/` with `--global`), and graphbrain hooks merged into `.claude/settings.local.json`. Every `/brain` verb resolves but prints "not yet implemented — Milestone N" stubs in this milestone; real behavior fills in via Milestones #2–#7. The init flow is idempotent (re-run safe), creates a `.bak` before any destructive edit, and refuses to run in a non-project directory unless `--global` is passed.

## Patterns to Mirror

| Category | Source | Pattern |
|---|---|---|
| npm package shape | `/Users/dev/Desktop/Project/OSS/idea/graphbrain/package.json` | `name`, `version`, `bin: { graphbrain: "./bin/graphbrain.js" }`, `license: "MIT"`, `engines: { node: ">=18" }`, `files: [...]` whitelist (don't ship `.claude/`, `reference/` to npm registry — only what `init` needs to copy) |
| Init script logic | `/Users/dev/Desktop/Project/OSS/idea/graphbrain/brain-init.sh` (scaffold target dir + idempotency guard) + ECC's `/scripts/install-apply.js` (cross-target install) | Detect target (project-local default, `--global` opt-in); refuse if not in a project dir without `--global`; create `.bak` before any destructive edit; idempotent re-run; JSON-aware merge for settings.local.json (preserve user's existing hooks); explicit OK / SKIP / WARN report per file |
| CLI entry point | graphbrain `bin/graphbrain` (bash dispatcher; graphbrain uses Node not bash) | `#!/usr/bin/env node` shebang; minimal verb dispatch — `init`, `version`, `help`, fallback shows help |
| Subcommand dispatch (slash command body) | `/Users/dev/Desktop/Project/OSS/idea/ECC/commands/checkpoint.md` | One `.md` file with `$ARGUMENTS` routing to verbs (`init | ingest | query | lint | learn | status`); this file is the *template* shipped in the npm package and copied to the user's `.claude/commands/brain.md` by init |
| Skill format | `/Users/dev/Desktop/Project/OSS/idea/ECC/skills/continuous-learning-v2/SKILL.md` + `/Users/dev/Desktop/Project/OSS/idea/graphbrain/skills-registry/ingestion/concept-extraction/SKILL.md` | YAML frontmatter merging ECC base + graphbrain additions (`tier`, `pattern`, `related_skills`, `detect`); body sections "When to Activate", "How It Works", "Examples" |
| E2E test | `/Users/dev/Desktop/Project/OSS/idea/graphbrain/tests/e2e-test.sh` | Bash, pass/fail counter, structural validation; ~80–100 lines; <5s runtime; no LLM calls, no network |
| File naming | `/Users/dev/Desktop/Project/OSS/idea/ECC/.claude/rules/node.md` | lowercase-with-hyphens (`brain.md`, `graphbrain.js`, not `Brain.md` or `brain_init.md`) |

**Patterns we are NOT mirroring (intentional):**
- ECC's `.claude-plugin/plugin.json` + `marketplace.json` + `PLUGIN_SCHEMA_NOTES.md` — graphbrain is **not** a Claude Code plugin (Design Decision #28).
- ECC's `install.sh` shell-wrapper + `install-apply.js` Node runner — graphbrain's `init` is a single Node script invoked via `npx graphbrain init`. No shell wrapper.
- graphbrain's `postinstall.js` (npm postinstall hook that auto-runs init) — graphbrain requires an *explicit* `graphbrain init` step. Auto-running on npm install pollutes user state without consent.
- ECC's full `.github/` directory (CI, dependabot, ISSUE_TEMPLATE, PR template, CODEOWNERS, FUNDING) — deferred per Design Decision #30.

## Files to Change

| File | Action | Why |
|---|---|---|
| `package.json` | CREATE | npm manifest: `name`, `version`, `bin`, `license`, `engines`, `files` whitelist, no `dependencies` (Node stdlib only for M#1) |
| `bin/graphbrain.js` | CREATE | CLI entry: shebang `#!/usr/bin/env node`; verb dispatch (`init` | `version` | `help`); ≤80 lines |
| `scripts/init.js` | CREATE | Core init logic: target detection (project-local vs `--global`); project-dir guard; copy `commands/*.md` → `.claude/commands/`; JSON-merge graphbrain hooks into `.claude/settings.local.json`; scaffold `.brain/`; append `## graphbrain` block to `CLAUDE.md` inside a managed region; idempotent; `.bak` before destructive edits |
| `commands/brain.md` | CREATE | Template — copied verbatim by init into the user's `.claude/commands/brain.md`. Verb dispatcher with `$ARGUMENTS` routing to Milestone-N stubs |
| `commands/graphbrain.md` | CREATE | Alias template (identical body) |
| `skills/behavioral/graphbrain/SKILL.md` | CREATE | Meta skill describing graphbrain — bundled in the npm package; init copies into target's skill location |
| `skills/registry.json` | CREATE | Empty registry shell — `{ "version": "0.1.0", "skills": {} }`; seeds the `detect:` rule format for Milestone #2 auto-detection |
| `skills/README.md` | CREATE | Documents the 5-tier model + SKILL.md frontmatter convention |
| `skills/{ingestion,core,detected,available}/.keep` | CREATE | Reserve tier directories |
| `agents/registry.json` | CREATE | Empty agent registry shell: `{ "version": "0.1.0", "agents": {} }` |
| `agents/README.md` | CREATE | Documents merged ECC + graphbrain agent frontmatter convention + the dual-layer guardrail expectation + the prompt-defense-reference rule |
| `agents/{brain,observers}/.keep` | CREATE | Reserve agent category directories |
| `reference/claude-code-conventions.md` | CREATE | Vendored from ECC docs (`hooks/README.md`, command/skill format notes) — documents what shape the `.claude/commands/*.md`, `.claude/settings.local.json` hooks block, and `agents/*.md` files must follow. **This is the surface the `init` script must produce correctly.** |
| `reference/llm-wiki.md` | EXISTS — verify | Already present from PRD phase; no change |
| `LICENSE` | CREATE | MIT |
| `README.md` | CREATE | OSS-facing: install (`npx graphbrain init`), quickstart, link to PRD, roadmap; ~150 lines |
| `CLAUDE.md` | CREATE | Project-internal contributor guidance; **vendors the Prompt Defense Baseline** verbatim from ECC (Design Decision #20); documents agent + skill conventions |
| `.gitignore` | CREATE | Node (`node_modules/`, `dist/`, `*.log`), OS, editor; explicit warning "DO NOT gitignore .brain/" |
| `.npmignore` | CREATE | Tells npm to skip `.claude/`, `reference/`, `tests/` (smaller package; init only needs `commands/`, `skills/`, `agents/`, `scripts/`, `bin/`) |
| `tests/e2e-test.sh` | CREATE | Run `npx graphbrain init` in a tmpdir (`mktemp -d`); assert `.brain/`, `.claude/commands/brain.md`, `.claude/settings.local.json` hook entries; runtime <5s |
| `.claude/prds/graphbrain.prd.md` | UPDATE (done) | Milestone #1 row flipped to `in-progress` with plan link |

**Files explicitly NOT created in Milestone #1:**
- `hooks/` directory in graphbrain itself — the *content* of the hooks block lives inline in `scripts/init.js` (the merge template) until Milestone #4 ships real hooks.
- `agents/brain/{ingester,linker,verifier}.md` — Milestones #3, #5, #6.
- `agents/observers/observer.md` — Milestone #7.
- `skills/ingestion/{page-format,concept-extraction,entity-extraction}/SKILL.md` — Milestone #3.
- `skills/core/{query,lint,learn,status}/SKILL.md` — Milestones #5, #6, #7.
- `skills/detected/{react,python,go,typescript}/SKILL.md` — Milestone #3 (when detection lands).
- `.github/` directory, `CI`, `SECURITY.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `CHANGELOG.md` — deferred per Design Decision #30.

## Tasks

### Task 1: package.json (npm manifest)

- **Action**: Create `package.json` with:
  - `name: "graphbrain"` (verify availability on npm before publish)
  - `version: "0.1.0"`
  - `description`: one-line pitch from PRD hypothesis
  - `bin: { "graphbrain": "./bin/graphbrain.js" }`
  - `license: "MIT"`
  - `author`: placeholder `{ "name": "<owner>" }`
  - `homepage`, `repository`, `bugs` — placeholders
  - `keywords`: `["claude-code", "agentic-development", "knowledge-graph", "obsidian", "code-context", "continuous-learning"]`
  - `engines: { "node": ">=18" }`
  - `files`: explicit whitelist — `["bin/", "scripts/", "commands/", "skills/", "agents/", "reference/llm-wiki.md", "reference/claude-code-conventions.md", "README.md", "LICENSE"]`
  - No `dependencies` for M#1 (Node stdlib only)
- **Mirror**: `/Users/dev/Desktop/Project/OSS/idea/graphbrain/package.json`
- **Validate**: `node -e "require('./package.json')"`; `npm pack --dry-run` shows only the whitelisted files

### Task 2: bin/graphbrain.js (CLI entry)

- **Action**: Create `bin/graphbrain.js` with:
  - Shebang: `#!/usr/bin/env node`
  - Verb dispatch from `process.argv[2]`:
    - `init` → `require('../scripts/init.js')(process.argv.slice(3))`
    - `version` → print contents of `package.json.version`
    - `update` → **stub for v0.2**: print `graphbrain update is not yet implemented in v0.1. For now, re-run \`graphbrain init --force\` to refresh templates after upgrading graphbrain via npm.`; exit 0
    - `uninstall` → **stub for v0.2**: print `graphbrain uninstall is not yet implemented in v0.1. Manual removal: (1) delete \`.brain/\` from your repo, (2) remove entries with \`id\` starting \`graphbrain:\` from \`.claude/settings.local.json\`, (3) delete \`.claude/commands/{brain,graphbrain}.md\`.`; exit 0
    - `help` (or no arg or unknown verb) → print help listing all 5 verbs (init, version, update, uninstall, help) with one-liners + link to README
  - ≤100 lines
  - `chmod 755` permission set (done by Task 1's `files` whitelist; the npm publish handles this)
- **Mirror**: graphbrain's `bin/graphbrain` (the dispatch shape; graphbrain's is Node not bash)
- **Validate**: `node bin/graphbrain.js` prints help; `node bin/graphbrain.js version` prints `0.1.0`; `node bin/graphbrain.js update` and `node bin/graphbrain.js uninstall` print their deferred messages; `node bin/graphbrain.js init --help` prints init-specific help (delegated to scripts/init.js)

### Task 3: scripts/init.js (the init logic — load-bearing)

- **Action**: Create `scripts/init.js` as a CommonJS module exporting `function init(argv)`:

  **Flags**:
  - `--global` — write to `~/.claude/` instead of `<cwd>/.claude/`
  - `--force` — overwrite without confirmation (re-copy templates even if present)
  - `--dry-run` — print plan, write nothing

  **Target detection**:
  - Default: `<cwd>/.claude/`
  - `--global`: `os.homedir() + '/.claude/'`

  **Project-dir guard** (default mode only): if not `--global` and cwd has no `.git/`, no `package.json`, no `pyproject.toml`, no `go.mod`, no `Cargo.toml` — refuse with explicit error and exit 1.

  **Claude Code presence soft-check**: if `~/.claude/` does not exist, emit a WARN line: `WARN: Claude Code not detected (~/.claude/ missing). Files written, but /brain commands won't work until Claude Code is installed.` Proceed anyway.

  **Plan + atomic-write protocol**:
  - **Templates copied** to `<target>/commands/`: `brain.md`, `graphbrain.md`. Each copy prepends a version-marker comment line `<!-- graphbrain v0.1.0 -->` so the installed version is identifiable (per Design Decision #33's spirit, applied to templates).
  - **Skills** to `<target>/skills/` (`--global` only — for project-local, skills are read from the npm-installed location at runtime via Claude Code's skill-path resolution; we do NOT scatter copies into every repo)
  - **Hooks merge into `<target>/settings.local.json`** — see "Hooks merge contract" below
  - **Scaffold `<cwd>/.brain/`** (always cwd, even with `--global` — the vault is per-repo):
    - `.brain/code/.keep`, `.brain/concepts/.keep`, `.brain/decisions/.keep`
    - `.brain/{index,log,overview,decisions,status}.md` — each with minimal valid frontmatter (`kind:`, `status: UNENRICHED`, `created:`) + section headings only (content lands in M#2)
    - `.brain/.graphbrain-version` — one line: `0.1.0` (per Design Decision #33). This is the upgrade-detection anchor.
  - **CLAUDE.md managed-region** — append to `<cwd>/CLAUDE.md` (create if missing):
    ```
    <!-- graphbrain:begin -->
    ## graphbrain
    _placeholder schema block — populated by Milestone #2 init skill_
    <!-- graphbrain:end -->
    ```
    Skip if `<!-- graphbrain:begin -->` already present (idempotency); refresh content between markers if `--force`.

  **Hooks merge contract** (per Design Decision #32):
  - Read `<target>/settings.local.json`. If absent, start with `{ "hooks": {} }`. If present but unparseable JSON, abort with FAIL and instructions (don't overwrite a corrupt file).
  - For each phase array (`PreToolUse`, `PostToolUse`, `SessionStart`, `SessionEnd`, `Stop`, `PreCompact`, `UserPromptSubmit`):
    1. Partition the existing array into `[graphbrain-owned]` (entries whose `id` field starts with `graphbrain:`) and `[other]` (everything else — user's or other tools' hooks)
    2. Discard the `[graphbrain-owned]` partition
    3. Append graphbrain's current hooks (for M#1: empty — M#4 fills these in) **after** `[other]`, preserving non-graphbrain order
  - Result: graphbrain hooks always reflect the installed graphbrain version; non-graphbrain hooks are untouched.

  **Atomic write protocol** for every modified file (`settings.local.json`, `CLAUDE.md`):
  1. Write `.bak` of original (skip on first creation)
  2. Write new content to `<target>.tmp`
  3. `fs.fsync` the temp file
  4. `fs.rename(tmp, target)` (atomic on POSIX; on Windows this is effectively atomic for our use)
  5. If any step fails: leave `.bak` in place, log FAIL with restoration hint

  **Idempotency**: re-running with the same graphbrain version produces no diff; emits SKIP for already-present, version-current files. `--force` ignores SKIPs.

  **Report format**: one line per action — `OK <file>`, `SKIP <file> (already configured)`, `WARN <file> (manual review)`, `FAIL <file> (<reason>)`. Final summary line: `<N OK, M SKIP, K WARN, J FAIL>`.

  **Post-init message** (printed last): `Done. Restart Claude Code or open a new session to use /brain commands. Try \`/brain init\` to see Milestone #2 status.` (Cautious default — assumes restart needed; can soften later if live-discovery is confirmed.)

  **Exit code**: 0 on all-OK / all-SKIP / all-WARN; 1 if any FAIL; never silent.

- **Mirror**: graphbrain `brain-init.sh` (scaffold pattern + idempotency guard) + ECC `scripts/install-apply.js` (target detection + reporting)
- **Validate**: covered by Task 15 (E2E test) — `npx graphbrain init` in a tmpdir produces the expected files; re-running shows SKIPs; `--dry-run` writes nothing; `--global` writes to a stubbed HOME; pre-existing non-graphbrain hooks in settings.local.json are preserved; re-init doesn't duplicate graphbrain hooks; missing `~/.claude/` produces a WARN but proceeds

### Task 4: commands/brain.md (primary slash-command template)

- **Action**: Create `commands/brain.md` (this file is the **template** the init script copies into the user's `.claude/commands/brain.md`):
  - **First line**: `<!-- graphbrain v0.1.0 -->` — version marker so installed templates are identifiable for debugging "which version configured this" (paired with Design Decision #33's `.brain/.graphbrain-version`)
  - YAML frontmatter: `description: graphbrain — agent-maintained codebase wiki (init, ingest, query, lint, learn, status)`
  - Body interprets `$ARGUMENTS` as `<verb> [args]` and routes to a stub per verb. Each stub prints one line: "Milestone #N (<feature-name>) — not yet implemented; see `<repo-root>/README.md` roadmap".
  - Verbs: `init`, `ingest`, `query`, `lint`, `learn`, `status`
  - With no args (`/brain`), print help summary listing all verbs + link to README
- **Mirror**: ECC `commands/checkpoint.md` (subcommand dispatch via `$ARGUMENTS`)
- **Validate**: file starts with `<!-- graphbrain v0.1.0 -->`; YAML frontmatter on lines 2–4 parses; smoke test post-init — `/brain` shows help, `/brain init` shows "Milestone #2" stub

### Task 5: commands/graphbrain.md (alias template)

- **Action**: Create `commands/graphbrain.md` with body identical to `commands/brain.md` (the dispatcher logic is the same; only the slash-command name differs because the file name differs). One-line header note: "alias for `/brain`".
- **Mirror**: Same as Task 4
- **Validate**: `/graphbrain ingest` produces the same output as `/brain ingest`; byte-identical body content

### Task 6: skills/behavioral/graphbrain/SKILL.md (meta skill)

- **Action**: Create `skills/behavioral/graphbrain/SKILL.md` with:
  - Frontmatter (merged ECC + graphbrain shape per Design Decisions #17, #21):
    ```yaml
    ---
    name: graphbrain
    description: agent-maintained markdown wiki of the codebase (folder-mirrored, Obsidian-viewable, with continuous learning) — invoke /brain init to scaffold .brain/ inside your repo
    origin: graphbrain
    version: 0.1.0
    tier: behavioral
    pattern: Meta
    related_skills: []
    ---
    ```
  - Body sections: **When to Activate**, **How It Works** (three-layer architecture from PRD §Architecture), **Agent Execution Model** (foreground-first + trigger_phrases per #16), **Examples** (`/brain init`, `/brain ingest src/`, `/brain query "..."`)
  - Links to: PRD, `reference/llm-wiki.md`, `agents/README.md`, `skills/README.md`
- **Mirror**: ECC `skills/continuous-learning-v2/SKILL.md` (frontmatter) + graphbrain `skills-registry/ingestion/concept-extraction/SKILL.md` (tier/pattern/related_skills)
- **Validate**: `head -12 skills/behavioral/graphbrain/SKILL.md` shows valid frontmatter with all 6 fields

### Task 7: Reserve the skills/ 5-tier directory structure

- **Action** (per Design Decisions #21, #22):
  - `skills/registry.json` — `{ "version": "0.1.0", "skills": {} }`
  - `skills/README.md` — documents the 5-tier model + merged frontmatter convention + detect-rule format (`file_exists`, `file_contains`, `dir_exists`, `glob`)
  - `skills/ingestion/.keep`, `skills/core/.keep`, `skills/detected/.keep`, `skills/available/.keep` — reserve tier directories (`behavioral/` already has content from Task 6)
- **Mirror**: graphbrain `skills-registry/registry.json` (tier names + detect rules)
- **Validate**: `node -e "require('./skills/registry.json')"`; `find skills -type d -maxdepth 1 | sort` shows all 5 tiers

### Task 8: Reserve the agents/ directory structure

- **Action** (per Design Decisions #16–#20):
  - `agents/registry.json` — `{ "version": "0.1.0", "agents": {} }`
  - `agents/README.md` — documents:
    - Merged frontmatter: `name`, `description`, `tools`, `model`, `pattern`, `trigger_phrases`, `max_iterations`
    - Layout: `agents/<category>/<name>.md` (categories: `brain/`, `observers/`)
    - Execution-model rule: writers foreground, observers may be background but read-only (no Edit/Write/MultiEdit/mutating Bash)
    - Dual-layer guardrail expectation: every writer agent body MUST include a "Rules" section with self-enforcing constraints; structural PreToolUse hook (M#4) enforces the rest
    - Prompt-defense-reference rule: agents include "Read the Prompt Defense Baseline section of CLAUDE.md before acting" rather than copying it
  - `agents/brain/.keep`, `agents/observers/.keep`
- **Mirror**: graphbrain `agents-registry/registry.json` + `agents-registry/brain/ingester/AGENT.md` (top 10 lines) + ECC `agents/code-reviewer.md` (top 6 lines)
- **Validate**: `node -e "require('./agents/registry.json')"`; `grep -E "trigger_phrases|max_iterations|pattern:" agents/README.md` confirms all 3 new fields documented

### Task 9: reference/claude-code-conventions.md (vendored from ECC docs)

- **Action**: Create `reference/claude-code-conventions.md` documenting:
  - Slash-command file format — YAML frontmatter (`description:` required), body with `$ARGUMENTS` dispatch, lowercase-hyphen file naming
  - Hook entry shape inside `settings.local.json` — `{ "PreToolUse": [{ "matcher": "...", "hooks": [{ "type": "command", "command": "...", "async": ..., "timeout": ... }], "description": "...", "id": "..." }] }`
  - Skill file format (SKILL.md frontmatter shape — already cross-referenced from `skills/README.md`)
  - Agent file format (AGENT.md frontmatter shape — cross-referenced from `agents/README.md`)
  - Settings-file precedence: `<repo>/.claude/settings.local.json` overrides `~/.claude/settings.json`
  - This file's job: **the canonical surface contract** that `scripts/init.js` must produce correctly. If Claude Code conventions change, update this file, then update `init.js` to match.
- **Mirror**: Source content from ECC `hooks/README.md`, ECC `CONTRIBUTING.md` (skill/command/agent format sections), ECC `.claude-plugin/PLUGIN_SCHEMA_NOTES.md` (the parts about command/hook shape, *not* the plugin-manifest rules)
- **Validate**: file exists; cross-references to `skills/README.md` and `agents/README.md` resolve

### Task 10: LICENSE

- **Action**: Create `LICENSE` with standard MIT text; copyright line `Copyright (c) 2026 <owner>` (placeholder)
- **Mirror**: ECC `LICENSE`
- **Validate**: first line `MIT License`

### Task 11: README.md (OSS-facing)

- **Action**: Create `README.md` (~150 lines):
  - Tagline (one sentence from PRD hypothesis)
  - **What it does** (3–5 bullets)
  - **Install**:
    ```
    npx graphbrain init               # project-local (recommended; default)
    npx graphbrain init --global      # writes to ~/.claude/ instead
    ```
  - **Quickstart**: `/brain init` → `/brain ingest src/` → `/brain query "..."`
  - **How it works** (link to PRD §Architecture, `reference/llm-wiki.md`)
  - **Roadmap** (8 milestones from PRD, status indicators)
  - **License**: MIT
  - Credit line: built atop the LLM-Wiki pattern; adapts the three-layer architecture from documents to codebases; credits ECC, graphbrain, graphify as inspiration
- **Validate**: renders in GitHub preview; all linked files exist

### Task 12: CLAUDE.md (contributor-facing)

- **Action**: Create `CLAUDE.md` for sessions working **on graphbrain itself**:
  - One-line project summary
  - Where the PRD/plans/reference/agents/skills live
  - Build/test: `bash tests/e2e-test.sh`; `npm pack --dry-run`
  - Coding conventions: lowercase-hyphens, markdown-with-YAML-frontmatter
  - **Prompt Defense Baseline section** — verbatim from ECC `CLAUDE.md` lines 8–15 (Design Decision #20); single source of truth that agents reference rather than re-copy
  - **Agent conventions section** — points to `agents/README.md` (Design Decision #17); names the dual-layer guardrail model (#19); notes where each layer lands (hook = M#4, agent self-rules = each agent file)
  - **Skill conventions section** — points to `skills/README.md` (Design Decision #21)
- **Mirror**: ECC `CLAUDE.md` (Prompt Defense block + structure)
- **Validate**: `grep "Prompt Defense Baseline" CLAUDE.md` returns the section

### Task 13: .gitignore

- **Action**: Create `.gitignore`:
  - Node: `node_modules/`, `npm-debug.log*`, `dist/`, `*.tgz`
  - OS: `.DS_Store`, `Thumbs.db`
  - Editor: `.vscode/`, `.idea/`, `*.swp`
  - Coverage: `coverage/`
  - Explicit comment: `# DO NOT gitignore .brain/ — graphbrain commits the brain by default (Design Decision #3)`
- **Mirror**: ECC `.gitignore` (Node + OS sections)
- **Validate**: `git check-ignore -v .brain/` (in a test repo with this gitignore) does not match

### Task 14: .npmignore

- **Action**: Create `.npmignore`:
  - `.claude/` (PRDs and plans don't ship to npm)
  - `tests/`
  - `reference/` (except `reference/llm-wiki.md` and `reference/claude-code-conventions.md` — those are needed at runtime by docs links, but actually we're shipping them via `files:` whitelist in package.json, so `.npmignore` is the negative path; safer is to use ONLY `files:` and let `.npmignore` be a backstop)
  - `*.bak`
  - `coverage/`
  - `CLAUDE.md`, `.claude/`
- **Mirror**: ECC `.npmignore`
- **Validate**: `npm pack --dry-run` output does not list `.claude/`, `tests/`, `CLAUDE.md`

### Task 15: tests/e2e-test.sh

- **Action**: Create `tests/e2e-test.sh`:
  - Creates tmpdir via `mktemp -d`, copies graphbrain source in
  - Runs `node bin/graphbrain.js init` from a *different* tmpdir simulating the user's repo (with a fake `.git/` so the project-dir guard passes)
  - **Core scaffold assertions**:
    - `<user-tmpdir>/.brain/{code,concepts,decisions}/` exist
    - `<user-tmpdir>/.brain/{index,log,overview,decisions,status}.md` exist with valid frontmatter
    - `<user-tmpdir>/.brain/.graphbrain-version` exists and contains `0.1.0` (per Design Decision #33)
    - `<user-tmpdir>/.claude/commands/brain.md` exists, starts with `<!-- graphbrain v0.1.0 -->`, and body matches the source template
    - `<user-tmpdir>/.claude/commands/graphbrain.md` exists with the same version marker
    - `<user-tmpdir>/.claude/settings.local.json` parses as valid JSON
    - `<user-tmpdir>/CLAUDE.md` contains `<!-- graphbrain:begin -->` and `<!-- graphbrain:end -->`
  - **Hooks-ownership assertions** (per Design Decision #32):
    - Pre-seed `<user-tmpdir>/.claude/settings.local.json` with a fake non-graphbrain hook: `{ "hooks": { "PreToolUse": [{ "matcher": "Bash", "hooks": [...], "id": "user:pre:my-hook" }] } }`
    - Run `node bin/graphbrain.js init`
    - Assert the `user:pre:my-hook` entry is **still present** post-init (non-graphbrain hooks preserved)
    - Assert the file parses as JSON post-init (no corruption)
  - **Re-init non-duplication** (per Design Decision #32):
    - Run `init` once, then run `init` again
    - Count entries in `settings.local.json` hooks arrays whose `id` starts with `graphbrain:` — must match between the two runs (no duplication)
    - All output lines from the second run start with `SKIP` (idempotency)
  - **Dry-run safety**:
    - Run `node bin/graphbrain.js init --dry-run` in a fresh tmpdir
    - Assert NO filesystem changes (no `.brain/`, no `.claude/commands/brain.md` written)
  - **Project-dir guard**:
    - Run `node bin/graphbrain.js init` in a tmpdir with NO `.git/`, NO `package.json`, etc., without `--global`
    - Assert exit code 1 + error message mentions project-dir requirements
  - **Claude-Code-presence soft check**:
    - Run `init` with `HOME` set to a tmpdir that does NOT contain `.claude/`
    - Assert output contains a WARN line about "Claude Code not detected"
    - Assert init still proceeds and exits 0
  - **Atomic-write resilience** (best-effort — hard to simulate crash in bash):
    - Pre-seed `<user-tmpdir>/.claude/settings.local.json` with a known-good JSON file
    - Run `init`
    - Assert `<user-tmpdir>/.claude/settings.local.json.bak` exists post-run (backup written)
  - **CLI verbs**:
    - `node bin/graphbrain.js update` prints the deferred-to-v0.2 message and exits 0
    - `node bin/graphbrain.js uninstall` prints its deferred message and exits 0
  - Pass/fail counter; exits non-zero on any failure; prints summary
  - Total runtime <5s
- **Mirror**: graphbrain `tests/e2e-test.sh` (pass/fail counter style; ~150 lines now given the expanded fixture set)
- **Validate**:
  - `bash tests/e2e-test.sh` exits 0 on a clean graphbrain checkout
  - `bash tests/e2e-test.sh` exits non-zero if the hooks-preservation assertion is broken (test by temporarily making init overwrite all hooks)
  - Total runtime confirmed <5s

## Validation

```bash
# 1. package.json is valid + npm pack respects the files whitelist
node -e "require('./package.json')"
npm pack --dry-run | tee /tmp/graphbrain-pack.txt
# Expect: only bin/, scripts/, commands/, skills/, agents/, reference/llm-wiki.md,
# reference/claude-code-conventions.md, README.md, LICENSE
! grep -E "\.claude/|tests/|CLAUDE\.md" /tmp/graphbrain-pack.txt
# Expect: exit 0 (no matches — these stay out of the published tarball)

# 2. CLI entry runs
node bin/graphbrain.js version           # prints 0.1.0
node bin/graphbrain.js                   # prints help
node bin/graphbrain.js help              # prints help
node bin/graphbrain.js bogus-verb        # prints help + non-zero exit

# 3. JSON files well-formed
node -e "require('./package.json'); require('./skills/registry.json'); require('./agents/registry.json'); console.log('OK')"

# 4. All required surface files exist
for f in \
  package.json \
  bin/graphbrain.js \
  scripts/init.js \
  commands/brain.md \
  commands/graphbrain.md \
  skills/behavioral/graphbrain/SKILL.md \
  skills/registry.json \
  skills/README.md \
  agents/registry.json \
  agents/README.md \
  reference/claude-code-conventions.md \
  reference/llm-wiki.md \
  LICENSE \
  README.md \
  CLAUDE.md \
  .gitignore \
  .npmignore \
  tests/e2e-test.sh \
  .claude/prds/graphbrain.prd.md \
  .claude/plans/graphbrain.plan.md
do
  test -f "$f" || { echo "MISSING: $f"; exit 1; }
done
echo "All surface files present"

# 4b. Tier + category directories reserved
find skills agents -type d -maxdepth 1 | sort
# Expect: skills/, skills/{behavioral,ingestion,core,detected,available}/, agents/, agents/{brain,observers}/

# 5. YAML frontmatter parseable on shipped templates
for f in commands/brain.md commands/graphbrain.md skills/behavioral/graphbrain/SKILL.md; do
  head -1 "$f" | grep -q '^---$' || { echo "BAD FRONTMATTER: $f"; exit 1; }
done

# 6. E2E test (automates the previous manual smoke test)
bash tests/e2e-test.sh
# Expect: exit 0, runtime <5s, summary line shows all PASS
```

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| `scripts/init.js` JSON-merge corrupts an existing `.claude/settings.local.json` | Med | Always write `.bak` before edit; JSON-aware merge (parse + manipulate AST, never text concat); E2E test covers the "existing settings.local.json with prior hooks" case (Task 15 should add this fixture) |
| Operator runs `graphbrain init` outside a project dir → pollutes `~` or `cwd` | Med | Project-dir guard refuses if no `.git/`, `package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`; explicit error; `--global` is the only path that writes to `~/.claude/` |
| `npm pack` includes `.claude/` (PRD/plans) or `CLAUDE.md` in the published tarball | Low | `files:` whitelist in `package.json` is the primary control; `.npmignore` as backstop; Validation §1 asserts the tarball contents explicitly |
| `npx graphbrain init` runs against a Claude Code config layout that's changed | Low | `reference/claude-code-conventions.md` is the canonical contract — if Claude Code changes, update that file then update `init.js` to match; a post-MVP CI check could fetch the current convention docs and diff |
| Operator confuses Milestone #1 stubs for broken behavior | Med | Each stub message explicitly says "Milestone #N — not yet implemented; see README roadmap"; README's Roadmap section uses status indicators |
| Alias file drift (`brain.md` and `graphbrain.md` diverge over time) | Low | Future milestones edit `brain.md` and re-copy to `graphbrain.md`; consider CI assertion of body equality post-MVP |
| Operator runs `init --global` then later wants project-local — needs to clean up | Low | Document in README; defer `graphbrain uninstall` to post-MVP |
| Idempotency bug: re-running init duplicates the CLAUDE.md schema block | Med | Init checks for `<!-- graphbrain:begin -->` marker before append; E2E test (Task 15) re-runs init and asserts no diff |
| `npm publish` fails due to a name conflict (someone else owns `graphbrain` on npm) | Med | **Action item before publish, not for M#1**: `npm view graphbrain` to check availability; fallback names: `@<scope>/graphbrain`, `graphbrain-cli`, `the-graphbrain` |

## Acceptance

- [ ] All 15 tasks complete
- [ ] Validation §1 (`package.json` valid, `npm pack --dry-run` whitelist respected) passes
- [ ] Validation §2 (CLI entry runs for `version`, `help`, no-arg, bogus verb) passes
- [ ] Validation §3 (JSON files well-formed) passes
- [ ] Validation §4 + §4b (all surface files present; skill/agent tier+category directories reserved) passes
- [ ] Validation §5 (frontmatter parseable) passes
- [ ] Validation §6 (E2E test: scaffold + idempotent re-run + dry-run + project-dir guard) passes, <5s
- [ ] PRD Milestone #1 row updated to `in-progress` with plan link
- [ ] Patterns mirrored from ECC + graphbrain comparison (skill format, agent frontmatter, registry, dual-layer guardrails, prompt-defense reference, 5-tier skills, project-local init default) — not reinvented
- [ ] `scripts/init.js` is idempotent (re-run produces only SKIPs), JSON-merge preserves existing settings, refuses to run outside a project dir without `--global`
- [ ] No `.claude-plugin/` directory, no `plugin.json`, no `marketplace.json` (Design Decision #29)
- [ ] No `.github/` directory, no `SECURITY.md`, no `CONTRIBUTING.md`, no `CODE_OF_CONDUCT.md`, no `CHANGELOG.md` (Design Decision #30 — deferred)
