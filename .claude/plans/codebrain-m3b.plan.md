# Plan: codebrain — Milestone #3b (Folder ingest + concept pages + linker)

**Source PRD**: `.claude/prds/codebrain.prd.md`
**Selected Milestone**: #3b — second sub-step of the 3-way split of original M#3
**Complexity**: Medium-to-Large — second writer agent (linker); first concept pages; first cross-page wikilinks
**Status**: **DRAFT** — will be refined after M#3a ships and dogfood reveals what changed. Lock decisions here are tentative.

## Summary

Take what M#3a proved on one file and scale it to a folder. `/brain ingest <folder>` walks the folder, invokes the M#3a ingester per source file (sequentially in M#3b — no parallelism), then spawns the **linker agent** to scan all written pages and produce: (a) bidirectional wikilinks (Cross-references sections in code pages now reference each other), (b) concept pages in `.brain/concepts/` for cross-cutting ideas the linker spots across files. Operator pauses are gated at the folder-completion checkpoint, not per file (operator gets one consent at start).

## Patterns to Mirror (provisional — depends on M#3a's shipped shape)

| Category | Source | Pattern |
|---|---|---|
| Agent file format | `agents/brain/ingester.md` (shipped by M#3a) | Copy the merged-frontmatter shape; same Rules-section discipline + prompt-defense reference |
| Per-file ingest invocation | `commands/brain.md` (M#3a's ingest section) | The linker calls the same procedure per source file; no re-implementation |
| Concept page template | `skills/ingestion/page-format/templates/code-page.md` (M#3a's code template) | Mirror the `<!-- AGENT: ... -->` instruction-comment pattern; different sections (concept pages have Definition / Spans / Examples / Related rather than Exports/Imports) |
| Wikilink resolution | `skills/core/init/templates/claude-md-schema.md` (M#2's wikilink convention spec) | `[[code/<path>]]` for code pages; `[[concepts/<name>]]` for concepts; bidirectional |
| Tests | M#3a's T14/T15 | Add T16 (linker agent + concept-extraction skill + concept-page template); T17 (folder-ingest verb wired; cross-page wikilinks present in fixture run) |

## Files to Change (provisional)

| File | Action | Why |
|---|---|---|
| `agents/brain/linker.md` | CREATE | Second writer agent. Reviewer pattern (reads pages, spots cross-cutting ideas, decides what gets a concept page). Tools: Read, Glob, Grep, Edit, Write. max_iterations: 5. |
| `skills/ingestion/concept-extraction/SKILL.md` | CREATE | Defines when a cross-cutting idea earns its own concept page (graphbrain has good prior art here: "2+ sources or strong evidence"). |
| `skills/ingestion/concept-extraction/templates/concept-page.md` | CREATE | Template for `.brain/concepts/*.md`. Sections: Definition (1-3 sentences), Spans (which code pages reference this), Examples (links to specific lines/symbols), Related (other concept pages). Frontmatter: `kind: concept, status, sources: [list of code page paths]` (Design Decision #10 sources frontmatter). |
| `commands/brain.md` | UPDATE | Replace the M#3b stub on `ingest <folder>` with the folder-walk + linker-invoke procedure. Single-file case (M#3a) unchanged. No-arg case (M#3c) still stubbed. |
| `commands/codebrain.md` | UPDATE | Mirror brain.md (alias parity) |
| `tests/e2e-test.sh` | UPDATE | Add T16 (linker + concept skill + template structural assertions) and T17 (folder-ingest wiring) |
| `.claude/prds/codebrain.prd.md` | UPDATE | M#3b row → in-progress with link to this plan |

## Tasks (provisional)

1. **`agents/brain/linker.md`** — Reviewer-pattern agent. Frontmatter (name, description, tools, model, pattern=Reviewer, trigger_phrases, max_iterations=5). Body persona + Rules + prompt-defense reference. Rules emphasize: NEVER create a concept page from a single source; ALWAYS update both sides of a wikilink; NEVER overwrite a `status: VERIFIED` concept page.

2. **`skills/ingestion/concept-extraction/SKILL.md`** — When-to-extract criteria (≥2 source files reference the concept; OR strong evidence in a single file like a top-level docstring describing an architecture). What-to-extract examples (entity types, integration boundaries, conventions, glossaries). What-NOT-to-extract (one-off implementations; trivial utility functions).

3. **`skills/ingestion/concept-extraction/templates/concept-page.md`** — The verbatim template the linker fills. Frontmatter includes `sources:` array (PRD Design Decision #10) so the M#4 staleness hook can propagate STALE when any listed source changes.

4. **Update `commands/brain.md` — folder-ingest case**. New section after M#3a's single-file section: `## When $ARGUMENTS starts with ingest <folder>`. Procedure: (i) preconditions, (ii) walk folder respecting `.gitignore` + skip `node_modules/.git/.brain/.claude`, (iii) for each file: invoke the M#3a single-file procedure (call the same step-by-step), (iv) when all files done, invoke the linker agent against the produced set of pages, (v) log + report.

5. **Update `commands/codebrain.md`** — alias parity for the new folder section.

6. **Update `tests/e2e-test.sh`** — T16 (structural for linker + skill + template; npm pack inclusion); T17 (folder-ingest verb wired; alias parity for folder section).

7. **PRD update** — M#3b row → in-progress with link.

## Sweep Findings (folded into Tasks above)

Five findings from the post-draft sweep, each will tighten the relevant Task when M#3b is refined post-M#3a:

- **B1 — Folder-walk file filter**: walk skips the existing M#3a binary blocklist + lockfiles (`package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `poetry.lock`, `Cargo.lock`, `go.sum`) + minified/generated files (`*.min.js`, `*.bundle.js`, `dist/**`, `build/**`). Documented in Task 4's Step 2.
- **B2 — Linker idempotency on concept pages**: linker reads existing `.brain/concepts/*.md` BEFORE proposing new ones. If a concept already has a page, the linker UPDATES it (adds new sources to the `sources:` frontmatter array, refreshes the Spans section) rather than creating a duplicate. Documented in Task 3.
- **B3 — `## Concept pages` section in index.md**: linker creates the section if missing (mirroring M#3a's `## Code pages` pattern). Documented in Task 4.
- **B4 — Wikilink self-check before write**: linker verifies that every `[[code/<path>]]` it writes resolves to an actual `.brain/code/<path>.md` file. If not, downgrade to a plain mention (no wikilink); flag in the report. Prevents dangling wikilinks the M#6 lint pass would otherwise catch.
- **B5 — Partial-completion warning**: if N>0 files failed mid-folder, the linker's input is incomplete. The linker still runs, but its output report includes `WARNING: linker analyzed M of N requested files; X concepts may be missing sources. Re-run after addressing failed files.`

## Open Questions to Resolve After M#3a Ships

- **Walk order**: alphabetical, importance-heuristic (entry points first), or operator-supplied? Likely alphabetical for M#3b; importance-heuristic is part of M#3c's tiered auto-prioritize.
- **Cost gate**: should folder ingest pause and ask for operator confirmation before starting if it'll touch >N files? Lean N=20 as a default; configurable later. Cost estimate (token count × per-file rate) shown alongside the count.
- **Failure mid-folder**: skip-and-report (locked); final report shows which files failed and why.
- **Concept-page placement**: flat `.brain/concepts/<name>.md` or nested (`.brain/concepts/entities/<name>.md`, `.brain/concepts/integrations/<name>.md`)? Depends on what the linker discovers in dogfood.
- **Linker re-runs**: if `/brain ingest <folder>` runs twice, do we re-run the linker each time? Lean yes (cheap; concept pages might gain new sources). Idempotent per B2.
- **Sequential vs parallel per-file ingest**: M#3b sequential (no race on index/status/log). Parallelism is a post-MVP optimization once we have a write-coordinator.

## Risks (provisional)

| Risk | Likelihood | Mitigation |
|---|---|---|
| Folder ingest cost balloons on a large folder | High | Cost gate (>20 files asks confirmation); per-file SKIPs if source-hash unchanged make re-runs cheap |
| Linker creates too many concept pages (spam) | Med | Concept-extraction skill's "2+ sources OR strong evidence" rule; M#6 lint catches orphan concepts |
| Wikilinks introduce circular references that confuse the lint pass | Low | Bidirectional is the expected shape; cycles are OK; lint asserts presence-of-link, not acyclicity |
| Concept pages drift when source files are edited | Med | This is exactly what the M#4 staleness hook + Design Decision #10's `sources:` frontmatter handles — concept pages with `sources: [path1, path2]` get STALE when any listed source is edited |
| Alias drift between brain.md and codebrain.md (folder section) | Low | Same T15-style assertion as M#3a |

## Acceptance Criteria (provisional)

- All tasks complete
- Linker agent + concept-extraction skill + concept-page template ship
- `/brain ingest <folder>` walks files, ingests each, runs linker; report shows N files ingested + M concept pages created
- E2E tests pass (~100 total after T16+T17 added)
- No regression in M#1+M#2+M#3a (73 + ~17 from M#3a = 90 → ~110 after M#3b)

---

**This plan is a draft.** Refinement after M#3a:
- Update the Patterns table with M#3a's actual code-page template shape
- Confirm the per-file invocation contract (does the linker call the slash-command body, or call the agent directly?)
- Lock the cost-gate threshold based on dogfood ingest timings
- Confirm concept-page taxonomy after seeing what cross-cutting ideas a real codebase produces
