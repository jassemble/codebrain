# codebrain

> An agent-maintained, folder-mirrored markdown wiki of your codebase. Installed via `npx graphbrain init`; navigated by Claude Code; viewed in Obsidian.

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
npx graphbrain init

# Global — slash commands available in every repo
npx graphbrain init --global

# Re-run safe; --force overrides; --dry-run prints the plan
npx graphbrain init --dry-run
```

`init` is idempotent. It writes `.brain/` to the current repo, copies `/brain` slash command templates into `.claude/commands/`, and merges codebrain's hooks block into `.claude/settings.local.json`. Existing user hooks are preserved (codebrain owns only entries whose `id` starts with `codebrain:`).

After `init`, **restart Claude Code or open a new session** to load the new slash commands.

## Quickstart

Three-step onboarding:

1. **Install graphbrain into the repo** (run once per repo):
   ```
   npx graphbrain init
   ```
   Scaffolds `.brain/`, copies `/brain:*` slash commands into `.claude/commands/`, merges hooks into `.claude/settings.local.json`.

2. **Restart Claude Code or open a new session**, then populate the brain:
   ```
   /brain:init
   ```
   Writes the full schema block into `CLAUDE.md`, populates `.brain/overview.md`, detects your tech stack.

3. **Ingest source files** — three modes, pick what fits:
   ```
   /brain:ingest src/api/auth.ts       # single file (Milestone #3a)
   /brain:ingest src/                  # whole folder + concept pages (Milestone #3b)
   /brain:ingest                       # tiered auto-prioritize across the codebase (Milestone #3c)
   ```

   Both forms work — `/brain init` and `/brain:init` produce identical behavior. The colon (`:`) is Claude Code's subdirectory-namespace separator; the legacy space form is preserved as a dispatcher shim for muscle memory.

Then navigate the wiki in Obsidian (open the repo root as an Obsidian vault and explore `.brain/`) or query via Claude Code:

```
/brain:query "how does auth work?"        # pointer-first lookup (M#5)
/brain:lint                                # health-check the wiki (M#6)
/brain:lint --fix                          # batch re-ingest STALE pages
/brain:learn on                            # enable continuous-learning observer (M#7)
/brain:status                              # dashboard view (M#7)
/brain:spec "add OAuth login"              # spec-orchestrate via ECC (M#10a — v0.2)
/brain:creds add staging-db host=... ...   # per-project credential registry (M#11 — v0.2)
```

The legacy `/brain <verb>` form (with a space) still works — `/brain ingest src/auth.ts` and `/brain:ingest src/auth.ts` are equivalent. The namespaced form is more discoverable in Claude Code's command palette.

## What's new in v0.2

- **Slash-command namespacing** (M#12) — every verb has its own file under `.claude/commands/brain/<verb>.md` for better Claude Code autocomplete + lower per-invocation token cost. Legacy `/brain <verb>` dispatcher preserved for muscle memory.
- **`/brain:spec`** (M#10a) — orchestrate a feature intent through ECC's `plan-prd` → `plan` → optional `santa-loop` into a converged PRD + plan. Spec-first discipline.
- **`/brain:creds`** (M#11) — per-project credential registry at `<XDG>/codebrain/projects/<git-hash>/credentials.toon`. Plaintext but outside the repo, chmod 0600, refusal-pattern enforcement (Stripe live keys / AWS / GitHub PATs / "prod" context all rejected), mask-by-default `show`, auditable override flag.
- **`.brain/llms.txt`** (v0.1.2) — agent-portable AEO site map; external agents read it to route into the wiki.
- **`.brain/CHANGELOG.md`** (M#10d) — curated compound-learning narrative; appended on every ingest + consolidate.
- **`supersedes` / `superseded_by` frontmatter** (M#10d) — pink-elephant fix; `/brain:query` skips superseded pages and follows the pointer to the replacement.
- **Runtime bridge probe** (M#9-prereq) — filesystem-probe pattern (`~/.claude/plugins/<vendor>/skills/<name>/SKILL.md`) lets per-stack skills load ECC's expert pattern skills at ingest time.
- **8 new `detected/*` skills** (M#9-coverage) — vue, rails, flask, koa, hapi, gin, echo, fiber + `expert_skills:` bridges for the four M#3d skills (react, typescript, python, go).
- **`wiki-reading-principles`** behavioral skill (M#10d) — 3-tier always/ask/never rules for how agents engage with `.brain/`.
- **`discovery-loop`** skill (M#10b) — codifies the iterative convergence-sweep pattern; reusable.
- **Intent-routing meta-skill section** (M#10c) — opt-in via `.brain/.codebrain-intent-routing-state`; when on, the agent suggests `/brain:spec` before code edits on feature-intent prompts.

## How it works

Three layers with clear ownership ([full architecture](.claude/prds/codebrain.prd.md#architecture)):

| Layer | What | Mutability |
|---|---|---|
| **Raw sources** | Your codebase | Read-only from codebrain's perspective |
| **The wiki** (`.brain/`) | LLM-authored markdown pages mirroring the source tree | Owned by codebrain skills; operator reads, agent writes |
| **The schema** | `## codebrain` managed region in your `CLAUDE.md` | Co-evolved by operator + agent |

The architectural lineage: [LLM Wiki pattern reference](reference/llm-wiki.md).

## Roadmap

**v0.1** (shipped):

| # | Milestone | Status |
|---|---|---|
| 1 | npm package skeleton + `init` | complete |
| 2 | `init` skill — scaffold + CLAUDE.md schema block | complete |
| 3a/b/c/d | `ingest` pipeline + stack-aware extras | complete |
| 4 | 4-tier staleness model via PostToolUse hook | complete |
| 5 | `query` — pointer-first lookup with auto-refresh | complete |
| 6 | `lint` — defects + gaps + contradictions + `--fix` | complete |
| 7 | Continuous-learning observer | complete |
| 8 | Dogfood + measure on 3 sample repos | complete |

**v0.1.1** (framework detection):

| Milestone | Outcome | Status |
|---|---|---|
| 6 framework skills | nestjs / nextjs / express / django / fastapi / springboot | complete |

**v0.1.2** (.brain/llms.txt + reciprocity):

| Milestone | Outcome | Status |
|---|---|---|
| llms.txt | AEO-convention agent-portable site map | complete |
| reciprocity test | SKILL.md `related_skills:` resolution check | complete |

**v0.2** (this release):

| # | Milestone | Outcome | Status |
|---|---|---|---|
| 9 | Framework-detection runtime probe + 8 more frameworks | complete |
| 10a | `/brain:spec` verb + spec-orchestrator agent | complete |
| 10b | discovery-loop skill (convergence sweep) | complete |
| 10c | Intent-routing behavioral update (opt-in) | complete |
| 10d | supersedes frontmatter + CHANGELOG + wiki-reading-principles | complete |
| 11 | Credential registry (`/brain:creds` + TOON store) | complete |
| 12 | Slash-command namespacing (per-verb files) | complete |

See [the PRD](.claude/prds/codebrain.prd.md) for the full spec, 33 locked design decisions, success metrics, and risk register.

## Dogfood + validate

Codebrain ships with a validation harness for measuring whether the wiki delivers on its claims.

**Static checks** (automated, run anytime):

```bash
bash scripts/dogfood/install-validate.sh   # validates clean install scaffold
bash scripts/dogfood/static-baseline.sh    # gathers shipped-artifact metrics → .claude/validation/v0.1-static-baseline.md
```

**LLM-driven measurements** (operator procedure, requires real Claude Code sessions):

See [`scripts/dogfood/MANUAL-MEASUREMENTS.md`](scripts/dogfood/MANUAL-MEASUREMENTS.md) for the step-by-step:

- **M1** Token-reduction A/B (10 questions × 3 repos)
- **M2** Freshness drift (7-day measurement window)
- **M3** Wikilink precision (sampled manual review)
- **M4** Time-to-first-value (wall-clock)
- **M5** Continuous-learning lift (deferred pending Milestone #7)

Results land in [`.claude/validation/v0.1-baseline.md`](.claude/validation/v0.1-baseline.md) — a living report you fill as evidence accumulates.

## Credits

codebrain is the synthesis of three OSS projects:

- **[ECC](https://github.com/affaan-m/ECC)** — agent harness conventions, continuous-learning model, plugin manifest discipline, prompt-defense baseline
- **[graphbrain](https://github.com/jassemble/graphbrain)** — LLM-wiki applied to codebases, source-hash stale detection, page templates, agent registry pattern, foreground-first execution
- **The LLM Wiki pattern** — the source idea (see `reference/llm-wiki.md`)

## License

MIT. See [LICENSE](LICENSE).
