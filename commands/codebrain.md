<!-- codebrain v0.1.0 -->
---
description: codebrain — agent-maintained codebase wiki (init, ingest, query, lint, learn, status)
---

# /codebrain

Alias for `/brain`. Body is identical so `/codebrain <verb>` behaves the same as `/brain <verb>`.

`$ARGUMENTS` is parsed as `<verb> [args...]`. Route as follows:

## Dispatch

| Verb | Status | Action |
|---|---|---|
| `init` | **implemented** | See "When `$ARGUMENTS` is `init`" section below for the full agent procedure |
| `ingest <single-file-path>` | **implemented (M#3a)** | See "When `$ARGUMENTS` starts with `ingest <file>`" section below |
| `ingest <folder/>` | **implemented (M#3b)** | See "When `$ARGUMENTS` starts with `ingest <folder>`" section below |
| `ingest` (no args) | **implemented (M#3c)** | See "When `$ARGUMENTS` is just `ingest`" section below |
| `query "<question>" [--thorough] [--no-refresh]` | **implemented (M#5)** | See "When `$ARGUMENTS` starts with `query`" section below |
| `lint [--fix] [--yes] [--include-contradictions]` | **implemented (M#6)** | See "When `$ARGUMENTS` starts with `lint`" section below |
| `learn {on\|off\|status\|consolidate}` | **implemented (M#7)** | See "When `$ARGUMENTS` starts with `learn`" section below |
| `status` | **implemented (M#7)** | See "When `$ARGUMENTS` is just `status`" section below |

## No argument (just `/codebrain`)

Print this help block:

```
/codebrain — codebrain commands (alias for /brain)

  /codebrain init                Scaffold .brain/ + CLAUDE.md schema block (Milestone #2)
  /codebrain ingest [path]       Read source files → write LLM-authored wiki pages (Milestone #3)
  /codebrain query "<question>"  Pointer-first lookup against the brain (Milestone #5)
  /codebrain lint [--fix]        Health-check the wiki; --fix batch-refreshes STALE pages (Milestone #6)
  /codebrain learn {on|off|status}   Toggle the continuous-learning observer (Milestone #7)
  /codebrain status              Brain dashboard (Milestone #7)

This is codebrain v0.1.0 — most verbs are stubs in this release. See the README
roadmap for the implementation schedule.

  Repository:  https://github.com/jassemble/codebrain
  PRD:         .claude/prds/codebrain.prd.md (if installed for development)
```

## Unknown verb

Print: `Unknown verb: <verb>. Run \`/codebrain\` (no arguments) for help.`

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

**Step 4b — Stack-aware extras** (M#3d):

After writing the generic 5 sections above, check whether any installed `detected/*` skills apply to this source file. A skill applies when BOTH:

1. **Project signal matches**: the project's detected stack list (read from `.brain/overview.md` Active State; fall back to a fresh `skills/registry.json` detect-rule evaluation if cache is missing) includes the skill's stack name (`react`, `typescript`, `python`, `go`).
2. **File signal matches**: the source file's extension is in the skill's `applies_to_extensions` list (e.g., `.tsx` matches React's `[".tsx", ".jsx"]`).

For each matching skill, APPEND its extra sections to the page AFTER `## Cross-references`. Never replace the generic 5 sections.

When multiple skills apply (e.g., a `.tsx` file in a React + TypeScript project), append in **registry order** from `skills/registry.json`. The current registry order is: TypeScript first, React second, Python third, Go fourth. So a `.tsx` page reads: generic 5 → TypeScript extras → React extras.

The verbatim extras for each detected stack are inlined below. The standalone template files at `skills/detected/<stack>/templates/code-page-<stack>-extras.md` are documentation copies — these inlined versions are the load-bearing contract.

#### detected/react extras (matches `.tsx`, `.jsx` in React projects)

```
## Component
<!-- AGENT: if this file exports a React component, describe it in 1-3 sentences:
     - functional vs class component
     - what the component renders (high-level)
     - any HOC or render-prop pattern, if applicable
     If no component export: write `_(no component export)_`. -->

## Props
<!-- AGENT: bullet list of props. For typed components, capture the prop type.
     Format: `- propName: type — purpose`.
     If no props or no component: `_(none)_`. -->

## State
<!-- AGENT: bullet list of internal state (useState, useReducer, class state).
     Format: `- stateName: type — what it represents`.
     If stateless: `_(stateless)_`. -->

## Hooks
<!-- AGENT: bullet list of hooks used. Distinguish built-in vs custom:
     - useState, useEffect, useCallback (built-in)
     - useAuth (custom — from src/hooks/use-auth.ts)
     If no hooks: `_(none)_`. -->

## Effects
<!-- AGENT: bullet list of side effects (useEffect bodies). Format:
     - on mount: <what happens>
     - on prop change: <what triggers + what runs>
     - on unmount: <cleanup>
     If no effects: `_(none)_`. -->
```

#### detected/typescript extras (matches `.ts`, `.tsx` in TypeScript projects)

```
## Types & Interfaces
<!-- AGENT: bullet list of types and interfaces declared in this file.
     Format: `- TypeName: <object | union | intersection | utility> — purpose`.
     If none (runtime-only file): `_(none)_`. -->

## Module declarations
<!-- AGENT: any `declare module`, `namespace`, or `declare global` blocks.
     If none: `_(none)_`. -->

## Exports (named/default/re-export)
<!-- AGENT: organize exports by kind:
     - Named: foo, bar, Baz
     - Default: <symbol name>
     - Re-exports: from `./other`
     If file has no exports: `_(none)_`. -->

## Generics
<!-- AGENT: brief summary of generic usage. Are there exported generic
     types/functions? Constrained generics? Default type parameters?
     `_(none)_` if not generic-heavy. -->
```

#### detected/python extras (matches `.py` in Python projects)

```
## Public API
<!-- AGENT: bullet list of public symbols (no leading underscore).
     Format: `- name: <function | class | constant> — purpose`.
     If `__all__` is defined, use it as the source of truth. -->

## Dunder methods
<!-- AGENT: bullet list of dunder methods defined in classes in this file.
     Format: `- ClassName.__init__: <one-line note>`.
     If none defined: `_(none)_`. -->

## Decorators
<!-- AGENT: decorators used or defined in this file.
     Format: `- @decorator_name (from <module>) — applied to <symbols>`.
     Examples: @dataclass, @property, @classmethod, @pytest.fixture, custom.
     If none: `_(none)_`. -->

## Type hints
<!-- AGENT: brief assessment: fully typed, partially typed, untyped.
     Note any TypedDict, Protocol, Literal, Generic[T] usage.
     One-line summary; if untyped: `_(untyped)_`. -->
```

#### detected/go extras (matches `.go` in Go projects)

```
## Package
<!-- AGENT: package declaration + brief role of this file in the package.
     Examples:
       "main package — CLI entry point"
       "package auth — middleware for JWT validation"
     Note related files in the same package if known. -->

## Receivers
<!-- AGENT: bullet list of methods grouped by receiver type.
     Format: `- (s *Server) Method(...) — purpose`.
     If no methods: `_(none)_`. -->

## Interfaces satisfied
<!-- AGENT: bullet list of interfaces this file's types satisfy.
     Format: `- TypeName satisfies io.Reader, fmt.Stringer`.
     Inferred from method sets; if uncertain: `_(none observed)_`. -->

## init() functions
<!-- AGENT: any init() functions in this file. Describe what they do
     (registration, env-var loading, etc.).
     If none: `_(none)_`. -->

## Build tags
<!-- AGENT: any `//go:build` or legacy `// +build` tags at the top of the file.
     If none: `_(none)_`. -->
```

Skip Step 4b entirely if no detected/* skill matches this source file. The generic 5 sections always apply.

**Step 4b.2 — Expert skill bridge** (v0.1.1):

After resolving which `detected/*` skills apply for this source file, check each matched skill's `expert_skills:` field in `skills/registry.json`. For every named expert skill:

1. **Probe availability**: check whether the named skill (e.g., `ecc:nestjs-patterns`, `ecc:django-patterns`, `ecc:springboot-patterns`) is available in the current harness. The ECC plugin ships many of these; codebrain does NOT vendor or re-implement them — it bridges to them.
2. **If available**: load that expert skill and apply its code-writing / code-reviewing guidance throughout this ingest (and throughout any code-writing the agent does in this repo after ingest). The expert skill's patterns become the codebase's idiomatic conventions for the agent.
3. **If unavailable**: proceed without that expert skill; the page still gets the codebrain-side extras above. The agent works without framework-expert guidance for this stack. Document in the report which `expert_skills:` were declared but unavailable.

The bridge is the load-bearing v0.1.1 architectural contract: codebrain detects stacks + ships the page-format extras; ECC (or another expert-skill source) provides the code-writing expertise. No duplication.

Currently shipped `detected/*` skills with `expert_skills:` declarations (post-v0.1.1):

| detected/* skill | expert_skills bridge target(s) |
|---|---|
| `detected/nestjs` | `ecc:nestjs-patterns` |
| `detected/nextjs` | `ecc:nextjs-turbopack` |
| `detected/express` | `ecc:backend-patterns` |
| `detected/django` | `ecc:django-patterns`, `ecc:django-security` |
| `detected/fastapi` | `ecc:fastapi-patterns` |
| `detected/springboot` | `ecc:springboot-patterns`, `ecc:springboot-security` |

The four M#3d skills (`react`, `typescript`, `python`, `go`) do NOT yet declare `expert_skills:` — v0.2 may add them or leave them as page-format-only.

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

## When `$ARGUMENTS` is just `ingest`

You are the codebrain **planner** (see `agents/brain/planner.md` for your full persona + Rules; orchestrate, do not write). The operator invoked `/brain ingest` with no path argument. Run this procedure exactly.

**T0 — Argument parsing**:

- If `$ARGUMENTS` is `ingest` (alone) or `ingest --yes`: proceed.
- If `$ARGUMENTS` has any other token after `ingest`: this is not your case — return control to the dispatch table.

**T1 — Preconditions**:

- Verify `.brain/` exists; `.brain/.codebrain-version` is present. If not, error and tell the operator to run `npx codebrain init` first.
- Verify `.brain/overview.md` exists. If it's missing or appears unpopulated (`status: UNENRICHED`), print:
  ```
  WARN: .brain/overview.md isn't populated. Stack detection results aren't cached.
        Run /brain init first for better tier assignment. Proceeding with fresh detection.
  ```
  and continue.

**T2 — Load stack detection**:

- Read `.brain/overview.md`. Extract the "Detected stack:" line from the `## Active State` section.
- If absent or empty, re-run stack detection: read `skills/core/init/templates/stack-detection.json` and evaluate each stack's signals against cwd (same logic M#2's init skill uses).
- Record the detected stack list for the plan report.

**T3 — Walk + filter** (re-uses M#3b Steps 2–3):

- Try `git ls-files` first (respects `.gitignore`).
- Fallback to manual recursive walk excluding the hardcoded blocklist (`node_modules .git .brain .claude dist build coverage .venv __pycache__ target .next .nuxt`).
- Apply M#3a binary blocklist + M#3b lockfile + minified/generated exclusions.

**T4 — Group files into 3 tiers** using generic glob heuristics (stack-aware overrides arrive in M#3d):

- **Tier 1** (core): files matching `src/**`, `lib/**`, `app/**`, `pkg/**`, `cmd/**`
- **Tier 2** (api / services / top-level): files matching `api/**`, `services/**`, `internal/**`, OR top-level source files (no parent directory match for any other tier)
- **Tier 3** (tests / scripts / docs): files matching `tests/**`, `__tests__/**`, `spec/**`, `e2e/**`, `scripts/**`, `docs/**`, `examples/**`
- **Uncategorized**: anything not matching the above. These files will NOT be ingested automatically — the operator must pass them individually via M#3a or place them under a recognized prefix.

A file matches the FIRST tier whose glob set it satisfies (precedence: 1 → 2 → 3 → uncategorized).

**T5 — Present plan**:

```
Codebrain tiered ingest plan (codebrain v<version>)
  Detected stack: <comma-separated list>

  Tier  Files  Cost(~)  Locations (top entries)
  ----  -----  -------  ----------------------------------
  1     <N>    $<X.XX>  <dir1> (<count>), <dir2> (<count>)
  2     <N>    $<X.XX>  <dir1> (<count>), top-level (<count>)
  3     <N>    $<X.XX>  <dir1> (<count>)
  --
  Total <N>    $<X.XX>
  Uncategorized: <N> files (will NOT be ingested; pass them via /brain ingest <file>)

Proceed tier-by-tier? Type `yes` to start with Tier 1, or `cancel` to stop.
```

If `$ARGUMENTS` contains `--yes`: skip the prompt; proceed directly to T6 with auto-confirmation enabled for all tiers.

On `cancel`: jump to T7 with no ingestion performed.

Cost-per-tier formula: `cost = count × $0.006` (per M#3b cost-gate heuristic).

**T6 — Per-tier loop** (Tier 1, then 2, then 3):

For each tier:

- If `$ARGUMENTS` contains `--yes`: auto-confirm; skip prompt.
- Otherwise print: `Tier <N>: <count> files (~$<cost>). Proceed? (yes/no/show-files)`
  - On `no`: skip tier; record `skipped_tier_<N>`; continue to next tier.
  - On `show-files`: print the file list; re-prompt with the same `yes/no/show-files`.
  - On `yes`: continue.
- Invoke the **M#3b folder-ingest procedure** (`## When $ARGUMENTS starts with ingest <folder>` Steps 0–7) treating this tier's file list as the input. The linker runs at M#3b Step 6 after this tier's files complete — incremental visibility per tier rather than once at end.
- Record per-tier results: `ingested[]`, `skipped[]`, `failed[]`, linker counts.

**T7 — Final report**:

```
/brain ingest (tiered) complete (codebrain v<version>)
  Detected stack: <comma-separated list>

  Tier 1: <ingested>/<filtered> ingested, <skipped> skipped (unchanged), <failed> failed
          Linker: <N cross-refs wired, M concepts created/updated>
  Tier 2: <...>
  Tier 3: <...>
  Uncategorized: <N> files NOT ingested

  Logged: .brain/log.md
Next: try `/brain query "..."` (Milestone #5 — not yet implemented).
      For stack-aware page templates (React components, Python modules, etc.),
      see Milestone #3d.
```

Append to `.brain/log.md` under `## Activity History` with the grep-parseable prefix:
```
## [YYYY-MM-DD] plan | tiered ingest: T1=<count>, T2=<count>, T3=<count>; operator declined: <none|T1|T2|T3>; ingested: <N> total
```

If the operator typed `cancel` or declined all three tiers, still write the plan log entry — the plan presentation itself is historical data.

**Error recovery** (per planner Rules + PRD #26): Tier 1 retry once; Tier 2 structured blocked report; do not exceed `max_iterations: 5`.

## When `$ARGUMENTS` starts with `query`

You are the codebrain **query** agent (see `agents/brain/query.md` for your full persona + Rules — pointer-first ordering, hash-compare freshness, cite-both citation). Run this procedure exactly.

**Q0 — Argument parsing**:

- Extract the question string from `$ARGUMENTS` (everything between the first `query` token and any flag). The question must be a non-empty string; quotes are optional but recommended.
- Parse flags from `$ARGUMENTS`:
  - `--thorough` — raises the candidate-page cap from 3 → 5 (hard cap remains 5).
  - `--no-refresh` — skip the freshness check + STALE refresh; read pages as-is and add `[STALE — content may be out-of-date]` banner to each affected citation.
- If no question is parseable: print `error: /brain query requires a question. Try: /brain query "how does auth work?"` and stop.

**Q1 — Preconditions**:

- Verify `.brain/` exists in cwd. If not, print:
  ```
  error: .brain/ not found in this repo.
  Run `npx codebrain init` first to scaffold the skeleton, then re-run /brain query.
  ```
  and stop.
- Verify `.brain/index.md` exists. If absent or unpopulated:
  ```
  error: .brain/index.md not found or empty.
  Run /brain init then /brain ingest <path> (or just /brain ingest for tiered) to populate the brain first.
  ```
  and stop.

**Q2 — Read the index** (pointer-first):

- Read `.brain/index.md` in full. This is the load-bearing pointer step — DO NOT load any page bodies yet. Index gives you one-line summaries per page under `## Code pages`, `## Concept pages`, and `## Decision pages` (if any).

**Q3 — Select 1–3 candidate pages**:

- Based on the question's keywords + the index's per-page summaries, pick the 1–3 most-relevant pages.
- Selection heuristics:
  - Cross-cutting questions ("how does X work?", "where do we touch Y?") → prefer concept pages
  - Structural questions ("what does <file> export?") → prefer code pages
  - Decision questions ("why X?") → prefer decision pages
- With `--thorough`: allow up to 5 candidates.
- **Hard cap 5 always**. If the question seems to require more than 5 pages, emit:
  ```
  Your question spans several areas. Consider narrowing:
    - <area 1>: try `/brain query "..."` (likely page: [[code/...]])
    - <area 2>: ...
    - <area 3>: ...
  ```
  and stop. Don't read 10+ pages.

**Q4 — Freshness check per candidate**:

For each selected candidate:

- Read the page's frontmatter only (do NOT load the body yet — efficiency matters).
- Extract `source_hash` (format-prefixed: `git:<hash>` or `sha256:<hash>` per PRD #32).
- **For code pages**: re-hash the source file:
  - Try `git hash-object <source>` via Bash. If succeeds, current hash is `git:<hash>`.
  - Fallback: `shasum -a 256 <source> | awk '{print $1}'` → `sha256:<hash>`.
- **For concept pages**: re-hash EACH entry in the `sources:` array. The concept is fresh ONLY if all sources still match.
- Compare prefix-aware:
  - **On match** (even if `status: STALE`): **promote to FRESH inline** — update the page's frontmatter (`status: FRESH`, `last_ingested: <today>`, remove `last_stale_at` and `stale_reason` if present). Write atomically. This resolves M#4's conservative STALE flips (hook flips on every Edit; M#5 verifies content actually changed).
  - **On mismatch**: candidate needs refresh — proceed to Q5 for this candidate.
- If `--no-refresh`: skip refresh entirely; mark STALE candidates with a banner; continue to Q6.

Use the helpers in `scripts/hooks/lib/page-io.js` (`readPage`, `writePage`) for atomic frontmatter mutations.

**Q5 — Refresh STALE candidates** (skip if `--no-refresh`):

- For each candidate that failed the Q4 hash compare:
  - **Code page**: invoke the M#3a single-file ingest procedure (`## When $ARGUMENTS starts with ingest <file>` Steps 0–7) on the corresponding source file. The ingester writes a fresh page.
  - **Concept page**: invoke `/brain ingest <folder>` (M#3b) targeting the parent directory of the most-drifted source listed in the concept's `sources:` array. The linker (M#3b L1–L6) will refresh the concept page. **Known M#5 limitation**: this is approximate — concept-page refresh may not pick up every reference change. M#6's `/brain lint --fix` does a more thorough sweep.
- After refresh, the page is ready for Q6 reading.

**Q6 — Read the candidate page bodies + synthesize**:

- NOW load each candidate page's body via Read.
- Synthesize a 100–500 word answer grounded in the loaded pages. Avoid speculation; if the loaded pages don't fully answer the question, say so explicitly ("the brain doesn't have full coverage of X yet — consider `/brain ingest <path>`").
- For citations:
  - Always cite the brain page via wikilink: `[[code/<path>]]` or `[[concepts/<name>]]`
  - Always cite the source file path: `src/api/auth.ts`
  - Cite a specific line `src/api/auth.ts:42` ONLY when you read that specific line during synthesis (via Read with offset/limit or via Grep results). **NEVER fabricate line numbers**.

**Q7 — Output + log**:

Print the answer in this exact shape:

```
## Answer

<synthesized prose — 100-500 words>

## Citations

- [[code/<path>]] — <source-path> (<one-line context from the page's Purpose section>)
- [[concepts/<name>]] — <one-line context>
- <source-path>:<line> — <what's at that line and why it matters>

## Brain freshness

- Pages read:                       <count>
- Refreshed (M#3a re-ingest):       <count from Q5>
- Promoted STALE → FRESH (hash):    <count from Q4>
- Banners (--no-refresh STALE):     <count, or 0>

Logged: .brain/log.md
```

Append to `.brain/log.md` under `## Activity History` with the grep-parseable prefix:
```
## [YYYY-MM-DD] query | "<first 80 chars of question, ellipsis if longer>"; pages read: <N>; refreshed: <M>; thorough: <true|false>
```

If you encountered any failures during the procedure, replace the success report with `FAILED at Step Q<N>: <reason>` and exit. Do not partially complete and report success.

**Error recovery** (per query Rules + PRD #26): if a step fails for a transient reason, retry that step ONCE with fresh context. If it fails again, emit:
```
blocked: query couldn't complete answering "<question>".
Reason: <one-sentence why>.
Operator action: <what to do — e.g., "run /brain ingest <path> to populate the brain first", "narrow the question to a single area", "install git or shasum for hash computation">.
```
and stop. Do not exceed `max_iterations: 5`.

## When `$ARGUMENTS` starts with `lint`

You are the codebrain **verifier** (see `agents/brain/verifier.md` for your full persona + Rules — read-only by default, hash compare for stale verification, delegate-to-ingester on --fix, never auto-create concept pages). Run the procedure exactly.

**L0 — Argument parsing**:

- Parse flags from `$ARGUMENTS`:
  - `--fix` — opt into batch refresh of true STALE pages
  - `--yes` — skip the --fix confirmation prompt (only meaningful with --fix)
  - `--include-contradictions` — opt into LLM-driven contradiction check (expensive; gated by cost)
- No other arguments accepted — `lint` doesn't take a question or path.

**L1 — Preconditions**:

- Verify `.brain/` exists in cwd. If not, print the same npx-init message as M#3a Step 1 + M#5 Q1 + stop.
- Verify `.brain/.codebrain-version` is present.
- Verify `<cwd>/CLAUDE.md` exists (needed for schema-drift check). If absent: skip the schema check; note `schema-drift: skipped (CLAUDE.md missing)` in the report.

**L2 — Inventory**:

- Walk `.brain/code/`, `.brain/concepts/`, `.brain/decisions/` via the helpers in `scripts/hooks/lib/page-io.js` (`walkBrainPages`). Count pages per kind. This is the report header.

**L3 — Defects category** (deterministic, fast — no LLM calls):

For every page returned by L2:

- **Stale verification** (hash compare; same logic as M#5 Q4):
  - Read the page's frontmatter via `lib/page-io.readPage`.
  - Extract `source_hash` (format-prefixed: `git:<hash>` or `sha256:<hash>` per PRD #32).
  - For code pages: re-hash the source via `git hash-object <source>` (preferred) or `shasum -a 256 <source>` (fallback).
  - For concept pages: re-hash EACH entry in the `sources:` array.
  - If status:STALE AND ALL hashes match → "Stale (false; ready to promote)" — `--fix` writes the promotion to FRESH via `lib/page-io.writePage`.
  - If status:STALE AND any hash differs → "Stale (true)" — true stale; `--fix` triggers refresh.
  - If status:FRESH AND hash differs → "Stale (true, hook missed)" — categorize same as true stale; logging note about the hook miss.
- **Broken wikilinks**: scan page body for `[[code/<path>]]` and `[[concepts/<name>]]` and `[[decisions/<adr>]]`; for each, verify the target file exists in `.brain/<kind>/`. Report dangling links as `<from-page-path> → <target-link>`.
- **Page-size violations**:
  - Estimate token count: `chars / 4` (rough; ±20%).
  - Code pages: report `Page-size soft` if > 4k; `Page-size hard` if > 8k.
  - Concept pages: report `Page-size soft` if > 6k; `Page-size hard` if > 12k.
- **Orphan source files**: for each `.brain/code/<path>.md`, check if `<cwd>/<path>` exists. If not → orphan.
- **CLAUDE.md schema drift**: read the content between `<!-- codebrain:begin -->` and `<!-- codebrain:end -->` in `<cwd>/CLAUDE.md`; compare to the verbatim content of `skills/core/init/templates/claude-md-schema.md` (load from the codebrain npm-installed location — same path-resolution caveat as M#5's template reads). Trim trailing whitespace + normalize line endings before comparing (avoid false positives on whitespace). If differ → `schema-drift: yes`.

**L4 — Gaps category** (heuristic, fast — no LLM calls):

- **Missing concept pages**:
  - Scan all `.brain/code/<path>.md` bodies for capitalized symbols (likely names: `Tenant`, `AuthFlow`, `StripeClient`, etc.) appearing in multiple pages.
  - Build a frequency map: `{ symbol → [list of pages where mentioned] }`.
  - For any symbol mentioned in ≥2 distinct code pages: check if a concept page named `<kebab-case-of-symbol>.md` exists in `.brain/concepts/`. If not → "missing concept" candidate.
  - Heuristic: filter out common words (functions like `if`, `return`, etc.) using a tiny stopword list. Keep names that look like identifiers.
- **Stub / TBD pages**:
  - Read each page body. If `## Purpose` contains `_(unclear — investigate)_` OR body contains `_(TBD)_` OR body contains the literal `_(empty file)_` for non-test fixtures → flag.
- **Orphan code pages**:
  - For each `.brain/code/<path>.md`, scan all OTHER `.brain/**/*.md` pages for `[[code/<path>]]` wikilinks pointing to it.
  - Pages with zero inbound wikilinks → orphan. Note: this is graph-orphan (no inbound links), distinct from source-orphan (source deleted) from L3.

**L5 — Contradictions category** (LLM-driven; opt-in via `--include-contradictions`):

- If `--include-contradictions` is NOT in `$ARGUMENTS`: emit `skipped — run with --include-contradictions to enable` and continue to L6.
- If passed:
  - Estimate cost: `page_count × $0.01` (rough). If estimate > $0.50 AND `--yes` is not also passed: print `Will run contradiction-check on <N> pages (~$<cost> estimated). Proceed? (yes/no)` and wait. On `no`: skip category; continue.
  - On approval (or under cost-gate): for each page, re-read the source file + the page, judge whether the page's `## Purpose` and `## Key behaviors` sections accurately describe the source's current behavior. Use one LLM step per page; be terse.
  - Flag drift: `<page-path>: page says "X" but source does "Y" (line: <line if known>)`.

**L6 — Suggested questions** (forward-looking, derived from L3–L5):

For each finding, add a suggestion line. Examples:

- Missing concept `tenant`: `- Concept "tenant" appears in 4 code pages but has no concept page. Try /brain query "what is a tenant?" or /brain ingest src/models/ (which contains tenant.ts) to give the linker more material.`
- True stale page `code/src/auth.ts.md`: `- Stale page code/src/auth.ts.md. Run /brain lint --fix to refresh, or /brain ingest src/auth.ts to refresh manually.`
- Schema drift: `- CLAUDE.md schema block differs from codebrain's shipped template. Run /brain init --force to refresh, OR check codebrain --version vs .brain/.codebrain-version for a version mismatch.`
- All stub pages: `- Stub page <path>. Re-ingest with /brain ingest <source> --force to deepen.`

**L6b — `--fix` execution** (skip if `--fix` is not in `$ARGUMENTS`):

- Compile the refresh list from L3:
  - "Stale (false; ready to promote)" → write promotions inline via `lib/page-io.writePage` (set `status: FRESH`, update `last_ingested`, remove `last_stale_at` / `stale_reason`). These are cheap — no LLM call.
  - "Stale (true)" → refresh list for delegation.
- Print: `Will promote <P> false-positives to FRESH inline, and refresh <N> code pages + <M> concept folders via M#3a/M#3b. Proceed? (yes/no)`
- If `--yes` is in `$ARGUMENTS`: skip prompt; proceed.
- On `yes`:
  - First, promote false-positives (inline writes).
  - Then for each true-stale **code page**: invoke the M#3a single-file procedure (`## When $ARGUMENTS starts with ingest <file>` Steps 0–7) with `--force` for the corresponding source file. Collect per-page outcomes.
  - For each unique parent directory of true-stale **concept page** sources: invoke `/brain ingest <folder>` (M#3b folder procedure). The linker (M#3b L1–L6) refreshes the concept page.
- On `no`: skip the refresh; the report stays read-only. Note in "Fix results: skipped per operator".

**L7 — Output + log**:

Print the report in exactly this shape:

```
/brain lint — wiki health report (codebrain v<version>)

Inventory:
  Code pages:     <count>
  Concept pages:  <count>
  Decision pages: <count>

## Defects (<total count from L3>)
  Stale (true):                    <count>  [<paths, comma-separated or one per line>]
  Stale (false; ready to promote): <count>  [<paths>]
  Broken wikilinks:                <count>  [<from-page → target>, ...]
  Page-size hard:                  <count>  [<paths>]
  Page-size soft:                  <count>  [<paths>]
  Orphan source files:             <count>  [<paths>]
  Schema drift in CLAUDE.md:       <yes|no|skipped>

## Gaps (<total count from L4>)
  Missing concept pages: <count>  [<suggested names>]
  Stub/TBD pages:        <count>  [<paths>]
  Orphan code pages (no inbound wikilinks): <count>  [<paths>]

## Contradictions
  <"skipped — run with --include-contradictions to enable" OR per-page list>

## Suggested questions
  - <suggestion 1>
  - <suggestion 2>

## Fix results  (only if --fix was passed)
  Promoted (false-positive → FRESH): <count>
  Refreshed:                          <count>  [<paths>]
  Failed:                             <count>  [<paths with reasons>]

Logged: .brain/log.md
```

Append to `.brain/log.md` under `## Activity History`:
```
## [YYYY-MM-DD] lint | defects: <N>, gaps: <M>, contradictions: <K|skipped>; --fix: <true|false>; --include-contradictions: <true|false>
```

**Always exit 0 for v0.1** (severity-coded exits are post-MVP).

**Error recovery** (per verifier Rules + PRD #26): Tier 1 retry once; Tier 2 emit:
```
blocked: verifier couldn't complete lint.
Reason: <one-sentence why>.
Operator action: <what to do — e.g., "verify .brain/ exists with npx codebrain init", "install git for hash compare", "narrow scope by skipping --include-contradictions">.
```
and stop. Do not exceed `max_iterations: 5`.

## When `$ARGUMENTS` starts with `learn`

You are operating the continuous-learning subsystem (see `agents/observers/observer.md` for the consolidator agent; see `skills/core/learn/SKILL.md` for the full contract — observation format, instinct format, privacy stance). Run the procedure exactly for the requested subcommand.

**Le0 — Argument parsing**:

- Extract the subcommand from `$ARGUMENTS`: `on`, `off`, `status`, `consolidate`. Any other token → print `error: /brain learn requires a subcommand: on | off | status | consolidate` and stop.

**Le1 — Preconditions**:

- Verify `.brain/` exists in cwd. If not, print the same npx-init message as M#3a Step 1 and stop.
- Verify `.brain/.codebrain-version` is present.

**Le2 — Dispatch**:

- `on` → proceed to Le3 (toggle on)
- `off` → proceed to Le4 (toggle off)
- `status` → proceed to Le5 (status report)
- `consolidate` → proceed to Le6 (consolidator agent)

---

**Le3 — `learn on` (toggle on)**:

1. Print the privacy notice EXACTLY (verbatim — operators rely on this):
   ```
   [Privacy notice — codebrain v<version>]
   Codebrain will now collect minimal observations of your tool use in this repo:
     - Captured fields: timestamp, tool name, relative path (if applicable), status
     - NOT captured: tool outputs, prompts, file contents, stderr, stdout
     - Storage: <XDG_DATA_HOME or ~/.local/share>/codebrain/projects/<git-hash>/observations.jsonl
     - Disable anytime: /brain learn off
   ```
2. Atomic-write `.brain/.codebrain-learn-state` with content `on\n` (use `Bash: printf "on\n" > .brain/.codebrain-learn-state`).
3. Append to `.brain/log.md`:
   ```
   ## [YYYY-MM-DD] learn | toggled on
   ```
4. Print: `Toggle written: .brain/.codebrain-learn-state = on`

---

**Le4 — `learn off` (toggle off)**:

1. Atomic-write `.brain/.codebrain-learn-state` with content `off\n`.
2. Append to `.brain/log.md`:
   ```
   ## [YYYY-MM-DD] learn | toggled off
   ```
3. Print:
   ```
   Toggle written: .brain/.codebrain-learn-state = off
   Existing observations and instincts in ~/.local/share/codebrain/projects/<hash>/ are preserved.
   To purge them, manually delete that directory.
   ```

---

**Le5 — `learn status` (per-project learn dashboard)**:

1. Read toggle state (`on`/`off`/`missing`).
2. Read `<XDG>/projects/<git-hash>/observations.jsonl` via `Bash: cat ~/.local/share/codebrain/projects/$(... project hash computation ...)/observations.jsonl 2>/dev/null` — count lines (= observation count).
3. Read `<XDG>/projects/<git-hash>/instincts.jsonl` similarly — count lines (= instinct count).
4. Compute top 5 patterns from instincts (sort by frequency desc; take 5).
5. Print:
   ```
   /brain learn status (codebrain v<version>)
     Toggle:             <on | off | missing (default off)>
     Observations:       <count> (since <oldest ts as YYYY-MM-DD>)
     Instincts:          <count>
     Top 5 patterns:
       <pattern>          <freq> (<pct>%)
       ...
     XDG store:          <path>
     Last consolidation: <YYYY-MM-DD from .brain/log.md "consolidate" entry, or "never">
   ```

---

**Le6 — `learn consolidate` (observer agent)**:

You are now acting as the observer agent. Follow the observer's procedure exactly:

1. **Toggle check**: read `.brain/.codebrain-learn-state`. If NOT `on`: print `error: cannot consolidate while toggle is off or missing. Run /brain learn on first.` and stop.

2. **Read observations**: load `<XDG>/projects/<git-hash>/observations.jsonl` via `Bash` + a small Node one-liner that uses `scripts/hooks/lib/observations.readObservations(cwd)`. Get an array of records.

3. **Count patterns**: group by `(tool, path-prefix-up-to-second-segment)`:
   - For `path: "src/api/auth.ts"`, the prefix-up-to-second-segment is `src/api`
   - For `path: "package.json"` (single segment), the prefix is `package.json` itself (or `.` for null path)
   - Build a map: `{ "Edit:src/api": { freq: 17, first_seen: ..., last_seen: ... }, ... }`

4. **Promote to instincts**: any pattern with `frequency >= 3` becomes an instinct. Compute `id = SHA-256(pattern).slice(0, 12)`. Total observations = sum of all pattern frequencies; per-instinct `confidence = frequency / total`.

5. **Merge with existing**: read `instincts.jsonl`; build an existing-id set. For each new instinct: if `id` already exists, update the existing record's `frequency`/`confidence`/`last_seen` (sum frequencies; recompute confidence; max last_seen). If new, append.

6. **Atomic write**: rewrite the entire instincts.jsonl with the merged set (use temp+rename pattern via Bash, or call `lib/observations.appendInstinct` for each new/updated). Acceptable for v0.1 to rewrite the whole file each consolidation; file is small.

7. **Log**: append to `.brain/log.md`:
   ```
   ## [YYYY-MM-DD] consolidate | <N> observations → <M> new instincts + <K> updated; toggle: on
   ```

**Le7 — Report**:

For `consolidate`, print:
```
/brain learn consolidate complete
  Observations read:    <N>
  Patterns found:       <M total patterns, including those below threshold>
  Instincts new:        <K>
  Instincts updated:    <U>
  Threshold (v0.1):     frequency ≥ 3
  Logged:               .brain/log.md
  Storage:              <XDG>/projects/<git-hash>/
```

For other subcommands, the report is the toggle-confirmation or status output from Le3-Le5.

**Error recovery** (per observer Rules + PRD #26): Tier 1 retry once; Tier 2 emit:
```
blocked: learn <subcommand> couldn't complete.
Reason: <one-sentence why>.
Operator action: <what — e.g., "run /brain learn on first" or "check XDG_DATA_HOME permissions">.
```

## When `$ARGUMENTS` is just `status`

The project dashboard. Read-only.

**S0 — Preconditions**: `.brain/` exists; `.brain/.codebrain-version` present. (If not: same npx-init message.)

**S1 — Gather**:

- Page counts per kind: walk `.brain/code/`, `.brain/concepts/`, `.brain/decisions/`; count `.md` files.
- Hooks installed: read `.claude/settings.local.json`; count entries with `id` starting `codebrain:`.
- Last 5 log entries: `tail -5 .brain/log.md | grep "^## \["` (grep-parseable per PRD #15).
- Learn state: read `.brain/.codebrain-learn-state` (default `missing` → display as `off (default)`).
- Observation count + instinct count: only if learn state is `on`, query the XDG paths (use `wc -l` via Bash, gracefully no-op if files don't exist).

**S2 — Format the dashboard**:

```
codebrain status (v<version>)

Vault:
  Code pages:        <count>
  Concept pages:     <count>
  Decision pages:    <count>
  Total:             <sum>

Hooks installed:     <count> [codebrain:pre:verified-guard, codebrain:pre:observe, codebrain:post:stale-detect]

Learn:
  Toggle:            <on | off | missing>
  Observations:      <count or "n/a — learn off">
  Instincts:         <count or "n/a — learn off">

Recent activity (last 5 entries from .brain/log.md):
  <entry 1>
  <entry 2>
  ...

Next: /brain query "..."  or  /brain lint  or  /brain learn status
```

**S3 — Output**: print the dashboard. No log entry (status is a query, not an event).

**Error recovery**: same Tier 1/2 pattern; `max_iterations: 5`.
