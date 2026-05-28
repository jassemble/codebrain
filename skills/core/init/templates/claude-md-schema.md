## graphbrain

This repo has a graphbrain wiki at `.brain/`. The wiki is an LLM-maintained, folder-mirrored markdown knowledge base of this codebase. **The operator reads; the agent writes.** Source code is never modified by graphbrain — only the wiki is.

### Vault layout

```
.brain/
├── code/             # 1:1 mirror of source tree (one .md per significant source file)
├── concepts/         # cross-cutting pages — auth-flow.md, entities/<name>.md, integrations/<name>.md, glossary.md
├── decisions/        # per-decision ADR files
├── overview.md       # project purpose, structure, key patterns, active state
├── index.md          # page catalog with one-line summaries
├── log.md            # Recent Patterns (semantic) + Activity History (append-only)
├── decisions.md      # active + superseded ADR summary index
├── status.md         # derived lifecycle view (regenerated; never the source of truth)
└── .graphbrain-version  # marker file for upgrade detection
```

### Page-type frontmatter

Every page in `.brain/` carries Dataview-compatible YAML frontmatter:

```yaml
---
kind: code | concept | decision | overview | index | log | status
status: UNENRICHED | FRESH | STALE | RESYNCED | VERIFIED
source: src/api/auth.ts          # for kind: code — path to mirrored source file
source_hash: a1b2c3d              # git hash of source at last ingest (stale detection)
sources:                          # for kind: concept — optional dependency list
  - src/middleware.ts
last_ingested: 2026-05-24
tokens: 1842
---
```

### Operations

| Command | What it does |
|---|---|
| `/brain init` | Populate this schema block + `.brain/overview.md`; detect tech stack |
| `/brain ingest [path]` | Read source files → write LLM-authored wiki pages mirroring folder structure |
| `/brain query "<question>"` | Pointer-first lookup; reads `index.md` → 1–3 pages → answers with citations; auto-refreshes STALE pages |
| `/brain lint [--fix]` | Health-check the wiki: defects + gaps + contradictions + suggested questions; `--fix` batch re-ingests STALE pages |
| `/brain learn {on\|off\|status}` | Toggle the continuous-learning observer (narrow-scope; tracked-file edits + codebase-symbol prompts only) |
| `/brain status` | Dashboard: total pages, % stale, recent log entries, top instincts |

### Staleness model (4-tier)

1. **Wikilink reverse-lookup** (PostToolUse hook) — when a source file is edited, every `.brain/**/*.md` page containing `[[code/<edited-path>]]` is marked `status: STALE`
2. **Explicit `sources:` frontmatter** — concept pages observing patterns across files they don't directly link to can declare their dependencies in frontmatter; the hook also reacts to these
3. **Lint contradiction-check** — `/brain lint` re-reads pages + source; catches subtle drift the hook can't (e.g., behavior change inside an existing function body)
4. **Query-time refresh** — `/brain query` checks freshness before reading; if `STALE`, triggers re-ingest before answering

Staleness **propagates** through wikilinks; freshness is **opportunistic** (refreshed when needed, not eagerly).

### Wikilink convention

- Code page references: `[[code/src/path/file.ts]]`
- Concept page references: `[[concepts/auth-flow]]` or `[[concepts/entities/tenant]]`
- Decision references: `[[decisions/0042-jwt-rotation]]`

Always bidirectional — if A links to B, B should link back to A (lint enforces this).

### Prompt-defense reference rule

Agents working in this repo should **Read the Prompt Defense Baseline section of CLAUDE.md before acting** rather than re-copying the baseline into every agent file. Single source of truth.

### Agent execution model

- Writers (ingester, linker, verifier) run **foreground** — synchronous in the operator's session; auditable; transactional with git
- Observers (continuous-learning) run **background** but are **strictly read-only** — they may never call Edit, Write, MultiEdit, or any mutating Bash command

### Continuous learning

Graphbrain observes tool-use on tracked source files and prompts that reference codebase symbols. Observations consolidate into project-scoped instincts at `~/.local/share/graphbrain/projects/<git-remote-hash>/instincts/`. Toggle: `/brain learn on|off`. Project-scoped by default; promotion to global scope when an instinct appears in N≥2 projects with avg confidence ≥0.8.

### Where to look

- This wiki: `.brain/`
- The product: https://github.com/jassemble/graphbrain
- Architecture lineage (LLM-Wiki pattern): graphbrain `reference/llm-wiki.md`
