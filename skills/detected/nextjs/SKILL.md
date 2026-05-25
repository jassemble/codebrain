---
name: detected/nextjs
description: Stack-aware page-template extras + ECC-bridge for Next.js code pages. Activates when package.json contains "next" AND the source file is .tsx/.jsx/.ts/.js. Bridges to ecc:nextjs-turbopack.
origin: codebrain
version: 0.1.1
tier: detected
pattern: Generator
related_skills: [behavioral/codebrain, ingestion/page-format, detected/react, detected/typescript]
detect:
  - { file_exists: "package.json", contains: "\"next\"" }
applies_to_extensions: [".tsx", ".jsx", ".ts", ".js"]
expert_skills: [ecc:nextjs-turbopack]
---

# detected/nextjs — Next.js-aware extras + ECC bridge

## When Activated

Both conditions must hold:

1. **Project signal**: `package.json` contains `"next"`
2. **File signal**: source file extension is `.tsx`, `.jsx`, `.ts`, or `.js`

When a `.tsx` file matches, `detected/typescript` and `detected/react` also apply. Registry order: TypeScript → React → Next.js.

## Inheritance Contract

Same as siblings — extras append AFTER `## Cross-references`. Never replaces.

## Extra Sections This Skill Declares

| Section | What goes in it |
|---|---|
| `## Next.js route role` | `app/<path>/page.tsx`, `app/<path>/route.ts`, `app/<path>/layout.tsx`, `middleware.ts`, `next.config.{js,ts}`, or legacy `pages/` file |
| `## Server vs Client component` | For `app/` files: presence of `"use client"`; what makes it server (data fetch, async, no hooks) vs client (hooks, event handlers, browser APIs) |
| `## Data fetching` | `fetch` with `{cache, revalidate, tags}`, `unstable_cache`, `unstable_noStore`; Server Actions; Route Handlers |
| `## Caching + revalidation` | `revalidatePath` / `revalidateTag` calls; route segment config exports (`dynamic`, `revalidate`, `fetchCache`) |
| `## Edge / Node runtime` | `export const runtime = "edge" \| "nodejs"` declarations |

## Expert-Skill Bridge (v0.1.1)

`expert_skills: [ecc:nextjs-turbopack]` — when present, load for Turbopack-aware build/dev guidance, route conventions, performance patterns.

## Cross-references

- Generic page contract: `../../ingestion/page-format/SKILL.md`
- Siblings: `../typescript/SKILL.md`, `../react/SKILL.md`
- ECC bridge target: `ecc:nextjs-turbopack`
- Inlined extras: `../../../commands/brain.md` Step 4b
- Registry entry: `../../registry.json`
