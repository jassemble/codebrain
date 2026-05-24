# codebrain

## Problem
Coding agents (Claude Code, Cursor, Codex) lose context across sessions, waste tokens re-reading source files, and rediscover codebase structure on every question. The three closest tools each solve a slice: **graphify** extracts AST relations across 31 languages but is CLI-heavy and its Obsidian export clusters by community rather than mirroring the source tree; **graphbrain** has the right *LLM-maintains-a-wiki* shape but explicitly dropped its extractor in v0.5.0 and ships as a bash scaffold; **ECC** provides a mature agent harness and continuous-learning system but has no native code-graph capability (`knowledge-ops` documents the intent and leaves ingestion as an exercise). The leaving-unsolved cost: every fresh agent session pays the rediscovery tax, and "knowledge" about the codebase lives in chat history, not as a compounding artifact.

## Evidence
- graphbrain v0.5.0 release notes drop the Python AST extractor — the maintainer chose the LLM-Wiki pattern over deterministic extraction (signal that pure-LLM page-writing is viable).
- graphify's `extract.py` is 329KB and `__main__.py` 159KB — the AST path is heavyweight, and the Obsidian exporter (`export.py`, 54KB) folders by *community cluster*, not by source tree.
- ECC ships 232 skills and continuous-learning-v2 (project-scoped instincts, XDG storage, promotion pipeline) but `knowledge-ops` describes an MCP-memory graph layer the user must populate themselves.
- The "LLM Wiki" pattern document provided by the user (the reference doc included in the project's `reference/` directory) lays out a proven three-layer architecture — raw sources, LLM-owned wiki, co-evolved schema — for articles/research/personal knowledge. codebrain is the **codebase-as-source** adaptation: no public implementation has applied this pattern to code, where the "raw sources" are the project's own files and the wiki mirrors the source tree.
- Assumption — needs validation via dogfooding: that an agent navigating `.brain/` pages instead of grepping/reading source measurably reduces token cost and improves answer quality.

## Users
- **Primary**:
  - **Coding-agent operators** running Claude Code (initially) in unfamiliar or evolving codebases who want the agent to "know" the project and not relearn it every session.
  - **The coding agent itself** — the wiki is structured for *agent-readability*: pointer-first navigation (index → page), bounded page sizes, wikilink jumps, predictable paths (`.brain/code/src/api/auth.ts.md` mirrors `src/api/auth.ts`).
- **Not for**:
  - Document / research / personal-knowledge use cases — use the original LLM Wiki pattern.
  - Teams wanting a Wikipedia-style human-edited wiki — codebrain is agent-maintained, humans curate questions and review.
  - Workflows that require deterministic AST extraction as the source of truth — use graphify standalone.

## Hypothesis
We believe a **folder-mirrored, agent-maintained markdown wiki of the codebase**, distributed as an **npm package** that installs harness-native skills + hooks via a single `npx codebrain init` step (no setup wizard, no external extractor; post-init, all flow is directed by LLM agents inside the harness), will **reduce context-loading cost and improve agent decision quality in coding sessions** for **operators of coding agents and the agents themselves**.

We'll know we're right when, in a fresh session on a brain-ingested repo, an agent answers a structural question ("what calls X?", "what does this module touch?", "where is Y configured?") by reading 1–3 markdown pages from `.brain/` instead of grepping or reading 10+ source files — and when the wiki measurably stays current across a week of normal agent work without human intervention.

## Architecture

codebrain is the LLM-Wiki pattern (per the reference document the user provided) **adapted from documents/research to codebases**. Three explicit layers, with clear ownership and immutability rules:

| Layer | What | Owned by | Mutability contract |
|---|---|---|---|
| **1. Raw sources** | The codebase itself — every file under the repo root, excluding `.brain/` | The developer + their agent's normal coding work | The brain layer **never** modifies source code. Source is read-only from codebrain's perspective. Source edits happen through the operator's normal workflow (the agent's Edit/Write tools); the PostToolUse hook then *reacts* to those edits by marking pages STALE. |
| **2. The wiki** (`.brain/`) | Folder-mirrored code pages, cross-cutting concept pages, decisions/ADRs, overview, index, log, status | codebrain skills (init/ingest/query/lint) — the LLM writes, never the human | The operator reads; the agent writes. Humans can manually edit pages (they're just markdown), but the contract is that the agent maintains them. |
| **3. The schema** (the `## codebrain` block in `CLAUDE.md`) | Layout description, conventions, ingest/query/lint operating rules, page-type taxonomy | Co-evolved by operator + LLM over the project's lifetime | `/brain init` is **re-runnable** — it updates the *managed region* (delimited by `<!-- codebrain:begin -->` / `<!-- codebrain:end -->`) without destroying any human edits inside or outside that region. The operator can edit conventions inside the managed region and re-running init preserves their changes (template-merge, not template-replace). |

This three-layer design is the load-bearing differentiator vs. just "another agent skill that writes some markdown files": **the source remains the source of truth** (no drift risk like a duplicated codebase), the wiki **compounds across sessions** (knowledge isn't re-derived per query), and the schema **adapts to the project** (conventions for a Next.js monorepo differ from a Rust crate).

## Success Metrics
| Metric | Target | How measured |
|---|---|---|
| Token reduction on structural questions | ≥ 50% vs. grep+read baseline | Manual A/B on 10 canned questions across 3 sample repos (small/medium/large) |
| Stale-page detection accuracy | ≥ 95% | Edit N tracked files in a fixture repo, verify N stale flags raised by the hook |
| Wiki freshness drift | < 5% of pages stale after one week of typical agent work | Lint pass counts on a dogfood repo |
| Time-to-first-value | < 5 min from `npx codebrain init` to first useful wiki page | Wall-clock during onboarding test on a fresh machine |
| Wikilink precision | ≥ 90% — wikilinks resolve to real pages and reference real relationships | Sample 100 wikilinks from a dogfood ingest, manually verify |
| Continuous-learning lift | TBD — needs validation via dogfooding | Compare agent answer quality before/after a week of instinct accumulation on the same repo |

## Design Decisions (Resolved)

These were debated as open questions and are now locked into the MVP:

| # | Decision | Rationale |
|---|---|---|
| 1 | Vault directory name: **`.brain/`** | Short, reads well in paths, matches product name |
| 2 | Ingest default: **tiered auto-prioritize** | `/brain ingest <path>` is the documented common case; `/brain ingest` with no args proposes a 3-tier plan (e.g., `src/` first, `tests/` last) and pauses for operator OK between tiers — prevents the "I ran ingest and spent $40" foot-gun |
| 3 | `.brain/` is **committed by default** | LLM-Wiki "compounding artifact" property requires version history + team sharing; PR-noise concern is solved by the hook keeping wiki edits bundled with code edits in the same commit. Opt-out via `/brain init --private` |
| 4 | Continuous-learning observer: **auto-on with first-run disclosure** | Passive accumulation is the whole value; disclosure-on-first-use is the standard responsible default. Narrow scope by design — only tool-calls on tracked source files + prompts naming codebase symbols, NOT every Read/Bash/WebFetch |
| 5 | Deterministic AST fallback: **none, ever** | All extraction is LLM-driven inside the harness; if wikilink precision is low, fix is better prompts / multi-pass / a wikilink-resolver agent — not an external extractor |
| 6 | License: **MIT** | Matches graphify/graphbrain/ECC; lowest friction for the primary user; no realistic SaaS-capture risk for an npm-distributed tool that runs inside the operator's harness |
| 7 | Page-size caps (per type, soft warn / hard error): **`code/` 4k / 8k · `concepts/` 6k / 12k · single-file pages 4k / 8k** | Per-type caps preserve agent-readability; pages that hit hard limits get split or summarized to a child |
| 8 | Slash commands: **`/brain *`** primary, `/codebrain *` registered as an alias | Short, matches `.brain/` directory; alias keeps unambiguous form for tab-complete |
| 9 | Cross-cutting pages: **renamed `wiki/` → `concepts/`** | "Wiki" is overloaded; "concepts" says exactly what's in there for a code context |
| 10 | Staleness model: **4-tier, all in MVP** | (a) wikilink reverse-lookup via PostToolUse hook — free, deterministic; (b) optional `sources:` frontmatter for pages observing patterns across files they don't directly link; (c) `/brain lint` contradiction-check — second line for subtle drift; (d) query-time refresh — `query` checks freshness before reading, triggers re-ingest if STALE. Staleness *propagates* through wikilinks, freshness is *opportunistic*. |
| 11 | Additional scaffolded files (from graphbrain prior art): **`decisions.md` + `decisions/` ADRs, `overview.md`, `status.md` (derived view)** | ADRs are the highest-ROI invisible-from-source artifact; overview is the agent's first-read digest; status is a fast-scan view regenerated from per-page frontmatter (single source of truth = the frontmatter) |
| 12 | **Source immutability contract** — the brain layer never modifies source code; source changes happen via the operator's normal agent workflow, and the PostToolUse hook reacts | Prevents drift between source and wiki; the wiki is always a *derived* view, never a *parallel* one |
| 13 | **Schema co-evolution via managed region** — `init` is re-runnable; operator-edited conventions inside the managed region survive re-runs | The schema is meant to adapt as the project's domain stabilizes (the original LLM-Wiki insight: "you and the LLM co-evolve [the schema] over time") |
| 14 | **Dataview-compatible YAML frontmatter on every page** | Operators get Obsidian Dataview queries (`status:: STALE`, `kind:: code`) for free; gives them a code-aware dashboard inside the editor they're already using |
| 15 | **Grep-parseable log prefix** — `## [YYYY-MM-DD] <op> | <subject>` | `grep "^## \[" .brain/log.md \| tail -10` produces a clean timeline from any shell; the operator never needs a CLI tool for log inspection |
| 16 | **Agent execution model: foreground-first slash commands + trigger_phrases; background spawn only for read-only observers** | Foreground writes are auditable and transactional with git (graphbrain pattern). Background spawning (ECC continuous-learning pattern) is reserved for the observer agent which only reads; all `.brain/`-writing agents run synchronously in the same session as the operator. |
| 17 | **Agent file format: ECC base (`name`, `description`, `tools`, `model`) + graphbrain additions (`pattern`, `trigger_phrases`, `max_iterations`)**; agents live at `agents/<category>/<name>.md` (categories: `brain/`, `observers/`) | ECC's flat `agents/*.md` doesn't scale past ~30 agents; graphbrain's category hierarchy gives stable install tiers. The merged frontmatter keeps ECC's tool/model contract while gaining graphbrain's natural-language activation and loop-prevention. |
| 18 | **Agent registry: explicit `agents/registry.json`** declaring per-agent `tier` (`core` \| `community`), `install` mode (`always` \| `manual`), `version` | Filesystem-only discovery (ECC's choice) means no controlled install order, no stability tiers, no deprecation path. graphbrain's registry pattern is the precondition for an agent ecosystem that grows past the initial set. |
| 19 | **Dual-layer guardrails: PreToolUse hook (structural blocks) + self-enforcing rules in each agent body (semantic blocks)** — adopt graphbrain's status-based protection (block writes to pages with `status: VERIFIED`) | ECC's hook-only guardrails (GateGuard) catch destructive actions but miss semantic mistakes ("agent guessed at code behavior"). graphbrain's dual-layer catches both. The PreToolUse hook lands in Milestone #4 (beside the staleness hook); per-agent self-rules land per agent. |
| 20 | **Prompt Defense Baseline: vendored from ECC into the `## codebrain` CLAUDE.md schema block; agents reference it (don't re-copy) via "Read `.brain/protocol.md` for the prompt defense baseline" instruction** | ECC's prompt-defense block is duplicated across 60+ agent files (drift risk). graphbrain's runtime-read pattern is cleaner. Codebrain stores once, references everywhere. |
| 21 | **Skills tier model: `skills/{behavioral,ingestion,core,detected,available}/`** (graphbrain pattern) — *not* a flat `skills/*/` list | ECC's 232 flat skills make install scope, deprecation, and "what gets loaded by default" impossible to reason about. graphbrain's tiers give every skill a clear lifecycle: `behavioral` always loaded, `ingestion` loaded during `/brain ingest`, `core` always available, `detected` auto-installed by stack detection, `available` opt-in. Codebrain ships only a handful of skills — but seeds the structure from day one so it scales without restructuring. |
| 22 | **Tech-stack auto-detection via `skills/registry.json`** — each skill declares `detect: [{ file_exists, contains, glob }]` rules; `/brain init` scans the repo and auto-installs matching `detected/` skills | Without detection, every project gets the same generic concept templates. With detection, a Next.js repo auto-loads React-specific code-page conventions, a Python repo loads module/package conventions, etc. The quality of LLM ingest is bounded by the templates it has — detection is the cheapest way to make ingest meaningfully better per stack. |
| 23 | **Page templates vendored from graphbrain + extended**: `skills/ingestion/templates/{code-page,concept-page,decision-page,glossary-page}.md` plus the SDLC set (ADR, component, runbook, postmortem, checklist) | LLM ingest with a template produces consistent pages with required frontmatter, status fields, and section structure. Without templates, every ingest call rederives the format → lint catches drift but pages have already drifted. Templates are the lowest-cost, highest-impact quality lever for Milestone #3. |
| 24 | **Environment gates: `CODEBRAIN_PROFILE` (`minimal`\|`standard`\|`full`) + `CODEBRAIN_DISABLED_HOOKS` (comma-separated hook IDs)** — wrapper script gates every hook | ECC's `ECC_HOOK_PROFILE` + `ECC_DISABLED_HOOKS` pattern lets operators (and CI) scale codebrain's surface without code changes. Critical for cost-sensitive users who want, e.g., observer-off in PR-check sessions. |
| 25 | **`/brain lint` is read-only by default; `/brain lint --fix` opts into batch re-ingest of STALE pages** — *not* a separate `/brain sync` skill | Read-only lint stays safe to invoke from anywhere (CI, hooks, pre-commit, cron). The 4-tier staleness model (Design Decision #10) already self-heals per-page at query time; `--fix` is purely the batch operation when an operator wants to refresh everything before a coding session. Single verb, mode flag preserves safety. |
| 26 | **Error recovery (every codebrain agent): Tier 1 retry once → Tier 2 escalate to operator with structured "blocked" report** | graphbrain's full 4-tier model (retry → reflect → kill+report → escalate) is expensive at codebrain's scale. The "reflect" tier (ask the agent why it failed) can chew through tokens. Codebrain: retry once, then surface a "blocked: agent couldn't complete X because Y; operator action: Z" message. Documented in `agents/README.md` so every shipped agent follows the same pattern. |
| 27 | **E2E shell test from Milestone #1**: `tests/e2e-test.sh` runs `npx codebrain init` in a tmpdir and asserts `.brain/` scaffold, `.claude/commands/brain.md` written, settings.local.json hooks merged correctly | graphbrain's `tests/e2e-test.sh` is the right shape — fast, no LLM calls, deterministic. Codebrain ships this from M#1 so onboarding validation is automatable and every milestone-completion gate runs it. |
| 28 | **Distribution: npm package** (`npx codebrain init` or `npm install -g codebrain`) — **not** a Claude Code plugin | npm is the "normal" install path developers expect; graphbrain proves the model works for harness-config tooling. Plugin packaging may revisit post-MVP if there's discovery demand, but it's not a precondition for shipping. |
| 29 | **No `.claude-plugin/` directory**: no `plugin.json`, no `marketplace.json`, no vendored `PLUGIN_SCHEMA_NOTES.md` | We're not a plugin, so the strict plugin-manifest constraints don't apply. The knowledge in PLUGIN_SCHEMA_NOTES *about command/hook format* is still relevant for what the init script writes; vendored as `reference/claude-code-conventions.md` instead. |
| 30 | **OSS hygiene baseline deferred** — no CI, no SECURITY.md, no CONTRIBUTING.md, no CODE_OF_CONDUCT.md, no CHANGELOG.md, no `.github/` issue/PR templates in M#1 | Ship the code, README, LICENSE. Defer the bureaucratic surface until there's traction warranting it. Mirrors graphbrain's posture (which has no `.github/` at all). |
| 31 | **Install target default: project-local** (`<cwd>/.claude/commands/`, `<cwd>/.claude/settings.local.json`); `--global` flag opts into `~/.claude/` for cross-repo availability | Project-local matches the "this codebase's brain" mental model; explicit per-project consent for agent observation (Design Decision #4); aligns with the committed-by-default `.brain/` (Design Decision #3). The vault `.brain/` is always repo-local; only the slash commands + hooks have a global-vs-local choice. |
| 32 | **Hooks ownership via `id:` prefix** — codebrain owns only entries in `settings.local.json` whose `id` starts with `codebrain:` (e.g., `codebrain:pre:edit-write:stale-detect`). Merge preserves all non-codebrain entries unchanged; re-init replaces codebrain-prefixed entries in place (no duplicates); future `codebrain uninstall` removes only codebrain-prefixed entries. | Settings.local.json's hooks structure is `{ hooks: { PreToolUse: [...] } }` — there's no namespace key we can write under. Without a stable ownership marker, init can't tell its own entries from user/ECC/other-tool entries, can't safely upgrade, and can't safely uninstall. `id:` prefix is the canonical pattern (ECC uses `ecc:`, others use their own). |
| 33 | **`.brain/.codebrain-version` marker file shipped from M#1** — one line containing the codebrain version that scaffolded the repo (e.g., `0.1.0`). Updated only by `codebrain init` itself. | Without a version marker, a future codebrain release can't tell v0.1 state apart from v0.3 state without heuristics. Marker file is the cheap enabler that makes any future migration possible. Costs almost nothing; defers the migration script itself to post-MVP. |

## Scope

**MVP** — An **npm package** that, on `npx codebrain init` (project-local by default; `--global` for `~/.claude/`), scaffolds `.brain/` in the cwd, writes `/brain` slash commands into `.claude/commands/`, and merges codebrain hooks into `.claude/settings.local.json`. After init: no bash scripts the user runs, no setup wizard, no external extractor — every operation is `/brain *` slash commands directed by LLM agents inside Claude Code.

### Vault layout (scaffolded by `init`)
```
<repo>/
├── .brain/
│   ├── code/                  # 1:1 mirror of source tree (one .md per significant source file)
│   ├── concepts/              # cross-cutting pages (auth-flow.md, entities/tenant.md, integrations/stripe.md, glossary.md, etc.)
│   ├── decisions/             # per-decision ADR files
│   ├── overview.md            # Project Purpose / Codebase Structure / Key Patterns / Active State / Recent Activity
│   ├── index.md               # page catalog with one-line summaries
│   ├── log.md                 # Recent Patterns (semantic, consolidated) + Activity History (episodic, append-only)
│   ├── decisions.md           # Active + Superseded ADR summary index
│   └── status.md              # derived lifecycle view (Page | Status | Last Sync | Source Hash)
└── CLAUDE.md                  # gets a `## codebrain` schema block (managed region) appended
```

### Page frontmatter (Dataview-compatible)

Every page in `.brain/` carries YAML frontmatter so Obsidian + Dataview queries work out of the box (`status:: STALE`, `kind:: code`, etc.):

```yaml
---
kind: code          # code | concept | decision | overview | index | log | status
status: FRESH       # UNENRICHED | FRESH | STALE | RESYNCED | VERIFIED
source: src/api/auth.ts          # for kind: code — path to mirrored source file
source_hash: a1b2c3d              # git hash of source at last ingest (for stale detection)
sources:             # for kind: concept — optional explicit dependency list
  - src/middleware.ts
  - src/lib/auth.ts
last_ingested: 2026-05-24
ingested_by: claude-sonnet-4-6
tokens: 1842
---
```

### Log conventions

`.brain/log.md` uses a consistent entry prefix so it's grep-parseable from any shell:

```
## [YYYY-MM-DD] <op> | <subject>
```

Where `<op>` is one of `ingest | query | lint | refresh | learn | promote`. Example: `## [2026-05-24] ingest | src/api/auth.ts` lets `grep "^## \[" .brain/log.md | tail -10` produce a clean timeline.

### Skills (agent-invoked, no user CLI)
1. **`init`** — Scaffolds `.brain/`, writes the `## codebrain` schema block to `CLAUDE.md` inside a managed region (`<!-- codebrain:begin -->` / `<!-- codebrain:end -->`). **Re-runnable**: subsequent runs update only the managed region's *template-driven* sections; operator edits inside the managed region (e.g., project-specific conventions) and outside it are preserved (template-merge, not template-replace). Opt-out: `--private` flag adds `.brain/` to `.gitignore`.
2. **`ingest`** — Reads source files, writes LLM-authored pages mirroring folder structure (`src/api/auth.ts` → `.brain/code/src/api/auth.ts.md`); creates concept pages in `.brain/concepts/` for cross-cutting ideas; wires bidirectional wikilinks; updates `index.md`, `log.md`, `status.md`. **Tiered auto-prioritize** when no args (proposes 3-tier plan, pauses between tiers); single-folder when path given.
3. **`query`** — Pointer-first lookup. Reads `index.md` → identifies candidate pages → checks freshness → **if STALE, triggers `ingest --refresh <page>` before reading** → answers with citations to `.brain/` pages and source files. Good answers can be filed back into `.brain/concepts/` as new pages.
4. **`lint`** — Framed as wiki *health-check*, not just defect-finder. **Read-only by default; `/brain lint --fix` opts into batch re-ingest of STALE pages** (Design Decision #25). Reports:
   - **Defects** — stale pages (frontmatter STALE), broken wikilinks, page-size violations, schema-vs-skills coherence drift.
   - **Gaps** — important concepts mentioned across multiple pages but lacking their own page; data thin spots (pages with only a stub/TBD); files in `code/` with no inbound wikilinks (orphans).
   - **Contradictions** — claims across pages that conflict (LLM-driven contradiction-check tier).
   - **Suggested questions** — "places where ingesting deeper or asking the operator would enrich the brain" — the lint's *forward-looking* output. Operator-facing prompts the agent can offer to investigate.
5. **`learn {on|off|status}`** — Observer toggle, stored in project state. Auto-on after `init`; first-run disclosure surfaces the off command.
6. **`status`** — Dashboard view: total pages, % stale, recent log entries, top instincts.

### Hooks (harness-native, agent invisible)
1. **`PostToolUse` on Edit/Write/MultiEdit** — When a tracked source file is edited:
   - Flip `.brain/code/<path>.md` frontmatter to `status: STALE`, record source git hash.
   - Walk wikilinks: find all `.brain/**/*.md` containing `[[code/<edited-path>]]` or matching `sources:` frontmatter → mark those STALE too (wikilink reverse-lookup).
   - Update `status.md` derived view.
2. **`PostToolUse` on Bash for `mv`/`git mv`** — Detect rename → queue a refresh of the moved file's page + wikilink rewriting.
3. **`PreToolUse` observer (continuous-learning)** — Narrow scope: only captures Edit/Read on tracked source files + UserPrompt tokens matching codebase symbols. Async, ≤10s timeout, exits 0 on error (never blocks tool execution). Writes to `~/.local/share/codebrain/projects/<hash>/observations.jsonl`.

### Continuous-learning model (reuses ECC v2.1)
- **Atomic instincts** — small behaviors with confidence scores (0.3–0.9).
- **Project-scoped** by default at `~/.local/share/codebrain/projects/<git-remote-hash>/instincts/personal/`.
- **Codebase-specific signal** — observations of "auth tokens are validated in middleware.ts, not in route handlers" become candidate instincts; the observer-extractor agent (Haiku) periodically converts observations → instincts.
- **Promotion pipeline** — instincts seen in N≥2 projects with avg confidence ≥0.8 become candidates for `~/.local/share/codebrain/instincts/global/`.
- **Human-readable mirror** — episodic observations land in `.brain/log.md` Activity History; consolidated patterns surface in Recent Patterns (operator visibility, builds trust, allows pruning).

### Page-size caps (enforced by ingest + lint)
- `.brain/code/**/*.md` → **4k soft / 8k hard**
- `.brain/concepts/**/*.md` → **6k soft / 12k hard**
- `.brain/{overview,index,log,decisions,status}.md` → **4k soft / 8k hard**
- `log.md` Activity History auto-archives entries to `.brain/archive/logs/<YYYY-MM>.md` when log exceeds 4k (graphbrain's `consolidate-log.sh` pattern, ported to skill).

**Out of scope** (deferred to post-MVP, in priority order if revisited):
- AST-based deterministic extraction for 31 languages (graphify's `extract.py`) — pure LLM is the locked-in bet.
- Cluster/community/god-node analysis + `graph.html` + `graph.json` exports — Obsidian's graph view is the visualization.
- `routing.md` keyword index — `index.md` + LLM-driven query likely sufficient; add if query is too slow.
- `patterns.md` cross-cutting synthesis — needs a `brain-synthesizer` agent; post-MVP.
- PDF / image / video / Office / Google Workspace / SCIP ingestion.
- GitHub PR analysis, Mermaid callflow diagrams, Neo4j export, MCP graph server for external queries.
- Non-Claude-Code harnesses (Cursor, Codex, Gemini, OpenCode multi-target installer) — ship Claude Code first, port if traction.
- Cross-project federation / global codebase graph (`global_graph.py`).
- The other ~230 ECC skills — codebrain borrows only the harness primitives (skill format, command frontmatter shape, hook entry shape, continuous-learning-v2 core) from ECC's reference implementation.
- Automatic ingest on `SessionStart` — MVP keeps ingest agent-explicit so the operator stays in control of cost.
- Slack/meeting/external-source ingestion (the LLM-Wiki business-team example).

## Delivery Milestones

<!-- Business outcomes, not engineering tasks. /plan turns each into a plan. -->

| # | Milestone | Outcome | Status | Plan |
|---|---|---|---|---|
| 1 | npm package skeleton + init | `npx codebrain init` scaffolds `.brain/` in cwd, writes `/brain` + `/codebrain` slash commands into `.claude/commands/`, merges codebrain hooks block into `.claude/settings.local.json` — project-local by default; `--global` for `~/.claude/`; `--force` overrides; idempotent on repeat | complete | [.claude/plans/codebrain.plan.md](.claude/plans/codebrain.plan.md) |
| 2 | Init + schema scaffolding | `/brain init` creates full `.brain/` layout (code/, concepts/, decisions/, overview.md, index.md, log.md, decisions.md, status.md); appends `## codebrain` schema block to CLAUDE.md; idempotent | complete | [.claude/plans/codebrain-m2.plan.md](.claude/plans/codebrain-m2.plan.md) |
| 3a | Ingest pipeline — single-file end-to-end | `/brain ingest <single-file-path>` invokes the ingester agent which writes `.brain/code/<path>.md` using the page-format template; updates index/status/log; idempotent on unchanged source | complete | [.claude/plans/codebrain-m3a.plan.md](.claude/plans/codebrain-m3a.plan.md) |
| 3b | Ingest pipeline — folder + concept pages + linker | `/brain ingest <folder>` walks the folder, ingests each file via the M#3a ingester; linker agent creates concept pages for cross-cutting ideas and wires bidirectional wikilinks | complete | [.claude/plans/codebrain-m3b.plan.md](.claude/plans/codebrain-m3b.plan.md) |
| 3c | Ingest pipeline — tiered auto-prioritize | `/brain ingest` (no args) invokes the planner agent: reads cached stack detection, groups files into 3 tiers using generic globs, presents the plan with per-tier cost estimates, gates each tier (yes/no/show-files/cancel/--yes), delegates each confirmed tier to the M#3b folder procedure; linker runs after each tier for incremental visibility | complete | [.claude/plans/codebrain-m3c.plan.md](.claude/plans/codebrain-m3c.plan.md) |
| 3d | Ingest pipeline — stack-aware page templates (detected/* skills) | 4 detected/* skills (react, python, go, typescript) ship with per-stack code-page extras using an INHERITANCE pattern (extras append AFTER the generic 5 sections — never replace). Ingester picks matching skill when project's detected stack + source file's extension both match; multiple skills can apply per file (e.g., `.tsx` in React+TS gets TypeScript extras + React extras in registry order). registry.json populated. Stack-aware tier-glob overrides for M#3c deferred to future polish per sweep finding E7. | complete | [.claude/plans/codebrain-m3d.plan.md](.claude/plans/codebrain-m3d.plan.md) |
| 4 | Staleness model — tiers 1+2 (PostToolUse hook + PreToolUse verified-guard) | PostToolUse `codebrain hook stale-detect` flips `.brain/code/<edited>.md` to STALE; walks all `.brain/**/*.md` to find wikilinks AND `sources:` array references; flips matching pages STALE too. PreToolUse `codebrain hook verified-guard` blocks writes to `status: VERIFIED` pages without `--force` (structural layer of dual-layer guardrail, PRD #19). Tier 3 (lint contradiction-check) lands in M#6; tier 4 (query-time refresh) lands in M#5. | complete | [.claude/plans/codebrain-m4.plan.md](.claude/plans/codebrain-m4.plan.md) |
| 5 | Query helper | `/brain query "..."` pointer-first: index → 1–3 pages → cite source; auto-refresh on STALE hit; A/B baseline against grep+read established on one fixture repo | pending | — |
| 6 | Lint pass | `/brain lint` reports stale, broken wikilinks, orphans, missing concepts, contradictions, page-size violations, schema coherence | pending | — |
| 7 | Continuous-learning observer | Auto-on with first-run disclosure; narrow-scope observer writes to XDG; observation→instinct extraction; `/brain status` + `.brain/log.md` show what was learned; project-scoped with promotion candidate detection | pending | — |
| 8 | Dogfood + measure | Install on 3 repos (codebrain itself + 2 OSS targets, small/medium/large); run hypothesis tests; capture token Δ, freshness drift, wikilink precision, time-to-first-value; write validation report | pending | — |

## Open Questions

All Q1–Q8 from the design pass resolved (see "Design Decisions"). Remaining genuinely-open items:

- [ ] **Promotion threshold tuning** — N=2 projects + avg confidence ≥0.8 inherited from ECC; may need adjustment once dogfood instincts accumulate.
- [ ] **Concepts/ taxonomy** — Should we ship a default convention (`concepts/auth-flow.md`, `concepts/entities/<name>.md`, `concepts/integrations/<name>.md`, `concepts/glossary.md`) or let each project's ingest discover its own structure? Lean ship-defaults-as-suggestions in the schema block.
- [ ] **Multi-file rename detection** — `git mv` is detectable; refactor-style multi-file renames (e.g., moving a directory tree) may need a separate skill. Defer to Milestone 4 implementation.
- [ ] **First-run disclosure UX** — Where exactly does the observer's first-run notice surface? In the agent's first response post-init? As a hook-emitted message? Defer to Milestone 7.

## Risks
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Wiki goes stale faster than agent refreshes in active dev | High | Med | 4-tier staleness model: PostToolUse hook + wikilink reverse-lookup + lint contradiction-check + query-time refresh |
| LLM ingest cost too high for large codebases | Med | High | Per-page token caps; tiered auto-prioritize ingest with operator OK between tiers; model routing (Haiku for file summaries, Sonnet for synthesis); semantic cache on file-hash |
| Wikilinks rot when files move/rename | Med | Med | PostToolUse hook detects `mv`/`git mv`; lint catches the rest; rename-refresh queued as work item |
| Overlap with ECC's continuous-learning-v2 creates two competing instinct stores if user installs both | Med | Med | Codebrain instincts in their own XDG namespace under `codebrain/`; document interop; long-term factor v2 core out so both consume it |
| `codebrain init` corrupts existing `.claude/settings.local.json` when merging the hooks block | Med | High | Init script does JSON-aware merge (not text concat); preserves existing hooks; idempotent (re-running with same input is a no-op); always writes a `.bak` before edit; `--force` is the only path that overwrites |
| User runs `codebrain init` outside a project directory and pollutes `~` | Low | Med | Init detects cwd; if no git root + no package.json + no pyproject.toml, refuses with explicit error; `--global` is the only path that writes to `~/.claude/` |
| LLM-only ingest produces lower-precision wikilinks than AST extraction (no fallback by design) | Med | Med | Wikilink precision is a tracked Success Metric (≥90%); remediation is prompt/multi-pass improvement, not external extractor |
| Project reads as "graphbrain with a folder-mirror tweak" — insufficient differentiation | Low | Med | Differentiators: codebase-as-source (vs. docs), strict folder-mirror, ECC continuous-learning loop, 4-tier staleness model, opinionated agent-readability conventions, dual-layer guardrails |
| Schema (`CLAUDE.md` block) drifts from skill behavior over time | Low | Med | Lint skill includes "schema-vs-skills coherence" check; CI test asserts the block matches the shipped skills |
| Committed `.brain/` produces noisy PRs | Med | Low | Hook keeps wiki edits in the same commit as code edits → reviewers see them together, not as a separate diff; CODEOWNERS pattern + auto-approve recipe documented |

---
*Status: DESIGN-LOCKED — 8 open questions resolved; ready for `/plan .claude/prds/codebrain.prd.md` on Milestone #1.*
