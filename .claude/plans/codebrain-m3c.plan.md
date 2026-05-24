# Plan: codebrain — Milestone #3c (Tiered auto-prioritize + detected/* skills)

**Source PRD**: `.claude/prds/codebrain.prd.md`
**Selected Milestone**: #3c — third and final sub-step of the 3-way split of original M#3
**Complexity**: Large — biggest M#3 sub-milestone; ships 4+ new detected skills, the tiered ingest planner, and stack-aware templates
**Status**: **DRAFT** — will be heavily refined after M#3a + M#3b ship. The detected/* skill content depends on what we learn from dogfooding on real React/Python/Go/TypeScript repos.

## Summary

Final M#3 sub-milestone. Two big additions: (1) `/brain ingest` with no args invokes a **tiered auto-prioritize planner** that uses M#2's stack detection to propose a 3-tier ingest plan (e.g., Tier 1: `src/` core, Tier 2: `src/api/`, Tier 3: `tests/`), pauses between tiers for operator OK. (2) The **`detected/*` skills** finally ship — `detected/react`, `detected/python`, `detected/go`, `detected/typescript` — each providing stack-aware page templates (e.g., React component pages get a "Hooks" section; Python module pages get "Public API" + "Dunder methods"; Go pages get "Package + Exports" structure) that override the generic code-page template from M#3a.

This is also when M#2's stack detection actually starts installing things (M#2 only reported; M#3c acts).

## Patterns to Mirror (provisional — heavy refinement after M#3a/b)

| Category | Source | Pattern |
|---|---|---|
| Tiered procedure with operator gating | (no prior art; M#3c establishes this) | Print the tier plan as a table; ask operator `Proceed with Tier 1? (yes/no/show-plan)`; repeat per tier |
| Stack detection consumption | `skills/core/init/templates/stack-detection.json` (M#2) | Read matched stacks; for each, install the corresponding `detected/<stack>/` skill if it ships |
| Stack-aware template override | `skills/ingestion/page-format/templates/code-page.md` (M#3a base) | Per-stack template lives in `skills/detected/<stack>/templates/code-page-<stack>.md`; ingester picks the override when matching stack is installed AND source-file extension matches |
| Per-stack ingestion conventions | `skills/ingestion/page-format/SKILL.md` (M#3a) | Each `detected/*/SKILL.md` describes the per-stack page structure rationale |

## Files to Change (provisional)

| File | Action | Why |
|---|---|---|
| `skills/detected/react/SKILL.md` | CREATE | React-aware page conventions: Hooks section, Props/State, Component hierarchy, Effects |
| `skills/detected/react/templates/code-page-react.md` | CREATE | Verbatim template for `.tsx`/`.jsx` files when a React project is detected |
| `skills/detected/python/SKILL.md` | CREATE | Python: Public API, Dunder methods, Decorators, Type hints |
| `skills/detected/python/templates/code-page-python.md` | CREATE | Verbatim template for `.py` files |
| `skills/detected/go/SKILL.md` | CREATE | Go: Package, Exports, Receivers, Interfaces, Init functions |
| `skills/detected/go/templates/code-page-go.md` | CREATE | Verbatim template for `.go` files |
| `skills/detected/typescript/SKILL.md` | CREATE | TypeScript: Types/Interfaces, Exports (named/default), Decorators, Module declarations |
| `skills/detected/typescript/templates/code-page-typescript.md` | CREATE | Verbatim template for `.ts`/`.tsx` files |
| `skills/registry.json` | UPDATE | Add entries for the 4 detected skills with their `detect:` rules (mirror what M#2's stack-detection.json already names) |
| `commands/brain.md` | UPDATE | Replace M#3c stub on no-arg `ingest`. Procedure: detect → group source paths into 3 tiers (heuristic) → present plan → for each tier, ask operator OK → invoke M#3b folder-ingest on each tier scope |
| `commands/codebrain.md` | UPDATE | Alias parity |
| `tests/e2e-test.sh` | UPDATE | T18 (detected/* skill structural assertions); T19 (no-arg ingest wired; tiered plan output format); T20 (stack-aware template selection — verify the ingester picks the right template for a `.tsx` source in a React project — fixture-driven) |
| `.claude/prds/codebrain.prd.md` | UPDATE | M#3c row → in-progress with link |

## Tasks (provisional)

1. **`skills/detected/react/SKILL.md` + template** — Describes when activated (React detected by M#2 stack-detection.json), what sections the React-aware code page must have (Component, Props, State, Hooks, Effects, Children), and how the ingester picks this over the generic template (extension match on `.tsx`/`.jsx`).

2. **`skills/detected/python/SKILL.md` + template** — Python-aware structure: module-level Public API, Classes (with Public methods / Dunder methods / Private), top-level Functions, Decorators used, Type hints summary.

3. **`skills/detected/go/SKILL.md` + template** — Go-aware: Package declaration, Exports (uppercase symbols), Receivers, Interfaces satisfied, init() functions, build tags.

4. **`skills/detected/typescript/SKILL.md` + template** — TS-aware: Types vs Interfaces vs Classes, Exports (named/default/re-export), Module declarations, generics summary.

5. **`skills/registry.json` update** — Add 4 entries with `detect:` rules. Mirror what `skills/core/init/templates/stack-detection.json` (M#2) already names. This activates `/brain init`'s detection-then-install behavior (M#2 only reported; M#3c now installs).

6. **Update `commands/brain.md`** — Replace M#3c stub on no-arg `ingest`. Procedure:
   - **Step 0**: read M#2 stack detection results from `.brain/overview.md` (or re-run detection)
   - **Step 1**: read repo file tree (respect `.gitignore`)
   - **Step 2**: heuristic tier assignment:
     - Tier 1: source code in primary stack's conventional directories (`src/`, `lib/`, `app/`, `pkg/`)
     - Tier 2: secondary code (`api/`, `services/`, top-level `*.ts`/`*.py`/`*.go`)
     - Tier 3: tests, scripts, docs (`tests/`, `__tests__/`, `scripts/`, `docs/`)
   - **Step 3**: print the tier plan as a 3-line summary with file counts per tier
   - **Step 4–6**: for each tier, ask operator (`Proceed with Tier 1 (N files)? yes/skip/show-files`); if yes, invoke M#3b folder-ingest on the tier's paths; if skip, skip the tier; if show-files, print and re-prompt
   - **Step 7**: final report — files ingested per tier; concept pages created; total token cost estimate

7. **Update `commands/codebrain.md`** — alias parity for no-arg section.

8. **Update `tests/e2e-test.sh`** — T18 (4 detected/* skills + templates ship); T19 (no-arg verb wired; tier-plan output format matches spec); T20 (stack-aware template selection: a fixture repo with `package.json` + `react` dep + a `.tsx` file gets the React template when M#3b ingester runs).

9. **PRD update** — M#3c row → in-progress with link.

## Sweep Findings (folded into Tasks above)

Four findings from the post-draft sweep + two architectural questions worth flagging before M#3a ships (because the answer may affect M#3a's design):

- **C1 — Per-stack tier-glob patterns live in each `detected/<stack>/SKILL.md`**: rather than baking heuristics into `commands/brain.md`, each detected skill declares its tier-globs in frontmatter (`tier_globs: { tier1: ["src/**"], tier2: ["api/**"], tier3: ["tests/**"] }`). The no-arg ingest procedure reads all installed detected skills and merges. Keeps `commands/brain.md` small + lets per-stack knowledge stay with the stack.
- **C2 — Stack templates INHERIT the generic code-page template, don't duplicate**: each `detected/<stack>/templates/code-page-<stack>.md` declares ONLY the stack-specific sections (e.g., React's "Hooks", "Effects"); the ingester first renders the M#3a generic template, then appends the stack-specific sections from the matched detected template. Prevents template drift.
- **C3 — Linker invocation strategy across tiers**: linker runs **after each tier** (not once at end), so the operator sees concept-page updates incrementally and can abort between tiers if results look wrong. Cost is higher (linker runs 3x instead of 1x) but the visibility win is large for a no-arg ingest the operator can't preview.
- **C4 — README + CLAUDE.md need a 3-step onboarding update**: post-M#3c the operator flow is `npx codebrain init` → `/brain init` → `/brain ingest` (3 steps, two surfaces). Both README and the codebrain-internal CLAUDE.md need updating to make this explicit. Task to be added during M#3c implementation.

**Two architectural questions raised by sweep (may impact M#3a's design — worth answering BEFORE M#3a ships):**

- **Q1 — Template discovery from npm-installed location** (carried over from M#3a sweep): `commands/brain.md` can't read multiple `detected/<stack>/SKILL.md` files at runtime without knowing the install path. M#3a already chose to **inline the template content in the command body**. M#3c may need the same — inline a registry of detected-skill metadata into `commands/brain.md`, OR have `scripts/init.js` write a consolidated `.brain/.detected-skills.json` at npm install time. Lean: revisit after M#3a proves the inline-in-command-body pattern works.
- **Q2 — Operator escape from too-expensive tiered ingest mid-tier**: currently Ctrl-C kills the session; nothing graceful. Per-tier gating is good but doesn't help mid-tier. Possible: detect operator input during long-running ingest and bail; or chunk per-tier into per-file with confirm after each (too noisy); or just document Ctrl-C as the escape. Lean: document Ctrl-C for v0.1; better cancellation post-MVP.

## Open Questions to Resolve After M#3a/b Ship

- **Heuristic tier assignment**: covered by C1 above. Per-stack glob patterns in `detected/<stack>/SKILL.md` frontmatter.
- **What if no stack is detected**: default to generic ingest of `src/` if it exists, else current directory's top-level. Or refuse + ask the operator to pass a path.
- **Cost ceiling**: if Tier 1 alone is >50 files, do we sub-tier it? Lean: include a `Tier 1 has 78 files (estimated $X). Sub-divide? (yes/no)` prompt.
- **Operator interrupt mid-tier**: if Ctrl-C during a tier, do we resume? Probably not — operator re-runs.
- **Stack-aware template selection precedence**: if a `.ts` file is in a `tests/` dir, do we use the TS template or a "test file" template? Lean: TS template for now; specialized test-file template is post-MVP.
- **Multi-stack repos** (e.g., a TS monorepo with a Python script): each file picks the template matching its extension; whole-folder ingest may apply multiple templates per file batch.

## Risks (provisional)

| Risk | Likelihood | Mitigation |
|---|---|---|
| Tiered planner's heuristic is wrong for unconventional repos | High | Operator can `show-files` per tier and skip if wrong; `--explicit-tiers <tier1-glob>,<tier2-glob>,<tier3-glob>` flag for power users (post-MVP) |
| Token cost of no-arg ingest is alarming | High | Per-tier confirmation gate; cost estimate printed before each tier; SKIP-on-unchanged-source from M#3a keeps re-runs cheap |
| Detected/* skill content is shallow / generic in v0.1 (skill descriptions written without deep stack expertise) | Med | Skill content is markdown — easy to revise; community PRs can extend; the skills are scaffolds, not specs |
| Stack-aware template selection picks wrong template (e.g., a `.ts` config file in a non-React project gets the React template because `.tsx` shares the parser) | Low | Each `detected/<stack>/SKILL.md` declares extension+context matchers; the ingester picks the most-specific match |
| The 3-tier model is too coarse for very large repos | Med | Post-MVP: configurable tier count or `--max-tier <N>` flag; default 3 is enough for repos <500 files |
| Stack detection from M#2 gets out of sync with M#3c's installed skills | Low | Both read `skills/registry.json` as the source of truth; M#3c's update to that file ensures `/brain init` (M#2) sees the new detected/* skills automatically |

## Acceptance Criteria (provisional)

- All 9 tasks complete
- 4 detected/* skills ship, each with their own SKILL.md + per-stack template
- `/brain ingest` (no args) prints a 3-tier plan and gates between tiers
- E2E tests pass (~120 total after T18–T20)
- Manual smoke test: `/brain ingest` on 3 dogfood repos (a Next.js app, a Python FastAPI project, a Go service) produces stack-appropriate code pages without operator intervention beyond tier confirmation

---

**This plan is a sketch — heaviest refinement after M#3a + M#3b ship.** The detected/* skill content in particular will be revised once we've ingested at least one repo per stack and see what page sections matter most. The tier-assignment heuristic is best-guess until we have dogfood evidence.
