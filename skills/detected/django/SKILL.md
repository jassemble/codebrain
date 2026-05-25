---
name: detected/django
description: Stack-aware page-template extras + ECC-bridge for Django code pages. Activates when manage.py exists AND the source file is .py. Bridges to ecc:django-patterns + ecc:django-security.
origin: codebrain
version: 0.1.1
tier: detected
pattern: Generator
related_skills: [behavioral/codebrain, ingestion/page-format, detected/python]
detect:
  - { file_exists: "manage.py" }
applies_to_extensions: [".py"]
expert_skills: [ecc:django-patterns, ecc:django-security]
---

# detected/django — Django-aware extras + ECC bridge

## When Activated

1. **Project signal**: `manage.py` exists
2. **File signal**: `.py`

`detected/python` also applies.

## Inheritance Contract

Extras append AFTER `## Cross-references` and AFTER `detected/python` extras (registry order).

## Extra Sections This Skill Declares

| Section | What goes in it |
|---|---|
| `## Django role` | Model, view, URL conf, admin, settings, middleware, management command, signal handler, migration, or serializer (DRF). |
| `## Models / fields` | For models: bullet list of fields with type + constraints (Meta, indexes, unique). |
| `## URL patterns` | For URL confs: route patterns + view targets + names. |
| `## Forms / serializers` | Validators, write-only/read-only fields, nested serializers. |
| `## ORM hotspots` | `select_related`, `prefetch_related`, raw SQL, N+1 risks, Manager/QuerySet customizations. |

## Expert-Skill Bridge (v0.1.1)

`expert_skills: [ecc:django-patterns, ecc:django-security]` — load both when present.

## Cross-references

- Generic page contract: `../../ingestion/page-format/SKILL.md`
- Sibling: `../python/SKILL.md`
- ECC bridge targets: `ecc:django-patterns`, `ecc:django-security`
- Inlined extras: `../../../commands/brain.md` Step 4b
- Registry entry: `../../registry.json`
