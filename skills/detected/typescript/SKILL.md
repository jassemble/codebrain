---
name: detected/typescript
description: Stack-aware page-template extras for TypeScript code pages. Loaded by /brain ingest when a TypeScript project is detected (tsconfig.json exists) AND the source file's extension is .ts or .tsx. Extras APPEND AFTER the generic 5 sections — never replace. When a .tsx file matches BOTH this skill AND detected/react, both apply in registry order (TypeScript extras first, React extras second).
origin: codebrain
version: 0.1.0
tier: detected
pattern: Generator
related_skills: [behavioral/codebrain, ingestion/page-format, detected/react]
detect:
  - { file_exists: "tsconfig.json" }
applies_to_extensions: [".ts", ".tsx"]
---

# detected/typescript — TypeScript-aware code-page extras

## When Activated

Activates when BOTH conditions are met:

1. **Project signal**: `tsconfig.json` exists in the repo root.
2. **File signal**: source file extension is `.ts` or `.tsx`.

## Inheritance Contract

Always appends AFTER `## Cross-references`. Never replaces.

**Co-application with `detected/react`**: when a `.tsx` file matches BOTH this skill AND `detected/react`, both sets of extras append in **registry order**. The `skills/registry.json` lists TypeScript first, then React — so the page reads:

1. Generic 5 sections (Purpose, Exports, Imports, Key behaviors, Cross-references)
2. TypeScript extras (Types & Interfaces, Module declarations, Exports, Generics)
3. React extras (Component, Props, State, Hooks, Effects)

This is intentional: types and declarations are language-level facts (apply broadly); component/hooks are framework-level (apply narrowly). Reading bottom-up, the page tells the reader "this is a TypeScript module that happens to be a React component" — the natural conceptual order.

## Extra Sections This Skill Declares

| Section | What goes in it |
|---|---|
| `## Types & Interfaces` | Bullet list of types and interfaces declared in this file. Format: `- TypeName: <object \| union \| intersection \| utility> — purpose`. `_(none)_` if the file only contains runtime code. |
| `## Module declarations` | Any `declare module`, `namespace`, or `declare global` blocks. `_(none)_` if absent. |
| `## Exports (named/default/re-export)` | Organize exports by kind: Named (foo, bar), Default (<symbol>), Re-exports (from `./other`). `_(none)_` if no exports. |
| `## Generics` | Brief summary of generic usage: exported generic types/functions, constrained generics, etc. `_(none)_` if not generic-heavy. |

## Examples

### Example 1: A TS utility module

For `src/lib/result.ts`:

```ts
export type Ok<T> = { ok: true; value: T };
export type Err<E> = { ok: false; error: E };
export type Result<T, E = Error> = Ok<T> | Err<E>;

export function ok<T>(value: T): Ok<T> { return { ok: true, value }; }
export function err<E>(error: E): Err<E> { return { ok: false, error }; }
```

TypeScript extras:

```
## Types & Interfaces
- Ok<T>: object — success variant of Result, wraps a value of type T
- Err<E>: object — failure variant of Result, wraps an error of type E
- Result<T, E>: union — Ok<T> | Err<E>, with E defaulting to Error

## Module declarations
_(none)_

## Exports (named/default/re-export)
- Named: Ok, Err, Result, ok, err

## Generics
Three exported generic types (Ok, Err, Result) and two generic helpers (ok, err).
Result's E parameter has a default of Error — usable as Result<T> for the common case.
```

### Example 2: A barrel re-export file

For `src/api/index.ts`:

```ts
export * from "./auth";
export { Client } from "./client";
export type { Config } from "./types";
```

TypeScript extras:

```
## Types & Interfaces
_(none — all type declarations live in the re-exported modules)_

## Module declarations
_(none)_

## Exports (named/default/re-export)
- Re-exports:
  - * from `./auth`
  - { Client } from `./client`
  - type { Config } from `./types`

## Generics
_(none)_
```

## Cross-references

- Generic code-page contract: `../../ingestion/page-format/SKILL.md`
- Sibling stack skill that often applies alongside (for `.tsx`): `../react/SKILL.md`
- Inlined load-bearing copy: `../../../commands/brain.md` Step 4b
- Registry entry: `../../registry.json`
- PRD design decisions: #21, #22, #23, #7
