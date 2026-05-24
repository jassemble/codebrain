# Plan: codebrain — Milestone #3d (Stack-aware page templates — detected/* skills)

**Source PRD**: `.claude/prds/codebrain.prd.md`
**Selected Milestone**: #3d — fourth and final sub-step of the M#3 split
**Complexity**: Medium — 4 new skills, 4 templates, brain.md ingest procedure extended; no new agents; inheritance pattern means no template duplication
**Status**: READY — sweep findings inline (E1–E7)

## Summary

Ship the four detected/* skills (`react`, `python`, `go`, `typescript`) with **extra-section templates** that extend M#3a's generic code-page template via an **inheritance pattern**: the ingester writes the generic 5 sections (Purpose, Exports, Imports, Key behaviors, Cross-references), then APPENDS the stack-specific extras when the source file's extension + the project's detected stack both match. No template duplication; each detected skill declares only the sections it adds.

Examples:
- `.tsx` file in a React project → generic 5 sections + **Component, Props, State, Hooks, Effects** (the React extras)
- `.py` file in a Python project → generic 5 + **Public API, Dunder methods, Decorators, Type hints**
- `.go` file → generic 5 + **Package + Exports, Receivers, Interfaces satisfied, init() functions**
- `.ts` file (not React) → generic 5 + **Types/Interfaces, Module declarations, Exports (named/default)**

## Patterns to Mirror (from shipped M#3a-c + M#4)

| Category | Source | Pattern |
|---|---|---|
| SKILL.md frontmatter shape (detected tier) | `skills/README.md` + `skills/ingestion/page-format/SKILL.md` | `tier: detected`; mandatory `detect:` array per PRD #22; everything else matches the merged 7-field frontmatter |
| Verbatim template with AGENT directives | `skills/ingestion/page-format/templates/code-page.md` + `skills/ingestion/concept-extraction/templates/concept-page.md` | `<!-- AGENT: ... -->` instruction-comment pattern; agent reads + fills the comments |
| Registry entries | `skills/registry.json` (empty shell from M#1) | M#3d populates with `{ "detected/<stack>": { "tier": "detected", "detect": [...rules], "version": "0.1.0" } }` |
| Procedure extension pattern | `commands/brain.md` ingest Step 4 (inline verbatim template) | M#3d adds a per-stack-extras inline block referenced from Step 4: after writing the generic 5 sections, append matching detected extras |
| Inlined-in-command-body for the load-bearing copy | M#2/M#3a/M#3b pattern (the slash-command body is the contract; standalone files are documentation) | The extras are inlined into `commands/brain.md`; the `templates/code-page-<stack>-extras.md` files ship for documentation + future M#6 verifier reuse |
| Tests | T14, T16 (skill structural shape) | T23: 4 detected skills + 4 templates structural shape; T24: registry.json populated with `detect:` rules; T25: brain.md ingest procedure has per-stack extras block + alias parity |

## Sweep Findings (E1–E7, folded in)

- **E1 — Inheritance pattern locked**: detected templates contain ONLY the extra sections (no duplication of the generic 5). The ingester always writes the generic 5 first, then appends matched extras.
- **E2 — `detect:` rules mandatory** per PRD #22 + `skills/README.md`. Each `detected/<stack>/SKILL.md` declares its detection signals in frontmatter; rules use the format already documented (`file_exists`, `file_contains`, `dir_exists`, `glob`).
- **E3 — Extras appended AFTER `## Cross-references`** in the generic template. Never interleaved. Preserves the generic page shape; stack-aware sections are clearly a layer on top.
- **E4 — Multiple detected skills can apply to one file**: a `.tsx` file in a React+TypeScript project gets both React extras AND TypeScript extras (in registry order). Document this in each SKILL.md.
- **E5 — Installation is implicit**: detected/* skills are "installed" by being present in `skills/detected/`. The `detect:` rules determine which APPLY at ingest time; presence in the npm package determines AVAILABILITY. Skipping detected/* skills happens at the package level (defer to future "skip a stack" flag).
- **E6 — registry.json shape**: extends M#1's empty `{ version, skills: {} }` shell. Per-skill record: `{ tier, detect: [...], version, applies_to_extensions: [...] }`. The `applies_to_extensions` field gates which source extensions trigger this stack's extras (e.g., React → `.tsx`, `.jsx`; Python → `.py`).
- **E7 — Stack-aware tier-glob overrides DEFERRED**: M#3c's generic tier-globs (`src/`, `lib/`, `app/`, `tests/`, etc.) work fine across stacks. Per-stack tier-glob overrides (e.g., Python's `src/<package_name>/` Tier-1 default) are a future polish — M#3e or post-MVP. M#3d focuses on per-page templates only.

## Files to Change

| File | Action | Why |
|---|---|---|
| `skills/detected/react/SKILL.md` | CREATE | React-aware extras: when activated (`package.json` contains `"react"`), what extras (Component, Props, State, Hooks, Effects), `applies_to_extensions: [.tsx, .jsx]`, examples |
| `skills/detected/react/templates/code-page-react-extras.md` | CREATE | Verbatim extras the ingester appends. ~30 lines; just the 5 React-specific sections with AGENT directives |
| `skills/detected/python/SKILL.md` | CREATE | Python extras: when activated (`pyproject.toml` exists), Public API / Dunder methods / Decorators / Type hints summary; `applies_to_extensions: [.py]` |
| `skills/detected/python/templates/code-page-python-extras.md` | CREATE | Verbatim Python extras |
| `skills/detected/go/SKILL.md` | CREATE | Go extras: Package + Exports / Receivers / Interfaces satisfied / init() functions / build tags; `applies_to_extensions: [.go]` |
| `skills/detected/go/templates/code-page-go-extras.md` | CREATE | Verbatim Go extras |
| `skills/detected/typescript/SKILL.md` | CREATE | TypeScript extras: Types/Interfaces, Module declarations, Exports (named/default/re-export), generics; `applies_to_extensions: [.ts, .tsx]` — overlaps React for `.tsx` |
| `skills/detected/typescript/templates/code-page-typescript-extras.md` | CREATE | Verbatim TypeScript extras |
| `skills/registry.json` | UPDATE | Populate the empty shell with 4 entries (one per detected stack) |
| `commands/brain.md` | UPDATE | Extend ingest Step 4 with a new sub-section: "Stack-aware extras". After writing the generic 5 sections (per Step 4's verbatim template), check installed `detected/*` skills against (a) the project's detected stack list AND (b) the source file's extension. For each match, append the verbatim extras inlined in brain.md. |
| `commands/codebrain.md` | UPDATE | Alias parity |
| `tests/e2e-test.sh` | UPDATE | T23 (4 detected skills + 4 templates structural shape; frontmatter `tier: detected` + `detect:` field present); T24 (registry.json has 4 entries); T25 (brain.md has stack-aware extras section + alias parity + inlined per-stack content for all 4 stacks) |
| `.claude/prds/codebrain.prd.md` | UPDATE | M#3d row → in-progress with plan link |

**Not in M#3d (deferred):**
- Stack-aware tier-glob overrides for M#3c's no-arg planner — future polish (sweep finding E7)
- Other detected stacks (Vue, Next, Django, FastAPI, Rust, Kotlin, etc.) — codebrain v0.1 ships only the 4 most-common; community-extensible later
- `applies_to_extensions` runtime resolution helper (the slash-command body inlines the matching logic for M#3d; a shared helper can be extracted in M#6+)

## Tasks

### Task 1: skills/detected/react/SKILL.md + template

Create with frontmatter:
```yaml
---
name: detected/react
description: Stack-aware page-template extras for React/JSX/TSX code pages. Loaded by /brain ingest when a React project is detected (package.json contains "react") AND the source file's extension is .tsx or .jsx. Extras append AFTER the generic 5 sections (Purpose, Exports, Imports, Key behaviors, Cross-references) — never replace.
origin: codebrain
version: 0.1.0
tier: detected
pattern: Generator
related_skills: [behavioral/codebrain, ingestion/page-format]
detect:
  - { file_exists: "package.json", contains: "\"react\"" }
applies_to_extensions: [".tsx", ".jsx"]
---
```

Body sections: When activated, Inheritance contract (extras append after Cross-references), Extra sections this skill declares (Component, Props, State, Hooks, Effects), Examples (1 functional component, 1 class component), Cross-references.

Template at `templates/code-page-react-extras.md` — verbatim ~30 lines with `## Component`, `## Props`, `## State`, `## Hooks`, `## Effects` sections plus AGENT instruction comments for each.

### Task 2: skills/detected/python/SKILL.md + template

Same shape. Frontmatter:
```yaml
detect:
  - { file_exists: "pyproject.toml" }
applies_to_extensions: [".py"]
```

Body extras: `## Public API`, `## Dunder methods`, `## Decorators`, `## Type hints`. Decorators section captures `@dataclass`, `@property`, `@classmethod`, etc. Type hints section summarizes whether the file uses type hints + any TypedDict/Protocol/etc. notable.

### Task 3: skills/detected/go/SKILL.md + template

Frontmatter:
```yaml
detect:
  - { file_exists: "go.mod" }
applies_to_extensions: [".go"]
```

Body extras: `## Package`, `## Receivers`, `## Interfaces satisfied`, `## init() functions`, `## Build tags`.

### Task 4: skills/detected/typescript/SKILL.md + template

Frontmatter:
```yaml
detect:
  - { file_exists: "tsconfig.json" }
applies_to_extensions: [".ts", ".tsx"]
```

Body extras: `## Types & Interfaces`, `## Module declarations`, `## Exports (named/default/re-export)`, `## Generics`.

Note in the body: when a `.tsx` file is being ingested in a React+TypeScript project, BOTH this skill's extras AND React's extras apply (in registry order: TypeScript first, React second).

### Task 5: skills/registry.json — populate the 4 detected entries

Replace empty `{ "version": "0.1.0", "skills": {} }` with:
```json
{
  "version": "0.1.0",
  "skills": {
    "detected/typescript": {
      "tier": "detected",
      "version": "0.1.0",
      "detect": [{ "file_exists": "tsconfig.json" }],
      "applies_to_extensions": [".ts", ".tsx"]
    },
    "detected/react": {
      "tier": "detected",
      "version": "0.1.0",
      "detect": [{ "file_exists": "package.json", "contains": "\"react\"" }],
      "applies_to_extensions": [".tsx", ".jsx"]
    },
    "detected/python": {
      "tier": "detected",
      "version": "0.1.0",
      "detect": [{ "file_exists": "pyproject.toml" }],
      "applies_to_extensions": [".py"]
    },
    "detected/go": {
      "tier": "detected",
      "version": "0.1.0",
      "detect": [{ "file_exists": "go.mod" }],
      "applies_to_extensions": [".go"]
    }
  }
}
```

(Order matters for E4 — TypeScript first means a `.tsx` file gets `TypeScript extras → React extras` appended in that order.)

### Task 6: Update commands/brain.md — Stack-aware extras

Find the ingest Step 4 section. After the generic template fence, add a new sub-section:

```markdown
**Step 4b — Stack-aware extras** (M#3d):

After writing the generic 5 sections above, check whether any installed `detected/*` skills apply to this source file. A skill applies when BOTH:

1. The project's detected stack (from `.brain/overview.md` Active State, or fresh detection) includes the skill's stack name (e.g., `react`).
2. The source file's extension matches the skill's `applies_to_extensions` list (e.g., `.tsx` matches React's `[".tsx", ".jsx"]`).

For each matching skill, append its extra sections to the page AFTER `## Cross-references`. Inlined below — one block per detected skill ships with M#3d:

#### detected/react extras (matches `.tsx`, `.jsx` in React projects)

```
## Component
<!-- AGENT: if this file exports a React component, describe it in 1-3 sentences:
     - functional vs class component
     - what the component renders (high-level)
     - any HOC or render-prop pattern
     If no component export: write `_(no component export)_`. -->

## Props
<!-- AGENT: bullet list of props. For typed components, capture the prop type.
     Format: `- propName: type — purpose`. If no props: `_(none)_`. -->

## State
<!-- AGENT: bullet list of internal state (useState, useReducer, Class state).
     Format: `- stateName: type — what it represents`. If stateless: `_(stateless)_`. -->

## Hooks
<!-- AGENT: bullet list of hooks used. Format:
     - useState, useEffect, useCallback (built-in)
     - useAuth (custom — from src/hooks/use-auth.ts)
     If no hooks: `_(none)_`. Stateless functional components without hooks: `_(stateless)_`. -->

## Effects
<!-- AGENT: bullet list of side effects (useEffect bodies). Format:
     - on mount: <what happens>
     - on prop change: <what triggers + what runs>
     If no effects: `_(none)_`. -->
```

#### detected/typescript extras (matches `.ts`, `.tsx` in TypeScript projects)

```
## Types & Interfaces
<!-- AGENT: bullet list of types and interfaces declared in this file.
     Format: `- TypeName: <object/union/intersection/utility> — purpose`.
     If none: `_(none)_`. -->

## Module declarations
<!-- AGENT: any `declare module`, `namespace`, or `declare global` blocks.
     If none: `_(none)_`. -->

## Exports (named/default/re-export)
<!-- AGENT: organize exports by kind:
     - Named: foo, bar, Baz
     - Default: <symbol name>
     - Re-exports: from `./other`
     If file has no exports: `_(none)_`. -->

## Generics
<!-- AGENT: brief summary of generic usage. Are there exported generic
     types/functions? Constrained generics? `_(none)_` if not generic-heavy. -->
```

#### detected/python extras (matches `.py` in Python projects)

```
## Public API
<!-- AGENT: bullet list of public symbols (no leading underscore).
     Format: `- name: <function | class | constant> — purpose`.
     If `__all__` defined, use it as the source of truth. -->

## Dunder methods
<!-- AGENT: bullet list of dunder methods defined in classes in this file.
     Format: `- ClassName.__init__: <one-line note>`.
     If none defined: `_(none)_`. -->

## Decorators
<!-- AGENT: decorators used or defined in this file.
     Format: `- @decorator_name (from <module>) — applied to <symbols>`.
     Examples: @dataclass, @property, @classmethod, custom decorators.
     If none: `_(none)_`. -->

## Type hints
<!-- AGENT: brief assessment: does this file use type hints?
     Note any TypedDict, Protocol, Literal, Generic[T] usage.
     One line summary; if untyped: `_(untyped)_`. -->
```

#### detected/go extras (matches `.go` in Go projects)

```
## Package
<!-- AGENT: package declaration + brief role of this file in the package
     (e.g., "main package — CLI entry point" or "package auth — middleware
     for JWT validation"). -->

## Receivers
<!-- AGENT: bullet list of methods grouped by receiver type.
     Format: `- (s *Server) Method(...) — purpose`.
     If no methods: `_(none)_`. -->

## Interfaces satisfied
<!-- AGENT: bullet list of interfaces this file's types satisfy.
     Format: `- TypeName satisfies io.Reader, fmt.Stringer`.
     Inferred from method sets; if uncertain: `_(none observed)_`. -->

## init() functions
<!-- AGENT: any init() functions in this file. Describe what they do.
     If none: `_(none)_`. -->

## Build tags
<!-- AGENT: any `//go:build` or `// +build` tags at the top of the file.
     If none: `_(none)_`. -->
```

When multiple skills apply (e.g., both React and TypeScript for a `.tsx`), append BOTH sets of extras in registry order (`skills/registry.json` order: TypeScript first, React second).

Skip Step 4b entirely if no detected/* skill matches. The generic 5 sections always apply.
```

Update the dispatch table footer notes — no new dispatch rows needed, just behavior extension to existing `ingest <file>` and `ingest <folder>` paths.

### Task 7: Update commands/codebrain.md (alias parity)

Mirror Task 6 — copy Step 4b verbatim into codebrain.md. T25 asserts byte-identical via awk pattern (consistent with M#3b/M#3c).

### Task 8: tests/e2e-test.sh — T23 + T24 + T25

**T23 — Detected skill structural shape:**
- All 4 SKILL.md files exist with frontmatter, all 7 fields + `detect` + `applies_to_extensions`
- `tier: detected`
- Templates exist with AGENT directives (≥4 per template)
- npm pack includes all 8 new files

**T24 — registry.json populated:**
- Has 4 entries (`detected/react`, `detected/python`, `detected/go`, `detected/typescript`)
- Each entry has `tier`, `version`, `detect`, `applies_to_extensions`
- `applies_to_extensions` are arrays

**T25 — brain.md Stack-aware extras section + alias parity:**
- `Step 4b — Stack-aware extras` section present in brain.md
- All 4 stack sub-sections present (`#### detected/react extras`, etc.)
- Each sub-section contains the stack's required body sections (e.g., React: Component, Props, State, Hooks, Effects)
- codebrain.md mirrors (byte-identical via awk anchor)
- npm pack includes the brain.md update

## Validation

```bash
# 1. E2E (M#1+M#2+M#3a/b/c+M#4+M#3d)
bash tests/e2e-test.sh
# Expect: ~290 passes, 0 failures, <5s

# 2. New files
test -f skills/detected/react/SKILL.md
test -f skills/detected/react/templates/code-page-react-extras.md
# (×4 stacks)

# 3. registry.json populated
node -e "
const r = require('./skills/registry.json');
const expected = ['detected/react','detected/typescript','detected/python','detected/go'];
for (const k of expected) {
  if (!r.skills[k]) { console.error('missing skill:', k); process.exit(1); }
  if (r.skills[k].tier !== 'detected') { console.error('wrong tier:', k); process.exit(1); }
  if (!Array.isArray(r.skills[k].detect)) { console.error('detect not array:', k); process.exit(1); }
  if (!Array.isArray(r.skills[k].applies_to_extensions)) { console.error('applies_to_extensions not array:', k); process.exit(1); }
}
"

# 4. brain.md has Step 4b
grep -qF 'Step 4b — Stack-aware extras' commands/brain.md

# 5. All 4 stack sub-sections present
for stack in react python go typescript; do
  grep -qF "detected/${stack} extras" commands/brain.md
done

# 6. Alias parity
diff <(awk '/^\*\*Step 4b — Stack-aware extras\*\*/{flag=1} flag' commands/brain.md) \
     <(awk '/^\*\*Step 4b — Stack-aware extras\*\*/{flag=1} flag' commands/codebrain.md)
# Expect: empty

# 7. npm pack
npm pack --dry-run | grep -E 'skills/detected/(react|python|go|typescript)/'
```

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Ingest procedure's extras-resolution logic produces wrong section for a `.tsx` file in a TypeScript-only project (no React) | Low | E2 detect rules: React requires `package.json` contains `"react"`; if absent, React extras don't apply. Strict AND on rules. |
| Multiple detected skills' extras have section-name collisions (e.g., both declare `## Exports`) | Low | The generic template already has `## Exports`; detected skills' extras use stack-specific names (Component, Props, Public API, Receivers, etc.) — no collisions in v0.1. |
| brain.md size growth | Med | M#3d adds ~100 lines (Step 4b + 4 stack extras blocks). Total brain.md ~700 lines after M#3d. M#5/M#6 will push further; M#5 may force the "extract to .brain/.runtime/" decision deferred from M#3c sweep. |
| Alias drift between brain.md and codebrain.md (Step 4b is large) | Low | T25 byte-identical via awk |
| Operator unfamiliar with the inheritance pattern thinks generic template stopped applying when a detected/* skill matches | Med | Step 4b explicitly states "extras append AFTER `## Cross-references` — never replace"; each detected SKILL.md repeats this in its "Inheritance contract" body section |
| A file matches multiple stacks (TypeScript + React for `.tsx`) and the extras are too long together | Low | Both stacks combined add ~10 sections; still under the 8k hard cap (PRD #7); if a specific page exceeds, the ingester's page-size self-check (M#3a Step 4) catches it |
| `applies_to_extensions` is a new field not documented in skills/README.md | Med | Update skills/README.md to document the field in M#3d (small task; can be folded into Task 5 — registry update — for consistency). NOTE: I'll add this to Task 5. |

## Acceptance

- [ ] All 8 tasks complete
- [ ] Validation §1 (e2e ~290) passes; <5s
- [ ] Validation §2–§7 pass
- [ ] PRD M#3d row → in-progress with plan link
- [ ] M#3 fully complete (3a + 3b + 3c + 3d all green)
- [ ] No regression: 240 prior tests still pass; total ~290 after T23+T24+T25 added
- [ ] (Optional) Manual smoke: run `/brain ingest src/SomeComponent.tsx` in a React project; verify the generated page has the React extras (Component, Props, State, Hooks, Effects) after the generic 5 sections
