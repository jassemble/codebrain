---
name: detected/flask
description: Stack-aware page-template extras for Flask (Python) code pages. Activates when `pyproject.toml` contains `flask` AND source file extension is one of `.py`. Extras APPEND AFTER the generic 5 sections.
origin: graphbrain
version: 0.1.0
tier: detected
pattern: Generator
related_skills: [behavioral/graphbrain, ingestion/page-format, detected/python]
detect:
  - { file_exists: "pyproject.toml", contains: "flask" }
applies_to_extensions: [".py"]
expert_skills: []
---

# detected/flask — flask extras

## When Activated

Both conditions must hold:

1. **Project signal**: `pyproject.toml` contains `flask`
2. **File signal**: source file extension is one of `.py`

## Inheritance Contract

Generic 5 sections always written first → flask extras append AFTER `## Cross-references`. Never replaces. Same pattern as `detected/react` and the other v0.1.1 framework skills.

## Extra Sections This Skill Declares

No ECC counterpart skill exists yet (`ecc:flask-patterns` was assumed in v0.2 but never shipped by ECC — audited v1.0.7). For flask code-writing expertise, see the recommendations surfaced by `/brain:init` Step 4c: patterns.dev/skills/javascript covers general patterns; no Python/Ruby framework-specific external skill is recommended yet.

This skill (graphbrain-side) provides flask-specific page-template extras during `/brain:ingest`. The generic 5 sections (`## Purpose`, `## Exports`, `## Imports`, `## Key behaviors`, `## Cross-references`) are intentionally light in v1.x; flesh out as operator dogfood produces evidence of what's needed.

## Related

- **`commands/brain/ingest.md` Step 4b.3** (M#9-prereq) — runtime probe + activation
- **`/brain:init` Step 4c** — surfaces recommended flask skills (patterns.dev for general JS / Python patterns, ECC bridges where available)
