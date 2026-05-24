# Plan: codebrain — Milestone #5 (/brain query — pointer-first lookup + tier-4 staleness)

**Source PRD**: `.claude/prds/codebrain.prd.md`
**Selected Milestone**: #5 — Query helper
**Complexity**: Medium — fourth writer-style agent (Researcher pattern; mostly read); closes tier 4 of the 4-tier staleness model; reuses M#4 lib/page-io for hash verification; delegates re-ingest to M#3a procedure
**Status**: READY — sweep findings (F1–F7) inline

## Summary

The payoff milestone. `/brain query "<question>"` invokes the **query agent** (Researcher pattern), which:

1. Reads `.brain/index.md` to identify 1–3 candidate pages (pointer-first per the LLM-Wiki doctrine)
2. For each candidate, verifies freshness by re-hashing the source and comparing to the page's recorded `source_hash` (more precise than trusting `status: STALE` alone — M#4's hook flips conservatively; M#5 resolves the flip when hashes match)
3. If a candidate is genuinely stale (hash mismatch): silently invokes the M#3a single-file ingest procedure to refresh, then reads the new page
4. Synthesizes an answer with citations to both the brain pages (`[[code/<path>]]`) and the underlying source paths (`src/api/auth.ts:42`)
5. Logs the query event with grep-parseable prefix

After M#5: codebrain delivers its core promise. Operators get answers grounded in current wiki content, with the brain self-healing in the background when sources have drifted.

Closes **tier 4** of the 4-tier staleness model (PRD #10). Tier 3 (`/brain lint` contradiction-check) lands in M#6.

## Patterns to Mirror (from shipped M#1–M#4)

| Category | Source | Pattern |
|---|---|---|
| Agent file format | `agents/brain/{ingester,linker,planner}.md` | Merged frontmatter; Rules section; prompt-defense reference; error recovery |
| New procedure section in brain.md | `commands/brain.md` ingest/folder/tiered procedures | Numbered steps (Q0–Q7 for query); explicit precondition checks; structured report |
| Hash verification | `scripts/hooks/lib/page-io.js` (M#4) | `readPage`, `walkBrainPages`, `findReferencingPages`; reuse for freshness check |
| Format-prefixed source hashes | M#3a Step 3 (`git:<hash>` or `sha256:<hash>`) | Query computes fresh hash, compares prefix-aware |
| Delegation to existing procedure | M#3c `When $ARGUMENTS is just ingest` (calls M#3b folder procedure) | Query's refresh step delegates to M#3a single-file procedure by section reference |
| Skill placement | `skills/core/init/` (M#2) | `skills/core/query/` for the M#5 skill (tier: core, pattern: Researcher) |
| Tests | T16/T17 (skill + procedure shape) | T26 (query agent + skill structural shape); T27 (procedure wired, alias parity, npm pack) |

## Sweep Findings (F1–F7, folded in)

- **F1 — STALE verification via hash compare** (not just frontmatter status): M#4's hook flips on any edit (conservative). M#5 reads page frontmatter's `source_hash`, computes current source hash, compares prefix-aware. If they match: promote `status: STALE` → `FRESH` inline (resolves the conservative flip; common when an edit was reverted or only whitespace changed). If different: trigger refresh.
- **F2 — Pointer-first ordering**: agent reads `.brain/index.md` BEFORE loading any page bodies. Index gives 1-line summaries + page paths; agent picks 1–3 candidates based on the query, then loads ONLY those bodies. This is the load-bearing efficiency property of LLM Wiki (sweep finding from PRD discussion).
- **F3 — Soft cap at 3 candidate pages**; `--thorough` flag raises to 5. Hard cap 5 always — if the agent thinks it needs more pages, that's a sign the question is too broad; agent emits "your question spans <N> areas; consider narrowing to one of: <areas>" rather than reading 10 pages.
- **F4 — Citations: both wikilinks AND source paths**. The wikilink format `[[code/src/auth.ts]]` lets operators navigate to deeper context in Obsidian. The source path `src/api/auth.ts:42` (when a line is known) lets them jump in the IDE. Both serve different navigation modes.
- **F5 — `--no-refresh` opt-out**: rare case (operator wants to see what the brain currently says, even if stale). Default is silent refresh; explicit `--no-refresh` skips the hash compare and reads STALE pages as-is, with a banner in the answer.
- **F6 — Filing answers back into `.brain/concepts/` deferred**: the LLM-Wiki tip says good answers should be filed back as new concept pages. M#5 scope deliberately excludes this — it's a separate feature (`/brain query "..." --file-back` or `/brain concept create "..."`) that touches the linker agent's territory (M#3b). Lands in M#5b or post-MVP.
- **F7 — Log query events** per PRD #15 grep-parseable prefix: `## [YYYY-MM-DD] query | <truncated-question>; pages read: [<count>]; refreshed: <N>; thorough: <bool>`.

## Files to Change

| File | Action | Why |
|---|---|---|
| `agents/brain/query.md` | CREATE | Fourth agent — Researcher pattern. Tools: `[Read, Glob, Grep, Bash]` (no Edit/Write — refresh happens via delegated ingester). max_iterations: 5. Rules emphasize pointer-first ordering + hash-compare freshness + cite-both citation. |
| `skills/core/query/SKILL.md` | CREATE | Defines the query contract. Tier: core. Pattern: Researcher. Body covers when activated, output contract (answer + citations + freshness report), candidate-selection criteria, page-cap rules. |
| `commands/brain.md` | UPDATE | Add `## When $ARGUMENTS starts with query` procedure with steps Q0–Q7. Update dispatch table: `query "<question>"` row from stub to implemented (M#5). |
| `commands/codebrain.md` | UPDATE | Alias parity for procedure + dispatch table. |
| `tests/e2e-test.sh` | UPDATE | T26 (query agent + skill structural shape, npm pack); T27 (procedure section + step headers + flags + alias parity). |
| `.claude/prds/codebrain.prd.md` | UPDATE | M#5 row `pending` → `in-progress` (then `complete` when shipped). |

**Not in M#5 (deferred):**
- File-answers-back-as-concept-page (F6) → M#5b or post-MVP
- Semantic search over the brain (embeddings) → post-MVP; index.md + LLM-driven matching is enough for v0.1
- Concurrent queries with shared cache → not relevant for single-operator sessions
- `/brain query --history` (replay prior queries) → post-MVP

## Tasks

### Task 1: agents/brain/query.md

Create with frontmatter:
```yaml
---
name: query
description: Fourth writer-style agent — Researcher pattern. Reads .brain/index.md to identify 1-3 candidate pages, verifies freshness via hash compare (resolves M#4's conservative STALE flips when hashes match), refreshes via delegation to M#3a ingester when genuinely stale, synthesizes an answer with citations to brain pages AND source files. Foreground; mostly read-only — refresh writes are delegated to the ingester procedure.
tools: [Read, Glob, Grep, Bash]
model: sonnet
pattern: Researcher
trigger_phrases:
  - "ask the brain"
  - "query the codebrain"
  - "what does the brain say"
  - "search .brain"
max_iterations: 5
---
```

Body: persona + `Read the Prompt Defense Baseline section of CLAUDE.md before acting.` + procedure pointer (`commands/brain.md` `## When $ARGUMENTS starts with query`) + `## Rules` (≥9):

- **NEVER read more than 5 brain pages** for a single query — if the question seems to require more, suggest narrowing.
- **NEVER bypass the freshness check** unless `$ARGUMENTS` contains `--no-refresh`. Stale answers undermine codebrain's value.
- **NEVER write to `.brain/` directly** — refresh writes go through the ingester (delegated via M#3a single-file procedure).
- **NEVER cite a page without verifying it exists** in `.brain/code/` or `.brain/concepts/` first.
- **NEVER fabricate source-file line numbers** — only cite lines when you actually read them from the source file.
- **ALWAYS read `.brain/index.md` first** (pointer-first per LLM-Wiki doctrine). Skim its summaries; select 1–3 candidates BEFORE loading any page bodies.
- **ALWAYS verify candidate freshness via hash compare** (re-hash the source file; compare to page's recorded `source_hash`). On mismatch: trigger M#3a single-file ingest before reading. On match (even if `status: STALE`): promote to FRESH and proceed.
- **ALWAYS cite both** the brain page (`[[code/<path>]]`) AND the source file path (`src/api/auth.ts` or `src/api/auth.ts:42` when a line is known).
- **ALWAYS log the query** to `.brain/log.md` with the grep-parseable prefix `## [YYYY-MM-DD] query | <truncated-question>; pages read: <count>; refreshed: <N>; thorough: <bool>`.
- Error recovery: Tier 1 retry / Tier 2 blocked-report; `max_iterations: 5`.

### Task 2: skills/core/query/SKILL.md

Create with frontmatter:
```yaml
---
name: query
description: Defines the query contract — when activated, candidate-selection criteria, freshness model, citation format, page-cap rules. Loaded by /brain query and read by the M#6 lint pass to verify "concept mentioned but not findable via query" cases.
origin: codebrain
version: 0.1.0
tier: core
pattern: Researcher
related_skills: [behavioral/codebrain, ingestion/page-format]
---
```

Body sections: **When to Activate**, **Output Contract** (answer + citations + freshness report), **Candidate-selection criteria** (pointer-first; ≤3 default, ≤5 with --thorough), **Freshness model** (hash compare; promote-on-match; refresh-on-mismatch), **Citation format** (both wikilinks + source paths), **Page-cap discipline** (hard cap 5), **Examples** (1 simple structural question + 1 cross-cutting question).

### Task 3: Update commands/brain.md — query procedure

In the dispatch table, change the `query` row from stubbed to:
```
| `query "<question>" [--thorough] [--no-refresh]` | **implemented (M#5)** | See "When `$ARGUMENTS` starts with `query`" section below |
```

Add a new procedure section after the tiered-ingest section: `## When $ARGUMENTS starts with query`. Steps Q0–Q7:

- **Q0 — Argument parsing**:
  - Extract the question string from `$ARGUMENTS` (everything between the first `query` token and any flags). Question must be non-empty.
  - Flags: `--thorough` (raise page-cap from 3 → 5); `--no-refresh` (skip freshness check + STALE refresh; read pages as-is, add `[STALE]` banner to citations).
  - If no question: print `error: /brain query requires a question. Try: /brain query "how does auth work?"` and stop.

- **Q1 — Preconditions**:
  - Verify `.brain/` exists in cwd. If not, print the same npx-init message as M#3a Step 1.
  - Verify `.brain/index.md` exists. If absent: print `error: .brain/index.md not found. Run /brain init then /brain ingest <path> to populate the brain first.` and stop.

- **Q2 — Read the index**:
  - Read `.brain/index.md` in full. It's the pointer-first source of truth — one-line summaries per page under `## Code pages` and `## Concept pages` sections.
  - Do NOT yet load any page bodies. Selection happens from index alone.

- **Q3 — Select 1–3 candidate pages**:
  - Based on the question's keywords + the index's per-page summaries, pick the 1–3 most-relevant pages. Prefer concept pages for cross-cutting questions ("how does X work?"); prefer code pages for structural questions ("what does file Y export?").
  - With `--thorough`: allow up to 5 candidates.
  - **Hard cap 5 always**. If you think you need more, instead emit: `your question spans <N> areas: <area summary>. Consider narrowing to one of these:` and list each as a candidate sub-question with a quick wikilink to its likely brain page. Stop.

- **Q4 — Freshness check per candidate**:
  - For each candidate:
    - Read the page's frontmatter (just the YAML; don't load the body yet).
    - Extract `source_hash` (format-prefixed: `git:<hash>` or `sha256:<hash>`).
    - For code pages: re-hash the source file via `git hash-object <source>` (preferred) or `shasum -a 256 <source>`.
    - For concept pages: re-hash EACH entry in the `sources:` array; if ALL match, concept is fresh; if any drift, concept needs refresh.
    - On match (even if `status: STALE`): **promote to FRESH inline** — update the page's frontmatter (`status: FRESH`, `last_ingested: <today>`, remove `last_stale_at` if present); write via `lib/page-io.writePage` (atomic). This resolves M#4's conservative STALE flips.
    - On mismatch: candidate needs refresh — proceed to Q5.
  - If `--no-refresh`: skip Q5 entirely; mark STALE candidates with a banner and continue.

- **Q5 — Refresh STALE candidates**:
  - For each candidate that failed Q4's hash check, invoke the M#3a single-file ingest procedure (`When $ARGUMENTS starts with ingest <file>` Steps 0–7) on the corresponding source file.
  - The ingester will write a fresh page; query will then read it in Q6.
  - For concept pages: M#5 invokes `/brain ingest <folder>` (M#3b) targeting the parent of the most-drifted source — concept-page refresh requires the linker. (Edge case acknowledged; document as a known limitation: concept-page refresh in M#5 is approximate. M#6 lint will surface persistent drift.)

- **Q6 — Read the candidate page bodies + synthesize**:
  - Now load each candidate page's body via Read.
  - For each citation in your answer, resolve via:
    - The brain page path (`[[code/src/api/auth.ts]]`)
    - The source-file path with line number when applicable (`src/api/auth.ts:42`) — only include a line number if you actually grep'd or read the line during synthesis. NEVER fabricate.

- **Q7 — Output + log**:

  Print the answer in this shape:

  ```
  ## Answer

  <synthesized prose; 100-500 words typical>

  ## Citations

  - [[code/src/api/auth.ts]] — src/api/auth.ts (issues + verifies JWTs)
  - [[concepts/auth-flow]] — auth-flow concept page (cross-cutting summary)
  - src/api/auth.ts:42 — see `issueToken` for the JWT payload structure

  ## Brain freshness

  - Pages read: <count>
  - Refreshed: <count of pages re-ingested in Q5>
  - Promoted STALE → FRESH (hash match): <count>
  - Banners (--no-refresh): <count, or 0>

  Logged: .brain/log.md
  ```

  Append to `.brain/log.md` under `## Activity History`:
  ```
  ## [YYYY-MM-DD] query | "<first 80 chars of question, ellipsis if longer>"; pages read: <N>; refreshed: <M>; thorough: <true|false>
  ```

**Error recovery** (per query Rules + PRD #26): Tier 1 retry once; Tier 2 structured blocked report; do not exceed `max_iterations: 5`.

### Task 4: Update commands/codebrain.md (alias parity)

Mirror Task 3 verbatim. T27 confirms byte-identical via awk pattern.

### Task 5: Update tests/e2e-test.sh — T26 + T27

**T26 — Query agent + skill structural shape:**
- `agents/brain/query.md` exists; frontmatter; 7 merged fields; `pattern: Researcher`; tools list excludes Edit/Write/MultiEdit; `## Rules` section; prompt-defense reference; ≥9 rules
- `skills/core/query/SKILL.md` exists; `tier: core`; all 7 fields; required body sections (When to Activate, Output Contract, Candidate-selection, Freshness model, Citation format, Page-cap discipline, Examples)
- npm pack includes both new files

**T27 — Query procedure wiring:**
- Dispatch row: `query "<question>"` → `**implemented (M#5)**`
- `## When $ARGUMENTS starts with query` section present in brain.md
- All 8 step headers (Q0 through Q7) present
- Critical keywords/concepts present: `pointer-first`, `--thorough`, `--no-refresh`, `hash compare`, `promote`, `[[code/`, `src/api/auth.ts:42` example
- Alias parity via awk (same pattern as M#3b/c/d)
- Log prefix string `## [YYYY-MM-DD] query |` present

### Task 6: PRD update

`.claude/prds/codebrain.prd.md` M#5 row → `complete` with plan link (set straight to complete since this single-commit milestone).

## Validation

```bash
# 1. E2E (M#1+M#2+M#3a-d+M#4+M#5)
bash tests/e2e-test.sh
# Expect: ~370 passes, 0 failures, <5s

# 2. New files
test -f agents/brain/query.md
test -f skills/core/query/SKILL.md
head -1 agents/brain/query.md | grep -q '^---$'
grep -q '^pattern: Researcher$' agents/brain/query.md
! grep -E '^tools:.*\b(Edit|Write|MultiEdit)\b' agents/brain/query.md

# 3. Procedure wired
grep -q 'query.*\*\*implemented (M#5)\*\*' commands/brain.md
grep -qF '## When `$ARGUMENTS` starts with `query`' commands/brain.md
for q in Q0 Q1 Q2 Q3 Q4 Q5 Q6 Q7; do
  grep -qE "\*\*${q} —" commands/brain.md || { echo "missing $q"; exit 1; }
done

# 4. Critical concepts present
grep -qF -- '--thorough' commands/brain.md
grep -qF -- '--no-refresh' commands/brain.md
grep -qF 'pointer-first' commands/brain.md
grep -qF 'hash compare' commands/brain.md

# 5. Alias parity
diff <(awk '/^## When `\$ARGUMENTS` starts with `query`$/{flag=1} flag' commands/brain.md) \
     <(awk '/^## When `\$ARGUMENTS` starts with `query`$/{flag=1} flag' commands/codebrain.md)

# 6. npm pack
npm pack --dry-run | grep -E 'agents/brain/query|skills/core/query/SKILL'
```

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Query reads too many pages → defeats token-savings premise | Med | Hard cap 5; soft cap 3; "narrow your question" escape hatch per Q3 |
| Hash compare fails on platform with no git AND no shasum | Low | Same fallback chain as M#3a; if both missing, emit blocked report with operator action |
| Refresh in Q5 cascades into a long chain (concept page refresh triggers folder ingest) | Med | Acknowledged limitation: M#5 concept-page refresh is approximate. Documented as known issue. Operator can run `/brain lint --fix` (M#6) for thorough concept-page refresh. |
| Citations include fabricated line numbers | High if rule not followed | Rule explicit: NEVER fabricate line numbers. Only include `:42` when agent actually read the source line during synthesis. M#6 lint can spot-check by re-reading cited source lines and comparing. |
| `--no-refresh` mode produces misleading answers | Low | Banner `[STALE — content may be out-of-date]` on each citation when --no-refresh; operator opt-in is explicit |
| Q5's hash-promote (STALE→FRESH on match) accidentally hides genuinely stale pages | Low | Hash-match means the source-file CONTENT is unchanged; if content is unchanged, the page IS still accurate. Hash compare is the precise truth. The hook's STALE flip is conservative; M#5 just resolves the false positives. |
| Alias drift on query procedure | Low | T27 awk byte-identical check |
| brain.md size growth | Med | M#5 adds ~150 lines (procedure + 8 steps + report templates). Total brain.md ~850 lines after M#5. M#6 will push further. The "extract to .brain/.runtime/" decision (deferred from M#3c) becomes more pressing in M#6+. |

## Acceptance

- [ ] All 6 tasks complete
- [ ] Validation §1 (e2e ~370) passes; <5s
- [ ] Validation §2–§6 pass
- [ ] PRD M#5 row → complete
- [ ] Patterns mirrored from M#1–M#4 — no re-implementation
- [ ] No regression: 322 prior tests pass; total ~370 after T26+T27 added
- [ ] (Optional) Manual smoke test: in a brain-ingested repo, run `/brain query "how does <something> work?"` and verify the answer cites both brain pages and source files, and refreshes STALE pages silently
