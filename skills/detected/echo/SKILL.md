---
name: detected/echo
description: Stack-aware page-template extras + ECC-bridge for Echo (Go) code pages. Activates when `go.mod` contains `labstack/echo` AND source file extension is one of `.go`. Extras APPEND AFTER the generic 5 sections. Bridges to ECC's expert skill (ecc:golang-patterns) when available via the M#9-prereq runtime probe.
origin: graphbrain
version: 0.1.0
tier: detected
pattern: Generator
related_skills: [behavioral/graphbrain, ingestion/page-format, detected/go]
detect:
  - { file_exists: "go.mod", contains: "labstack/echo" }
applies_to_extensions: [".go"]
expert_skills: [ecc:golang-patterns]
---

# detected/echo — echo extras + ECC bridge

## When Activated

Both conditions must hold:

1. **Project signal**: `go.mod` contains `labstack/echo`
2. **File signal**: source file extension is one of `.go`

## Inheritance Contract

Generic 5 sections always written first → echo extras append AFTER `## Cross-references`. Never replaces. Same pattern as `detected/react` and the other v0.1.1 framework skills.

## Extra Sections This Skill Declares

This skill is a minimal v0.2 shipment. The bridge to `ecc:golang-patterns` is the load-bearing primitive — when ECC's expert skill is available (M#9-prereq filesystem probe), it provides the code-writing guidance. Graphbrain-side extras (`## echo-specific` section) are intentionally light in v0.2; flesh out as operator dogfood produces evidence of what's needed.

For now the generic 5 sections (`## Purpose`, `## Exports`, `## Imports`, `## Key behaviors`, `## Cross-references`) are sufficient for most echo files.

## Related

- **`commands/brain/ingest.md` Step 4b.3** (M#9-prereq) — runtime probe + activation
- **`skills/registry.json`** — registry entry with the bridge target
- **`ecc:golang-patterns`** (external, ECC) — the code-writing expertise this skill bridges to
