---
kind: concept
status: <!-- AGENT: FRESH on creation, RESYNCED on update of an existing concept page -->
name: <!-- AGENT: short kebab-case identifier matching the file name, e.g. "auth-flow" or "tenant" -->
last_ingested: <!-- AGENT: today's ISO date YYYY-MM-DD -->
ingested_by: <!-- AGENT: your model identifier, e.g. claude-sonnet-4-6 -->
tokens: <!-- AGENT: best estimate of page token count; informational, ±20% is fine, not enforced -->
sources:
  <!-- AGENT: one entry per source file that contributes to this concept.
       Format (YAML list of objects with per-source-hash per PRD #32):

         - path: src/api/auth.ts
           hash: git:a1b2c3d4

       Compute each hash via `git hash-object <path>` (preferred) or
       `shasum -a 256 <path>` and prefix with `sha256:`. The M#4 staleness
       hook iterates this list and flips status: STALE when any source's
       current hash drifts from the recorded one.

       Must have at least ONE entry. Concept-extraction criteria normally
       require ≥2 entries; single-source extraction is the documented
       exception (top-level docstring declares architectural significance,
       README excerpt, ADR reference). -->
---

# <!-- AGENT: human-readable concept name, e.g. "Auth flow" or "Tenant entity" -->

## Definition
<!-- AGENT: 1-3 sentences explaining the concept in DOMAIN terms.
     Explain the idea, not the implementation. Avoid restating code.

     Good: "Tenant is the unit of multi-tenancy isolation. Every request
     resolves to exactly one Tenant via the auth token, and all queries are
     scoped to the resolved tenant_id."

     Bad: "The Tenant class has fields id, name, created_at, plan_id..."
     (that's a code description; belongs on the code page). -->

## Spans
<!-- AGENT: bullet list of code pages this concept lives in. Format:
       - [[code/<path>]] — <one-line description of what role this file
         plays in the concept>

     Verify each [[code/<path>]] resolves to a real file under
     `.brain/code/` BEFORE writing (linker Rules). If a target doesn't
     exist, downgrade to a plain mention (no `[[ ]]`) and note in the
     report.

     Example:
       - [[code/src/models/tenant.ts]] — type definition + DB schema
       - [[code/src/middleware/tenant-resolve.ts]] — extracts tenant from auth token
       - [[code/src/services/billing/tenant-plan.ts]] — billing logic per tenant -->

## Examples
<!-- AGENT: 1-3 concrete examples illustrating the concept in use. Each
     example MUST link to a code page; quoted snippets are optional but
     keep them <5 lines.

     Format:
       1. **<short heading>** ([[code/<path>]]):
          <1-2 sentence explanation; optional fenced snippet>

     Example:
       1. **Resolving a tenant from a request** ([[code/src/middleware/tenant-resolve.ts]]):
          The middleware decodes the JWT and looks up the tenant_id claim;
          unresolvable tenants get a 401 before the route handler runs. -->

## Related
<!-- AGENT: bullet list of related concept pages: `- [[concepts/<name>]] — <one-line relation>`.

     If no related concepts exist yet, write `_(none yet)_`.

     Example:
       - [[concepts/billing-plan]] — Tenants have one plan; plan dictates rate limits
       - [[concepts/route-conventions]] — Tenant resolution happens before withAuth runs -->
