---
name: detected/react
description: Stack-aware page-template extras for React/JSX/TSX code pages. Loaded by /brain ingest when a React project is detected (package.json contains "react") AND the source file's extension is .tsx or .jsx. Extras APPEND AFTER the generic 5 sections from M#3a's code-page template — never replace.
origin: graphbrain
version: 0.1.0
tier: detected
pattern: Generator
related_skills: [behavioral/graphbrain, ingestion/page-format, detected/typescript]
detect:
  - { file_exists: "package.json", contains: "\"react\"" }
applies_to_extensions: [".tsx", ".jsx"]
---

# detected/react — React-aware code-page extras

## When Activated

This skill activates when BOTH conditions are met:

1. **Project signal**: `package.json` exists in the repo root AND contains the literal string `"react"` (matches both `dependencies.react` and `devDependencies.react`).
2. **File signal**: the source file being ingested has extension `.tsx` or `.jsx`.

If both match, the ingester appends this skill's extra sections to the page AFTER `## Cross-references`. If either fails, the page gets only the generic 5 sections from M#3a.

## Inheritance Contract

This skill **extends**, never **replaces**, the generic code-page template. The order is always:

1. Generic frontmatter (kind, status, source, source_hash, last_ingested, ingested_by, tokens)
2. Generic `# <source-path>` header
3. Generic `## Purpose`
4. Generic `## Exports`
5. Generic `## Imports`
6. Generic `## Key behaviors`
7. Generic `## Cross-references`
8. **This skill's extras** (Component, Props, State, Hooks, Effects)

When multiple `detected/*` skills apply (e.g., `.tsx` matches both TypeScript AND React), all matching skills' extras append in **registry order** — see `skills/registry.json`. TypeScript's extras come before React's because the TypeScript entry is listed first in the registry.

## Extra Sections This Skill Declares

The verbatim template lives at `./templates/code-page-react-extras.md`. The load-bearing copy is inlined in `commands/brain.md` Step 4b under the `#### detected/react extras` heading.

| Section | What goes in it |
|---|---|
| `## Component` | 1–3 sentences identifying whether this file exports a React component, its style (functional/class), and what it renders at a high level. `_(no component export)_` if not applicable. |
| `## Props` | Bullet list of props with their TS types if available. `_(none)_` for prop-less components or non-component files. |
| `## State` | Bullet list of internal state (`useState`, `useReducer`, class state). `_(stateless)_` for pure functional components without hooks. |
| `## Hooks` | Bullet list of hooks used — both React built-ins and custom hooks from the codebase. `_(none)_` if no hooks. |
| `## Effects` | Bullet list of side effects (`useEffect` bodies) with their trigger conditions. `_(none)_` for components without side effects. |

## Examples

### Example 1: A functional component with hooks

For a file `src/components/Counter.tsx`:

```tsx
export function Counter({ initial = 0 }: { initial?: number }) {
  const [count, setCount] = useState(initial);
  useEffect(() => { document.title = `Count: ${count}`; }, [count]);
  return <button onClick={() => setCount(c => c + 1)}>{count}</button>;
}
```

The React extras section would look like:

```
## Component
Functional component. Renders a single button that displays and increments a counter.

## Props
- initial: number (optional, default 0) — initial counter value

## State
- count: number — current counter value, managed by useState

## Hooks
- useState (built-in)
- useEffect (built-in)

## Effects
- on count change: updates document.title to reflect the new count
```

### Example 2: A component-less utility file

For a file `src/utils/format.tsx` that exports helper functions but no components:

```
## Component
_(no component export)_

## Props
_(none)_

## State
_(none)_

## Hooks
_(none)_

## Effects
_(none)_
```

## Cross-references

- Generic code-page contract: `../../ingestion/page-format/SKILL.md`
- Sibling stack skill that often applies alongside (for `.tsx`): `../typescript/SKILL.md`
- Inlined load-bearing copy of the extras: `../../../commands/brain.md` Step 4b
- Registry entry: `../../registry.json`
- PRD design decisions: #21 (5-tier skills), #22 (detect rules), #23 (page templates), #7 (page caps — generic 5 + 5 React = ~10 sections, still under 8k cap on typical components)
