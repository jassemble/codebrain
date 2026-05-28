---
name: detected/vue
description: Stack-aware page-template extras + ECC-bridge for Vue.js code pages. Activates when `package.json` contains `"vue"` AND source file extension is one of `.vue` / `.ts` / `.js`. Extras APPEND AFTER the generic 5 sections. Bridges to ECC's expert skill (ecc:vue-patterns) when available via the M#9-prereq runtime probe.
origin: graphbrain
version: 0.1.0
tier: detected
pattern: Generator
related_skills: [behavioral/graphbrain, ingestion/page-format, detected/typescript]
detect:
  - { file_exists: "package.json", contains: "\"vue\"" }
applies_to_extensions: [".vue", ".ts", ".js"]
expert_skills: [ecc:vue-patterns]
---

# detected/vue — vue extras + ECC bridge

## When Activated

Both conditions must hold:

1. **Project signal**: `package.json` contains `"vue"`
2. **File signal**: source file extension is one of `.vue` / `.ts` / `.js`

## Inheritance Contract

Generic 5 sections always written first → vue extras append AFTER `## Cross-references`. Never replaces. Same pattern as `detected/react` and the other v0.1.1 framework skills.

## Extra Sections This Skill Declares

This skill is a minimal v0.2 shipment. The bridge to `ecc:vue-patterns` is the load-bearing primitive — when ECC's expert skill is available (M#9-prereq filesystem probe), it provides the code-writing guidance. Graphbrain-side extras (`## vue-specific` section) are intentionally light in v0.2; flesh out as operator dogfood produces evidence of what's needed.

For now the generic 5 sections (`## Purpose`, `## Exports`, `## Imports`, `## Key behaviors`, `## Cross-references`) are sufficient for most vue files.

## Related

- **`commands/brain/ingest.md` Step 4b.3** (M#9-prereq) — runtime probe + activation
- **`skills/registry.json`** — registry entry with the bridge target
- **`ecc:vue-patterns`** (external, ECC) — the code-writing expertise this skill bridges to
