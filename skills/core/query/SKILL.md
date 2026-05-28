---
name: query
description: Defines the query contract — when activated, candidate-selection criteria, freshness model (hash compare with promote-on-match), citation format (both wikilinks + source paths), page-cap rules. Loaded by /brain query (M#5); also read by the M#6 lint pass to verify "concept mentioned but not findable via query" cases.
origin: graphbrain
version: 0.1.0
tier: core
pattern: Researcher
related_skills: [behavioral/graphbrain, ingestion/page-format]
---

# query — pointer-first lookup with freshness verification

This skill defines what `/brain query` does and how it does it. The query agent (`agents/brain/query.md`) consumes this contract; the M#6 lint pass also reads it to identify cases where a concept is referenced but no query would find it.

## When to Activate

- Operator runs `/brain query "<question>" [--thorough] [--no-refresh]`
- A trigger phrase matches (e.g., "ask the brain", "search .brain")

## Output Contract

Every successful query produces three sections:

1. **`## Answer`** — 100–500 words of synthesized prose grounded in the loaded pages. Avoid speculation; if the loaded pages don't fully answer, say so explicitly.
2. **`## Citations`** — bulleted list, mixing two citation forms:
   - **Brain page**: `[[code/<path>]]` or `[[concepts/<name>]]` — for Obsidian-side navigation
   - **Source path**: `<path>` or `<path>:<line>` — for IDE jump-to-code. Line suffix only when actually read during synthesis.
3. **`## Brain freshness`** — meta-information about the query run: pages read, count refreshed (M#3a re-ingest), count promoted STALE → FRESH via hash match, count banner'd for `--no-refresh`.

## Candidate-Selection Criteria

The query agent reads `.brain/index.md` first (pointer-first per the LLM-Wiki doctrine). From the index's per-page one-line summaries, the agent picks:

- **Default**: 1–3 candidate pages, biased toward the most-specific matches first.
- **`--thorough`**: up to 5 candidates.
- **Hard cap 5 always**: if the agent thinks it needs more, that's a sign the question is too broad. The agent emits "your question spans <N> areas" and lists each as a candidate sub-question with a tentative brain-page wikilink, rather than reading 10 pages.

Selection heuristics (informal, agent-judged):
- Cross-cutting questions ("how does X work?", "where do we touch Y?") → prefer `.brain/concepts/` pages
- Structural questions ("what does <file> export?", "what does <symbol> do?") → prefer `.brain/code/` pages
- Decision questions ("why did we choose X?") → prefer `.brain/decisions/` pages

## Freshness Model

For each selected candidate, the agent:

1. Reads page frontmatter only (not the body yet).
2. Extracts `source_hash` (format-prefixed: `git:<hash>` or `sha256:<hash>` per PRD #32).
3. For **code pages**: re-hashes the source file via `git hash-object <source>` (preferred) or `shasum -a 256 <source>`. For **concept pages**: re-hashes EACH entry in the `sources:` array.
4. **On match** (even if `status: STALE`): promotes the page to `FRESH` inline. Updates frontmatter and writes via `scripts/hooks/lib/page-io.writePage` (atomic — temp+fsync+rename). This resolves M#4's conservative STALE flips (the hook flips on every Edit; M#5 verifies the content actually changed).
5. **On mismatch**: invokes the M#3a single-file ingest procedure to refresh the code page. For concept pages: invokes the M#3b folder ingest on the most-drifted source's parent directory (approximate — concept refresh is a known M#5 limitation; M#6 lint will surface persistent drift).

`--no-refresh` flag opts out: pages read as-is (including STALE), with a `[STALE — content may be out-of-date]` banner on each affected citation.

## Citation Format

Every citation appears in BOTH forms when applicable:

```
- [[code/src/api/auth.ts]] — src/api/auth.ts (issues + verifies JWTs)
- [[concepts/auth-flow]] — auth-flow concept (cross-cutting summary)
- src/api/auth.ts:42 — see `issueToken` for the JWT payload structure
```

Wikilinks navigate to brain pages in Obsidian. Source paths jump to code in the IDE.

**Line numbers are precision-mandatory**: include `:42` ONLY when the agent actually read line 42 from the source file during synthesis (via Read with offset/limit, or via Grep results). NEVER fabricate line numbers — broken citations destroy operator trust.

## Page-Cap Discipline (PRD #7)

Pages loaded per query: hard cap 5. This isn't a performance limit; it's a quality signal. If a question needs more than 5 pages, the question is asking too much — the agent suggests narrowing rather than loading 10.

Brain pages themselves stay under their own caps (code: 4k/8k; concepts: 6k/12k) per the ingestion contract. Query honors those caps by trusting the ingester to have produced page-sized pages.

## Examples

### Example 1: Structural question

Operator: `/brain query "what does auth.ts export?"`

Selection: just `.brain/code/src/api/auth.ts.md` (or wherever auth.ts lives).
Freshness: hash check; if match → read; if mismatch → re-ingest first.
Output: lists the exported symbols from the page's `## Exports` section, citing the page + source path.

### Example 2: Cross-cutting question

Operator: `/brain query "how does authentication work end-to-end?"`

Selection: `.brain/concepts/auth-flow.md` (cross-cutting) + the 1–2 code pages it references most heavily.
Freshness: check each. Concept page's `sources:` array drives the multi-source freshness check.
Output: synthesized prose explaining the flow, citing the concept page + each code page + relevant source lines (only those actually read).

## Cross-references

- The agent that runs this skill: `../../../agents/brain/query.md`
- The procedure (load-bearing): `../../../commands/brain.md` `## When $ARGUMENTS starts with query`
- Page contract (what query reads): `../../ingestion/page-format/SKILL.md`
- Hash-compare helpers: `../../../scripts/hooks/lib/page-io.js` (M#4 — query reuses)
- Sibling skill (concept extraction — query understands what concept pages mean): `../../ingestion/concept-extraction/SKILL.md`
- PRD design decisions: #10 (4-tier staleness — query closes tier 4), #15 (log prefix), #17 (merged agent frontmatter), #19 (dual-layer guardrails), #32 (source-hash format)
