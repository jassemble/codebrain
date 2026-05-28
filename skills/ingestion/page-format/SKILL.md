---
name: page-format
description: Defines the required shape of a .brain/code/<path>.md page — frontmatter fields, section structure, wikilink convention, page-size cap. Loaded during /brain ingest. Every ingester (and the verifier landing in Milestone #6) reads this skill to know what a valid page looks like.
origin: graphbrain
version: 0.1.0
tier: ingestion
pattern: Reviewer
related_skills: [behavioral/graphbrain]
---

# page-format — code-page contract

This skill defines what a valid `.brain/code/<path>.md` page looks like. The ingester (Milestone #3a) writes pages that conform; the verifier (Milestone #6) reads pages and flags violations.

## When to Activate

- Automatically loaded during any `/brain ingest` invocation
- Loaded by `/brain lint` (Milestone #6) when validating page shape
- Read by Milestone #6's verifier agent before flagging a page as malformed

## How It Works

A code page is a markdown file at `.brain/code/<relative-source-path>.md` that mirrors a single source file. Each page has two parts:

1. **YAML frontmatter** (between two `---` lines): machine-readable metadata
2. **Body**: human + agent-readable description, organized into 5 required sections

The ingester reads the source file, the page-format contract (this skill), and the template (`./templates/code-page.md` — or the inlined copy in `commands/brain.md`, which is the load-bearing reference), then fills in every section.

## Page contract

### Required frontmatter fields

| Field | Type | Example | Meaning |
|---|---|---|---|
| `kind` | string | `code` | Always `code` for code pages |
| `status` | enum | `FRESH` | `UNENRICHED \| FRESH \| STALE \| RESYNCED \| VERIFIED` |
| `source` | string | `src/api/auth.ts` | Path relative to repo root |
| `source_hash` | string | `git:a1b2c3d` | Format-prefixed hash: `git:<hash>` or `sha256:<hash>` (PRD #32 — staleness detection consumes this) |
| `last_ingested` | string | `2026-05-24` | ISO date the page was written or refreshed |
| `ingested_by` | string | `claude-sonnet-4-6` | Model identifier of the agent that wrote the page |
| `tokens` | int | `1842` | Agent's best estimate of page token count (informational; not enforced; ±20% is fine) |

### Required body sections (in this order)

| Section | Purpose | When to write `_(none)_` |
|---|---|---|
| `## Purpose` | 1–3 sentences. What this file is responsible for. For non-code files (config, schema, docs), describe what the file configures/declares/documents. | Empty file: `_(empty file)_` |
| `## Exports` | Bullet list of exported symbols (functions, classes, constants, types). One line per symbol: `- name: one-line purpose`. | File has no exports |
| `## Imports` | Bullet list grouped by source module: `- from \`<module>\`: <names> — <why>`. Skip stdlib unless load-bearing. | File has no notable imports |
| `## Key behaviors` | Bullet list of notable behaviors, error paths, side effects, I/O, state mutation, network calls. 3–7 items max. | Trivial file (re-export shim): `_(trivial — see Exports)_` |
| `## Cross-references` | Wikilinks to other `.brain/code/` pages this file calls or extends. Format: `- [[code/<path>]] — <why linked>`. | Single-file ingest (Milestone #3a): `_(none yet — see Milestone #3b for cross-page linking)_` |

NEVER omit a section. If you have no content, write the fallback string for that section above.

## Wikilink convention

For when cross-page links exist (Milestone #3b+):

- Code page references: `[[code/src/api/auth.ts]]`
- Concept page references: `[[concepts/auth-flow]]` or `[[concepts/entities/tenant]]`
- Decision references: `[[decisions/0042-jwt-rotation]]`

Wikilinks are bidirectional by convention — if A links to B, B should link back to A. The Milestone #6 lint pass enforces this.

## Page-size cap (PRD Design Decision #7)

Code pages: **4k tokens soft warn / 8k tokens hard error**. The ingester self-checks and:

- Below 4k: write normally
- Between 4k–8k: write but flag in the report; consider summarizing more aggressively
- Above 8k: do not write; emit a blocked report recommending the operator break the source file into smaller modules

## Examples

### Minimal valid page (empty source file)

```markdown
---
kind: code
status: FRESH
source: src/empty.ts
source_hash: git:e69de29bb2d1d6434b8b29ae775ad8c2e48c5391
last_ingested: 2026-05-24
ingested_by: claude-sonnet-4-6
tokens: 50
---

# src/empty.ts

## Purpose
_(empty file)_

## Exports
_(none)_

## Imports
_(none)_

## Key behaviors
_(empty file)_

## Cross-references
_(none yet — see Milestone #3b for cross-page linking)_
```

### Populated page (small TypeScript module)

```markdown
---
kind: code
status: FRESH
source: src/api/auth.ts
source_hash: git:a1b2c3d
last_ingested: 2026-05-24
ingested_by: claude-sonnet-4-6
tokens: 380
---

# src/api/auth.ts

## Purpose
Issues, validates, and rotates short-lived JWTs for API requests. Sits behind the middleware layer; pure functions (no I/O).

## Exports
- `issueToken(userId: string): string` — sign a JWT with the configured secret + 15-minute exp
- `verifyToken(token: string): Claims | null` — return claims if valid, null otherwise
- `rotateSecret(): void` — swap the in-memory signing secret; called by the scheduled rotation job

## Imports
- from `jose`: SignJWT, jwtVerify — JWT primitives
- from `../config`: AUTH_SECRET — the current signing key

## Key behaviors
- Tokens carry only `userId` + `iat` + `exp` claims; no role data
- `verifyToken` swallows signature errors and returns null (callers check for null, never see the underlying error)
- `rotateSecret` is racy if called during a verify; callers must drain in-flight requests first

## Cross-references
_(none yet — see Milestone #3b for cross-page linking)_
```

## Cross-references

- Template (verbatim, agent reads + fills): `./templates/code-page.md`
- Load-bearing inlined copy: `commands/brain.md` under "When `$ARGUMENTS` starts with `ingest <file>`"
- The ingester agent that produces these pages: `agents/brain/ingester.md`
- Meta skill: `../../behavioral/graphbrain/SKILL.md`
- Skill tier model + frontmatter convention: `../../README.md`
