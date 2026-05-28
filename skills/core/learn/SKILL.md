---
name: learn
description: Defines the continuous-learning loop — observation format, instinct format, consolidation policy (deterministic in v0.1; LLM-driven distillation deferred to v0.2). Loaded by /brain learn (M#7). Privacy by design — only minimal {ts, tool, path?, status} records.
origin: graphbrain
version: 0.1.0
tier: core
pattern: Observer
related_skills: [behavioral/graphbrain, core/lint]
---

# learn — continuous-learning loop contract

The fourth and final `core/*` skill. Defines what `/brain learn` does, what shape the observation + instinct stores take, and how the deterministic consolidation works in v0.1.

After M#7 ships, graphbrain has a complete loop: ingest (M#3a-d) → query (M#5) → lint (M#6) → learn (M#7). With observation toggled on, graphbrain quietly accumulates a sense of how the operator + agents actually work in this codebase.

## When to Activate

- Operator runs `/brain learn {on|off|status|consolidate}`
- Trigger phrases match (see observer agent)
- The PreToolUse hook fires on every tool call (always — but exits silently unless toggle is `on`)

## Observation format

Each line in `<XDG>/projects/<git-hash>/observations.jsonl` is a JSON object with **exactly these fields** (whitelist-enforced by `scripts/hooks/lib/observations.js`):

```json
{ "ts": 1716580800000, "tool": "Edit", "path": "src/api/auth.ts", "status": "ok" }
```

| Field | Type | Meaning |
|---|---|---|
| `ts` | int | Unix milliseconds at hook fire time |
| `tool` | string | Tool name (Edit, Read, Write, Bash, Glob, Grep, etc.) |
| `path` | string \| null | Relative path within cwd (absolute paths outside cwd are nulled by the hook) |
| `status` | string | `"ok"` for v0.1; future: include exit code / error type |

**Never captured**: tool output, user prompts, file content, stderr, stdout. Whitelist-enforced — even if the hook tried to add other fields, the library would strip them.

## Instinct format

Each line in `<XDG>/projects/<git-hash>/instincts.jsonl`:

```json
{
  "id": "a3f7e9b2c1d4",
  "pattern": "Edit:src/api",
  "frequency": 17,
  "confidence": 0.42,
  "first_seen": 1716000000000,
  "last_seen": 1716580800000
}
```

| Field | Type | Meaning |
|---|---|---|
| `id` | string | First 12 chars of SHA-256(pattern) — stable across consolidations |
| `pattern` | string | `<tool>:<path-prefix-up-to-second-segment>` (e.g., `Edit:src/api`) |
| `frequency` | int | Total observations matching this pattern across all consolidations |
| `confidence` | float | `frequency / total_observations` — 0.0-1.0 |
| `first_seen` | int | Unix ms of the earliest matching observation |
| `last_seen` | int | Unix ms of the most-recent matching observation |

## Consolidation policy (v0.1 — deterministic)

When `/brain learn consolidate` is invoked, the observer agent:

1. Reads all observations from `observations.jsonl`
2. Groups by pattern key: `(tool, path-prefix-up-to-second-segment)`. Example: `Edit src/api/auth.ts` and `Edit src/api/middleware.ts` both group to `Edit:src/api`.
3. Counts frequency per pattern
4. Promotes any pattern with **frequency ≥3** to an instinct
5. Merges with existing instincts.jsonl: updates `frequency`/`confidence`/`last_seen` for existing `id`s; appends new ones
6. Logs the consolidation event to `.brain/log.md`

The frequency threshold (3) and the path-prefix-segment (2) are v0.1 stakes-in-the-ground — likely revisited in v0.2 based on dogfood (M#8 M5 measurement).

## Privacy (load-bearing)

Three layers of defense:

1. **Hook script** (`scripts/hooks/observe.js`): only extracts the 4 whitelist fields from the Claude Code hook payload. Never reads tool output. Never reads stdin tools'  outputs.
2. **Library layer** (`scripts/hooks/lib/observations.js`): `appendObservation` whitelist-enforces. Even if the hook misbehaved, only 4 fields land on disk.
3. **Toggle** (`.brain/.graphbrain-learn-state`): default `off`. Operator opts in per-project. `/brain learn off` immediately stops new observations (history preserved unless operator deletes).

Worst-case audit: read `<XDG>/projects/<hash>/observations.jsonl`. Every line is `{ts, tool, path?, status}` — no surprises.

## Toggle semantics

| State | File content | Hook behavior |
|---|---|---|
| `on` | `.brain/.graphbrain-learn-state` = `on\n` | Hook appends observations |
| `off` | `.brain/.graphbrain-learn-state` = `off\n` | Hook exits 0 silently |
| `missing` | file does not exist | Hook exits 0 silently (default) |

Flipping `on` → `off` does NOT delete accumulated observations or instincts; only future observations stop. To purge, manually delete `<XDG>/projects/<hash>/` (intentional — let the operator be deliberate about deletion).

## Storage location

```
<XDG_DATA_HOME or ~/.local/share>/graphbrain/projects/<12-char-git-hash>/
  ├── observations.jsonl   (append-only; hook writes)
  └── instincts.jsonl       (consolidator writes; operator-triggered)
```

`<git-hash>` is the first 12 chars of SHA-256(`git remote get-url origin`). If no remote: SHA-256 of cwd path. This means moving the repo to a new machine but keeping the remote URL preserves history; renaming the local clone doesn't.

Per-project toggle lives IN the repo (`.brain/.graphbrain-learn-state`); per-project DATA lives OUTSIDE the repo (in XDG). The toggle is git-trackable (so a team can commit `on` together); the data is operator-local (each developer's instincts reflect their own workflow).

## Future work (v0.2+)

- `--llm-distill` flag: feed accumulated patterns to a Haiku model to generate human-readable insights (e.g., "you frequently edit `src/api/*.ts` after running `grep auth`" → instinct: "you tend to investigate auth before editing API")
- `/brain learn export` + `/brain learn import` — share instincts across machines / team
- `/brain learn promote` — instincts seen in N≥2 projects promote to global scope (~/.local/share/graphbrain/instincts/global/)
- Cost-tracking for the LLM distill flag
- Smarter pattern grouping (semantic similarity, not just path-prefix)

## Examples

### `/brain learn on`

```
[Privacy notice]
Graphbrain will now collect minimal observations of your tool use in this repo:
  - Fields: timestamp, tool name, relative path (if applicable), status
  - NOT captured: tool outputs, prompts, file contents
  - Storage: ~/.local/share/graphbrain/projects/<hash>/observations.jsonl
  - Disable anytime: /brain learn off

Toggle written: .brain/.graphbrain-learn-state = on
```

### `/brain learn status`

```
/brain learn status (graphbrain v0.1.0)
  Toggle:             on
  Observations:       1,247 (since 2026-04-10)
  Instincts:          18
  Top 5 patterns:
    Edit:src/api          412 (33%)
    Read:src/api          287 (23%)
    Edit:src/components   156 (12%)
    Bash:.              123  (10%)
    Grep:.               89   (7%)
  XDG store:          ~/.local/share/graphbrain/projects/a3f7e9b2c1d4/
  Last consolidation: 2026-05-20
```

### `/brain learn consolidate`

```
/brain learn consolidate (observer agent)
  Observations read:   1,247
  Patterns found:      34
  Instincts new:       6
  Instincts updated:   12
  Threshold (v0.1):    frequency ≥ 3
  Logged:              .brain/log.md
```

## Cross-references

- The agent that runs this skill: `../../../agents/observers/observer.md`
- The procedure (load-bearing): `../../../commands/brain.md` `## When $ARGUMENTS starts with learn`
- Hook script: `../../../scripts/hooks/observe.js`
- Shared library: `../../../scripts/hooks/lib/observations.js`
- Companion skill: `../lint/SKILL.md` (lint surfaces gaps; learn surfaces patterns)
- PRD design decisions: #4 (opt-in default off), #16 (foreground-first except observers), #19 (dual-layer guardrails), #20 (prompt-defense reference), #32 (hooks ownership id-prefix)
