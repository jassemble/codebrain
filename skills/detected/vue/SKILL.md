---
name: detected/vue
description: Stack-aware page-template extras for Vue.js code pages. Activates when `package.json` contains `"vue"` AND source file extension is one of `.vue` / `.ts` / `.js`. Extras APPEND AFTER the generic 5 sections.
origin: graphbrain
version: 0.1.0
tier: detected
pattern: Generator
related_skills: [behavioral/graphbrain, ingestion/page-format, detected/typescript]
detect:
  - { file_exists: "package.json", contains: "\"vue\"" }
applies_to_extensions: [".vue", ".ts", ".js"]
expert_skills: []
---

# detected/vue — vue extras

## When Activated

Both conditions must hold:

1. **Project signal**: `package.json` contains `"vue"`
2. **File signal**: source file extension is one of `.vue` / `.ts` / `.js`

## Inheritance Contract

Generic 5 sections always written first → vue extras append AFTER `## Cross-references`. Never replaces. Same pattern as `detected/react` and the other v0.1.1 framework skills.

## Extra Sections This Skill Declares

No ECC counterpart skill exists yet (`ecc:vue-patterns` was assumed in v0.2 but never shipped by ECC — audited v1.0.7). For vue code-writing expertise, see the recommendations surfaced by `/brain:init` Step 4c: patterns.dev/skills/javascript covers general patterns; patterns.dev/skills/vue covers Vue-specific.

This skill (graphbrain-side) provides vue-specific page-template extras during `/brain:ingest`. The generic 5 sections (`## Purpose`, `## Exports`, `## Imports`, `## Key behaviors`, `## Cross-references`) are intentionally light in v1.x; flesh out as operator dogfood produces evidence of what's needed.

## Related

- **`commands/brain/ingest.md` Step 4b.3** (M#9-prereq) — runtime probe + activation
- **`/brain:init` Step 4c** — surfaces recommended vue skills (patterns.dev for Vue + JS, ECC bridges where available)
