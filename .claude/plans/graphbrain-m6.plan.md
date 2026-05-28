# Plan: graphbrain — Milestone #6 (/brain lint — wiki health-check + tier-3 staleness)

**Source PRD**: `.claude/prds/graphbrain.prd.md`
**Selected Milestone**: #6 — Lint pass with `--fix`
**Complexity**: Medium — fifth agent (Verifier pattern); maximum reuse of M#4 lib/page-io + M#3a/b ingest procedures; closes the final tier of the 4-tier staleness model
**Status**: READY — 8 sweep findings (G1–G8) inline

## Summary

`/brain lint` runs a comprehensive wiki health-check. Categories:

1. **Defects** (deterministic): stale pages (verified via hash compare), broken wikilinks, page-size violations, orphan code pages (source deleted), CLAUDE.md schema coherence drift
2. **Gaps** (heuristic): concepts mentioned in ≥2 code pages without a concept page, stub/TBD pages, code pages with no inbound wikilinks
3. **Contradictions** (LLM-driven, opt-in via `--include-contradictions` — tier 3 of the 4-tier staleness model per PRD #10): re-reads page + source, judges drift between described behavior and implemented behavior
4. **Suggested questions** (forward-looking): operator-actionable next steps (e.g., "concept 'auth-flow' mentioned but lacks page; consider /brain query 'how does auth work?'")

Read-only by default. `--fix` opts into batch refresh of STALE pages (delegated to M#3a / M#3b ingesters). Closes **tier 3** of the 4-tier staleness model — all 4 tiers now operational.

After M#6: graphbrain is feature-complete in spirit. Continuous-learning observer (M#7) and dogfood validation (M#8) are the remaining items.

## Patterns to Mirror (from shipped M#1–M#5)

| Category | Source | Pattern |
|---|---|---|
| Agent file format | `agents/brain/{ingester,linker,planner,query}.md` | Merged frontmatter; Rules section; prompt-defense reference; error recovery; orchestration-only tools when delegating writes |
| Procedure shape | `commands/brain.md` query Q0–Q7 + planner T0–T7 | Numbered steps (L0–L7 for lint); explicit preconditions; structured report |
| Hash compare for stale verification | M#5 Q4 + `scripts/hooks/lib/page-io.js` (M#4) | Same exact logic — read frontmatter, re-hash source, compare prefix-aware |
| Cost gate with operator confirmation | M#3b cost gate / M#3c tier gate | `--include-contradictions` defaults off; if requested, show "will run N LLM calls; proceed? (yes/no)" |
| `--fix` delegates to ingester | M#5 Q5 (refresh delegates to M#3a procedure) | Same pattern — lint identifies STALE pages, --fix invokes M#3a per code page + M#3b per concept folder |
| Skill placement | `skills/core/query/` (M#5) | `skills/core/lint/` for M#6 — second new `core/*` skill |
| Tests | T26/T27 | T28 (verifier agent + lint skill structural shape); T29 (procedure section + step headers + flag wiring + alias parity) |

## Sweep Findings (G1–G8, folded in)

- **G1 — Verifier tools `[Read, Glob, Grep, Bash]`** — no Edit/Write/MultiEdit. Same orchestration-only pattern as planner (M#3c) and query (M#5). `--fix` writes happen via delegated ingester procedures.
- **G2 — Reuse `scripts/hooks/lib/page-io.js`** heavily: `readPage` for every page; `walkBrainPages` for the inventory; `findReferencingPages` for orphan detection; `flipToStale` is NOT used (lint reports; doesn't mutate). No duplicated I/O code.
- **G3 — Contradiction-check is opt-in** (`--include-contradictions`). It's an LLM call per page (re-read source + page, judge drift); expensive at scale. Default lint skips it. When opted in: cost gate at >20 pages (same threshold as M#3b folder cost gate).
- **G4 — Structured report** — 4 categories clearly delimited; counts at the top; details under each. Grep-parseable for the operator who wants to pipe `| grep STALE`. Final summary line with overall health.
- **G5 — `--fix` requires confirmation** unless `--yes` is passed. Mirrors M#3c tiered planner's interaction model. Print "will refresh <N> code pages + <M> concept folders; proceed? (yes/no)". On `yes`: delegate. On `no`: exit with the report only.
- **G6 — Lint always exits 0** for v0.1 (regardless of findings). Future post-MVP can extend to exit-code severity (0 = clean, 1 = errors, 2 = warnings) for CI hook usage; skip for now.
- **G7 — CLAUDE.md schema coherence check**: compare the content between `<!-- graphbrain:begin -->` and `<!-- graphbrain:end -->` in user's CLAUDE.md against the verbatim content of `skills/core/init/templates/claude-md-schema.md`. If they differ: flag as "schema drift — run /brain init --force to refresh, OR graphbrain may have shipped a new schema version (check `graphbrain version` vs your .brain/.graphbrain-version)".
- **G8 — Hook interaction is already safe**: M#4's stale-detect hook ignores edits to `.brain/` (`if relEdited.startsWith('.brain' + path.sep) → exit 0`). So when `--fix` triggers ingester writes to `.brain/code/<path>.md`, the hook silently no-ops. No extra work needed.

## Files to Change

| File | Action | Why |
|---|---|---|
| `agents/brain/verifier.md` | CREATE | Fifth agent — Verifier pattern. Tools `[Read, Glob, Grep, Bash]` (no mutation; --fix delegates). max_iterations 5. Rules emphasize: read-only by default; hash-compare-not-frontmatter; delegate-fixes; never-auto-create-concept-pages (operator decision). |
| `skills/core/lint/SKILL.md` | CREATE | Defines the lint contract. Tier: core. Pattern: Verifier. Body covers 4 categories, flag matrix (`--fix`, `--yes`, `--include-contradictions`, `--severity=errors\|warnings\|info`), output shape, cost gate. |
| `commands/brain.md` | UPDATE | Replace M#6 stub on `lint` dispatch row. Add `## When $ARGUMENTS starts with lint` procedure section, steps L0–L7. |
| `commands/graphbrain.md` | UPDATE | Alias parity. |
| `tests/e2e-test.sh` | UPDATE | T28 (verifier + skill structural shape); T29 (procedure + flags + alias parity + npm pack). |
| `.claude/prds/graphbrain.prd.md` | UPDATE | M#6 row → complete. |

**Not in M#6 (deferred):**
- Severity-coded exit codes for CI usage → post-MVP
- Auto-create missing concept pages → out of scope; lint reports, operator decides
- Lint scheduling / cron mode → post-MVP
- Per-rule disable flags (e.g., `--skip-orphan-check`) → post-MVP; v0.1 ships all-or-nothing

## Tasks

### Task 1: agents/brain/verifier.md

Frontmatter:
```yaml
---
name: verifier
description: Fifth agent — Verifier pattern. Read-only by default. Walks .brain/, runs 4 categories of checks (defects, gaps, contradictions [opt-in], suggested questions), produces structured health report. When --fix is passed, delegates batch STALE refresh to M#3a (code pages) and M#3b (concept folders). Mostly reads source files + brain pages; computes hashes via Bash.
tools: [Read, Glob, Grep, Bash]
model: sonnet
pattern: Verifier
trigger_phrases:
  - "lint the brain"
  - "health-check the brain"
  - "audit .brain"
  - "find stale pages"
max_iterations: 5
---
```

Body: persona + prompt-defense reference + procedure pointer (`commands/brain.md` `## When $ARGUMENTS starts with lint`) + `## Rules` (≥9):

- **NEVER mutate `.brain/` directly** — verifier is read-only. `--fix` writes go through M#3a/M#3b ingesters.
- **NEVER auto-create missing concept pages** — lint REPORTS gaps; the operator decides whether to ingest more or accept the gap.
- **NEVER trust `status: STALE` alone** — always verify via hash compare (same as M#5 Q4). Promote-on-match writes go through `lib/page-io.writePage` (M#4), invoked only when --fix is active.
- **NEVER run the LLM-driven contradiction-check** unless `--include-contradictions` is explicit (cost protection per G3).
- **NEVER skip the operator confirmation** for `--fix` unless `--yes` is also passed (G5).
- **ALWAYS use `scripts/hooks/lib/page-io.js` helpers** (`readPage`, `walkBrainPages`, `findReferencingPages`) — don't reimplement page I/O.
- **ALWAYS produce the structured 4-category report** even when categories are empty (operator should see "0 defects, 0 gaps, 0 contradictions" for confidence).
- **ALWAYS append a log entry** with grep-parseable prefix `## [YYYY-MM-DD] lint | <counts>; --fix: <bool>; --include-contradictions: <bool>`.
- **ALWAYS exit 0** for v0.1 (G6 — severity-coded exits are post-MVP).
- Error recovery: Tier 1 retry / Tier 2 blocked-report; max_iterations 5.

### Task 2: skills/core/lint/SKILL.md

Frontmatter:
```yaml
---
name: lint
description: Defines the lint contract — 4 categories (defects, gaps, contradictions, suggested questions), flag matrix (--fix, --yes, --include-contradictions), output shape, cost-gate for opt-in contradiction-check. Loaded by /brain lint. Closes tier 3 of the 4-tier staleness model (PRD #10).
origin: graphbrain
version: 0.1.0
tier: core
pattern: Verifier
related_skills: [behavioral/graphbrain, ingestion/page-format, core/query]
---
```

Body sections: **When to Activate**, **The 4 Categories** (with subsection per category listing each check + its severity), **Flag Matrix** (table of all flags + behavior), **Output Contract** (structured report shape with counts), **`--fix` Confirmation Flow** (G5), **Cost-Gate for `--include-contradictions`** (G3), **Exit Behavior** (always 0 in v0.1; future severity codes), **Examples** (1 clean repo, 1 with stale + gaps, 1 with --fix).

### Task 3: Update commands/brain.md — lint procedure

Dispatch table:
```
| `lint [--fix] [--yes] [--include-contradictions]` | **implemented (M#6)** | See "When `$ARGUMENTS` starts with `lint`" section below |
```

Add procedure section after the query section. Steps L0–L7:

- **L0 — Argument parsing**:
  - Flags: `--fix` (opt into batch refresh), `--yes` (skip --fix confirmation), `--include-contradictions` (opt into LLM contradiction-check; expensive)
  - No question/path expected — `lint` takes only flags
- **L1 — Preconditions**: `.brain/` exists; `.brain/.graphbrain-version` present; CLAUDE.md exists (for schema check)
- **L2 — Inventory**: walk `.brain/code/`, `.brain/concepts/`, `.brain/decisions/` via `lib/page-io.walkBrainPages`. Count pages per kind.
- **L3 — Defects category** (deterministic, fast):
  - **Stale verification**: for every page with `status: STALE`, re-hash the source(s) and compare. Pages where hashes match → "false stale" (should be promoted; lint reports the count; `--fix` promotes via `lib/page-io.writePage`). Pages where hashes don't match → true stale; reported under "needs refresh".
  - **Broken wikilinks**: scan every page body for `[[code/<path>]]` and `[[concepts/<name>]]`; for each, verify the target file exists in `.brain/`. Report dangling links with source page + target.
  - **Page-size violations**: read each page; estimate token count (chars / 4); flag pages over the cap (code: 4k soft / 8k hard; concept: 6k / 12k).
  - **Orphan source files**: for each `.brain/code/<path>.md`, check if `<cwd>/<path>` (source file) still exists. If not, flag as "orphan: source deleted; consider removing the page".
  - **Schema coherence drift**: read the content between `<!-- graphbrain:begin -->` and `<!-- graphbrain:end -->` in `<cwd>/CLAUDE.md`; compare to the verbatim content of `skills/core/init/templates/claude-md-schema.md` (load via Read). If differ: flag as "schema drift — run /brain init --force or check version mismatch".
- **L4 — Gaps category** (heuristic):
  - **Missing concept pages**: scan code pages for repeated mentions of named ideas (capitalized symbols, domain terms) across ≥2 pages; cross-reference against `.brain/concepts/`. Anything mentioned 2+ times with no concept page → "consider creating concept: <name>".
  - **Stub/TBD pages**: any page whose `## Purpose` section is `_(unclear — investigate)_` or whose body contains `_(TBD)_` patterns → "stub: needs deeper ingest".
  - **Orphan code pages (graph sense)**: any `.brain/code/<path>.md` with NO inbound wikilinks from other pages. May or may not be a problem; report as info.
- **L5 — Contradictions category** (LLM-driven, opt-in via `--include-contradictions`):
  - If flag not passed: skip entirely; note in report "skipped (run with --include-contradictions to enable)".
  - If flag passed: estimate cost (`page_count × $0.01` rough — each check is read source + read page + LLM judgment). If `> $0.50`: print "Will run contradiction-check on <N> pages (~$<cost> estimated). Proceed? (yes/no)" and wait. On `yes`: per-page LLM judgment ("does this page accurately describe the source's current behavior?"). Report drift.
- **L6 — Suggested questions** (forward-looking, derived from L3–L5 findings):
  - For each "missing concept": suggest `/brain query "<question framed around that concept>"`
  - For each "stub page": suggest `/brain ingest <source> --force`
  - For each "schema drift": suggest `/brain init --force`
  - For each STALE page: suggest `/brain lint --fix` if not already in --fix mode
- **L6b — `--fix` execution** (only if --fix flag is passed):
  - Compile the refresh list: every page identified as truly STALE in L3.
  - Print: `Will refresh <N> code pages + <M> concept folders. Proceed? (yes/no)`
  - If `--yes` flag is also passed: skip prompt; proceed.
  - On `yes`: for each code page, delegate to the M#3a single-file procedure with `--force`; for each unique parent folder of stale concept-page sources, delegate to the M#3b folder procedure.
  - Track per-page outcomes; collect into the report.
- **L7 — Output + log**:
  ```
  /brain lint — wiki health report (graphbrain v<version>)

  Inventory:
    Code pages:     <count>
    Concept pages:  <count>
    Decision pages: <count>

  ## Defects (<total count>)
    Stale (true):        <count>  [<page paths>]
    Stale (false; ready to promote): <count>  [<paths>]
    Broken wikilinks:    <count>  [<from-page → target>]
    Page-size hard exceeded: <count>  [<paths>]
    Page-size soft exceeded: <count>  [<paths>]
    Orphan source files: <count>  [<paths>]
    Schema drift in CLAUDE.md: <yes|no>

  ## Gaps (<total count>)
    Missing concept pages: <count>  [<suggested names>]
    Stub/TBD pages:        <count>  [<paths>]
    Orphan code pages (no inbound wikilinks): <count>  [<paths>]

  ## Contradictions
    <"skipped — run with --include-contradictions" OR per-page list>

  ## Suggested questions
    - <suggestion 1>
    - <suggestion 2>

  ## Fix results  (only if --fix was passed)
    Refreshed: <count>  [<paths>]
    Failed:    <count>  [<paths with reasons>]

  Logged: .brain/log.md
  ```

  Log entry: `## [YYYY-MM-DD] lint | defects: <N>, gaps: <M>, contradictions: <K|skipped>; --fix: <true|false>; --include-contradictions: <true|false>`

**Error recovery**: same Tier 1 / Tier 2 pattern; max_iterations 5.

### Task 4: Update commands/graphbrain.md (alias parity)

Copy Task 3's dispatch row + procedure section verbatim.

### Task 5: tests/e2e-test.sh — T28 + T29

**T28 — Verifier agent + lint skill structural shape:**
- `agents/brain/verifier.md` exists with frontmatter; all 7 merged fields; `pattern: Verifier`; tools list excludes Edit/Write/MultiEdit; `## Rules` section; prompt-defense reference; ≥9 rules
- `skills/core/lint/SKILL.md` exists; `tier: core`; all 7 fields; required body sections (When to Activate, The 4 Categories, Flag Matrix, Output Contract, `--fix` Confirmation Flow, Cost-Gate, Exit Behavior, Examples)
- npm pack includes both

**T29 — Lint procedure wiring:**
- Dispatch table: `lint` row → `**implemented (M#6)**`
- `## When $ARGUMENTS starts with lint` section present
- All step headers L0–L7 (plus L6b) present
- Critical keywords: `hash compare`, `schema coherence`, `wikilink`, `orphan`, `stub`, `contradiction`, `--include-contradictions`, `--fix`, `--yes`
- Log prefix `## [YYYY-MM-DD] lint |` present
- Alias parity via awk

### Task 6: PRD update

`.claude/prds/graphbrain.prd.md` M#6 row → `complete` with plan link.

## Validation

```bash
# 1. E2E (M#1+M#2+M#3a-d+M#4+M#5+M#6)
bash tests/e2e-test.sh
# Expect: ~420 passes, 0 failures, <5s

# 2. New files
test -f agents/brain/verifier.md
test -f skills/core/lint/SKILL.md
grep -q '^pattern: Verifier$' agents/brain/verifier.md
! grep -E '^tools:.*\b(Edit|Write|MultiEdit)\b' agents/brain/verifier.md

# 3. Procedure wired
grep -qF '**implemented (M#6)**' commands/brain.md
grep -qF '## When `$ARGUMENTS` starts with `lint`' commands/brain.md
for l in L0 L1 L2 L3 L4 L5 L6 L7; do
  grep -qE "\*\*${l} —" commands/brain.md || { echo "missing $l"; exit 1; }
done

# 4. Critical concepts
for kw in 'hash compare' 'schema coherence' 'wikilink' 'orphan' 'stub' 'contradiction'; do
  grep -qF "$kw" commands/brain.md
done

# 5. Flags documented
grep -qF -- '--include-contradictions' commands/brain.md
grep -qF -- '--fix' commands/brain.md
grep -qF -- '--yes' commands/brain.md

# 6. Alias parity
diff <(awk '/^## When `\$ARGUMENTS` starts with `lint`$/{flag=1} flag' commands/brain.md) \
     <(awk '/^## When `\$ARGUMENTS` starts with `lint`$/{flag=1} flag' commands/graphbrain.md)

# 7. npm pack
npm pack --dry-run | grep -E 'agents/brain/verifier|skills/core/lint/SKILL'
```

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Contradiction-check too expensive | Med | G3 — opt-in flag + cost gate at >$0.50 |
| `--fix` cascades into unintended refresh | Med | G5 — explicit operator confirmation unless `--yes` |
| Schema drift false positive (whitespace differences) | Low | Normalize whitespace before comparing (trim trailing spaces, normalize line endings); compare token-by-token rather than byte-for-byte |
| Wikilink check is slow on large brains | Low | Walk is O(pages); per-link verify is O(1) file-exists; <1s for any reasonable brain |
| Schema coherence reads `skills/core/init/templates/claude-md-schema.md` from npm-installed location (Q1) | Low | Same as M#5 query — the template file ships in the npm package; agent reads from the installed location. Document path resolution like M#3a does ("locate in the graphbrain npm package"). |
| brain.md size growth | Med | M#6 adds ~180 lines (procedure + report templates). Total brain.md ~1030 lines after M#6. The "extract to runtime config" decision from M#3c/M#5 is now genuinely pressing — flag for M#7 or post-MVP. |
| Alias drift on the lint procedure | Low | T29 awk byte-identical check |
| Verifier triggers M#3a/M#3b indirectly through --fix; cascading hook events | Resolved | G8 — M#4 stale-detect hook ignores edits to `.brain/`. Safe. |

## Acceptance

- [ ] All 6 tasks complete
- [ ] Validation §1 (e2e ~420) passes; <5s
- [ ] Validation §2–§7 pass
- [ ] PRD M#6 row → complete
- [ ] No regression: 375 prior tests pass; total ~420 after T28+T29 added (≈45 new)
- [ ] Patterns mirrored from M#1–M#5 — minimal new code
