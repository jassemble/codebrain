---
description: Read source files → write LLM-authored .brain/ wiki pages. Accepts a file path, a folder, or no args (tiered).
---

## When `$ARGUMENTS` starts with `ingest <file>`

You are the graphbrain ingester (see `agents/brain/ingester.md` for your full persona + Rules; the Rules apply throughout this procedure). Run the procedure exactly. If any step's preconditions fail, emit a clear error and stop — do not improvise.

**Step 0 — Argument parsing + path guards**:

- Extract the path arg from `$ARGUMENTS` (the token after `ingest`).
- If no path was given: route to the no-arg tiered procedure in the `## When $ARGUMENTS is just \`ingest\`` section below.
- **Out-of-repo guard**: compute the absolute path. If it does NOT start with cwd: print `error: refused — <path> resolves outside the project root` and stop.
- **Symlink guard**: if the resolved path is a symlink (use `Bash: test -L <path>`), print `error: refused — symlinks not supported; pass the target path directly` and stop.
- If the resolved path is a directory: route to the folder procedure in the `## When $ARGUMENTS starts with \`ingest <folder>\`` section below.
- If the resolved path does not exist: print `error: file not found: <path>` and stop.
- **Binary-file guard**: check the file extension against the blocklist `[.png, .jpg, .jpeg, .gif, .webp, .pdf, .exe, .bin, .so, .dylib, .o, .a, .zip, .tar, .tgz, .gz, .mp4, .mp3, .wav, .ico, .ttf, .woff, .woff2]`. If matched, print `error: refused — <path> looks like a binary file (extension <ext>); graphbrain ingests text source files only` and stop. Additionally, read the first 1024 bytes; if a null byte is present, treat as binary and refuse with the same message.

**Step 1 — Preconditions**:

- Verify `.brain/` exists in cwd. If not, print:
  ```
  error: .brain/ not found in this repo.
  Run `npx graphbrain init` first to scaffold the skeleton, then re-run /brain ingest.
  ```
  and stop.
- Read `.brain/.graphbrain-version` to confirm M#1's scaffold is present.

**Step 2 — Read inputs**:

- Read the source file in full when it fits (<4k tokens). For larger files, Read in chunks using offset/limit; do NOT skim by sampling random lines — read sequentially.
- The page contract (frontmatter + 5 required sections, fallback strings, page-size cap) is defined below. The verbatim template is the literal-text fenced block in Step 4. The standalone files `skills/ingestion/page-format/SKILL.md` and `skills/ingestion/page-format/templates/code-page.md` document the same contract (load them only if you need extended examples).

**Step 3 — Compute output path and source hash** (format-prefixed per PRD Design Decision #32; v1.0.13 — delegates to a Node helper):

- Mirror the source path under `.brain/code/`: `src/api/auth.ts` → `.brain/code/src/api/auth.ts.md`
- Run the hash helper:
  ```bash
  HELPER_DIR=$([ -d .claude/plugins/graphbrain/scripts/lib ] \
    && echo .claude/plugins/graphbrain/scripts/lib \
    || echo "$HOME/.claude/plugins/graphbrain/scripts/lib")
  node "$HELPER_DIR/hash-source.js" <source-path>
  ```
  Output: `{"hash":"...","prefix":"git|sha256","formatted":"<prefix>:<hash>"}`. The page's `source_hash` field is the `formatted` string.
- If the helper exits non-zero (neither git nor shasum available — rare), emit `blocked: ingester couldn't compute source hash for <path>. Reason: neither git nor shasum produced a result. Operator action: install git or ensure shasum is on PATH.` and stop.
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
     Single-file ingest: usually `_(none yet — folder ingest wires cross-page links)_`. -->
```

**Page-size self-check**:
- Aim for <4k tokens (soft warn). If the rendered page approaches 4k, summarize more aggressively.
- If approaching 8k (hard error per PRD #7), emit `blocked: ingester couldn't fit page for <source-path> under the 8k cap. Reason: source file is too large for a single page. Operator action: split the source into smaller modules, then re-ingest.` and stop.

**Step 4b — Stack-aware extras** (M#3d; **v1.0.12 subtree-routed**):

After writing the generic 5 sections above, check whether any installed `detected/*` skills apply to this source file. A skill applies when BOTH:

1. **Project signal matches (subtree-routed, v1.0.12)**: read `.brain/.graphbrain-stacks.json` (written by `/brain:init` Step 4c). For the source file's path, pick the entry whose `path` is the **longest prefix** of the source path:
   - Source path `server/src/foo.ts` → match `path: "server"` (length 6) over `path: ""` (length 0)
   - Source path `README.md` → match `path: ""` (root)
   - Tie-break: prefer the more-specific (longer) path; if no subtree matches, use root.
   - The matched entry's `stacks` array is the project signal set for this file.
   - **Fallback if `.graphbrain-stacks.json` missing or unreadable**: re-run a fresh cwd-root detect via `skills/registry.json` (legacy v1.0.11 behavior). Emit a one-line WARNING in the Step 7 report (`stacks_map_missing: re-running /brain:init recommended`).
   - The skill applies if its stack name (`react`, `typescript`, `nestjs`, `python`, `go`, …) appears in this file's matched stacks array.
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

1. **Probe availability**: check whether the named skill (e.g., `ecc:nestjs-patterns`, `ecc:django-patterns`, `ecc:springboot-patterns`) is available in the current harness. The ECC plugin ships many of these; graphbrain does NOT vendor or re-implement them — it bridges to them.
2. **If available**: load that expert skill and apply its code-writing / code-reviewing guidance throughout this ingest (and throughout any code-writing the agent does in this repo after ingest). The expert skill's patterns become the codebase's idiomatic conventions for the agent.
3. **If unavailable**: proceed without that expert skill; the page still gets the graphbrain-side extras above. The agent works without framework-expert guidance for this stack. Document in the report which `expert_skills:` were declared but unavailable.

The bridge is the load-bearing v0.1.1 architectural contract: graphbrain detects stacks + ships the page-format extras; ECC (or another expert-skill source) provides the code-writing expertise. No duplication.

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

**Step 4b.3 — Active bridge probe + activation** (M#9-prereq):

Operationalizes the declarative contract from Step 4b.2. For each matched `detected/*` skill's `expert_skills:` array, probe filesystem availability + load each available skill into context for the remainder of this ingest.

1. **Compute the probe set**: gather every `expert_skill` entry from every `detected/*` skill that matched this source file in Step 4b.1. Each entry is shaped `<vendor>:<skill-name>` (e.g., `ecc:nestjs-patterns`).

2. **Probe each entry** via Bash, in order. Two candidate paths per skill (user-global, then project-local):

   ```bash
   # Probe candidates for <vendor>:<skill-name>:
   test -e "$HOME/.claude/plugins/<vendor>/skills/<skill-name>/SKILL.md" \
     || test -e "$PWD/.claude/plugins/<vendor>/skills/<skill-name>/SKILL.md"
   ```

   Use `2>/dev/null` to suppress noise; the exit code is the signal. If either path exists, the skill is **available**; record the winning absolute path. Otherwise **unavailable**.

3. **Load each available skill**: Read the resolved `SKILL.md` path. Treat the body as authoritative code-writing / code-reviewing guidance for the remainder of this ingest (and any code-writing the agent does in this repo immediately after). The expert skill's patterns become the codebase's idiomatic conventions.

4. **Track for the report**: build two arrays:
   - `bridges_loaded[]` — entries shaped `<vendor>:<skill-name> @ <resolved-path>`
   - `bridges_unavailable[]` — entries shaped `<vendor>:<skill-name> (declared by <detected-skill> but no SKILL.md at either probe path)`

5. **Idempotency + caching**: if the same `<vendor>:<skill-name>` appears in multiple `detected/*` matches (e.g., a `.ts` file in a NestJS project loads both `detected/nestjs` and `detected/typescript`, and both list `ecc:typescript-patterns`), probe + load it ONCE. Dedupe by the colon-separated key.

6. **Failure modes**:
   - Bash unavailable (rare): skip Step 4b.3 entirely; add a single `bridges_unavailable: [all (Bash unavailable for probe)]` entry to the report; continue with the graphbrain-side extras only.
   - Probe path resolves but Read fails (permission denied, broken symlink): treat as unavailable for that entry; log a one-line warning in the report (`bridges_unavailable: <key> (path exists but Read failed: <reason>)`); continue.

7. **Never** invoke the skill via a Skill() tool call — the probe-and-Read pattern is intentionally portable across harnesses that do not expose cross-plugin Skill() invocation. Reading the SKILL.md body and treating it as authoritative is the load-bearing primitive.

**Step 5 — Write the page**:

- Ensure `.brain/code/<dir-of-source>/` exists (create directories as needed).
- Write the filled template to `.brain/code/<source-path>.md`. Use Write (full file content), not Edit — we're replacing whatever was there.

**Step 6 — Update derived files** (per-file path; **SKIP when invoked from folder-ingest Step 5** — folder mode batches all derived-file updates into a single pass at Step 5b for ~10× fewer I/O ops):

- **Batch-mode guard (v1.0.12)**: if you were invoked from `## When $ARGUMENTS starts with ingest <folder>` Step 5, return a structured result instead of writing here:
  ```
  { page_path, source_path, source_hash, top_dir, purpose_oneliner, bridges_used[] }
  ```
  The folder orchestrator's Step 5b uses these results to update index.md / status.md / log.md / llms.txt / CHANGELOG.md once for the whole batch.

- **Single-file path** (the only path that reaches the writes below) — when the operator typed `/brain:ingest <single-file>` directly, no batching is possible; do the per-file writes inline:

- `.brain/index.md`: append a one-line entry under `## Code pages`. If the section does not exist yet (M#1's init.js ships a generic `index.md` without subsections), CREATE the section with that exact heading as your first edit, then append. Entry format:
  ```
  - [[code/<source-path>]] — <one-line summary from your Purpose section, no leading "This file"/"This module">
  ```
  Dedupe if an entry for this `code/<source-path>` already exists; update it in place.
- `.brain/status.md`: append/update a row in the status table. **v1.0.11 routing**: rows live under per-top-level-dir sections, not a single flat table.
  - Determine the section: take the first path segment of `<source-path>` (e.g., `server` for `server/src/app.module.ts`, `client` for `client/src/main.tsx`). Files at the repo root (no directory) go under section `## root/`.
  - Find heading `## <top-dir>/` in `.brain/status.md`. If absent, **CREATE** it immediately before the `## Concepts` heading with a fresh 4-column table header:
    ```
    ## <top-dir>/

    | Page | Status | Last Sync | Source Hash |
    |---|---|---|---|
    ```
  - Append the row to that section's table:
    ```
    | code/<source-path>.md | FRESH | <ISO date> | <source-hash with format prefix> |
    ```
  - Dedupe / update by page path within the section.
  - **Do not touch** the `## Health` or `## Needs attention` blocks at the top of the file — those are refreshed by `/brain:lint`. Per-ingest writes only the table row.
- `.brain/log.md`: append under `## Activity History` using the grep-parseable prefix (PRD Design Decision #15):
  ```
  ## [YYYY-MM-DD] ingest | <source-path> → .brain/code/<source-path>.md
  ```
- `.brain/llms.txt`: refresh per the procedure in `skills/ingestion/llms-txt/SKILL.md`. Read that skill before refreshing. Deterministic, no LLM call.

**Step 7 — Report**:

Print exactly:

```
/brain ingest complete (graphbrain v<version-from-.graphbrain-version>)
  Source:        <source-path>
  Page:          .brain/code/<source-path>.md (~<token-count> tokens)
  Source hash:   <prefixed hash>
  Updated:       .brain/index.md, .brain/status.md, .brain/log.md, .brain/llms.txt, .brain/CHANGELOG.md, .brain/CHANGELOG.md
  Active bridges:
    loaded:      <comma-separated bridges_loaded, or "(none)" if all unavailable, or "(none declared)" if no detected/* matched>
    unavailable: <comma-separated bridges_unavailable, or "(none)">
Next: ingest more files individually for now.
      Folder ingest: /brain:ingest <folder/>. Tiered auto-prioritize: /brain:ingest (no args).
```

The `Active bridges` block is the M#9-prereq runtime evidence — operators see at a glance which expert skills loaded during this ingest. If no `detected/*` skill matched the source (e.g., a Markdown file in a TypeScript repo), print `loaded: (none declared)` to distinguish from the case where bridges were declared but unavailable.

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

- Verify `.brain/` exists in cwd. If not, print the same `npx graphbrain init` first message as M#3a Step 1.
- Read `.brain/.graphbrain-version` to confirm M#1's scaffold is present.

**Step 2-3 — Walk + filter** (v1.0.13 — delegates to a Node helper):

Run the walk-and-filter helper. It tries `git ls-files <folder>` first (respects `.gitignore`), falls back to a recursive walk excluding the standard dirs (`node_modules`, `.git`, `.brain`, `.claude`, `dist`, `build`, `coverage`, `.venv`, `__pycache__`, `target`, `.next`, `.nuxt`, `.cache`, `vendor`). It then filters binaries, lockfiles, and minified/generated artifacts using the same blocklists previously inlined in the prompt.

```bash
HELPER_DIR=$([ -d .claude/plugins/graphbrain/scripts/lib ] \
  && echo .claude/plugins/graphbrain/scripts/lib \
  || echo "$HOME/.claude/plugins/graphbrain/scripts/lib")
node "$HELPER_DIR/walk-and-filter.js" <folder>
```

Output shape:

```json
{
  "total": 51,
  "files": ["server/src/main.ts", "client/src/App.tsx", ...],
  "skipped_binary":   ["assets/logo.png"],
  "skipped_lock":     ["package-lock.json"],
  "skipped_minified": ["client/dist/bundle.min.js"],
  "by_ext": { ".ts": 14, ".tsx": 5, ".json": 3, ".md": 1 }
}
```

Read the JSON. The `files[]` array is your ingest set for Step 4 (cost gate) and Step 5 (per-file loop). Print the breakdown to the operator: `Found {files.length} files: {by_ext as comma-separated counts}`. Surface `skipped_*` totals only if any are non-zero.

**Fallback (rare)**: if the helper is missing or fails, fall back to the v1.0.12 inline procedure — Bash `git ls-files` (or recursive walk) + inline blocklist matching. Same blocklists, same outcome.

**Step 4 — Cost gate**:

- Estimate `cost ≈ count × $0.006` (rough heuristic: ~2000 tokens per file × $0.003/1k input tokens, doubled for output).
- If count > 50 AND `$ARGUMENTS` does NOT contain `--yes`: print `Will ingest <count> files (~$<cost> estimated). This exceeds the 50-file auto-confirm threshold. Re-run with --yes to proceed.` and stop.
- If count is 20–50 AND `$ARGUMENTS` does NOT contain `--yes`: print `Will ingest <count> files (~$<cost> estimated). Proceed? (yes/no/show-files)` and wait for operator. On `yes`: continue. On `no`: stop. On `show-files`: print the list, then re-prompt.
- If count < 20: proceed without prompting.

**Step 5 — Per-file ingest loop** (v1.0.12 — batch mode):

- For each filtered file, invoke the **M#3a single-file procedure** (Steps 0–5 of `## When $ARGUMENTS starts with ingest <file>`; **SKIP Step 6** — derived-file updates are batched in Step 5b below). Each invocation returns a structured result `{ page_path, source_path, source_hash, top_dir, purpose_oneliner, bridges_used[] }`.
- Collect results: `ingested[]` (full results), `skipped[]` (source unchanged), `failed[]` (with reason).
- On any per-file FAIL, log the reason and continue. **Skip-and-report** behavior — do not abort the folder.
- **You may parallelize this loop with up to K=6 concurrent subagents** when `ingested[]` is expected to be ≥8 files (it removes the sequential bottleneck the user critique flagged: 411s linker for 46 files). Per-file ingest is read-only on derived files in batch mode, so parallel calls cannot race. Spawn shards via the Task tool; each shard returns its slice of results.

**Step 5b — Batched derived-file update** (v1.0.12):

After the per-file loop completes — and BEFORE invoking the linker — apply all derived-file updates in ONE pass each. This collapses what was previously 5 × N derived-file ops into 5 ops for the whole batch.

For the collected `ingested[]` results:

- **`.brain/index.md`** — open once, append all N `- [[code/<source-path>]] — <purpose_oneliner>` entries under `## Code pages`, dedupe by path, write once.
- **`.brain/status.md`** — open once. For each result, route the row `| code/<source-path>.md | FRESH | <ISO date> | <source_hash> |` to its `## <top_dir>/` section (create the section before `## Concepts` if absent). Write once. Do NOT touch `## Health` / `## Needs attention` (lint owns those).
- **`.brain/log.md`** — append a SINGLE batched entry under `## Activity History` instead of N per-file entries:
  ```
  ## [YYYY-MM-DD] ingest | <folder>: <N> files → .brain/code/<folder>/ (skipped <S>, failed <F>)
  ```
- **`.brain/llms.txt`** — regenerate once per `skills/ingestion/llms-txt/SKILL.md`. Read that skill before refreshing.
- **`.brain/CHANGELOG.md`** — append a single one-line summary entry under the current month's `## YYYY-MM` heading:
  ```
  - <YYYY-MM-DD>: ingested <folder> → <N> code pages (subtrees: <top_dirs comma-list>)
  ```

If `ingested[]` is empty (e.g., everything was skipped or failed), skip Step 5b entirely.

**Step 6 — Invoke the linker procedure**:

- After the per-file loop completes, jump to the `## Linker procedure (invoked after folder ingest)` section below. Pass the list of ingested code-page paths.

**Step 7 — Final report**:

```
/brain ingest <folder> complete (graphbrain v<version>)
  Files found:    <total before filter>
  Files filtered: <count after filter>
  Ingested:       <ingested.length> ([<one path per line>])
  Skipped:        <skipped.length>  (sources unchanged)
  Failed:         <failed.length>   ([<path: reason> per line])
  Linker result:  <wired N code-page cross-references, M concept pages created/updated>
  Logged:         .brain/log.md
Next: `/brain:query "..."` to ask a question over the ingested pages, or
      `/brain:ingest` (no args) to tier-prioritize across the rest of the codebase.
```

If linker emitted partial-completion warning (because per-file failures), include it before the `Next:` line.

## Linker procedure (invoked after folder ingest)

You are the graphbrain **linker** (see `agents/brain/linker.md` for your full persona + Rules; the Rules apply throughout). This procedure runs at Step 6 of the folder-ingest procedure, with the list of ingested code-page paths.

**L1 — Load inputs**:

- Read all `.brain/code/**/*.md` pages (the just-ingested set + any prior pages — they may participate in cross-references).
- Read all existing `.brain/concepts/**/*.md` pages (for idempotency: update rather than duplicate).
- The concept-extraction criteria are inlined in this body (see L3); the standalone documentation lives at `skills/ingestion/concept-extraction/SKILL.md`.

**L2 — Wire bidirectional Cross-references between code pages** (v1.0.12 — two-pass parallel):

The pre-v1.0.12 design walked code pages serially, writing both forward and reverse links per page. That made L2 the dominant linker cost (the user critique measured 411s for 46 pages — ~9s/page sequential LLM round-trips) and was structurally race-prone: if agent A processes page X importing Y and agent B processes Y importing X, both write to both files.

The v1.0.12 design splits L2 into a read-only extraction phase and a write-only consolidator phase:

**L2a — Edge extraction (parallel, read-only)**:

- Decide `K` (worker count): if `ingested[].length >= 8` then `K = 4` (or `min(4, ceil(N/4))`); else `K = 1` (serial — overhead of spawn dominates for tiny batches).
- Partition the ingested code pages into `K` shards by deterministic index (e.g., shard = `i % K`).
- Spawn `K` Task-tool subagents in parallel. Each shard worker:
  - Reads its assigned `.brain/code/<path>.md` pages plus the full set of `.brain/code/**/*.md` (for target-existence checks).
  - For each page in its shard, scans the `## Imports` section. For every imported module that resolves to another `.brain/code/<path>.md` page:
    - Verifies the target page EXISTS in `.brain/code/` (per linker Rule on dangling wikilinks). If absent, emit it to a `dangling[]` list and skip.
    - Emits an edge `{ importer: "<importer-path>", target: "<target-path>", reason: "<one-line why imported>" }` into the shard's result.
  - **Writes nothing.** The shard returns its `edges[]` + `dangling[]` + per-page span hints (the L3 inputs).
- Once all `K` shards return, **deduplicate edges** by `(importer, target)`. Concatenate all `edges[]` into a single global list.

**L2b — Consolidator write phase (per-target sharded, race-free)**:

- Group edges by `target` (the page that receives the reverse link). Each target page is now owned by exactly one writer — no two agents touch the same file.
- For each target group `{ target: T, edges: [...] }`:
  - Read `T`'s current page.
  - Append `- [[code/<edge.importer>]] — imported by` under `## Cross-references` for each edge in the group. Dedupe by `[[code/<importer>]]` link.
  - Write `T` once.
- Then group edges by `importer` and apply the forward links symmetrically: for each `{ importer: I, edges: [...] }`, read `I` once, append `- [[code/<edge.target>]] — <edge.reason>` per edge, dedupe, write `I` once.
- This pattern guarantees at most 2 writes per page (one for incoming edges, one for outgoing edges); the original design averaged `2 × in_degree` writes per page.

For folder ingests with `ingested[].length < 8`, L2a/L2b collapse to a serial pass over the edges — same correctness, no parallelism overhead.

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
- `.brain/status.md`: under the `## Concepts` section, append/update a row for each concept page (v1.0.11 layout — concepts have their own section, not the per-directory tables). Use a 4-column table; first time you write, replace the `_(no concept pages yet)_` placeholder with the table header:
  ```
  | Page | Status | Last Sync | Sources |
  |---|---|---|---|
  | concepts/<name>.md | FRESH | <ISO date> | <count> sources |
  ```
  Subsequent writes append rows / update in place by `concepts/<name>.md`. **Do not touch** the file's `## Health` or `## Needs attention` blocks — those are refreshed by `/brain:lint`.
- `.brain/log.md`: append under `## Activity History` with the grep-parseable prefix: `## [YYYY-MM-DD] link | <folder>: <N code pages wired, M concept pages>`.
- `.brain/llms.txt`: refresh per the procedure in `skills/ingestion/llms-txt/SKILL.md`. Read that skill before refreshing. Deterministic, no LLM call.
- `.brain/CHANGELOG.md` (M#10d): append a one-line narrative entry summarizing the linker's net contribution — concept pages created/refreshed + cross-references wired. Shape: `- <YYYY-MM-DD>: linked <folder> → <N concept pages created/updated>, <M cross-references wired> (concepts: <comma-separated names>)`. Append under the current month's `## YYYY-MM` heading.

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

You are the graphbrain **planner** (see `agents/brain/planner.md` for your full persona + Rules; orchestrate, do not write). The operator invoked `/brain ingest` with no path argument. Run this procedure exactly.

**T0 — Argument parsing**:

- If `$ARGUMENTS` is `ingest` (alone) or `ingest --yes`: proceed.
- If `$ARGUMENTS` has any other token after `ingest`: this is not your case — return control to the dispatch table.

**T1 — Preconditions**:

- Verify `.brain/` exists; `.brain/.graphbrain-version` is present. If not, error and tell the operator to run `npx graphbrain init` first.
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
Graphbrain tiered ingest plan (graphbrain v<version>)
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
/brain ingest (tiered) complete (graphbrain v<version>)
  Detected stack: <comma-separated list>

  Tier 1: <ingested>/<filtered> ingested, <skipped> skipped (unchanged), <failed> failed
          Linker: <N cross-refs wired, M concepts created/updated>
  Tier 2: <...>
  Tier 3: <...>
  Uncategorized: <N> files NOT ingested

  Logged: .brain/log.md
Next: `/brain:query "..."` to ask a question over the ingested pages.
      Stack-aware page-template extras (React components, Python modules,
      NestJS controllers, etc.) are applied automatically per-file based on
      the detected stack + the source's extension.
```

Append to `.brain/log.md` under `## Activity History` with the grep-parseable prefix:
```
## [YYYY-MM-DD] plan | tiered ingest: T1=<count>, T2=<count>, T3=<count>; operator declined: <none|T1|T2|T3>; ingested: <N> total
```

If the operator typed `cancel` or declined all three tiers, still write the plan log entry — the plan presentation itself is historical data.

**Error recovery** (per planner Rules + PRD #26): Tier 1 retry once; Tier 2 structured blocked report; do not exceed `max_iterations: 5`.

