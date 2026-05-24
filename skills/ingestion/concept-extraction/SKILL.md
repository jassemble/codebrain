---
name: concept-extraction
description: Decides what qualifies as a concept page. Loaded by the linker agent during /brain ingest <folder>. Locks the criteria so concept-page creation is consistent across linker invocations.
origin: codebrain
version: 0.1.0
tier: ingestion
pattern: Reviewer
related_skills: [behavioral/codebrain, ingestion/page-format]
---

# concept-extraction — what becomes a concept page

This skill is consumed by the **linker** agent (`agents/brain/linker.md`) during `/brain ingest <folder>`. It defines, deliberately and narrowly, the criteria for promoting a cross-cutting idea into its own `.brain/concepts/<name>.md` page.

The criteria are deliberately restrictive. **A wiki of trivial concept pages is worse than no concepts at all** — operators stop trusting the brain when it spams `.brain/concepts/utility-helpers.md`, `.brain/concepts/internal-types.md`, etc.

## When to Activate

- Automatically loaded by the linker agent during the linker procedure's L3 step
- Reference material when the linker decides whether to promote a candidate

## DO extract a concept page when

1. **A named idea is referenced across ≥2 code pages.** Examples:
   - A **domain entity** referenced from a model, a validator, a route, and a test → `.brain/concepts/tenant.md`
   - An **integration boundary** that spans a webhook handler, a client wrapper, and config → `.brain/concepts/stripe.md`
   - A **convention** the codebase enforces across many files (e.g., "all routes use middleware X") → `.brain/concepts/route-conventions.md`
   - A **glossary term** with project-specific meaning (e.g., "MAU = monthly active user, counted with these dedupe rules") → `.brain/concepts/glossary.md` (single page with many entries is fine for a glossary)

2. **A single code page explicitly declares architectural significance** via:
   - A top-level docstring that labels itself a boundary (e.g., `"""This is the auth boundary — all incoming requests pass through verifyToken here."""`)
   - A README excerpt that names this file as the authoritative source for some pattern
   - An ADR reference (`// See decisions/0042-jwt-rotation.md`)

   Single-source extraction is the exception, not the rule. Use it sparingly.

## DO NOT extract a concept page when

- **Utility functions** referenced from a handful of places — they live on the code page where they're defined; no concept needed.
- **Single-use helpers** — the importing page describes the import; that's enough.
- **One-off implementations** — even if cross-referenced once or twice, if it's "this one specific thing this one route does", it stays on the code page.
- **Type aliases used only in their defining file** — even if exported, no separate concept.
- **Wrappers around standard library** (e.g., a custom `fetchJson` that wraps `fetch`) — note in the code page; don't promote.
- **A name that already has a code page** — if `auth.ts` has a clear page, don't also create `concepts/auth.md`. Promote a concept only when the IDEA spans multiple files.

## When uncertain (defer)

If a candidate is borderline, **do not create the concept page**. The M#6 lint pass will surface "concept mentioned across N pages but lacking a concept page" as a future-work hint. The operator can then prompt `/brain ingest <folder>` again with `--include-concept "<name>"` (post-MVP) or manually create the page.

The cost of a wrong concept page is high (operator confusion, drift, broken navigation). The cost of a missing concept page is low (lint surfaces it later). Bias toward not extracting.

## Concept-page contract

Every concept page lives at `.brain/concepts/<name>.md` (or with optional slash-separated hierarchy when natural: `.brain/concepts/entities/tenant.md`, `.brain/concepts/integrations/stripe.md`).

### Required frontmatter

| Field | Type | Example | Meaning |
|---|---|---|---|
| `kind` | string | `concept` | Always `concept` for concept pages |
| `status` | enum | `FRESH` | `UNENRICHED \| FRESH \| STALE \| RESYNCED \| VERIFIED` |
| `name` | string | `auth-flow` | Short kebab-case identifier matching the file name |
| `last_ingested` | string | `2026-05-24` | ISO date the page was written or refreshed |
| `ingested_by` | string | `claude-sonnet-4-6` | Model identifier |
| `tokens` | int | `420` | Best estimate (informational; ±20% is fine; not enforced) |
| `sources` | array | see below | Per-source-hash tracking (PRD #32) |

### `sources` array format

Each entry is an object `{ path, hash }`:

```yaml
sources:
  - path: src/api/auth.ts
    hash: git:a1b2c3d4
  - path: src/middleware.ts
    hash: git:e5f6a7b8
```

The hash field is **format-prefixed** per PRD Design Decision #32:
- `git:<hash>` from `git hash-object <path>`
- `sha256:<hash>` from `shasum -a 256 <path>` (fallback)

M#4's staleness hook iterates over `sources:` and checks each `hash` against the source file's current hash; if any drift, flips the concept page's `status` to `STALE` and notes which source drifted.

### Required body sections

1. **`## Definition`** — 1–3 sentences explaining the IDEA in domain terms (not code). Avoid restating the implementation.
2. **`## Spans`** — bullet list of code pages where this concept lives: `- [[code/<path>]] — <what role this file plays in the concept>`. Use wikilinks; verify each target exists in `.brain/code/` before writing (per linker Rules).
3. **`## Examples`** — 1–3 concrete examples, each with a wikilink to a code page AND optionally a quoted symbol/snippet. Keep snippets <5 lines.
4. **`## Related`** — bullet list of related concept pages: `- [[concepts/<name>]] — <one-line relation>`. If none yet, write `_(none yet)_`.

### Page-size cap (PRD Design Decision #7)

Concept pages: **6k tokens soft warn / 12k tokens hard error**. (Larger than code pages because concept pages aggregate evidence from many sources.) If approaching 12k, prefer splitting into multiple concept pages (e.g., one big "auth" concept → `auth-flow` + `auth-storage` + `auth-rotation`).

## Examples

### Example 1: entity (DO extract)

A `Tenant` type appears in 6 places:
- `src/models/tenant.ts` (the type definition + DB schema)
- `src/api/tenants/[id]/route.ts` (the CRUD endpoints)
- `src/middleware/tenant-resolve.ts` (extracts tenant from the auth token)
- `src/services/billing/tenant-plan.ts` (billing logic per tenant)
- `tests/tenants.spec.ts` (test fixtures)
- `migrations/0007_add_tenants.sql` (schema migration)

**Promote** to `.brain/concepts/entities/tenant.md`. Definition explains what a Tenant is in the product. Spans lists all 6 pages with one-line roles. Examples links to the type definition + 1–2 most-illustrative usages. Related links to `[[concepts/billing-plan]]` if that concept exists.

### Example 2: integration boundary (DO extract)

Stripe is referenced from 4 places:
- `src/integrations/stripe/client.ts` (the SDK wrapper)
- `src/integrations/stripe/webhooks.ts` (incoming event handler)
- `src/services/billing/charge.ts` (calls the client)
- `config/stripe.ts` (env-var loading)

**Promote** to `.brain/concepts/integrations/stripe.md`. Definition states "Stripe is our payment provider; this section catalogs every place we touch their API." Spans + Examples cover the four pages.

### Example 3: convention (DO extract)

Looking at `src/api/**/*.ts`, every route file uses `withAuth()` middleware. This is implicit but consistent.

**Promote** to `.brain/concepts/route-conventions.md`. Definition: "All API routes wrap their handler in withAuth, which validates the JWT and rejects unauthenticated requests with 401." Spans cites 4–6 representative route files plus the middleware itself.

### Example 4: utility (DO NOT extract)

A `formatCurrency(cents: number, currency: string)` helper is called from 8 places.

**Do NOT promote.** This is a utility function. The fact that it has 8 callers is irrelevant — it's a single, simple primitive. Note it in `code/src/utils/format.ts.md`'s Exports section and stop. If someone is confused about how to format money, they can find the page via grep on `formatCurrency`.

## Cross-references

- Template (verbatim, agent reads + fills): `./templates/concept-page.md`
- Load-bearing inlined copy: `commands/brain.md` under `## Linker procedure (invoked after folder ingest)`
- The linker agent that produces these pages: `../../../agents/brain/linker.md`
- The companion page-format contract for code pages: `../page-format/SKILL.md`
- Skill tier model: `../../README.md`
