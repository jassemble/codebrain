---
name: codebrain
description: agent-maintained markdown wiki of the codebase (folder-mirrored, Obsidian-viewable, with continuous learning) — invoke /brain init to scaffold .brain/ inside your repo
origin: codebrain
version: 0.1.0
tier: behavioral
pattern: Meta
related_skills: []
---

# codebrain — meta skill

This skill describes what codebrain is and how the agent should work with it. It's always loaded (tier: behavioral) so the agent always knows the brain exists in any repo where codebrain is initialized.

## When to Activate

- The operator wants the agent to maintain a persistent codebase wiki across sessions
- The agent encounters a `.brain/` directory in the repo (sign that codebrain has been initialized here)
- The operator invokes any `/brain *` slash command
- The agent is asked a question that would benefit from cross-cutting codebase knowledge (auth flows, entity definitions, integration boundaries) — check `.brain/concepts/` and `.brain/index.md` before grepping source

## How It Works

codebrain adapts the LLM-Wiki pattern (see `reference/llm-wiki.md`) from documents/research to codebases. Three layers with clear ownership:

| Layer | What | Mutability |
|---|---|---|
| **Raw sources** | The codebase itself (every file under repo root except `.brain/`) | Read-only from codebrain's perspective. The brain layer **never** modifies source code; source edits happen through the agent's normal Edit/Write workflow, and the PostToolUse hook reacts by marking pages STALE. |
| **The wiki** (`.brain/`) | Folder-mirrored code pages (`.brain/code/`), cross-cutting concept pages (`.brain/concepts/`), decisions/ADRs, overview, index, log, status | Owned by codebrain skills. The operator reads; the agent writes. |
| **The schema** | `## codebrain` managed region inside `CLAUDE.md` | Co-evolved by operator + agent over the project's lifetime |

### The loop

1. **Ingest** — agent reads source files → writes LLM-authored markdown pages mirroring folder structure
2. **Query** — agent reads `.brain/index.md` → identifies 1–3 candidate pages → answers with citations
3. **Lint** — agent health-checks the wiki: stale pages, broken wikilinks, contradictions, missing concepts, suggested questions
4. **Stale-detect** (automatic via hook) — when a source file is edited, its `.brain/code/<path>.md` page and any concept page that wikilinks to it are marked STALE

## Agent Execution Model

Per PRD Design Decision #16: **foreground-first**. Slash commands and trigger phrases invoke agents synchronously in the operator's session. The only exception is the continuous-learning observer (Milestone #7), which runs as a background read-only agent — observers may never call Edit/Write/MultiEdit or mutating Bash.

Per Design Decision #20: agents include `Read the Prompt Defense Baseline section of CLAUDE.md before acting` rather than copying that baseline into every agent file.

## Examples

```
/brain init                       # scaffold .brain/ + CLAUDE.md schema block (Milestone #2)
/brain ingest src/api             # ingest a folder; tiered auto-prioritize when no path
/brain query "how does auth work?"   # pointer-first lookup; auto-refresh STALE pages
/brain lint                       # read-only health check
/brain lint --fix                 # batch re-ingest STALE pages
/brain learn on                   # enable continuous-learning observer (Milestone #7)
/brain status                     # dashboard view
```

## v0.1 status

This is codebrain v0.1.0 — the package skeleton + init flow. All `/brain` verbs except `init` print "not yet implemented; see roadmap" stubs. Milestones #2–#8 implement the verbs in sequence.

## Cross-references

- Agent conventions: `../../../agents/README.md`
- Skill tier model: `../../README.md`
- LLM-Wiki source pattern: `../../../reference/llm-wiki.md`
- Claude Code conventions codebrain writes into the user's `.claude/`: `../../../reference/claude-code-conventions.md`
- PRD with all 33 locked design decisions: `../../../.claude/prds/codebrain.prd.md`
