---
description: Pointer-first lookup against the brain. Auto-refreshes STALE pages; supports --thorough and --no-refresh.
---

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
- **M#10d supersession check** — if frontmatter contains `superseded_by: <target>`, SKIP this candidate entirely. Replace it in the candidate list with the page named by `superseded_by`, then re-run Q4 on the replacement (recursive — but cap at 5 levels to prevent infinite loops from malformed chains; if cap is hit, emit `warn: supersession chain too deep at <slug>` and skip the chain). Log to the Sp7-equivalent report's "Pages consulted" footer: `(superseded: <old> → <new>)`. Rationale: the M#10d pink-elephant fix — a deprecated page anchors the model's reasoning even when nominally "still here."
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

