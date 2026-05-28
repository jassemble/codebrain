---
name: lint
description: Defines the lint contract — 4 categories (defects, gaps, contradictions, suggested questions), flag matrix (--fix, --yes, --include-contradictions), output shape, cost-gate for opt-in contradiction-check. Loaded by /brain lint. Closes tier 3 of the 4-tier staleness model (PRD #10).
origin: graphbrain
version: 0.1.0
tier: core
pattern: Verifier
related_skills: [behavioral/graphbrain, ingestion/page-format, core/query]
---

# lint — wiki health-check (4 categories)

This skill defines what `/brain lint` does. The verifier agent (`agents/brain/verifier.md`) consumes this contract.

Read-only by default. `--fix` opts into batch refresh of STALE pages via delegation to M#3a (code) and M#3b (concept folders).

## When to Activate

- Operator runs `/brain lint [--fix] [--yes] [--include-contradictions]`
- A trigger phrase matches (e.g., "lint the brain", "audit .brain")
- Periodic CI invocation (post-MVP — currently lint always exits 0; severity-coded exit codes are future work)

## The 4 Categories

### 1. Defects (deterministic — fast, no LLM calls)

| Check | What it catches | Severity |
|---|---|---|
| **Stale (true)** | Pages with `status: STALE` AND hash compare confirms source drifted | ERROR — needs refresh (or `--fix`) |
| **Stale (false-positive)** | Pages with `status: STALE` BUT hash compare shows source unchanged (M#4 hook flipped conservatively for an Edit that reverted to original content) | INFO — promoted to FRESH inline if `--fix` is active |
| **Broken wikilinks** | `[[code/<path>]]` or `[[concepts/<name>]]` references that don't resolve to a real file under `.brain/` | ERROR — fix manually or via re-ingest |
| **Page-size hard violations** | Code pages >8k tokens OR concept pages >12k tokens (PRD #7) | ERROR — split source file or split concept |
| **Page-size soft violations** | Code pages >4k tokens OR concept pages >6k tokens (PRD #7) | WARNING |
| **Orphan source files** | `.brain/code/<path>.md` exists but `<cwd>/<path>` (source) was deleted | WARNING — operator decides: keep page (historical) or remove it |
| **CLAUDE.md schema drift** | Managed-region content differs from `skills/core/init/templates/claude-md-schema.md` (the M#2 reference template) | WARNING — run `/brain init --force` to refresh, or check `graphbrain version` vs `.brain/.graphbrain-version` |

### 2. Gaps (heuristic — fast, no LLM calls)

| Check | What it catches | Severity |
|---|---|---|
| **Missing concept pages** | Named ideas mentioned in ≥2 code pages with no corresponding `.brain/concepts/<name>.md` (concept-extraction criteria from M#3b) | INFO — suggest `/brain ingest <folder>` to give the linker more material, OR `/brain query "..."` to surface the gap |
| **Stub / TBD pages** | Pages whose `## Purpose` is `_(unclear — investigate)_` or whose body contains `_(TBD)_` patterns | INFO — suggest re-ingest with deeper context |
| **Orphan code pages** | `.brain/code/<path>.md` with no inbound wikilinks from any other brain page (graph-orphan, not source-orphan) | INFO — may be a leaf module (no callers) or a missed link |

### 3. Contradictions (LLM-driven — opt-in)

Only runs when `--include-contradictions` is explicit. For each page: re-reads the source file + the brain page, judges whether the page accurately describes the source's current behavior. Catches **subtle drift the hook can't see** — e.g., a function's body changed but the signature stayed the same (M#4's hook flipped STALE on the edit, but the page's Purpose description may still be accurate).

This is tier 3 of the 4-tier staleness model (PRD #10) — the second-line check after tier 1 (hook reverse-lookup) and tier 2 (sources frontmatter).

### 4. Suggested questions (forward-looking)

Derived from L3–L5 findings. Operator-actionable next steps:

- For each "missing concept": `consider /brain query "<question>"` or `consider /brain ingest <folder>`
- For each "stub page": `consider /brain ingest <source> --force`
- For each "schema drift": `consider /brain init --force`
- For STALE pages (when not in `--fix` mode): `consider /brain lint --fix`

## Flag Matrix

| Flag | Default | Effect |
|---|---|---|
| (none) | — | Read-only health report; categories 1, 2, 4 run; category 3 skipped |
| `--include-contradictions` | off | Enables category 3 (LLM-driven); shows cost-gate at >$0.50 estimated |
| `--fix` | off | Opts into batch refresh of true STALE pages; asks operator confirmation (unless `--yes`); delegates to M#3a (code) / M#3b (concept folders) |
| `--yes` | off | Skips the `--fix` confirmation prompt; only meaningful with `--fix` |
| `--fix --include-contradictions --yes` | — | Full audit + auto-fix + no prompts; intended for CI/scheduled use |

## Output Contract

Structured 4-category report — always produced, even when categories are empty:

```
/brain lint — wiki health report (graphbrain v<version>)

Inventory:
  Code pages:     <count>
  Concept pages:  <count>
  Decision pages: <count>

## Defects (<total count>)
  Stale (true):                    <count>  [<paths>]
  Stale (false; ready to promote): <count>  [<paths>]
  Broken wikilinks:                <count>  [<from-page → target>]
  Page-size hard:                  <count>  [<paths>]
  Page-size soft:                  <count>  [<paths>]
  Orphan source files:             <count>  [<paths>]
  Schema drift in CLAUDE.md:       <yes|no>

## Gaps (<total>)
  Missing concept pages: <count>  [<suggested names>]
  Stub/TBD pages:        <count>  [<paths>]
  Orphan code pages (no inbound wikilinks): <count>  [<paths>]

## Contradictions
  <"skipped — run with --include-contradictions" OR per-page list>

## Suggested questions
  - <suggestion 1>
  - <suggestion 2>

## Fix results  (only when --fix was passed)
  Refreshed: <count>  [<paths>]
  Failed:    <count>  [<paths with reasons>]

Logged: .brain/log.md
```

## `--fix` Confirmation Flow

When `--fix` is passed:

1. Run categories 1–4 first.
2. Compile the refresh list: every page reported under "Stale (true)" in category 1.
3. Print: `Will refresh <N> code pages + <M> concept folders. Proceed? (yes/no)`
4. If `--yes` flag is also passed: skip the prompt; proceed.
5. On `yes`: for each code page, delegate to M#3a single-file procedure with `--force`; for each unique parent folder of stale concept-page sources, delegate to M#3b folder procedure.
6. On `no`: exit with the report only (no refresh performed).
7. Track per-page outcomes; collect into the "Fix results" report section.

## Cost-Gate for `--include-contradictions`

Contradiction-check is LLM-expensive: one call per page (re-read source + page, judge drift).

Cost estimate: `page_count × $0.01` (rough — heuristic; actual depends on page sizes).

If estimate > $0.50: print `Will run contradiction-check on <N> pages (~$<cost> estimated). Proceed? (yes/no)` and wait. Operator responds. `yes` proceeds; `no` skips category 3.

If estimate ≤ $0.50: proceed without prompting.

## Exit Behavior

**Always exits 0 for v0.1** — regardless of findings. The report's `## Defects` and `## Gaps` counts are the source of truth for whether action is needed.

Future post-MVP: severity-coded exit codes (0 = clean; 1 = errors; 2 = warnings only) for CI hook usage. Not yet — keeps the v0.1 lint friendly to interactive use without surprising operators with non-zero exits.

## Examples

### Example 1: Clean repo

```
/brain lint — wiki health report (graphbrain v0.1.0)

Inventory:
  Code pages:     12
  Concept pages:  3
  Decision pages: 0

## Defects (0)
  Stale (true):                    0
  Stale (false; ready to promote): 0
  Broken wikilinks:                0
  Page-size hard:                  0
  Page-size soft:                  0
  Orphan source files:             0
  Schema drift in CLAUDE.md:       no

## Gaps (1)
  Missing concept pages: 0
  Stub/TBD pages:        0
  Orphan code pages:     1  [code/src/legacy/old-handler.ts.md]

## Contradictions
  skipped — run with --include-contradictions to enable

## Suggested questions
  - Orphan code page code/src/legacy/old-handler.ts.md has no inbound wikilinks.
    Consider `/brain query "what calls old-handler?"` to confirm it's intentionally standalone.

Logged: .brain/log.md
```

### Example 2: Repo with stale pages + `--fix`

```
/brain lint --fix

[report shows 3 true stale pages + 1 false-positive]

Will refresh 3 code pages + 1 concept folder. Proceed? (yes/no) yes

[delegates to M#3a per code page, M#3b for the concept folder]

## Fix results
  Refreshed: 4  [code/src/auth.ts.md, code/src/middleware.ts.md, code/src/lib/jwt.ts.md, concepts/auth-flow.md]
  Failed:    0

Logged: .brain/log.md
```

### Example 3: Full audit (CI-friendly)

`/brain lint --fix --include-contradictions --yes`

Runs all 4 categories; auto-confirms refresh; no prompts. Suitable for periodic CI or cron.

## Cross-references

- The agent that runs this skill: `../../../agents/brain/verifier.md`
- The procedure (load-bearing): `../../../commands/brain.md` `## When $ARGUMENTS starts with lint`
- Page contract (what lint validates): `../../ingestion/page-format/SKILL.md`
- Concept-extraction criteria (lint applies inverse): `../../ingestion/concept-extraction/SKILL.md`
- Hash-compare helpers: `../../../scripts/hooks/lib/page-io.js` (M#4)
- Schema-drift reference template: `../../core/init/templates/claude-md-schema.md` (M#2)
- PRD design decisions: #7 (page caps lint enforces), #10 (4-tier staleness — M#6 closes tier 3), #25 (lint --fix combined, not separate /brain sync), #32 (id-prefix hashes lint reads)
