---
name: init
description: Populate the graphbrain wiki — write the full schema block to CLAUDE.md, customize .brain/overview.md with a project digest, detect tech stack, log the init event. Distinct from `npx graphbrain init` (M#1, file-system scaffold); this is the LLM-agent-driven content-population step that runs inside Claude Code via the `/brain init` slash command.
origin: graphbrain
version: 0.1.0
tier: core
pattern: Generator
related_skills: [behavioral/graphbrain]
---

# init — graphbrain content-population skill

This skill is the agent-side complement to `npx graphbrain init`. The npm step creates skeleton files with empty frontmatter; this skill fills them with project-aware content the agent infers from the user's repo.

## When to Activate

- Operator runs `/brain init`
- Operator types a trigger phrase: "initialize graphbrain", "set up the brain", "populate .brain/", "fill in the graphbrain schema"
- An automated workflow needs to refresh the schema block after a graphbrain upgrade (`/brain init --force`)

## Prerequisites

- `.brain/` directory must exist in the cwd. If not, `npx graphbrain init` hasn't been run yet — emit an error pointing the operator there.
- `CLAUDE.md` in cwd must contain both `<!-- graphbrain:begin -->` and `<!-- graphbrain:end -->` markers (M#1 wrote them). If missing, the operator's CLAUDE.md was modified externally — emit an error and stop rather than guess where to insert.

## How It Works

The full 7-step procedure is in `commands/brain.md` under "When `$ARGUMENTS` is `init`". That file is the **load-bearing contract** — Claude Code reads it from `.claude/commands/brain.md` at slash-command invocation time. This SKILL.md is for skill-tier discovery and human-readable documentation; the procedure is co-located with the command so it can't drift from what the harness actually executes.

In summary, init does:

1. **Preconditions** — verify `.brain/` and CLAUDE.md markers exist
2. **Read templates** — `claude-md-schema.md`, `overview-starter.md`, `stack-detection.json` from this skill's `templates/` directory
3. **Schema block** — splice the verbatim `claude-md-schema.md` content between the managed-region markers in the user's `CLAUDE.md` (preserve everything outside; skip if content already current unless `--force`)
4. **Detect stack** — match `stack-detection.json` signals against the cwd; collect matched stacks (e.g., `react`, `typescript`, `nodejs`)
4c. **Stack-specific skill recommendations (M#13a)** — for each detected stack, read the catalog's `recommended_skills[]` array. Apply LLM judgment (this is what makes init agent-driven, not imperative) to filter for relevance to THIS specific repo: e.g., is `package.json`'s `"main"` a CLI script or a web app entry? Are there test directories that suggest the operator does TDD? Skip recommendations that are technically applicable but unlikely to help in this codebase. Dedupe by `(source, package)`. Format the block for the Step 7 report.
5. **Populate overview.md** — read `overview-starter.md`; fill each `<!-- AGENT: ... -->` instruction comment using info inferred from `package.json`, `README.md`, top-level dir tree; update frontmatter (`status: FRESH`, `last_ingested`, `ingested_by`)
6. **Log** — append a grep-parseable entry to `.brain/log.md`: `## [YYYY-MM-DD] init | /brain init populated schema block + overview; detected: <stacks>`
7. **Report** — structured summary (schema-block status, overview status, detected stacks, log path, **Recommended skills block from Step 4c** when applicable, next-step pointer)

## Examples

```
/brain init
# Normal flow: idempotent if schema block already current; populates overview if it's a stub.

/brain init --force
# Refreshes the schema block in CLAUDE.md even if it's already current; useful after a graphbrain version bump.
```

Sample report on a Next.js project:

```
/brain init complete (v0.1.0)
  Schema block:   refreshed
  overview.md:    populated (Project Purpose, Codebase Structure, Active State)
  Detected stack: react, typescript, nodejs
    Note: no `detected/` skills installed yet — coming in Milestone #3.
  Logged:         .brain/log.md
Next: try `/brain ingest src/` (Milestone #3 — not yet implemented).
```

## Output Contract

After a successful `/brain init`:

- `<cwd>/CLAUDE.md` has the full ~120-line graphbrain schema block between the managed-region markers (replacing M#1's placeholder)
- `<cwd>/.brain/overview.md` has populated content; frontmatter `status: FRESH`
- `<cwd>/.brain/log.md` has a new entry under `## Activity History`
- Detected stacks are reported to the operator; **no `detected/` skills are installed yet** (that's M#3 — for now, detection is reported and the catalog is in place)

## Cross-references

- Meta skill: `../../behavioral/graphbrain/SKILL.md`
- Templates this skill reads: `./templates/`
- Load-bearing instructions: `../../../commands/brain.md` (the `init` verb section)
- Schema-block content the agent writes: `./templates/claude-md-schema.md`
- Frontmatter shape conventions: `../../README.md`
- PRD design decisions affecting init: #7 (page caps including schema), #9–#11 (concepts/ vs wiki/), #13 (schema co-evolution via managed region), #20 (prompt-defense reference), #22 (stack detection), #23 (page templates)
