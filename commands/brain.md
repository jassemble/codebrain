<!-- codebrain v0.1.0 -->
---
description: codebrain — agent-maintained codebase wiki (init, ingest, query, lint, learn, status)
---

# /brain

Codebrain's primary slash command. Dispatches on the first argument to one of six verbs.

`$ARGUMENTS` is parsed as `<verb> [args...]`. Route as follows:

## Dispatch

| Verb | Status | Message to print |
|---|---|---|
| `init` | not implemented | `Milestone #2 (Init + schema scaffolding) — not yet implemented in v0.1. See the Roadmap section of the codebrain README.` |
| `ingest` | not implemented | `Milestone #3 (Ingest pipeline) — not yet implemented in v0.1. See the Roadmap section of the codebrain README.` |
| `query` | not implemented | `Milestone #5 (Query helper) — not yet implemented in v0.1. See the Roadmap section of the codebrain README.` |
| `lint` | not implemented | `Milestone #6 (Lint pass) — not yet implemented in v0.1. Will support \`--fix\` to batch re-ingest STALE pages.` |
| `learn` | not implemented | `Milestone #7 (Continuous-learning observer) — not yet implemented in v0.1. Subverbs will be \`on\`, \`off\`, \`status\`.` |
| `status` | not implemented | `Milestone #7 — not yet implemented in v0.1. Will show dashboard of total pages, % stale, recent log entries, top instincts.` |

## No argument (just `/brain`)

Print this help block:

```
/brain — codebrain commands

  /brain init                Scaffold .brain/ + CLAUDE.md schema block (Milestone #2)
  /brain ingest [path]       Read source files → write LLM-authored wiki pages (Milestone #3)
  /brain query "<question>"  Pointer-first lookup against the brain (Milestone #5)
  /brain lint [--fix]        Health-check the wiki; --fix batch-refreshes STALE pages (Milestone #6)
  /brain learn {on|off|status}   Toggle the continuous-learning observer (Milestone #7)
  /brain status              Brain dashboard (Milestone #7)

This is codebrain v0.1.0 — most verbs are stubs in this release. See the README
roadmap for the implementation schedule.

  Repository:  https://github.com/jassemble/codebrain
  PRD:         .claude/prds/codebrain.prd.md (if installed for development)
```

## Unknown verb

Print: `Unknown verb: <verb>. Run \`/brain\` (no arguments) for help.`
