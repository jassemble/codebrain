# codebrain

> An agent-maintained, folder-mirrored markdown wiki of your codebase. Installed via `npx codebrain init`; navigated by Claude Code; viewed in Obsidian.

codebrain is the [LLM-Wiki pattern](reference/llm-wiki.md) adapted from documents/research to **codebases**. Instead of every coding-agent session re-grepping and re-reading the same files, your agent builds and maintains a persistent `.brain/` wiki that mirrors your source tree, surfaces cross-cutting concepts, tracks decisions, and stays current via stale-detection hooks.

## What it does

- **Folder-mirrored code pages** — `src/api/auth.ts` → `.brain/code/src/api/auth.ts.md` (one page per source file)
- **Cross-cutting concept pages** — `auth-flow.md`, `entities/tenant.md`, `integrations/stripe.md` for things that don't live in a single file
- **Decisions / ADRs** — `.brain/decisions/` for the architectural rationale invisible from source
- **Stale-detection via hooks** — editing a source file flips its wiki page (and any concept page that wikilinks to it) to STALE
- **Query-time refresh** — when an agent reads a STALE page, it re-ingests before answering
- **Continuous learning** — observes tool-use and prompts; extracts project-scoped "instincts" about the codebase
- **Obsidian-viewable** — Dataview-compatible YAML frontmatter; graph view shows the wiki shape
- **Agent-readable** — pointer-first navigation (`index.md` → page); bounded page sizes; predictable paths

## Install

Requires Node.js ≥18 and [Claude Code](https://claude.com/claude-code).

```bash
# Project-local (recommended; default)
npx codebrain init

# Global — slash commands available in every repo
npx codebrain init --global

# Re-run safe; --force overrides; --dry-run prints the plan
npx codebrain init --dry-run
```

`init` is idempotent. It writes `.brain/` to the current repo, copies `/brain` slash command templates into `.claude/commands/`, and merges codebrain's hooks block into `.claude/settings.local.json`. Existing user hooks are preserved (codebrain owns only entries whose `id` starts with `codebrain:`).

After `init`, **restart Claude Code or open a new session** to load the new slash commands.

## Quickstart

```
/brain init                          # scaffold the brain (Milestone #2)
/brain ingest src/                   # read source files → write LLM-authored wiki pages
/brain query "how does auth work?"   # pointer-first lookup; auto-refreshes STALE pages
/brain lint                          # health-check the wiki (read-only)
/brain lint --fix                    # batch re-ingest STALE pages
/brain learn on                      # enable continuous-learning observer
/brain status                        # dashboard view
```

## How it works

Three layers with clear ownership ([full architecture](.claude/prds/codebrain.prd.md#architecture)):

| Layer | What | Mutability |
|---|---|---|
| **Raw sources** | Your codebase | Read-only from codebrain's perspective |
| **The wiki** (`.brain/`) | LLM-authored markdown pages mirroring the source tree | Owned by codebrain skills; operator reads, agent writes |
| **The schema** | `## codebrain` managed region in your `CLAUDE.md` | Co-evolved by operator + agent |

The architectural lineage: [LLM Wiki pattern reference](reference/llm-wiki.md).

## Roadmap

| Milestone | Outcome | Status |
|---|---|---|
| 1 | npm package skeleton + `init` | **in-progress** (v0.1.0) |
| 2 | `init` skill — scaffold + CLAUDE.md schema block | pending |
| 3 | `ingest` pipeline — folder-mirrored pages with wikilinks | pending |
| 4 | 4-tier staleness model via PostToolUse hook | pending |
| 5 | `query` — pointer-first lookup with auto-refresh | pending |
| 6 | `lint` — defects + gaps + contradictions + `--fix` | pending |
| 7 | Continuous-learning observer (background, read-only) | pending |
| 8 | Dogfood + measure on 3 sample repos | pending |

See [the PRD](.claude/prds/codebrain.prd.md) for the full spec, 33 locked design decisions, success metrics, and risk register.

## Credits

codebrain is the synthesis of three OSS projects:

- **[ECC](https://github.com/affaan-m/ECC)** — agent harness conventions, continuous-learning model, plugin manifest discipline, prompt-defense baseline
- **[graphbrain](https://github.com/jassemble/graphbrain)** — LLM-wiki applied to codebases, source-hash stale detection, page templates, agent registry pattern, foreground-first execution
- **The LLM Wiki pattern** — the source idea (see `reference/llm-wiki.md`)

## License

MIT. See [LICENSE](LICENSE).
