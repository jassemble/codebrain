<!-- codebrain v0.1.0 -->
---
description: codebrain — agent-maintained codebase wiki (init, ingest, query, lint, learn, status)
---

# /brain

Codebrain's primary slash command. Dispatches on the first argument to one of six verbs.

`$ARGUMENTS` is parsed as `<verb> [args...]`. Route as follows:

## Dispatch

| Verb | Status | Action |
|---|---|---|
| `init` | **implemented** | See "When `$ARGUMENTS` is `init`" section below for the full agent procedure |
| `ingest <single-file-path>` | **implemented (M#3a)** | See "When `$ARGUMENTS` starts with `ingest <file>`" section below |
| `ingest <folder/>` | **implemented (M#3b)** | See "When `$ARGUMENTS` starts with `ingest <folder>`" section below |
| `ingest` (no args) | not implemented | `Milestone #3c (tiered auto-prioritize) — not yet implemented in v0.1. Pass a file or folder path for now: /brain ingest src/` |
| `query` | not implemented | `Milestone #5 (Query helper) — not yet implemented in v0.1. See the Roadmap section of the codebrain README.` |
| `lint` | not implemented | `Milestone #6 (Lint pass) — not yet implemented in v0.1. Will support \`--fix\` to batch re-ingest STALE pages.` |
| `learn` | not implemented | `Milestone #7 (Continuous-learning observer) — not yet implemented in v0.1. Subverbs will be \`on\`, \`off\`, \`status\`.` |
| `status` | not implemented | `Milestone #7 — not yet implemented in v0.1. Will show dashboard of total pages, % stale, recent log entries, top instincts.` |

## No argument (just `/brain`)

Print this help block:

```
/brain — codebrain commands

  /brain init                Scaffold .brain/ + CLAUDE.md schema block (Milestone #2)
  /brain ingest [path]       Read source files → write LLM-authored wiki pages (Milestone #3)
  /brain query "<question>"  Pointer-first lookup against the brain (Milestone #5)
  /brain lint [--fix]        Health-check the wiki; --fix batch-refreshes STALE pages (Milestone #6)
  /brain learn {on|off|status}   Toggle the continuous-learning observer (Milestone #7)
  /brain status              Brain dashboard (Milestone #7)

This is codebrain v0.1.0 — most verbs are stubs in this release. See the README
roadmap for the implementation schedule.

  Repository:  https://github.com/jassemble/codebrain
  PRD:         .claude/prds/codebrain.prd.md (if installed for development)
```

## Unknown verb

Print: `Unknown verb: <verb>. Run \`/brain\` (no arguments) for help.`

## When `$ARGUMENTS` is `init`

You are the codebrain init agent. Run this procedure exactly. If any step's preconditions fail, emit a clear error and stop — do not improvise.

**Step 1 — Preconditions**:

- Verify `.brain/` exists in cwd. If not, print this and stop:
  ```
  error: .brain/ not found in this repo.

  Run `npx codebrain init` first — that scaffolds the .brain/ skeleton.
  Then restart Claude Code (or open a new session) and re-run /brain init.
  ```
- Read `.brain/.codebrain-version` to confirm M#1's scaffold is present. If missing, print a similar error.
- Read `CLAUDE.md` from cwd. Locate `<!-- codebrain:begin -->` and `<!-- codebrain:end -->`. If either marker is missing, print and stop:
  ```
  error: CLAUDE.md is missing the codebrain managed-region markers.
  Re-run `npx codebrain init --force` to rewrite the markers, then retry /brain init.
  ```

**Step 2 — Read templates** (locate them in the installed codebrain npm package; the slash-command file you are reading was copied from `commands/brain.md` in that package, and the templates live alongside it under `skills/core/init/templates/`):

- `skills/core/init/templates/claude-md-schema.md` — the verbatim schema block
- `skills/core/init/templates/overview-starter.md` — the overview template with `<!-- AGENT: ... -->` instruction comments
- `skills/core/init/templates/stack-detection.json` — the stack-signal catalog

If you cannot locate these template files, ask the operator to run `npm root -g` (for global installs) or to point you at the codebrain package directory. Do not improvise the templates — the verbatim content is the contract.

**Step 3 — Splice schema block into CLAUDE.md**:

- Read `<cwd>/CLAUDE.md` in full.
- Extract the content between `<!-- codebrain:begin -->` and `<!-- codebrain:end -->`.
- Compare to the content of `claude-md-schema.md` (trimmed).
- If they match AND `$ARGUMENTS` does not contain `--force`: emit `SKIP CLAUDE.md (schema block already current)` and continue to Step 4.
- Otherwise: write the file with the new content between the markers (preserve everything outside the markers). This is the only modification to CLAUDE.md.
- Use a write strategy that preserves the file's existing line endings and final-newline state.

**Step 4 — Detect tech stack**:

- Parse `stack-detection.json`. For each entry in `stacks`, evaluate `signals`:
  - `{ "file_exists": "<path>" }` — match if `<cwd>/<path>` exists as a file
  - `{ "file_exists": "<path>", "contains": "<substring>" }` — match if file exists AND its content contains the substring
  - `{ "dir_exists": "<path>" }` — match if `<cwd>/<path>` exists as a directory
  - `{ "glob": "<pattern>" }` — match if at least one file matches the glob, relative to cwd
- A stack matches only if **all** of its `signals` match (logical AND).
- Collect the matched stack names. Dedupe (e.g., `python` and `python-legacy` both detect Python — report once as `python`).
- This is reporting-only for Milestone #2. Do NOT install any `detected/*` skills — those don't exist yet (Milestone #3 ships them).

**Step 5 — Populate overview.md**:

- Read `<cwd>/.brain/overview.md` (M#1 wrote a minimal skeleton).
- Use `overview-starter.md` as the new content template.
- For each `<!-- AGENT: ... -->` instruction comment in the template, follow its directive:
  - **Project Purpose** — infer from `package.json` description, `pyproject.toml` description, `README.md` tagline (first paragraph after H1), or top-level comments. If no signal: write the literal fallback the template specifies. Do not invent.
  - **Codebase Structure** — generate a 1-level dir tree of cwd's top-level entries (skip `.git`, `node_modules`, `.venv`, `__pycache__`, `dist`, `build`, `.brain`, `.claude`). Format as a bullet list with a one-line purpose per entry.
  - **Key Patterns** — write the exact placeholder line the template specifies; do not invent patterns at init time.
  - **Active State** — fill in: `Initialized: <today ISO YYYY-MM-DD>`, `Codebrain version: <from .brain/.codebrain-version>`, `Detected stack: <comma-separated list from Step 4>`, `Pages: <count from .brain/{code,concepts,decisions}>`, `Last ingest: never (run /brain ingest <path> to begin)`.
  - **Recent Activity** — exact placeholder line per template.
- Update the frontmatter: replace `<!-- AGENT: ... -->` placeholders in `created`, `last_ingested`, `ingested_by` with today's ISO date and your model identifier. Change `status: UNENRICHED` to `status: FRESH`.
- Write the result to `<cwd>/.brain/overview.md`. If the file already has populated content (not just M#1's skeleton) and `$ARGUMENTS` does not contain `--force`: emit `SKIP .brain/overview.md (already populated)` rather than overwrite.

**Step 6 — Log**:

- Append to `<cwd>/.brain/log.md` under the `## Activity History` section heading. Use the grep-parseable prefix from PRD Design Decision #15:
  ```
  ## [YYYY-MM-DD] init | /brain init populated schema block + overview; detected: <comma-separated stacks>
  ```
- Today's date in ISO format.

**Step 7 — Report**:

Print exactly:

```
/brain init complete (codebrain v<version-from-.codebrain-version>)
  Schema block:   <refreshed | unchanged>
  overview.md:    <populated | unchanged>
  Detected stack: <comma-separated list, or "(none detected)">
    Note: no `detected/` skills installed yet — coming in Milestone #3c.
  Logged:         .brain/log.md
Next: try `/brain ingest src/auth.ts` (single file — Milestone #3a is implemented).
      Folder ingest is Milestone #3b; no-arg tiered ingest is Milestone #3c.
```

If you encountered any failures during the procedure, replace the success report with a `FAILED at Step <N>: <reason>` line and exit. Do not partially complete and report success.

## When `$ARGUMENTS` starts with `ingest <file>`

You are the codebrain ingester (see `agents/brain/ingester.md` for your full persona + Rules; the Rules apply throughout this procedure). Run the procedure exactly. If any step's preconditions fail, emit a clear error and stop — do not improvise.

**Step 0 — Argument parsing + path guards**:

- Extract the path arg from `$ARGUMENTS` (the token after `ingest`).
- If no path was given: print `Milestone #3c (tiered auto-prioritize, no-arg ingest) — not yet implemented in v0.1. Pass a single file path: /brain ingest src/auth.ts` and stop.
- **Out-of-repo guard**: compute the absolute path. If it does NOT start with cwd: print `error: refused — <path> resolves outside the project root` and stop.
- **Symlink guard**: if the resolved path is a symlink (use `Bash: test -L <path>`), print `error: refused — symlinks not supported in v0.1; pass the target path directly` and stop.
- If the resolved path is a directory: print `Milestone #3b (folder ingest) — not yet implemented in v0.1. Pass a single file path: /brain ingest src/auth.ts` and stop.
- If the resolved path does not exist: print `error: file not found: <path>` and stop.
- **Binary-file guard**: check the file extension against the blocklist `[.png, .jpg, .jpeg, .gif, .webp, .pdf, .exe, .bin, .so, .dylib, .o, .a, .zip, .tar, .tgz, .gz, .mp4, .mp3, .wav, .ico, .ttf, .woff, .woff2]`. If matched, print `error: refused — <path> looks like a binary file (extension <ext>); codebrain ingests text source files only` and stop. Additionally, read the first 1024 bytes; if a null byte is present, treat as binary and refuse with the same message.

**Step 1 — Preconditions**:

- Verify `.brain/` exists in cwd. If not, print:
  ```
  error: .brain/ not found in this repo.
  Run `npx codebrain init` first to scaffold the skeleton, then re-run /brain ingest.
  ```
  and stop.
- Read `.brain/.codebrain-version` to confirm M#1's scaffold is present.

**Step 2 — Read inputs**:

- Read the source file in full when it fits (<4k tokens). For larger files, Read in chunks using offset/limit; do NOT skim by sampling random lines — read sequentially.
- The page contract (frontmatter + 5 required sections, fallback strings, page-size cap) is defined below. The verbatim template is the literal-text fenced block in Step 4. The standalone files `skills/ingestion/page-format/SKILL.md` and `skills/ingestion/page-format/templates/code-page.md` document the same contract (load them only if you need extended examples).

**Step 3 — Compute output path and source hash** (format-prefixed per PRD Design Decision #32):

- Mirror the source path under `.brain/code/`: `src/api/auth.ts` → `.brain/code/src/api/auth.ts.md`
- Try `git hash-object <source-path>` via Bash. If it succeeds, the `source_hash` value is `git:<hash>`.
- If git is unavailable or the repo isn't a git repo, fall back to SHA-256 via `shasum -a 256 <source-path> | awk '{print $1}'`. The `source_hash` value is `sha256:<hash>`.
- If BOTH fail, emit `blocked: ingester couldn't compute source hash for <path>. Reason: neither git nor shasum produced a result. Operator action: install git or ensure shasum is on PATH.` and stop.
- **Empty-file handling**: if the source file is 0 bytes, skip the read in Step 4 and produce a minimal page with all sections marked `_(empty file)_` or per the fallback strings below; tokens estimate is 0.
- If the output path already exists with `status: VERIFIED` in its frontmatter AND `$ARGUMENTS` does not contain `--force`: print `SKIP <output-path> (status: VERIFIED — pass --force to override)` and stop.
- If the output path exists with current frontmatter `source_hash` matching the just-computed hash (including the format prefix) AND `$ARGUMENTS` does not contain `--force`: print `SKIP <output-path> (already current, source unchanged)` and stop.

**Step 4 — Fill the template**:

Use this verbatim template as the structure. Replace each `<!-- AGENT: ... -->` instruction comment with content per its directive. Do NOT omit a section; if you have no content, write the fallback string shown after each instruction:

```markdown
---
kind: code
status: FRESH
source: <source-path verbatim>
source_hash: <prefixed hash from Step 3>
last_ingested: <today's ISO YYYY-MM-DD>
ingested_by: <your model identifier, e.g. claude-sonnet-4-6>
tokens: <your best estimate of page token count; informational, ±20% is fine>
---

# <source-path verbatim>

## Purpose
<!-- 1-3 sentences. What this file is responsible for. For code files,
     describe responsibility in terms of what the code does. For non-code
     files (config, schema, YAML, JSON, SQL, CSS, docs), describe what the
     file configures, declares, or documents.
     Empty file: write `_(empty file)_`.
     Cannot infer: write `_(unclear — investigate)_`. -->

## Exports
<!-- Bullet list of exported symbols. One line per symbol: `- name: one-line purpose`.
     File has no exports OR is a config/CSS/data file: write `_(none)_`.
     Empty file: `_(none)_`. -->

## Imports
<!-- Bullet list grouped by source module: `- from \`<module>\`: <names> — <why>`.
     Skip stdlib imports unless load-bearing.
     Nothing notable: `_(none)_`.
     Empty file: `_(none)_`. -->

## Key behaviors
<!-- Bullet list of 3-7 notable behaviors, error paths, side effects, I/O.
     NOT a line-by-line transcription.
     Trivial file (re-export shim): `_(trivial — see Exports above)_`.
     Empty file: `_(empty file)_`. -->

## Cross-references
<!-- Wikilinks to other .brain/code/ pages: `- [[code/<path>]] — <why linked>`.
     Milestone #3a single-file ingest: usually `_(none yet — see Milestone #3b for cross-page linking)_`. -->
```

**Page-size self-check**:
- Aim for <4k tokens (soft warn). If the rendered page approaches 4k, summarize more aggressively.
- If approaching 8k (hard error per PRD #7), emit `blocked: ingester couldn't fit page for <source-path> under the 8k cap. Reason: source file is too large for a single page. Operator action: split the source into smaller modules, then re-ingest.` and stop.

**Step 5 — Write the page**:

- Ensure `.brain/code/<dir-of-source>/` exists (create directories as needed).
- Write the filled template to `.brain/code/<source-path>.md`. Use Write (full file content), not Edit — we're replacing whatever was there.

**Step 6 — Update derived files**:

- `.brain/index.md`: append a one-line entry under `## Code pages`. If the section does not exist yet (M#1's init.js ships a generic `index.md` without subsections), CREATE the section with that exact heading as your first edit, then append. Entry format:
  ```
  - [[code/<source-path>]] — <one-line summary from your Purpose section, no leading "This file"/"This module">
  ```
  Dedupe if an entry for this `code/<source-path>` already exists; update it in place.
- `.brain/status.md`: append/update a row in the status table:
  ```
  | code/<source-path>.md | FRESH | <ISO date> | <source-hash with format prefix> |
  ```
  Dedupe / update by page path.
- `.brain/log.md`: append under `## Activity History` using the grep-parseable prefix (PRD Design Decision #15):
  ```
  ## [YYYY-MM-DD] ingest | <source-path> → .brain/code/<source-path>.md
  ```

**Step 7 — Report**:

Print exactly:

```
/brain ingest complete (codebrain v<version-from-.codebrain-version>)
  Source:        <source-path>
  Page:          .brain/code/<source-path>.md (~<token-count> tokens)
  Source hash:   <prefixed hash>
  Updated:       .brain/index.md, .brain/status.md, .brain/log.md
Next: ingest more files individually for now.
      /brain ingest <folder/> is Milestone #3b; /brain ingest (no args) is Milestone #3c.
```

If you encountered any failures during the procedure, replace the success report with `FAILED at Step <N>: <reason>` and exit. Do not partially complete and report success.

**Error recovery** (per the ingester agent's Rules, PRD Design Decision #26): if a step fails for a transient reason (e.g., a Read returned partial content), retry that step ONCE with fresh context. If it fails again, emit a `blocked: ...` report and stop. Do not exceed `max_iterations: 5` total retries across the procedure.

## When `$ARGUMENTS` starts with `ingest <folder>`

You are orchestrating a folder ingest. Run the M#3a ingester per file, then invoke the linker. Follow the procedure exactly.

**Step 0 — Argument parsing + path guards**:

- Extract the folder arg from `$ARGUMENTS`.
- **Out-of-repo guard**: compute the absolute path. If it does NOT start with cwd, print `error: refused — <path> resolves outside the project root` and stop.
- If the resolved path is a file (not a directory), print `error: <path> is a file, not a folder. Use /brain ingest <file-path> for single-file ingest.` and stop.
- If the resolved path does not exist, print `error: folder not found: <path>` and stop.

**Step 1 — Preconditions**:

- Verify `.brain/` exists in cwd. If not, print the same `npx codebrain init` first message as M#3a Step 1.
- Read `.brain/.codebrain-version` to confirm M#1's scaffold is present.

**Step 2 — Walk the folder**:

- Try `git ls-files <folder>` via Bash first (respects `.gitignore` automatically).
- If git is unavailable or the directory isn't tracked, fall back to a manual recursive walk excluding the hardcoded blocklist: `node_modules`, `.git`, `.brain`, `.claude`, `dist`, `build`, `coverage`, `.venv`, `__pycache__`, `target`, `.next`, `.nuxt`.

**Step 3 — Filter**:

- Apply the M#3a binary blocklist (`.png, .jpg, .jpeg, .gif, .webp, .pdf, .exe, .bin, .so, .dylib, .o, .a, .zip, .tar, .tgz, .gz, .mp4, .mp3, .wav, .ico, .ttf, .woff, .woff2`).
- Exclude lockfiles (`package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `poetry.lock`, `Cargo.lock`, `go.sum`, `composer.lock`, `Pipfile.lock`).
- Exclude minified/generated artifacts (`*.min.js`, `*.min.css`, `*.bundle.js`, `*.map`).
- Print the surviving file count and a per-extension breakdown: `Found 23 files: 14 .ts, 5 .tsx, 3 .json, 1 .md`.

**Step 4 — Cost gate**:

- Estimate `cost ≈ count × $0.006` (rough heuristic: ~2000 tokens per file × $0.003/1k input tokens, doubled for output).
- If count > 50 AND `$ARGUMENTS` does NOT contain `--yes`: print `Will ingest <count> files (~$<cost> estimated). This exceeds the 50-file auto-confirm threshold. Re-run with --yes to proceed.` and stop.
- If count is 20–50 AND `$ARGUMENTS` does NOT contain `--yes`: print `Will ingest <count> files (~$<cost> estimated). Proceed? (yes/no/show-files)` and wait for operator. On `yes`: continue. On `no`: stop. On `show-files`: print the list, then re-prompt.
- If count < 20: proceed without prompting.

**Step 5 — Per-file ingest loop**:

- For each filtered file, invoke the **M#3a single-file procedure** (Steps 0–7 of `## When $ARGUMENTS starts with ingest <file>`). Treat each file as if the operator typed `/brain ingest <file>`.
- Collect results: `ingested[]`, `skipped[]` (source unchanged), `failed[]` (with reason).
- On any per-file FAIL, log the reason and continue. **Skip-and-report** behavior — do not abort the folder.

**Step 6 — Invoke the linker procedure**:

- After the per-file loop completes, jump to the `## Linker procedure (invoked after folder ingest)` section below. Pass the list of ingested code-page paths.

**Step 7 — Final report**:

```
/brain ingest <folder> complete (codebrain v<version>)
  Files found:    <total before filter>
  Files filtered: <count after filter>
  Ingested:       <ingested.length> ([<one path per line>])
  Skipped:        <skipped.length>  (sources unchanged)
  Failed:         <failed.length>   ([<path: reason> per line])
  Linker result:  <wired N code-page cross-references, M concept pages created/updated>
  Logged:         .brain/log.md
Next: try `/brain query "..."` (Milestone #5 — not yet implemented).
      For tiered no-arg ingest, see Milestone #3c.
```

If linker emitted partial-completion warning (because per-file failures), include it before the `Next:` line.

## Linker procedure (invoked after folder ingest)

You are the codebrain **linker** (see `agents/brain/linker.md` for your full persona + Rules; the Rules apply throughout). This procedure runs at Step 6 of the folder-ingest procedure, with the list of ingested code-page paths.

**L1 — Load inputs**:

- Read all `.brain/code/**/*.md` pages (the just-ingested set + any prior pages — they may participate in cross-references).
- Read all existing `.brain/concepts/**/*.md` pages (for idempotency: update rather than duplicate).
- The concept-extraction criteria are inlined in this body (see L3); the standalone documentation lives at `skills/ingestion/concept-extraction/SKILL.md`.

**L2 — Wire bidirectional Cross-references between code pages**:

- For each code page, scan its `## Imports` section. For every imported module that resolves to another `.brain/code/<path>.md` page:
  - Verify the target page EXISTS in `.brain/code/` before writing the wikilink (per linker Rule on dangling wikilinks).
  - Add `- [[code/<target-path>]] — <one-line why imported>` under the importing page's `## Cross-references` section.
  - Add the reverse link on the target page: `- [[code/<importing-path>]] — imported by`.
- Dedupe: if a `[[code/<path>]]` link is already present, skip rather than duplicate.

**L3 — Discover concept candidates**:

Apply the concept-extraction criteria:

DO promote when:
- A named idea is referenced across ≥2 code pages (domain entity, integration boundary, convention, glossary term)
- A single code page explicitly declares architectural significance (top-level docstring labelling itself a boundary; README excerpt; ADR reference)

DO NOT promote when:
- Utility functions, single-use helpers, one-off implementations
- Type aliases used only in their defining file
- Wrappers around standard library
- A name that already has a code page (don't double up `auth.ts` with `concepts/auth`)

When uncertain: defer. M#6 lint surfaces "concept mentioned but lacking page" as a hint.

Produce a candidate list: `[{ name, sources: [{path, hash}], evidence: "..." }]`. Discard candidates with <2 sources unless evidence is strong (top-level architectural declaration).

**L4 — Materialize concept pages**:

For each surviving candidate:

- If a concept page with that name already exists at `.brain/concepts/<name>.md`:
  - **UPDATE**: extend the `sources:` frontmatter array with any new entries (per-source-hash format below); refresh the Spans and Examples sections; bump `status: RESYNCED`; update `last_ingested`.
- If new:
  - **WRITE** using this verbatim template:

```markdown
---
kind: concept
status: FRESH
name: <kebab-case name>
last_ingested: <today YYYY-MM-DD>
ingested_by: <your model id>
tokens: <best estimate>
sources:
  - path: <source path 1>
    hash: <git:<hash> or sha256:<hash>>
  - path: <source path 2>
    hash: <git:<hash> or sha256:<hash>>
---

# <Human-readable concept name>

## Definition
<1-3 sentences in domain terms; explain the idea, not the implementation>

## Spans
- [[code/<source path 1>]] — <role this file plays in the concept>
- [[code/<source path 2>]] — <role this file plays in the concept>

## Examples
1. **<short heading>** ([[code/<path>]]):
   <1-2 sentence explanation; optional snippet <5 lines>

## Related
- [[concepts/<name>]] — <one-line relation>
<or `_(none yet)_` if no related concepts exist>
```

Per-source-hash format (PRD Design Decision #32): for each source, compute `git hash-object <path>` (→ `hash: git:<hash>`) or `shasum -a 256 <path>` (→ `hash: sha256:<hash>`). The M#4 staleness hook iterates `sources:` and checks each `hash` to flip the concept page to STALE when any source drifts.

Page-size cap: concept pages 6k soft warn / 12k hard error (per PRD Design Decision #7). If a concept exceeds 12k, split into multiple narrower concepts.

**L5 — Update derived files**:

- `.brain/index.md`: append under `## Concept pages`. If the section does not exist, CREATE it as your first edit (mirror M#3a's `## Code pages` pattern). Entry format: `- [[concepts/<name>]] — <one-line summary from Definition section>`. Dedupe by `[[concepts/<name>]]` link.
- `.brain/status.md`: append/update a row for each concept page: `| concepts/<name>.md | FRESH | <ISO date> | <count> sources |`.
- `.brain/log.md`: append under `## Activity History` with the grep-parseable prefix: `## [YYYY-MM-DD] link | <folder>: <N code pages wired, M concept pages>`.

**L6 — Linker report**:

Produce a structured summary the folder-ingest Step 7 includes in its final report:

```
Linker:
  Cross-references wired: <count> (bidirectional)
  Concepts created:       <count> ([<concept-name per line>])
  Concepts updated:       <count> ([<concept-name per line>])
  Dangling wikilinks:     <count> (downgraded to plain mentions)
```

If any per-file ingest failed (passed in from Step 5's `failed[]`), prepend:

```
WARNING: linker analyzed <M> of <N> requested files; concepts may be missing sources. Re-run after addressing failed files.
```

**Error recovery** (per linker Rules + PRD #26): Tier 1 retry once; Tier 2 structured blocked report; do not exceed `max_iterations: 5`.
