# Plan: graphbrain — Milestone #3b (Folder ingest + concept pages + linker)

**Source PRD**: `.claude/prds/graphbrain.prd.md`
**Selected Milestone**: #3b — second sub-step of the 3-way split of original M#3
**Complexity**: Medium-to-Large — second writer agent (linker); first concept pages; first cross-page wikilinks; first per-source-hash tracking
**Status**: **READY** — draft refined post-M#3a with 12 sweep findings folded in

## Summary

Scale the M#3a single-file loop to a folder. `/brain ingest <folder>` walks the folder via `git ls-files` (with fallback), filters out the binary blocklist + lockfiles + generated artifacts, ingests each remaining file by following the **same Step 0–7 procedure** M#3a established (no re-implementation), then invokes the **linker agent** to: (a) wire bidirectional cross-page wikilinks in the ingested code pages, (b) create or update concept pages in `.brain/concepts/` for cross-cutting ideas spotted across the page set. Concept pages carry per-source hash tracking so M#4's staleness hook can propagate STALE precisely.

## Patterns to Mirror (from shipped M#3a)

| Category | Source | Pattern |
|---|---|---|
| Agent file format | `agents/brain/ingester.md:1-13` | YAML frontmatter (name, description, tools, model, pattern, trigger_phrases, max_iterations); body with persona + prompt-defense reference + `## Rules` (≥7 NEVER/ALWAYS) + Error recovery section |
| Slash-command procedure shape | `commands/brain.md` — `When $ARGUMENTS starts with ingest <file>` (Steps 0–7) | Numbered steps; explicit path guards; format-prefixed hashes; `_(none)_` fallback strings; structured `FAILED at Step N` error report |
| Page contract style | `skills/ingestion/page-format/SKILL.md` | Frontmatter spec table + body-section spec table with fallback strings; minimal + populated examples |
| Inlined verbatim template | `commands/brain.md` Step 4 (code-page template fenced in command body) | Template lives in `commands/brain.md` (load-bearing); standalone copy in `skills/ingestion/<skill>/templates/` (documentation) |
| Index.md section auto-creation | `commands/brain.md` Step 6 (auto-creates `## Code pages` if missing) | Linker auto-creates `## Concept pages` section on first concept |
| Source-hash format | `commands/brain.md` Step 3 (`git:<hash>` or `sha256:<hash>`) | Concept pages carry per-source hashes in `sources:` array entries |
| Test shape | `tests/e2e-test.sh` T14/T15 | T16: linker + concept-extraction skill + concept-page template; T17: folder-ingest wiring + alias parity for folder + linker procedure |

## Sweep Findings (folded into Tasks)

Twelve findings — five from the pre-M#3a sweep (B1–B5, refined) + seven new from this post-M#3a refresh (B6–B12):

- **B1 — Folder-walk file filter**: walk skips M#3a binary blocklist + lockfiles (`package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `poetry.lock`, `Cargo.lock`, `go.sum`, `composer.lock`, `Pipfile.lock`) + minified/generated artifacts (`*.min.js`, `*.min.css`, `*.bundle.js`, `*.map`).
- **B2 — Linker idempotency on concept pages**: linker reads existing `.brain/concepts/**/*.md` first; if a concept already has a page, UPDATE it (extend `sources:`, refresh Spans/Examples) rather than create a duplicate.
- **B3 — `## Concept pages` section auto-creation in index.md**: linker creates the section if missing (mirror M#3a's `## Code pages` pattern).
- **B4 — Wikilink self-check before write**: linker verifies every `[[code/<path>]]` and `[[concepts/<name>]]` it writes resolves to an actual file. If not, downgrade to a plain mention (no `[[ ]]`); flag in the report. Prevents the M#6 lint pass from flagging dangling links the linker itself produced.
- **B5 — Partial-completion warning**: if N>0 files failed mid-folder, the linker still runs but the report includes `WARNING: linker analyzed M of N requested files; X concepts may be missing sources. Re-run after addressing failed files.`
- **B6 — Per-source-hash tracking in concept pages**: `sources:` is an array of objects `[{ path, hash }]` rather than plain path strings. M#4's staleness hook iterates over each entry and checks the source hash; on mismatch, flips the concept page to `status: STALE` and records which source drifted. Compact alternative (`sources_digest:`) rejected because precision matters more than verbosity here.
- **B7 — Cost gate with concrete estimate**: walk completes → count text files; print `Will ingest N files (~$0.<NN> at $0.003/1k tokens × ~2000 tokens/file). Proceed? (yes/no/show-files)`. Default refuse at N>50 (require explicit `--force` or `--yes` to skip the gate); N=20–50 asks; N<20 proceeds without prompting.
- **B8 — Concrete concept-extraction criteria**: in `skills/ingestion/concept-extraction/SKILL.md`, lock the criteria:
  - DO extract: a name/idea referenced across **≥2** code pages (domain entity, integration boundary, convention, pattern, glossary term)
  - DO extract: a single page that explicitly declares architectural significance ("This is the auth boundary — all routes go through here")
  - DO NOT extract: utility functions, single-use helpers, one-off implementations, type aliases used only in their defining file
  - When uncertain: defer; M#6 lint flags "concept mentioned but lacking page" as a hint to come back later
- **B9 — Concept-page taxonomy: flat with optional slashes**: store at `.brain/concepts/<name>.md` by default; the linker is free to use slash-separated paths if it discovers a natural hierarchy (`.brain/concepts/entities/tenant.md`, `.brain/concepts/integrations/stripe.md`). Don't pre-define categories; let them emerge. The wikilink format accepts both: `[[concepts/tenant]]` or `[[concepts/entities/tenant]]`.
- **B10 — `commands/brain.md` file-size growth**: M#3a left brain.md ~330 lines. M#3b adds two procedure sections (~80 lines folder dispatch + ~60 lines linker). Total expected ~470 lines — manageable. The "do we inline templates or read them from disk" decision stays deferred to M#3c (when 4+ detected/* templates multiply the cost).
- **B11 — Orphan code pages NOT handled here**: if `/brain ingest <folder>` is re-run after source files are deleted, the corresponding `.brain/code/<path>.md` pages remain. M#3b does NOT garbage-collect them. M#6's lint pass will surface orphan pages with "source no longer exists" so the operator can decide what to do. Documented in the linker's Rules.
- **B12 — Use `git ls-files` for the walk**: prefer `git ls-files <folder>` because it already respects `.gitignore`. Fallback: manual recursive walk with the hardcoded exclusion list (`node_modules`, `.git`, `.brain`, `.claude`, `dist`, `build`, `coverage`, `.venv`, `__pycache__`, `target`, `.next`, `.nuxt`).

## Files to Change

| File | Action | Why |
|---|---|---|
| `agents/brain/linker.md` | CREATE | Second writer agent — Reviewer pattern. Reads ingested pages + source-file evidence, decides what becomes a concept page, wires bidirectional wikilinks. Tools: `[Read, Glob, Grep, Bash, Edit, Write]`. `max_iterations: 5`. |
| `skills/ingestion/concept-extraction/SKILL.md` | CREATE | The concept contract — when to extract, when not to. Tier: `ingestion`. Loaded automatically during folder ingest. |
| `skills/ingestion/concept-extraction/templates/concept-page.md` | CREATE | Verbatim template for `.brain/concepts/<name>.md`. Sections: Definition (1–3 sentences), Spans (which code pages reference this), Examples (links to specific symbols/lines), Related (other concept pages). Frontmatter: `kind: concept, status, sources: [{path, hash}]` (B6 format). |
| `commands/brain.md` | UPDATE | Add: (a) folder-dispatch row in dispatch table, (b) `## When $ARGUMENTS starts with ingest <folder>` procedure section, (c) `## Linker procedure (invoked after folder ingest)` section with the inlined concept-page template |
| `commands/graphbrain.md` | UPDATE | Mirror brain.md changes — alias parity for folder dispatch + folder procedure + linker procedure |
| `tests/e2e-test.sh` | UPDATE | T16 (linker agent + concept skill + concept template structural checks; npm pack inclusion); T17 (folder verb wired; folder dispatch stub for files-with-trailing-slash; linker procedure section present; alias parity for both new sections) |
| `.claude/prds/graphbrain.prd.md` | UPDATE | M#3b row → `in-progress` with link to this plan |

## Tasks

### Task 1: agents/brain/linker.md

- **Action**: Create with frontmatter:
  ```yaml
  ---
  name: linker
  description: Reviewer-pattern writer. Runs AFTER folder ingest. Reads the ingested .brain/code/ pages + concept-extraction criteria, then (a) wires bidirectional Cross-references wikilinks between code pages, (b) creates or updates concept pages in .brain/concepts/ for cross-cutting ideas spanning ≥2 sources. Idempotent on re-run. Foreground writer.
  tools: [Read, Glob, Grep, Bash, Edit, Write]
  model: sonnet
  pattern: Reviewer
  trigger_phrases:
    - "link the brain"
    - "wire wikilinks"
    - "find concepts"
    - "synthesize concepts"
  max_iterations: 5
  ---
  ```
  Body: persona + `Read the Prompt Defense Baseline section of CLAUDE.md before acting.` + procedure-pointer (canonical procedure lives in `commands/brain.md` under the linker section) + `## Rules`:
  - **NEVER overwrite a page with `status: VERIFIED`** without `--force`.
  - **NEVER create a concept page from a single source** unless that source explicitly declares architectural significance (top-level docstring, README excerpt, ADR reference).
  - **NEVER write a wikilink to a page that doesn't exist** — if the target's missing, write a plain mention and add a note to the report.
  - **NEVER garbage-collect** `.brain/code/<path>.md` pages whose source has been deleted; M#6 lint handles that.
  - **NEVER write outside `.brain/code/` and `.brain/concepts/`** plus the three derived files (`index.md`, `status.md`, `log.md`).
  - **ALWAYS update both sides of a wikilink** when introducing a new cross-reference.
  - **ALWAYS include per-source hashes** in concept-page `sources:` entries (`[{ path, hash: "git:<hash>" }]`); compute via `git hash-object` or `shasum -a 256` (M#3a's pattern).
  - **ALWAYS update `.brain/index.md`** under `## Concept pages` (create the section if missing).
  - **ALWAYS update `.brain/status.md`** for every concept page written.
  - **ALWAYS append `.brain/log.md`** with `## [YYYY-MM-DD] link | <folder>: <N code pages wired, M concept pages> [-/+]`.
  - Error recovery: same Tier 1 retry / Tier 2 blocked-report as M#3a; `max_iterations: 5`.
- **Mirror**: `agents/brain/ingester.md` (frontmatter + structure + Error recovery)
- **Validate**: T16 — frontmatter parses; all 7 merged fields present; `pattern: Reviewer`; ≥9 NEVER/ALWAYS rules; prompt-defense reference present

### Task 2: skills/ingestion/concept-extraction/SKILL.md

- **Action**: Create with frontmatter:
  ```yaml
  ---
  name: concept-extraction
  description: Decides what qualifies as a concept page. Loaded by the linker agent during /brain ingest <folder>. Locks the criteria so concept-page creation is consistent across linker invocations.
  origin: graphbrain
  version: 0.1.0
  tier: ingestion
  pattern: Reviewer
  related_skills: [behavioral/graphbrain, ingestion/page-format]
  ---
  ```
  Body sections: **When to Activate**, **DO extract**, **DO NOT extract**, **When uncertain (defer)**, **Concept-page contract** (frontmatter + sections + per-source-hash format), **Examples** (1 entity, 1 integration, 1 convention, 1 "do not extract" case).
- **Mirror**: `skills/ingestion/page-format/SKILL.md` (frontmatter shape + body structure)
- **Validate**: T16 — `tier: ingestion`; all 7 fields; body contains the 5 required section headers

### Task 3: skills/ingestion/concept-extraction/templates/concept-page.md

- **Action**: Verbatim template the linker fills. Structure:
  ```markdown
  ---
  kind: concept
  status: <!-- AGENT: FRESH on creation, RESYNCED on update -->
  name: <!-- AGENT: short kebab-case identifier, e.g. "auth-flow" or "tenant-entity" -->
  last_ingested: <!-- AGENT: today's ISO YYYY-MM-DD -->
  ingested_by: <!-- AGENT: your model id -->
  tokens: <!-- AGENT: best estimate; informational -->
  sources:
    <!-- AGENT: one entry per source file referenced. Format:
         - path: src/api/auth.ts
           hash: git:abc1234        # format-prefixed per PRD #32
    -->
  ---

  # <!-- AGENT: human-readable concept name, e.g. "Auth flow" -->

  ## Definition
  <!-- AGENT: 1-3 sentences explaining the concept in domain terms.
       Avoid restating code; explain the IDEA. -->

  ## Spans
  <!-- AGENT: bullet list of code pages this concept lives in:
       - [[code/src/api/auth.ts]] — issues + verifies JWTs
       - [[code/src/middleware.ts]] — validates incoming Authorization headers
       Use wikilinks; verify each target exists in .brain/code/ before writing. -->

  ## Examples
  <!-- AGENT: 1-3 concrete examples, each with a wikilink to the code page
       AND optionally a quoted symbol/snippet. Keep snippets <5 lines. -->

  ## Related
  <!-- AGENT: bullet list of related concept pages: `- [[concepts/<name>]] — <one-line relation>`.
       If none yet, write `_(none yet)_`. -->
  ```
- **Mirror**: `skills/ingestion/page-format/templates/code-page.md` (`<!-- AGENT: ... -->` instruction-comment pattern)
- **Validate**: T16 — starts with `---`; 4 required section headers (Definition, Spans, Examples, Related); ≥8 AGENT directives

### Task 4: Update commands/brain.md — folder ingest + linker procedure

- **Action**: Two new sections after M#3a's `When $ARGUMENTS starts with ingest <file>`:

  **Section A: `## When $ARGUMENTS starts with ingest <folder>`**

  Procedure:
  - **Step 0 — Argument parsing + path guards**: extract folder arg; out-of-repo guard (same as M#3a); resolve and verify it's a directory; error if missing.
  - **Step 1 — Preconditions**: `.brain/` exists; `.brain/.graphbrain-version` present.
  - **Step 2 — Walk the folder** (B12): try `git ls-files <folder>` first. If git unavailable, manual recursive walk excluding hardcoded blocklist (`node_modules .git .brain .claude dist build coverage .venv __pycache__ target .next .nuxt`).
  - **Step 3 — Filter** (B1): exclude binary blocklist + lockfiles + minified/generated. Print the file count + per-extension breakdown.
  - **Step 4 — Cost gate** (B7): estimate `cost ≈ count × $0.006`; if count > 50 require `--yes` flag; if 20–50 ask `Proceed? (yes/no/show-files)`; if <20 proceed.
  - **Step 5 — Per-file ingest loop**: for each filtered path, invoke the M#3a single-file procedure (Steps 0–7 of `When $ARGUMENTS starts with ingest <file>`). Collect results: `ingested[]`, `skipped[]`, `failed[]`. On any per-file FAIL, log it and continue (skip-and-report).
  - **Step 6 — Invoke linker procedure**: jump to the `## Linker procedure (invoked after folder ingest)` section below.
  - **Step 7 — Final report**: structured summary listing per-file outcomes + linker output + grep-parseable log entry.

  **Section B: `## Linker procedure (invoked after folder ingest)`**

  Procedure:
  - **L1 — Load inputs**: read all `.brain/code/**/*.md` pages (the ones just ingested + any prior). Read existing `.brain/concepts/**/*.md` (idempotency, B2). Read `skills/ingestion/concept-extraction/SKILL.md` to refresh extraction criteria (or use the inline criteria below).
  - **L2 — Wire Cross-references**: for each code page, scan its `## Imports` section. For every imported module that resolves to another `.brain/code/<path>.md` page (verify presence — B4), add a `[[code/<path>]] — <why>` line under the importing page's `## Cross-references` section. Add the reverse link on the imported page (bidirectional).
  - **L3 — Discover concept candidates**: scan across the page set for cross-cutting ideas per B8 criteria. Produce a list `[{ name, sources: [code pages where mentioned], evidence: "..." }]`. Discard candidates with <2 sources unless evidence is strong (per B8).
  - **L4 — Materialize concepts**: for each surviving candidate:
    - If a concept page with that name already exists (B2): UPDATE — extend `sources:` array with new entries (per-source hash format per B6); refresh Spans + Examples sections; bump `status: RESYNCED`.
    - If new: WRITE using the **inlined concept-page template** (verbatim copy of `skills/ingestion/concept-extraction/templates/concept-page.md` content, fenced below this Step in the slash-command body).
    - Per-source-hash format: each `sources:` entry is `{ path: <relative>, hash: git:<hash> or sha256:<hash> }` computed via M#3a's hashing logic.
  - **L5 — Update derived files**: append to `.brain/index.md` under `## Concept pages` (create section if missing per B3); append rows to `.brain/status.md` per concept page; append linker activity to `.brain/log.md` with grep-parseable prefix: `## [YYYY-MM-DD] link | <folder>: <N code pages wired, M concept pages>`.
  - **L6 — Linker report**: print a structured summary the calling folder-procedure prints in its Step 7. Include partial-completion warning per B5 if relevant.

  Embed the concept-page template verbatim (~30 lines) inside this section so the agent doesn't need to read it from disk (same pattern as M#3a's inlined code-page template).

  Update the dispatch table: change the `ingest <folder/>` row from stubbed to **implemented (M#3b)**; keep no-arg case stubbed → M#3c.

- **Mirror**: `commands/brain.md` `When $ARGUMENTS starts with ingest <file>` (Step structure + procedure shape + error reporting)
- **Validate**: T17 — both new sections present with their respective step headers; folder dispatch row updated; no-arg row still M#3c stub

### Task 5: Update commands/graphbrain.md (alias parity)

- **Action**: Copy Task 4's two sections verbatim. Update dispatch table identically. The post-M#3a alias-parity assertion (T15) confirmed the byte-identical strategy works.
- **Validate**: T17 — diff over both new section headers ↦ EOF is empty

### Task 6: Update tests/e2e-test.sh — T16 + T17

- **Action**: Add two new test sections before the Summary:

  **T16 — M#3b linker + concept-extraction skill + concept template surface:**
  - `agents/brain/linker.md` exists with valid YAML frontmatter; all 7 merged fields present; `pattern: Reviewer`; ≥9 NEVER/ALWAYS rules; prompt-defense reference
  - `skills/ingestion/concept-extraction/SKILL.md` exists with frontmatter; `tier: ingestion`; `related_skills` includes `behavioral/graphbrain` AND `ingestion/page-format`; 5 required body sections present
  - `skills/ingestion/concept-extraction/templates/concept-page.md` exists; starts with `---`; 4 section headers (Definition, Spans, Examples, Related); ≥8 AGENT directives; `sources:` example shows per-source-hash format (B6)
  - npm pack includes all 3 new files

  **T17 — M#3b folder + linker procedure wiring:**
  - Dispatch table: `ingest <folder/>` is implemented (M#3b); `ingest` no-arg still M#3c
  - `## When $ARGUMENTS starts with ingest <folder>` section present in brain.md
  - Section contains: Step 0–7 headers; references to `git ls-files`; binary blocklist; cost-gate language; per-file ingest invocation pattern; partial-completion warning text
  - `## Linker procedure (invoked after folder ingest)` section present in brain.md
  - Section contains: L1–L6 headers; bidirectional wikilink wording; per-source-hash format (`hash: git:` example); inlined concept-page template (fenced markdown block containing `kind: concept`)
  - Alias parity: both new sections byte-identical between brain.md and graphbrain.md (anchor-from-section-header sed pattern, same trick as T15 for ingest section)
- **Mirror**: T14/T15 patterns from `tests/e2e-test.sh`
- **Validate**: total ~155 (120 + ~35 new); runtime still <5s

### Task 7: PRD update — M#3b → in-progress

- **Action**: Edit `.claude/prds/graphbrain.prd.md`: flip M#3b row `pending` → `in-progress`; set `Plan` cell to `[.claude/plans/graphbrain-m3b.plan.md](.claude/plans/graphbrain-m3b.plan.md)`.
- **Validate**: `grep "3b" .claude/prds/graphbrain.prd.md` shows updated row

## Validation

```bash
# 1. E2E (combined M#1 + M#2 + M#3a + M#3b surface)
bash tests/e2e-test.sh
# Expect: ~155 passes, 0 failures, <5s

# 2. New files exist with correct shape
test -f agents/brain/linker.md
test -f skills/ingestion/concept-extraction/SKILL.md
test -f skills/ingestion/concept-extraction/templates/concept-page.md

# 3. Linker has Reviewer pattern + Rules + prompt-defense
grep -q '^pattern: Reviewer$' agents/brain/linker.md
grep -q '^## Rules' agents/brain/linker.md
grep -q 'Read the Prompt Defense Baseline' agents/brain/linker.md

# 4. Folder dispatch wired; no-arg still stubbed
grep -q 'ingest <folder/>` | \*\*implemented (M#3b)\*\*' commands/brain.md
grep -q 'Milestone #3c (tiered auto-prioritize' commands/brain.md

# 5. Both new procedure sections present
grep -qF '## When `$ARGUMENTS` starts with `ingest <folder>`' commands/brain.md
grep -qF '## Linker procedure (invoked after folder ingest)' commands/brain.md

# 6. Per-source-hash format documented in template
grep -qE 'hash:[[:space:]]*git:' skills/ingestion/concept-extraction/templates/concept-page.md
grep -qE 'hash:[[:space:]]*git:' commands/brain.md   # inlined copy

# 7. Alias parity for both new sections
diff <(sed -n '/^## When `$ARGUMENTS` starts with `ingest <folder>`$/,/^## /p' commands/brain.md | head -n -1) \
     <(sed -n '/^## When `$ARGUMENTS` starts with `ingest <folder>`$/,/^## /p' commands/graphbrain.md | head -n -1)
diff <(sed -n '/^## Linker procedure (invoked after folder ingest)$/,$p' commands/brain.md) \
     <(sed -n '/^## Linker procedure (invoked after folder ingest)$/,$p' commands/graphbrain.md)

# 8. npm pack ships new files
npm pack --dry-run | grep -E 'agents/brain/linker|concept-extraction'

# 9. Manual smoke test (post-merge, on a real repo):
#   In a Claude Code session inside a repo where /brain init has run:
#     /brain ingest src/                  → walks src/, ingests each file, runs linker, concepts emerge
#     /brain ingest src/ (re-run)          → mostly SKIPs (source unchanged); linker re-runs idempotently
#     /brain ingest some/nonexistent/      → error: refused / not found
#     /brain ingest .git/                  → walk excludes per blocklist
```

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Folder ingest cost balloons on large folders | High | B7 cost gate (>50 requires `--yes`; 20–50 asks); per-file SKIP-on-unchanged-source keeps re-runs cheap |
| Linker creates concept-page spam | Med | B8 hard criteria locked in concept-extraction SKILL; M#6 lint will surface orphans |
| Wikilinks introduced are dangling | Low | B4 self-check before write; lint catches anything missed |
| Concept page `sources:` format complicates the M#4 staleness hook | Med | The hook iterates `sources:` and checks each `hash` against the current source-file hash; format is explicit per B6; if hook can't parse the array, it warns rather than crashes |
| Alias drift between brain.md and graphbrain.md (two new sections) | Low | T17 byte-identical asserts on both section anchors |
| brain.md grows past 500 lines | Med | B10 — defer split decision to M#3c; M#3b expected total ~470 lines; M#3c forces the real decision when detected/* templates multiply |
| Per-file ingest in folder mode duplicates Step 0–7 logic in commands/brain.md | Low | The folder procedure REFERENCES `the M#3a single-file procedure (Steps 0–7)` by section name rather than re-listing; agent jumps back to that section per file |
| Operator interrupts mid-folder; partial state on disk | Low | Per-file writes are atomic (M#1's atomic-write pattern); `.brain/log.md` has the partial trail; re-run `/brain ingest <folder>` resumes via SKIPs |
| `git ls-files` includes deleted-but-not-committed files | Low | Walk filter applies `Bash: test -f <path>` before considering each file |
| Linker re-run creates duplicate `## Concept pages` entries in index.md | Low | B2 idempotency: linker reads existing index, dedupes by `[[concepts/<name>]]` link |

## Acceptance

- [ ] All 7 tasks complete
- [ ] Validation §1 (e2e test, ~155 assertions) passes; <5s
- [ ] Validation §2–§8 (new files + shape + dispatch wiring + per-source-hash format + alias parity + npm pack) pass
- [ ] PRD M#3b row → in-progress with plan link
- [ ] Patterns mirrored from M#3a's shipped artifacts — not reinvented
- [ ] No regression: all 120 M#1+M#2+M#3a tests still pass; total ~155 after T16+T17 added
- [ ] (Optional) Manual smoke test on a real repo (dogfood graphbrain itself or graphify/graphbrain/ECC); deferred to post-commit
