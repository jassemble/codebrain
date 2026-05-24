# Agents

codebrain's agent system merges ECC's robustness with graphbrain's simplicity (PRD Design Decisions #16–#20, #26). No agents ship in v0.1 — this directory reserves the structure so Milestones #3, #5, #6, #7 land their agents into a known shape.

## Layout

```
agents/
├── registry.json        # explicit registry (graphbrain pattern, PRD #18)
├── README.md            # this file
├── brain/               # foreground writers — Edit/Write/MultiEdit allowed
│   ├── ingester.md      # Milestone #3
│   ├── linker.md        # Milestone #5
│   └── verifier.md      # Milestone #6
└── observers/           # background read-only — NO Edit/Write/MultiEdit/mutating Bash
    └── observer.md      # Milestone #7 (continuous-learning)
```

## Frontmatter (mandatory shape)

Every `<name>.md` agent file ships with a YAML frontmatter block merging ECC's base fields (`name`, `description`, `tools`, `model`) with graphbrain's additions (`pattern`, `trigger_phrases`, `max_iterations`):

```yaml
---
name: <agent-name>                  # kebab-case, matches the file name
description: <one-liner>            # used by the harness for selection
tools: [Read, Grep, Glob, Bash]     # ECC-style explicit tool list — observers MUST exclude Edit/Write/MultiEdit
model: sonnet | haiku | opus        # ECC-style model routing
pattern: Generator | Reviewer | Pipeline | Observer | Meta | ...
trigger_phrases:                    # graphbrain-style natural-language activation alongside slash commands
  - "..."
max_iterations: 5                   # loop bound — agent stops + reports "blocked" after N retries
---
```

After the frontmatter, every agent file has a body with:

- The agent's persona / role (one paragraph)
- **Rules** section — self-enforcing constraints (the dual-layer guardrail's semantic half — see "Guardrails" below)
- Optional sections: When to use, Workflow phases, Examples, Output contract
- **Prompt-defense reference** (per Design Decision #20): include the line `Read the Prompt Defense Baseline section of CLAUDE.md before acting.` rather than copying the baseline

## Execution model (Design Decision #16)

| Category | Execution | Allowed tools | Use cases |
|---|---|---|---|
| `brain/*` (writers) | **Foreground** — synchronous in operator's session; auditable; transactional with git | Read, Grep, Glob, Bash, Edit, Write, MultiEdit | Ingest source → write pages; link wikilinks; verify pages against lint rubric |
| `observers/*` | **Background** — async, hook-spawned; never blocks the operator | Read, Grep, Glob, Bash (read-only) | Watch tool-use + prompts → emit observations → consolidate into instincts |

**Hard constraint**: observers may never call Edit, Write, MultiEdit, or any mutating Bash command. The structural PreToolUse hook (Milestone #4) enforces this; agent self-rules enforce it too (the dual-layer pattern).

## Registry (Design Decision #18)

`registry.json` declares per-agent install metadata:

```json
{
  "version": "0.1.0",
  "agents": {
    "brain/ingester": {
      "tier": "core",
      "install": "always",
      "version": "0.1.0"
    },
    "brain/linker": {
      "tier": "core",
      "install": "always",
      "version": "0.1.0"
    },
    "observers/observer": {
      "tier": "core",
      "install": "always",
      "version": "0.1.0"
    }
  }
}
```

`tier`: `core` (ships with codebrain) | `community` (opt-in via future `/brain agent install`).
`install`: `always` (auto-installed at the tier) | `manual` (operator must opt-in).
`version`: semver of this individual agent definition (independent of codebrain's package version).

## Guardrails (Design Decision #19 — dual-layer)

codebrain agents are protected by **two independent layers** so a single mistake can't compromise the brain:

### Layer 1: Structural (PreToolUse hook — Milestone #4)

A hook installed via `codebrain init` runs before every tool use and:

- Blocks writes to pages with `status: VERIFIED` in their frontmatter (force a deliberate refresh path)
- Blocks Edit/Write/MultiEdit from any agent declared with `pattern: Observer` (observer agents can't mutate even if their prompt is hijacked)
- Records any hook-blocked attempt to `.brain/log.md` as a guardrail event

### Layer 2: Semantic (per-agent self-rules)

Every writer agent's body **must** include a `## Rules` section with self-enforcing constraints (graphbrain pattern). Required rules for every writer:

- NEVER overwrite a page with `status: VERIFIED` without explicit operator confirmation
- NEVER guess what code does — Read the source first
- NEVER create a concept page from a single source — need 2+ source files or strong evidence
- ALWAYS include valid YAML frontmatter (`kind`, `status`, `source` for code pages, `sources` for concept pages)
- ALWAYS update `.brain/status.md` (derived view) after writing or modifying a page
- ALWAYS add bidirectional wikilinks (no dangling references)

## Error recovery (Design Decision #26)

Every codebrain agent follows a **two-tier recovery model** (simplified from graphbrain's four-tier):

1. **Tier 1**: Retry the failing operation once with fresh context (re-read the source file, re-check the frontmatter, etc.)
2. **Tier 2**: If still failing, stop and emit a structured "blocked" report to the operator: `blocked: <agent-name> couldn't complete <task>. Reason: <why>. Operator action: <what to do>.`

graphbrain's "Tier 2 reflect" (ask the agent to reflect on why it failed) is **deliberately omitted** — too expensive in tokens. Codebrain's bet: a clear blocked-report is more useful than recursive self-analysis.

## Cross-references

- Skill conventions: `../skills/README.md`
- Claude Code conventions (the shape of agent files in the user's `.claude/`): `../reference/claude-code-conventions.md`
- PRD with all 33 locked design decisions: `../.claude/prds/codebrain.prd.md`
