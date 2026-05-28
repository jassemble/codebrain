---
name: detected/rails
description: Stack-aware page-template extras + ECC-bridge for Ruby on Rails code pages. Activates when `Gemfile` contains `rails` AND source file extension is one of `.rb`. Extras APPEND AFTER the generic 5 sections. Bridges to ECC's expert skill (ecc:rails-patterns) when available via the M#9-prereq runtime probe.
origin: graphbrain
version: 0.1.0
tier: detected
pattern: Generator
related_skills: [behavioral/graphbrain, ingestion/page-format]
detect:
  - { file_exists: "Gemfile", contains: "rails" }
applies_to_extensions: [".rb"]
expert_skills: []
---

# detected/rails — rails extras + ECC bridge

## When Activated

Both conditions must hold:

1. **Project signal**: `Gemfile` contains `rails`
2. **File signal**: source file extension is one of `.rb`

## Inheritance Contract

Generic 5 sections always written first → rails extras append AFTER `## Cross-references`. Never replaces. Same pattern as `detected/react` and the other v0.1.1 framework skills.

## Extra Sections This Skill Declares

This skill is a minimal v0.2 shipment. The bridge to `ecc:rails-patterns` is the load-bearing primitive — when ECC's expert skill is available (M#9-prereq filesystem probe), it provides the code-writing guidance. Graphbrain-side extras (`## rails-specific` section) are intentionally light in v0.2; flesh out as operator dogfood produces evidence of what's needed.

For now the generic 5 sections (`## Purpose`, `## Exports`, `## Imports`, `## Key behaviors`, `## Cross-references`) are sufficient for most rails files.

## Related

- **`commands/brain/ingest.md` Step 4b.3** (M#9-prereq) — runtime probe + activation
- **`skills/registry.json`** — registry entry with the bridge target
- **`ecc:rails-patterns`** (external, ECC) — the code-writing expertise this skill bridges to
