<!-- codebrain v0.2.0 -->
---
description: codebrain — wiki health-check; --fix batch-refreshes STALE pages (Milestone #6)
---

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
- **Superseded pages still linked** (M#10d): for each page with `superseded_by: <target>` set, scan all OTHER `.brain/**/*.md` pages whose frontmatter does NOT also contain `superseded_by:` for wikilinks pointing to the superseded page. Report as `<linking-page> still references superseded page <target>` (operators should update those links to point at the replacement).

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
- **Asymmetric supersession** (M#10d): for each page that declares `superseded_by: <target>`, verify the target page declares `supersedes: [... <this-page> ...]`. If not, report `<page> declares superseded_by → <target> but <target> does not list <page> in supersedes:`. Symmetric supersession is the convention; asymmetric is a defect-class gap (the target page didn't ack the replacement).

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

Refresh `.brain/llms.txt` per the procedure in `skills/ingestion/llms-txt/SKILL.md`. Read that skill before refreshing. This is unconditional — even on a clean run with no defects, the refresh updates the `# Last refreshed:` header line (idempotent: skip the write if that is the only diff).

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
Refreshed: .brain/llms.txt
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

