# Skills

codebrain's skills are organized into a **5-tier model** borrowed from graphbrain's `skills-registry/` (PRD Design Decision #21). Each tier has a distinct lifecycle and load contract; reserving the structure from day one means the system scales as Milestones #3–#7 land their skills without restructuring.

## The five tiers

| Tier | Lifecycle | Examples (when shipped) |
|---|---|---|
| `behavioral/` | Always loaded; describes how the agent should act across every codebrain session | `behavioral/codebrain` (the meta skill — what is codebrain, how does it work) |
| `ingestion/` | Loaded during `/brain ingest`; describes how to extract pages, concepts, entities | `ingestion/page-format`, `ingestion/concept-extraction`, `ingestion/entity-extraction` (Milestone #3) |
| `core/` | Always available; the foundational `/brain` verbs | `core/query`, `core/lint`, `core/learn`, `core/status` (Milestones #5–#7) |
| `detected/` | Auto-installed by stack detection on `/brain init`; tech-stack-specific page templates and conventions | `detected/react`, `detected/python`, `detected/go`, `detected/typescript` (Milestone #3) |
| `available/` | Opt-in via a future `/brain skill install <name>`; specialized extensions | post-MVP |

## SKILL.md frontmatter (mandatory shape)

Every `SKILL.md` ships with a YAML frontmatter block merging ECC's base fields (`name`, `description`, `origin`, `version`) with graphbrain's tier-aware additions (`tier`, `pattern`, `related_skills`, `detect`):

```yaml
---
name: <skill-name>                  # kebab-case, matches the directory name
description: <one-liner>            # used by the harness for selection
origin: codebrain                   # provenance — useful when skills are mixed across plugins
version: 0.1.0                      # semver of this individual skill
tier: behavioral | ingestion | core | detected | available
pattern: Meta | Generator | Reviewer | Pipeline | Observer | Planner | ...
related_skills: [<other-skill-names>]
detect:                             # required for tier: detected; omit otherwise
  - { file_exists: "package.json", contains: "react" }
applies_to_extensions: [".tsx", ".jsx"]   # required for tier: detected — gates which
                                          # source-file extensions trigger this stack's
                                          # page-template extras at /brain ingest time
                                          # (M#3d adds this field; older tiers omit it)
---
```

## The `detect:` rule format (PRD Design Decision #22)

For `tier: detected` skills, `/brain init` auto-installs the skill if every rule in the `detect:` array matches the user's repo. Supported rules:

| Rule | Matches when |
|---|---|
| `{ file_exists: "<path>" }` | The file exists at the path relative to repo root |
| `{ file_exists: "<path>", contains: "<substring>" }` | The file exists AND contains the literal substring |
| `{ dir_exists: "<path>" }` | The directory exists at the path |
| `{ glob: "<pattern>" }` | At least one file matches the glob, relative to repo root |

All rules in the array must match (logical AND). For OR, ship two skills with different detect rules.

## Body sections (per ECC convention)

After the frontmatter, every SKILL.md has these sections:

- **When to Activate** — concrete triggers (operator intent, file types, lifecycle events)
- **How It Works** — what the skill does mechanically
- **Examples** — concrete invocations
- Optional skill-specific sections (Output Contract, Self-check, Rules, etc.)

## Why the tier model

ECC's 232 flat skills under `skills/*/` make install scope, deprecation, and "what gets loaded by default" impossible to reason about (PRD Design Decision #21 rationale). graphbrain's tier model — `core/`, `behavioral/`, `ingestion/`, `detected/`, `available/` — gives every skill a clear lifecycle. codebrain ships only a handful of skills at v0.1, but the tier structure is in place so growth doesn't require restructuring.

## Cross-references

- Agent conventions: `../agents/README.md`
- Shape of slash-command and hook files codebrain writes into the user's `.claude/`: `../reference/claude-code-conventions.md`
- The architectural lineage: `../reference/llm-wiki.md`
- PRD with all 33 locked design decisions: `../.claude/prds/codebrain.prd.md`
