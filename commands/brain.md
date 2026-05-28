<!-- graphbrain v1.0.0 -->
---
description: codebrain — agent-maintained codebase wiki. Dispatcher: routes to /brain:<verb> per-verb commands.
---

# /brain

Codebrain's primary slash command. After M#12 (slash-command namespacing), every verb lives in its own file under `.claude/commands/brain/<verb>.md`. This top-level file is a help disambiguator + legacy dispatcher.

`$ARGUMENTS` is parsed as `<verb> [args...]`. Route as follows.

## Dispatch

| Verb | Namespaced form | Action |
|---|---|---|
| `init` | `/brain:init` | Scaffold `.brain/` + CLAUDE.md schema block + stack detection. Procedure in `commands/brain/init.md`. |
| `ingest <file>` | `/brain:ingest <file>` | Single-file ingest. Procedure in `commands/brain/ingest.md`. |
| `ingest <folder>` | `/brain:ingest <folder>` | Folder ingest + linker. Procedure in `commands/brain/ingest.md`. |
| `ingest` (no args) | `/brain:ingest` | Tiered auto-prioritize ingest. Procedure in `commands/brain/ingest.md`. |
| `query "<question>"` | `/brain:query "<q>"` | Pointer-first lookup. Procedure in `commands/brain/query.md`. |
| `lint [--fix]` | `/brain:lint [--fix]` | Wiki health-check. Procedure in `commands/brain/lint.md`. |
| `learn {on\|off\|status\|consolidate}` | `/brain:learn <subcommand>` | Continuous-learning toggle + consolidator. Procedure in `commands/brain/learn.md`. |
| `status` | `/brain:status` | Brain dashboard. Procedure in `commands/brain/status.md`. |
| `spec "<intent>"` | `/brain:spec "<intent>"` | Spec-orchestrate via ECC's plan-prd → plan → optional santa-loop. Procedure in `commands/brain/spec.md`. (Milestone #10a) |
| `creds {list\|show\|add\|remove\|forget-all}` | `/brain:creds <sub-verb>` | Per-project credential registry at XDG plaintext store. Procedure in `commands/brain/creds.md`. (Milestone #11b) |

## Legacy-dispatcher behavior (`/brain <verb>`)

When invoked as `/brain <verb> [args...]` (dispatcher form, muscle-memory):

1. Parse the first whitespace-delimited token of `$ARGUMENTS` as `<verb>`.
2. Resolve `<verb>` against the dispatch table above. If `<verb>` is one of `init`, `ingest`, `query`, `lint`, `learn`, `status`, `spec`, `creds`, **Read** `commands/brain/<verb>.md` and execute its procedure with `$ARGUMENTS` interpreted as if the first token were stripped (i.e., `/brain ingest src/auth.ts` → execute `ingest.md` with `$ARGUMENTS = "ingest src/auth.ts"`; the per-verb procedure parses the rest).
3. If `<verb>` is unrecognized, fall through to the no-arg help block below.

The per-verb files are the canonical procedure location. This dispatcher is a thin Read-and-execute shim that preserves `/brain <verb>` muscle memory; the namespaced `/brain:<verb>` form invokes the same files directly (Claude Code's subdirectory-namespacing convention).

## No argument (just `/brain`)

Print this help block:

```
/brain — codebrain commands

  /brain:init                  Scaffold .brain/ + CLAUDE.md schema block (Milestone #2)
  /brain:ingest [path]         Read source files → write LLM-authored wiki pages (Milestone #3)
  /brain:query "<question>"    Pointer-first lookup against the brain (Milestone #5)
  /brain:lint [--fix]          Health-check the wiki; --fix batch-refreshes STALE pages (Milestone #6)
  /brain:learn {on|off|status} Toggle the continuous-learning observer (Milestone #7)
  /brain:status                Brain dashboard (Milestone #7)
  /brain:spec "<intent>"       Spec-orchestrate a feature via ECC (Milestone #10a)
  /brain:creds {list|show|add|remove|forget-all}  Credential registry (Milestone #11)

The legacy form /brain <verb> still works (muscle memory) — it dispatches to
the same per-verb files. The namespaced form is more discoverable in Claude
Code's command palette.

  Repository:  https://github.com/jassemble/codebrain
  PRD:         .claude/prds/codebrain.prd.md (if installed for development)
```

## Unknown verb

If `$ARGUMENTS` starts with anything not in the dispatch table, print:

```
error: unknown verb '<verb>'. Try /brain (no args) for the verb list.
```
