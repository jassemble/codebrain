---
name: detected/fastapi
description: Stack-aware page-template extras + ECC-bridge for FastAPI code pages. Activates when pyproject.toml contains "fastapi" AND the source file is .py. Bridges to ecc:fastapi-patterns.
origin: graphbrain
version: 0.1.1
tier: detected
pattern: Generator
related_skills: [behavioral/graphbrain, ingestion/page-format, detected/python]
detect:
  - { file_exists: "pyproject.toml", contains: "fastapi" }
applies_to_extensions: [".py"]
expert_skills: [ecc:fastapi-patterns]
---

# detected/fastapi — FastAPI-aware extras + ECC bridge

## When Activated

1. **Project signal**: `pyproject.toml` contains `fastapi`
2. **File signal**: `.py`

`detected/python` also applies.

## Inheritance Contract

Extras append AFTER `## Cross-references` and AFTER `detected/python` extras.

## Extra Sections This Skill Declares

| Section | What goes in it |
|---|---|
| `## FastAPI route role` | App entry (`FastAPI()` instance), router (`APIRouter`), endpoint function, dependency, middleware, exception handler, lifespan handler. |
| `## Endpoints` | Path operations: `@app.get/post/put/delete/patch` decorators with paths, response models, status codes. |
| `## Dependencies (DI)` | `Depends(...)` chains; security dependencies (`OAuth2PasswordBearer`, `APIKeyHeader`); database session providers. |
| `## Pydantic schemas` | Request/response models: required fields, validators (`@field_validator`), serialization aliases. |
| `## Async correctness` | `async def` endpoints; non-blocking I/O usage; sync routes that risk blocking the event loop. |

## Expert-Skill Bridge (v0.1.1)

`expert_skills: [ecc:fastapi-patterns]` — load when present.

## Cross-references

- Generic page contract: `../../ingestion/page-format/SKILL.md`
- Sibling: `../python/SKILL.md`
- ECC bridge target: `ecc:fastapi-patterns`
- Inlined extras: `../../../commands/brain.md` Step 4b
- Registry entry: `../../registry.json`
