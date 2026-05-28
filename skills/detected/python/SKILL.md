---
name: detected/python
description: Stack-aware page-template extras for Python code pages. Loaded by /brain ingest when a Python project is detected (pyproject.toml exists) AND the source file's extension is .py. Extras APPEND AFTER the generic 5 sections — never replace.
origin: graphbrain
version: 0.1.0
tier: detected
pattern: Generator
related_skills: [behavioral/graphbrain, ingestion/page-format]
detect:
  - { file_exists: "pyproject.toml" }
applies_to_extensions: [".py"]
---

# detected/python — Python-aware code-page extras

## When Activated

Activates when BOTH conditions are met:

1. **Project signal**: `pyproject.toml` exists in the repo root.
2. **File signal**: source file extension is `.py`.

Legacy Python projects with only `setup.py` are not auto-detected by this skill (the M#2 stack-detection catalog distinguishes; the `detected/python` entry registered in M#3d uses `pyproject.toml` as the canonical signal). To extend coverage to `setup.py` projects, add an entry to `skills/registry.json`.

## Inheritance Contract

Always appends AFTER `## Cross-references`. Never replaces the generic 5 sections. See `detected/react/SKILL.md` for the full inheritance ordering rule.

## Extra Sections This Skill Declares

| Section | What goes in it |
|---|---|
| `## Public API` | Bullet list of public symbols (no leading underscore). If the file defines `__all__`, use it as the source of truth. Format: `- name: <function \| class \| constant> — purpose`. |
| `## Dunder methods` | Bullet list of dunder methods defined in classes in this file. Format: `- ClassName.__init__: <one-line note>`. `_(none)_` if no dunders are explicitly defined. |
| `## Decorators` | Decorators used OR defined in this file. Format: `- @decorator_name (from <module>) — applied to <symbols>`. Examples: `@dataclass`, `@property`, `@classmethod`, `@pytest.fixture`, custom decorators. |
| `## Type hints` | Brief assessment of type-hint usage: fully typed, partially typed, untyped. Note any `TypedDict`, `Protocol`, `Literal`, `Generic[T]`, or other notable typing constructs. |

## Examples

### Example 1: A small typed module

For `src/auth.py`:

```python
from dataclasses import dataclass
from typing import Optional

__all__ = ["issue_token", "verify_token", "Claims"]

@dataclass
class Claims:
    user_id: str
    exp: int

    def __post_init__(self) -> None:
        if self.exp < 0:
            raise ValueError("exp must be non-negative")

def issue_token(user_id: str) -> str: ...
def verify_token(token: str) -> Optional[Claims]: ...
```

Python extras would be:

```
## Public API
- Claims: dataclass — JWT claim payload (user_id, exp)
- issue_token: function — signs a JWT for a given user
- verify_token: function — returns Claims or None on invalid signature

## Dunder methods
- Claims.__post_init__: validates exp is non-negative; raises ValueError otherwise

## Decorators
- @dataclass (from dataclasses) — applied to Claims

## Type hints
Fully typed. Uses Optional from typing for nullable return.
```

### Example 2: An untyped script

For `scripts/migrate.py` with no type hints:

```
## Public API
- main: function — entry point invoked when run as `python scripts/migrate.py`

## Dunder methods
_(none)_

## Decorators
_(none)_

## Type hints
_(untyped)_
```

## Cross-references

- Generic code-page contract: `../../ingestion/page-format/SKILL.md`
- Inlined load-bearing copy: `../../../commands/brain.md` Step 4b
- Registry entry: `../../registry.json`
- PRD design decisions: #21, #22, #23, #7
