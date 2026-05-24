# Plan: codebrain — Milestone #3a (Single-file ingest, end-to-end loop)

**Source PRD**: `.claude/prds/codebrain.prd.md`
**Selected Milestone**: #3a — first sub-step of the 3-way split of original M#3 (Ingest pipeline)
**Complexity**: Medium — first writer agent in codebrain; introduces a new tier (ingestion); pure-LLM ingest (no AST per PRD #5); deliberately scope-locked to single-file to prove the architecture before scaling

## Summary

Prove the end-to-end ingest loop on the smallest possible input: `/brain ingest src/auth.ts` → ingester agent reads the file → writes a folder-mirrored code page at `.brain/code/src/auth.ts.md` using a verbatim template → updates `index.md`, `log.md`, `status.md`. Multi-file/folder ingest (M#3b) and tiered auto-prioritize (M#3c) are deferred. This milestone establishes the first writer agent in codebrain — locking in the dual-layer guardrails pattern (agent self-rules now; structural PreToolUse hook lands in M#4) that every subsequent writer agent (linker M#3b, verifier M#6) will copy.

## Patterns to Mirror

| Category | Source | Pattern |
|---|---|---|
| Agent file format | `agents/README.md` (the spec) + (no existing agents — this is the first) | YAML frontmatter merging ECC + graphbrain shape (`name`, `description`, `tools`, `model`, `pattern`, `trigger_phrases`, `max_iterations`); body with persona + `## Rules` (self-enforcing, dual-layer guardrail's semantic half — PRD #19) + prompt-defense reference line (PRD #20) |
| Skill format + tier placement | `skills/core/init/SKILL.md:1-9` + `skills/README.md` | Merged frontmatter (`name`, `description`, `origin`, `version`, `tier`, `pattern`, `related_skills`); lands under `skills/ingestion/page-format/` because it's loaded during `/brain ingest` (tier definition from PRD #21) |
| Verbatim template the agent reads | `skills/core/init/templates/claude-md-schema.md` + `skills/core/init/templates/overview-starter.md` | Template file with `<!-- AGENT: ... -->` instruction comments per section; the agent reads it and fills it in (NOT paraphrases) |
| Slash-command verb wiring (load-bearing contract) | `commands/brain.md:50-130` (M#2's `When $ARGUMENTS is init` section) | Numbered step procedure embedded in the slash-command body; preconditions → read inputs → do work → log → report; if any step fails, emit `FAILED at Step <N>: <reason>` and stop |
| Page frontmatter (Dataview-compatible) | `scripts/init.js:148-156` (`frontmatter` helper) + `skills/core/init/templates/claude-md-schema.md` (the spec) | `kind: code`, `status: FRESH`, `source: <relative-path>`, `source_hash: <git-hash>`, `last_ingested: <ISO date>`, `ingested_by: <model>`, `tokens: <int>` |
| Tests | `tests/e2e-test.sh` (T1–T13) | bash; pass/fail counter; structural assertions only (LLM behavior is not bash-testable); <5s runtime |
| Log entry | `skills/core/init/templates/claude-md-schema.md` (grep-parseable prefix spec) + PRD #15 | `## [YYYY-MM-DD] ingest \| <relative-path> → .brain/code/<relative-path>.md` |
| Error recovery | PRD #26 (locked) | Tier 1: retry once with fresh context; Tier 2: emit structured `blocked: ingester couldn't complete <task>. Reason: <why>. Operator action: <what>.` and stop |

**Patterns we are NOT mirroring (intentional):**
- graphbrain's `brain-ingester` AGENT.md is a useful reference (it has a similar 5-phase procedure) but its `.ctx/` paths and conventions differ from codebrain's `.brain/` — adapt, don't copy.
- ECC's `tdd-guide` and other writer agents — those operate on user source code; codebrain's ingester writes only to `.brain/` and is therefore much narrower.
- No AST helper (PRD #5 locks pure-LLM); if precision is poor on dogfood, the fix is better prompts / multi-pass / a wikilink-resolver agent — not external extraction.
- Concept pages, cross-page wikilinks, multi-file batching — all deferred to M#3b (need 2+ pages first to be meaningful).

## Sweep Findings Folded In (M#3a Critical)

The plan was reviewed for gaps after first draft. Four high/medium-severity issues found:

1. **Template discovery from npm-installed location is unreliable** → **inline the page-format template content into the `commands/brain.md` ingest section** (same architectural choice as M#2's init: slash-command body is the load-bearing contract). The standalone `skills/ingestion/page-format/templates/code-page.md` file still ships (for documentation, M#6 verifier reuse), but the load-bearing copy is inline in commands/brain.md.
2. **Source-hash format consistency** → always prepend a format prefix: `git:abc...` (when in a git repo, via `git hash-object`) or `sha256:abc...` (fallback). M#4 staleness hook will read the prefix to know what to compare against.
3. **Binary-file guard** → refuse if the file extension is in a blocklist (`.png,.jpg,.gif,.webp,.pdf,.exe,.bin,.so,.dylib,.o,.a,.zip,.tar,.tgz,.gz,.mp4,.mp3,.wav`) OR if the first 1KB read fails a "mostly text" heuristic (e.g., contains a null byte).
4. **Out-of-repo path guard** → refuse if `path.resolve(cwd, arg)` does NOT start with cwd. Prevents `/brain ingest /etc/passwd`.

Five polish items also folded in:

5. **Empty file handling** — produce a minimal page with all sections marked `_(empty file)_`. Don't fail.
6. **Symlink handling** — refuse symlinks in M#3a (return error + suggest the operator pass the target path directly).
7. **Non-code files** (CSS, SQL, YAML, JSON config) — Purpose section instructions explicitly allow descriptions of "what the file configures, declares, or documents"; Exports/Imports become `_(none)_`.
8. **`## Code pages` section in index.md** doesn't pre-exist after M#1's init scaffold — the agent creates the section if missing on first ingest.
9. **Token count is the agent's best estimate** (no runtime tokenizer) — document in the template's instruction comment as "informational; off by ±20% is fine; not enforced".

## Files to Change

| File | Action | Why |
|---|---|---|
| `agents/brain/ingester.md` | CREATE | First writer agent. Merged ECC + graphbrain frontmatter; persona + Rules + prompt-defense reference; trigger_phrases enable natural-language activation alongside `/brain ingest`; `max_iterations: 5` per PRD #26 |
| `skills/ingestion/page-format/SKILL.md` | CREATE | The skill that defines what a `.brain/code/*.md` page **must** contain — frontmatter spec, required sections, wikilink rules. Tier: `ingestion` (loaded during `/brain ingest` per PRD #21) |
| `skills/ingestion/page-format/templates/code-page.md` | CREATE | The verbatim template the ingester reads and fills in. Sections: Purpose, Exports, Imports, Key behaviors, Cross-references. Each section prefaced with `<!-- AGENT: ... -->` instruction comments. |
| `commands/brain.md` | UPDATE | Replace the `ingest` row in the dispatch table with full agent instructions (single-file case only); folder + no-arg cases stay stubbed with explicit "coming in M#3b/c" pointers |
| `commands/codebrain.md` | UPDATE | Mirror brain.md changes (alias parity) |
| `tests/e2e-test.sh` | UPDATE | Add T14 (agent + skill + template structural assertions, alias parity, npm pack inclusion) and T15 (ingest verb wiring: single-file no longer stubbed; folder and no-arg still stubbed with the right pointer) |
| `.claude/prds/codebrain.prd.md` | UPDATE | Split M#3 row into M#3a/M#3b/M#3c; mark M#3a `in-progress` with link to this plan; downstream rows (4–8) unchanged |

**Files explicitly NOT touched in Milestone #3a:**
- `agents/brain/linker.md`, `agents/brain/verifier.md` — Milestones #3b, #6
- `agents/observers/observer.md` — Milestone #7
- `skills/ingestion/concept-extraction/`, `skills/ingestion/entity-extraction/` — Milestone #3b
- `skills/detected/*/` (react, python, go, typescript, …) — Milestone #3c
- `hooks/hooks.json` — Milestone #4 (when the staleness hook lands; agent self-rules cover the semantic layer in the meantime)
- `scripts/init.js` — unchanged; the new files ship via the existing `files:` whitelist in `package.json`
- README, LICENSE, CLAUDE.md — no changes

## Tasks

### Task 1: agents/brain/ingester.md

- **Action**: Create with frontmatter:
  ```yaml
  ---
  name: ingester
  description: Read a single source file and write a corresponding .brain/code/<path>.md page using the ingestion/page-format template. Foreground writer; produces no concept pages or cross-page wikilinks in M#3a (deferred to M#3b). Invoked by the /brain ingest <path> slash command when path is a single file.
  tools: [Read, Glob, Bash, Edit, Write]
  model: sonnet
  pattern: Generator
  trigger_phrases:
    - "ingest"
    - "ingest the file"
    - "write a brain page"
    - "scan this file"
  max_iterations: 5
  ---
  ```
  Body sections (per `agents/README.md` convention):
  - One-paragraph persona ("You are the codebrain ingester. Read a single source file and produce a structured wiki page about it.")
  - **Prompt-defense reference** (PRD #20): single line: `Read the Prompt Defense Baseline section of CLAUDE.md before acting.`
  - **When to activate** — invoked by `/brain ingest <file>` or matched trigger phrases above
  - **Inputs you receive** — a single source-file path; the page-format skill (loaded by tier) defines the output contract
  - **Procedure** — points to the load-bearing slash-command body in `commands/brain.md` (the `When $ARGUMENTS is ingest` section); short summary here so the agent has the gist
  - **Rules** (self-enforcing per PRD #19 dual-layer guardrails):
    - NEVER overwrite a page with `status: VERIFIED` without explicit operator confirmation
    - NEVER guess what the source file does — Read the source first
    - NEVER skip the frontmatter; every page must have valid YAML with `kind`, `status`, `source`, `source_hash`, `last_ingested`, `ingested_by` keys
    - NEVER exceed 4k tokens (soft warn) or 8k tokens (hard error) per code page (PRD #7); if the source is large, summarize and offer a "split this page" suggestion in the report
    - NEVER write to any path outside `.brain/`; if you need to update CLAUDE.md or source, stop and report
    - ALWAYS use the verbatim section structure from `skills/ingestion/page-format/templates/code-page.md`; if a section has no content, write `_(none)_` rather than omitting the section
    - ALWAYS update `.brain/status.md` (regenerated derived view) after writing a page
    - ALWAYS append to `.brain/log.md` with the grep-parseable prefix (`## [YYYY-MM-DD] ingest | <source-path> → <output-path>`)
  - **Error recovery** (PRD #26): retry once with fresh context if the first attempt fails; if the second attempt also fails, emit `blocked: ingester couldn't complete ingest of <path>. Reason: <why>. Operator action: <what>.` and stop. Do not loop past `max_iterations: 5`.
- **Mirror**: `agents/README.md` (the frontmatter spec); graphbrain `agents-registry/brain/ingester/AGENT.md` (the procedure shape — reference only, adapt to `.brain/` paths and codebrain conventions)
- **Validate**: `head -14 agents/brain/ingester.md | grep -q '^---$'`; `grep -c "^- NEVER\|^- ALWAYS" agents/brain/ingester.md` ≥ 7 (rules section present); `grep -q "Read the Prompt Defense Baseline" agents/brain/ingester.md`

### Task 2: skills/ingestion/page-format/SKILL.md

- **Action**: Create with frontmatter:
  ```yaml
  ---
  name: page-format
  description: Defines the required shape of a .brain/code/<path>.md page — frontmatter fields, section structure, wikilink convention, page-size cap. Loaded during /brain ingest. Every ingester (and future verifier in M#6) reads this skill to know what a valid page looks like.
  origin: codebrain
  version: 0.1.0
  tier: ingestion
  pattern: Reviewer
  related_skills: [behavioral/codebrain]
  ---
  ```
  Body sections:
  - **When to Activate** — automatically loaded during any `/brain ingest` invocation; also referenced by `/brain lint` (M#6) when validating page shape
  - **How It Works** — describes the page contract (frontmatter required fields, section order, what each section means, when to use `_(none)_`)
  - **Page contract** — full frontmatter spec table + section spec table
  - **Wikilink convention** — even though M#3a doesn't produce cross-page wikilinks, document the format `[[code/src/path.ts]]` and `[[concepts/<name>]]` for when M#3b adds them
  - **Page-size cap** (PRD #7): code pages 4k soft warn / 8k hard error
  - **Examples** — show a minimal valid page + a populated example
- **Mirror**: `skills/core/init/SKILL.md` (frontmatter shape + section structure)
- **Validate**: `head -10 skills/ingestion/page-format/SKILL.md | grep -q "tier: ingestion"`; all 7 frontmatter fields present

### Task 3: skills/ingestion/page-format/templates/code-page.md

- **Action**: Create the verbatim template the ingester fills in. Structure:
  ```markdown
  ---
  kind: code
  status: <!-- AGENT: insert FRESH on first ingest, RESYNCED on refresh -->
  source: <!-- AGENT: insert relative path from repo root, e.g. src/api/auth.ts -->
  source_hash: <!-- AGENT: insert `git hash-object <source-path>` result (run via Bash) -->
  last_ingested: <!-- AGENT: insert ISO YYYY-MM-DD -->
  ingested_by: <!-- AGENT: insert your model identifier, e.g. claude-sonnet-4-6 -->
  tokens: <!-- AGENT: insert your best estimate of page token count -->
  ---

  # <!-- AGENT: source-path verbatim, e.g. src/api/auth.ts -->

  ## Purpose
  <!-- AGENT: 1-3 sentences. What this file is responsible for. Infer from
       the file's symbols, comments, imports/exports, and any docstring at
       the top. Be concrete about responsibility; avoid generic phrases like
       "this module". If you cannot infer, write "_(unclear — investigate)_". -->

  ## Exports
  <!-- AGENT: bullet list of exported symbols (functions, classes, constants,
       types). One line per symbol: `- name: one-line purpose`. If the file
       has no exports, write "_(none)_". Keep purposes 1 line; do not
       enumerate parameters or return types here. -->

  ## Imports
  <!-- AGENT: bullet list grouped by source module. Format:
         - from `<module>`: <name1>, <name2> — <why this file needs them>
       Skip stdlib imports unless they're load-bearing (e.g., `fs/promises`
       for a file that reads disk). If nothing notable, write "_(none)_". -->

  ## Key behaviors
  <!-- AGENT: bullet list of notable behaviors, error paths, side effects,
       I/O, state mutation, network calls. NOT a line-by-line transcription
       of the code — pick the 3-7 things a reader most needs to know.
       If the file is trivial (e.g., a re-export shim), write "_(trivial —
       see Exports above)_". -->

  ## Cross-references
  <!-- AGENT: wikilinks to other .brain/code/ pages this file calls or
       extends. Format: `- [[code/src/path/other.ts]] — <why linked>`.
       In Milestone #3a there is typically only one page (this one), so
       this section is usually "_(none yet — see Milestone #3b for
       cross-page linking)_". If you have evidence of imports from other
       files in the repo that you know will be ingested later, you MAY
       wikilink to them; the lint pass (M#6) will flag dangling links. -->
  ```
- **Mirror**: `skills/core/init/templates/overview-starter.md` (the `<!-- AGENT: ... -->` instruction-comment pattern; agent reads, fills in, does NOT paraphrase the structure)
- **Validate**: `head -1 skills/ingestion/page-format/templates/code-page.md` is `---`; file contains all 5 section headers (`## Purpose`, `## Exports`, `## Imports`, `## Key behaviors`, `## Cross-references`); contains the literal string `<!-- AGENT:` at least 10 times (instructions densely present)

### Task 4: Update commands/brain.md — wire the single-file ingest case

- **Action**: Replace the `ingest` row in the dispatch table with a reference to the procedure section, then add the procedure section after the existing init section. Concretely:

  In the dispatch table, change:
  ```
  | `ingest` | not implemented | `Milestone #3 (Ingest pipeline) — not yet implemented in v0.1. See the Roadmap section of the codebrain README.` |
  ```
  to:
  ```
  | `ingest <single-file-path>` | **implemented (M#3a)** | See "When `$ARGUMENTS` starts with `ingest <file>`" below |
  | `ingest <folder/>` | not implemented | `Milestone #3b (folder ingest + concept pages) — not yet implemented. Pass a single file path for now.` |
  | `ingest` (no args) | not implemented | `Milestone #3c (tiered auto-prioritize) — not yet implemented. Pass a single file path for now.` |
  ```

  Then add a new section after the existing `## When $ARGUMENTS is init` section:

  ```markdown
  ## When `$ARGUMENTS` starts with `ingest <file>`

  You are the codebrain ingester. The operator has invoked `/brain ingest <file-path>`. Run this procedure exactly. If any step's preconditions fail, emit a clear error and stop.

  **Step 0 — Argument parsing + path guards**:
  - Extract the path arg from `$ARGUMENTS` (the token after `ingest`).
  - If no path was given: print `Milestone #3c (tiered auto-prioritize, no-arg ingest) — not yet implemented. Pass a single file path: /brain ingest src/auth.ts` and stop.
  - **Out-of-repo guard** (sweep finding #4): compute `path.resolve(cwd, arg)`. If the resolved absolute path does NOT start with cwd: print `error: refused — <path> resolves outside the project root` and stop.
  - **Symlink guard** (sweep finding #6): `lstat` the resolved path; if it's a symlink, print `error: refused — symlinks not supported in M#3a; pass the target path directly` and stop.
  - Resolve the path against cwd. If the resolved path is a directory: print `Milestone #3b (folder ingest) — not yet implemented. Pass a single file path: /brain ingest src/auth.ts` and stop.
  - If the resolved path does not exist: print `error: file not found: <path>` and stop.
  - **Binary-file guard** (sweep finding #3): check the file extension against the blocklist `[.png, .jpg, .jpeg, .gif, .webp, .pdf, .exe, .bin, .so, .dylib, .o, .a, .zip, .tar, .tgz, .gz, .mp4, .mp3, .wav, .ico, .ttf, .woff, .woff2]`. If matched, print `error: refused — <path> looks like a binary file (extension <ext>); codebrain ingests text source files only` and stop. Additionally, read the first 1024 bytes; if a null byte is present, treat as binary and refuse with the same message.

  **Step 1 — Preconditions**:
  - Verify `.brain/` exists in cwd. If not: same `npx codebrain init` first message as `/brain init` (Step 1).
  - Read `.brain/.codebrain-version` to confirm M#1's scaffold is present.

  **Step 2 — Read inputs**:
  - Read the source file in full.
  - Read `skills/ingestion/page-format/SKILL.md` to refresh the page contract.
  - Read `skills/ingestion/page-format/templates/code-page.md` to get the template.
  - Read `agents/brain/ingester.md` if you have not already loaded the ingester's persona + rules in this session.

  **Step 3 — Compute output path and source hash** (sweep finding #2 — format-prefixed):
  - Mirror the source path under `.brain/code/`: `src/api/auth.ts` → `.brain/code/src/api/auth.ts.md`
  - Try `git hash-object <source-path>` via Bash. If it succeeds, the `source_hash` value is `git:<hash>`.
  - If git is unavailable or the repo isn't a git repo, fall back to SHA-256 via `shasum -a 256 <source-path> | awk '{print $1}'`. The `source_hash` value is `sha256:<hash>`.
  - If BOTH fail, emit `blocked: ingester couldn't compute source hash for <path>. Reason: neither git nor shasum produced a result. Operator action: install git or ensure shasum is on PATH.` and stop.
  - **Empty-file handling** (sweep finding #5): if the source file is 0 bytes, skip the read in Step 4 and produce a minimal page with all sections marked `_(empty file)_`; frontmatter still has source/source_hash/etc.; tokens estimate is 0.
  - If the output path already exists with `status: VERIFIED` in its frontmatter AND `$ARGUMENTS` does not contain `--force`: print `SKIP <output-path> (status: VERIFIED — pass --force to override)` and stop.
  - If the output path exists with current frontmatter `source_hash` matching the just-computed hash (including the format prefix) AND `$ARGUMENTS` does not contain `--force`: print `SKIP <output-path> (already current, source unchanged)` and stop.

  **Step 4 — Fill the template**:
  - For each `<!-- AGENT: ... -->` instruction comment in `code-page.md`, follow its directive using your reading of the source file:
    - Frontmatter: insert source path, source hash, today's ISO date, your model identifier, your estimated token count
    - `# <source-path>` header: the relative path verbatim
    - Purpose / Exports / Imports / Key behaviors / Cross-references: per the instruction comments
  - If you cannot produce content for a section, write `_(none)_` or the section-specific fallback the template specifies. Never omit a section.
  - Self-check page size: aim for <4k tokens (soft warn). If the page approaches 8k (hard error), summarize more aggressively or suggest the operator break the source file into smaller modules in your report.

  **Step 5 — Write the page**:
  - Ensure `.brain/code/<dir-of-source>/` exists (create directories as needed).
  - Write the filled template to `.brain/code/<source-path>.md`.

  **Step 6 — Update derived files**:
  - `.brain/index.md`: append a one-line entry under a `## Code pages` section. If the section doesn't exist yet (sweep finding #8 — M#1's init.js ships a generic index.md without subsections), CREATE it as the first action; subsequent ingests append. Entry format: `- [[code/<source-path>]] — <one-line summary from your Purpose section>`. Dedupe if entry already present.
  - `.brain/status.md`: append/update a row in the status table: `| code/<source-path>.md | FRESH | <ISO date> | <source-hash-with-prefix> |`.
  - `.brain/log.md`: append under `## Activity History` using the grep-parseable prefix: `## [YYYY-MM-DD] ingest | <source-path> → .brain/code/<source-path>.md`.

  **Step 7 — Report**:

  Print exactly:
  ```
  /brain ingest complete (codebrain v<version>)
    Source:        <source-path>
    Page:          .brain/code/<source-path>.md (<token-count> tokens)
    Source hash:   <hash>
    Updated:       .brain/index.md, .brain/status.md, .brain/log.md
  Next: ingest more files individually for now (M#3b will add folder ingest + concept pages).
  ```

  If you encountered any failures during the procedure, replace the success report with `FAILED at Step <N>: <reason>` and exit. Do not partially complete and report success.

  **Error recovery** (per ingester agent rules, PRD #26): if a step fails for a transient reason (e.g., a Read returned partial content), retry that step once with fresh context. If it fails again, emit `blocked: ingester couldn't complete ingest of <path>. Reason: <why>. Operator action: <what>.` and stop. Do not exceed `max_iterations: 5`.
  ```

  Leave the other verb stubs (`query`, `lint`, `learn`, `status`) unchanged.

- **Mirror**: `commands/brain.md:80-148` (the M#2 `When $ARGUMENTS is init` section — same numbered-step shape, same error-report convention)
- **Validate**: `! grep -q 'ingest.*Milestone #3 (Ingest pipeline).*not yet implemented' commands/brain.md`; the new procedure section is present; folder + no-arg stubs are present with M#3b/M#3c pointers

### Task 5: Update commands/codebrain.md (alias parity)

- **Action**: Copy Task 4's procedure section verbatim into `commands/codebrain.md` (same `## When $ARGUMENTS starts with ingest <file>` heading). Mirror the dispatch-table changes.
- **Validate**: T14 (in Task 6) asserts the ingest procedure section is byte-identical between brain.md and codebrain.md, same way T12 does for the init procedure

### Task 6: Update tests/e2e-test.sh — M#3a assertions

- **Action**: Add two new test sections (T14, T15) just before the Summary section. Pattern: mirror T10/T11/T12/T13's style (grouped per concern, pass/fail counter, structural assertions only).

  **T14 — M#3a agent + skill + template surface**:
  - `agents/brain/ingester.md` exists with YAML frontmatter and all 7 merged-frontmatter fields (name, description, tools, model, pattern, trigger_phrases, max_iterations)
  - `agents/brain/ingester.md` contains a `## Rules` section header
  - `agents/brain/ingester.md` contains the prompt-defense-reference line (`grep -q "Read the Prompt Defense Baseline"`)
  - `agents/brain/ingester.md` has `max_iterations:` set to an integer (regex check)
  - `skills/ingestion/page-format/SKILL.md` exists with frontmatter; `tier: ingestion`; all 7 fields present
  - `skills/ingestion/page-format/templates/code-page.md` exists; starts with `---`; contains the 5 section headers (Purpose, Exports, Imports, Key behaviors, Cross-references); contains `<!-- AGENT:` at least 10 times
  - `npm pack --dry-run` includes the new agent file, the SKILL.md, and the template

  **T15 — `ingest` verb wiring**:
  - `! grep -q 'ingest.*Milestone #3 (Ingest pipeline).*not yet implemented' commands/brain.md` (the original M#3 stub is gone)
  - `grep -q "When \`\$ARGUMENTS\` starts with \`ingest <file>\`" commands/brain.md` (new procedure section is present)
  - `grep -q "Step 7 — Report" commands/brain.md` after the ingest section (numbered procedure complete)
  - Folder and no-arg cases still produce M#3b/M#3c "not yet implemented" pointers (grep for the exact strings)
  - Alias parity: the ingest procedure section is byte-identical between `commands/brain.md` and `commands/codebrain.md` (`diff <(sed -n '/^## When `\$ARGUMENTS` starts with `ingest <file>`$/,$p' brain.md) <(sed -n '...' codebrain.md)` is empty)
- **Mirror**: T10–T13 from `tests/e2e-test.sh`
- **Validate**: `bash tests/e2e-test.sh` exits 0; total count goes from 73 → ~90 (~17 new assertions); runtime still <5s

### Task 7: PRD update — split M#3 into 3a/3b/3c

- **Action**: Edit `.claude/prds/codebrain.prd.md`. In the Delivery Milestones table, replace the existing M#3 row:
  ```
  | 3 | Ingest pipeline | ... | pending | — |
  ```
  with three rows:
  ```
  | 3a | Ingest pipeline — single-file end-to-end | `/brain ingest <single-file-path>` invokes the ingester agent which writes `.brain/code/<path>.md` using the page-format template; updates index/status/log; idempotent on unchanged source | in-progress | [.claude/plans/codebrain-m3a.plan.md](.claude/plans/codebrain-m3a.plan.md) |
  | 3b | Ingest pipeline — folder + concept pages + linker | `/brain ingest <folder>` walks the folder, ingests each file via the M#3a ingester; linker agent creates concept pages for cross-cutting ideas and wires bidirectional wikilinks | pending | — |
  | 3c | Ingest pipeline — tiered auto-prioritize + detected/* skills | `/brain ingest` (no args) proposes a 3-tier plan based on stack detection, pauses between tiers; detected/{react,python,go,typescript} skills ship and light up stack-aware page templates | pending | — |
  ```
  Downstream rows (4–8) unchanged.
- **Mirror**: M#1 + M#2 PRD update pattern
- **Validate**: `grep "Ingest pipeline" .claude/prds/codebrain.prd.md | wc -l` returns 3

## Validation

```bash
# 1. E2E test (combined M#1 + M#2 + M#3a surface)
bash tests/e2e-test.sh
# Expect: ~90 passes, 0 failures, <5s

# 2. New files exist with correct shape
test -f agents/brain/ingester.md
test -f skills/ingestion/page-format/SKILL.md
test -f skills/ingestion/page-format/templates/code-page.md
head -1 agents/brain/ingester.md | grep -q '^---$'
head -1 skills/ingestion/page-format/SKILL.md | grep -q '^---$'

# 3. Agent has Rules section + prompt-defense reference
grep -q '^## Rules' agents/brain/ingester.md
grep -q 'Read the Prompt Defense Baseline' agents/brain/ingester.md
grep -cE '^- (NEVER|ALWAYS) ' agents/brain/ingester.md  # ≥ 7

# 4. Ingest verb is wired for single-file; folder + no-arg still stubbed
! grep -q 'ingest.*Milestone #3 (Ingest pipeline).*not yet implemented' commands/brain.md
grep -q 'Milestone #3b' commands/brain.md   # folder case points to 3b
grep -q 'Milestone #3c' commands/brain.md   # no-arg case points to 3c

# 5. Alias parity for ingest procedure
diff <(sed -n '/^## When `$ARGUMENTS` starts with `ingest <file>`$/,$p' commands/brain.md) \
     <(sed -n '/^## When `$ARGUMENTS` starts with `ingest <file>`$/,$p' commands/codebrain.md)
# Expect: empty diff

# 6. npm pack ships the new files
npm pack --dry-run | grep -E 'agents/brain/ingester.md|skills/ingestion/page-format/'

# 7. Manual smoke test (operator) — the agent-behavior part bash can't test:
#  In a Claude Code session inside a repo that already ran `npx codebrain init`
#  and `/brain init`:
#     /brain ingest src/somefile.ts
#       → ingester reads the file, writes .brain/code/src/somefile.ts.md
#       → page has valid frontmatter (kind: code, status: FRESH, source: ...)
#       → page has all 5 sections, each populated or marked _(none)_
#       → page token count <4k
#       → .brain/index.md gains a "Code pages" entry
#       → .brain/status.md gains a row
#       → .brain/log.md gets the grep-parseable entry
#     /brain ingest src/somefile.ts (re-run, source unchanged)
#       → SKIP (already current, source unchanged)
#     /brain ingest src/
#       → folder-case stub: "Milestone #3b (folder ingest) — not yet implemented"
#     /brain ingest
#       → no-arg stub: "Milestone #3c (tiered auto-prioritize) — not yet implemented"
#     /brain ingest some/nonexistent/path.ts
#       → "error: file not found: some/nonexistent/path.ts"
```

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Agent ignores the verbatim template and writes its own page shape | Med | Template uses `<!-- AGENT: ... -->` instruction comments (same pattern as M#2's `overview-starter.md`, which worked); ingester's Rules section forbids omitting sections; M#6 lint catches drift |
| Page exceeds the 4k soft / 8k hard cap on large source files | Med | Procedure Step 4 self-check; agent summarizes more aggressively past 4k; report includes a "consider splitting the source file" hint past 8k |
| Source hash computation fails (no git, no shasum) | Low | Procedure Step 3 falls back from `git hash-object` to `shasum -a 256`; if both fail, agent emits `blocked` with operator action ("install git or shasum") |
| `/brain ingest src/` (folder) accidentally triggers the single-file procedure | Low | Step 0 explicitly checks `if path is a directory` BEFORE doing any work; folder case stubs out cleanly |
| Re-running ingest on a modified source produces a duplicate page (path collision is impossible since path is deterministic, but content might double-up if the agent appends instead of overwrites) | Low | Step 5 says "write" not "append"; the page is replaced; the source-hash check in Step 3 makes re-ingest a SKIP unless content actually changed |
| First writer agent without the M#4 structural hook means agent self-rules are the ONLY guardrail | Med | This is by design — dual-layer is the target, but layers can land separately. Document in the ingester's body that the structural hook layer arrives in M#4. Ingester Rules cover the critical mutation guarantees (never overwrite VERIFIED, never write outside `.brain/`). |
| Alias drift between brain.md and codebrain.md ingest procedure | Low | T15 asserts the procedure section is byte-identical; same pattern as T12 for init |
| The agent invokes Bash for `git hash-object` but the tool isn't in the agent's `tools:` list | Low | Frontmatter declares `tools: [Read, Glob, Bash, Edit, Write]` — Bash is included; Glob for path resolution; Edit/Write for the page; Read for source + template |
| LLM ingest is expensive on a large source file (~5k LOC) | Low for M#3a (single-file is opt-in by the operator); high for M#3b/c | Out of scope for M#3a; M#3c's tiered auto-prioritize is where cost control matters |
| Operator confuses M#3 sub-milestones — "is folder ingest done yet?" | Low | Folder + no-arg cases produce explicit "Milestone #3b / #3c — not yet implemented" messages with the right pointer; PRD split rows make the roadmap obvious |

## Acceptance

- [ ] All 7 tasks complete
- [ ] Validation §1 (e2e test, ~90 assertions) passes; runtime <5s
- [ ] Validation §2 (files exist with correct shape) passes
- [ ] Validation §3 (Rules + prompt-defense reference in agent) passes
- [ ] Validation §4 (ingest verb wired for single-file; folder/no-arg stubbed) passes
- [ ] Validation §5 (alias parity) passes
- [ ] Validation §6 (npm pack includes new files) passes
- [ ] PRD M#3 row split into M#3a/M#3b/M#3c; M#3a in-progress with plan link
- [ ] Patterns mirrored from M#1 + M#2 + the agents/skills README conventions — not reinvented
- [ ] No regression: all 73 existing M#1+M#2 tests still pass; total ~90 after T14+T15 added
- [ ] (Optional but recommended) Manual smoke test on a real Claude Code session — `/brain ingest <some-source-file>` in the codebrain repo itself produces a valid `.brain/code/scripts/init.js.md` (or similar)
