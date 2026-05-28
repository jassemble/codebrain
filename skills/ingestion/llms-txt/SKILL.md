---
name: llms-txt
description: Defines how `.brain/llms.txt` is refreshed — the agent-portable site map (AEO / llmstxt.org convention) that external agents read to route into the codebrain wiki. Deterministic procedure, no LLM call. Loaded by `/brain ingest <file>` Step 6, `/brain ingest <folder>` linker L5, and `/brain lint` L7.
origin: codebrain
version: 0.1.0
tier: ingestion
pattern: Generator
related_skills: [behavioral/codebrain, ingestion/page-format]
---

# llms-txt — `.brain/llms.txt` refresh procedure

## When to Activate

Read this skill before refreshing `.brain/llms.txt`. Three callsites in the slash-command body reference this skill:

- `/brain ingest <file>` Step 6 (Update derived files)
- `/brain ingest <folder>` linker procedure L5 (Update derived files)
- `/brain lint` L7 (Output + log)

Each callsite says "Refresh `.brain/llms.txt` per the procedure in `skills/ingestion/llms-txt/SKILL.md`." This is the procedure.

## Why this file exists

`llms.txt` is the agent-portable site map for `.brain/` (AEO / llmstxt.org convention). External agents read it to route into the wiki without scanning every file. Per the agentctx-idea research (token-economics, AEO six-layer stack), a machine-readable index at a known path is the highest-leverage discoverability artifact for agent-consumed documentation.

Codebrain's `.brain/llms.txt` lives at the project's `.brain/` root and is regenerated on every ingest + every lint. It is **not** committed in the spirit of "deterministic from page state" — but operators are free to commit it if they want a snapshot.

## File format

```
# .brain — codebrain wiki
# llms.txt — agent-readable site map (https://llmstxt.org / AEO convention)
# Last refreshed: <ISO date>
# codebrain v<version-from-.codebrain-version>
# Pages: <total>, estimated tokens: ~<sum>

> .brain is a folder-mirrored markdown wiki of this codebase, maintained by codebrain. (one-paragraph blurb — keep verbatim from init scaffold)

## Top-level
- [overview.md](overview.md) — Project purpose, codebase structure, key patterns, active state
- [index.md](index.md) — Page catalog (code, concepts, decisions)
- [log.md](log.md) — Activity history + promoted recurring patterns
- [status.md](status.md) — Page lifecycle tracker (FRESH/STALE/RESYNCED)
- [decisions.md](decisions.md) — ADR index

## Code pages (<N>)
- [code/<path>.md](code/<path>.md) — <one-line summary> (~<T> tokens)
...

## Concept pages (<N>)
- [concepts/<slug>.md](concepts/<slug>.md) — <one-line definition> (~<T> tokens)
...

## Decision pages (<N>)
- [decisions/<adr>.md](decisions/<adr>.md) — <one-line decision summary> (~<T> tokens)
...
```

## Refresh algorithm

**Deterministic — no LLM call.** All inputs come from already-written page bodies + frontmatter.

1. Walk `.brain/code/**/*.md`, `.brain/concepts/**/*.md`, `.brain/decisions/**/*.md`. Skip `.keep` files and any non-`.md`.

2. For each page:
   - Read frontmatter via `lib/page-io.readPage`. Skip if status is `UNENRICHED`.
   - Extract a one-line summary:
     - **Code pages**: first non-empty paragraph under `## Purpose` (collapse to single line; strip leading `This file `/`This module `).
     - **Concept pages**: first non-empty paragraph under `## Definition`.
     - **Decision pages**: first non-empty paragraph under `## Decision` (fallback: page title).
     - If empty / `_(unclear — investigate)_` / `_(TBD)_`: write `_(stub)_`.
   - Estimate tokens: `Math.round(file_chars / 4)`. Round to nearest 100 for the bullet (`~1.2K tokens` for ≥1000; `~XYZ tokens` below). Use exact `chars/4` for the header total.

3. Build the file content from the format template above. Sort each section alphabetically by page path.

4. Update header: `# Pages: <N>` is the total across the three sections; `estimated tokens: ~<sum>` is the sum of per-page rounded estimates.

5. Update `# Last refreshed:` to today's ISO date.

6. Write via Write (full file content), not Edit. Atomicity comes from a single Write call; do not stream partial sections.

## Empty sections

If a section has 0 pages, write the corresponding placeholder (mirror the init.js starter scaffold):

- Code: `_(no pages yet — run \`/brain ingest <file>\` or \`/brain ingest <folder>\`)_`
- Concepts: `_(no pages yet — concepts are auto-extracted by the linker during folder ingest)_`
- Decisions: `_(no pages yet — manually record ADRs under decisions/ as your project evolves)_`

## Idempotency

Re-running the refresh with no ingest/lint deltas produces a byte-identical file **except** for `# Last refreshed:`. Callers MAY skip the write if the only diff is that header line — this preserves no-op semantics in `/brain lint` runs that found no defects (the lint already updates `.brain/log.md` once for the run; an additional llms.txt heartbeat write is noise).

## Failure modes

- **Page unreadable / malformed frontmatter**: fall back to `_(unreadable)_` for that page's summary; continue with other pages. Never abort the whole refresh.
- **`.brain/` directory missing**: should not happen — every callsite is reached only after a `.brain/` precondition check. If it does happen, log a warning and exit early without writing.
- **Disk full / I/O error on write**: report `blocked: llms.txt refresh failed — <reason>` to the operator; the partial write is rolled back by the atomic Write contract; the previous `llms.txt` remains.

## Never

- **Never** invoke an LLM during this procedure. All inputs are deterministic.
- **Never** read page bodies in full just to compute the summary — only the section heading + first non-empty paragraph after it. Use line-bounded reads where possible.
- **Never** write `.brain/llms.txt` in a state where the `# Pages: <total>` count disagrees with the actual section bullets. Build the file in memory first, then write atomically.
