# Plan: codebrain — Milestone #10 (Spec-first workflow + intent routing + discovery loop)

**Source PRD**: `.claude/prds/codebrain.prd.md` (v0.2 Roadmap section)
**Selected Milestone**: #10 — Gap C from operator dogfood + agent-readability hardening from external research (see "Evidence base" below)
**Complexity**: Large — now four distinct features (spec verb, discovery loop, intent routing, agent-readability hardening) in one milestone; introduces a new top-level verb (`/brain spec`); behavioral-skill update changes default agent behavior; codifies a multi-iteration pattern (discovery loop) that's currently implicit; adds frontmatter conventions + CHANGELOG + reading-principles behavioral skill
**Status**: DRAFT — most architecturally ambitious v0.2 work; sweep + split into 10a/10b/10c/10d expected before implementation

## Prerequisites (added during v0.2 sweep, 2026-05-28)

M#10 ships into the v0.2 master sequence after two earlier milestones:

1. **M#12 (slash-command namespacing) must ship first.** After M#12, the monolithic `commands/brain.md` is reduced to a help disambiguator; per-verb procedures live in `commands/brain/<verb>.md` and the codebrain alias mirror. **All M#10 file paths and validation greps below assume the post-M#12 layout.** M#10 creates `commands/brain/spec.md` (NEW), not a section in `commands/brain.md`.

2. **M#9-prereq (Tasks 1–3 of M#9 — bridge runtime) must ship first.** M#10's `/brain spec` invokes `ecc:plan-prd` / `ecc:plan` / `ecc:santa-loop` via the runtime probe + activation mechanism defined in M#9-prereq. Without it, M#10 falls back to documentation-only invocation (Bash-shelling at best). See `.claude/plans/codebrain-m9.plan.md` "Sub-split recommendation" for the split rationale.

**v0.2 master ordering**: M#12 → M#9-prereq → **M#10** → M#11 → M#9-coverage. M#10d (agent-readability hardening) is independent of M#10a–c and could ship in any order within M#10; recommend after M#10a so the spec verb is functional first.

## Evidence base (new — May 2026)

Beyond Gap C dogfood, M#10's scope is reinforced by an independent research wiki (`agentctx-idea` — 17 sources / 75+ concepts on agentic engineering as of 2026-05-14). Convergent findings:

| Concept | Source | M#10 sub-milestone supported |
|---|---|---|
| Spec-Driven Development (4-phase gated workflow) | Multiple Osmani articles (2026-01–04); ICSE JAWs 2026 research showing human-authored AGENTS.md cuts runtime 28.64% | M#10a (`/brain spec` verb) |
| Machine-Verifiable Criteria (boolean pass/fail acceptance) | Compound Pipeline pattern, snarktank/compound-product | M#10a (Sp2/Sp3 outputs must be machine-verifiable) |
| Inversion skill pattern (agent interviews operator before acting) | Saboo & Nigam, "5 Agent Skill Design Patterns" (2026-03-17) | M#10c (intent-routing's "do you want spec?" prompt is Inversion) |
| Pink-elephant problem (deprecated patterns in AGENTS.md anchor the model) | Eric Ma's AGENTS.md hierarchy research (2026-03) | M#10d (supersedes/superseded_by frontmatter) |
| Compound learning made visible (append-only changelog of context evolution) | Ryan Carson's Compound Product methodology; Geoffrey Huntley's Ralph loop | M#10d (`.brain/CHANGELOG.md`) |
| Behavioral-constraint skill pattern (Karpathy's four principles, 3-tier always/ask/never boundaries) | Multica AI distillation of Karpathy's coding principles (2026-05-14); Jonathan Vila's MCP architecture guide (2026-03-31) | M#10d (`skills/behavioral/wiki-reading-principles/SKILL.md`) |

M#10d is **new in this plan revision** — bundles three small but high-signal additions that share the thesis "operator-curated conventions beat inferred content," consistent with the Spec-Driven and Behavioral-Constraint research above.

## Summary

The v0.1 build session organically demonstrated three patterns that codebrain doesn't yet enforce:

1. **Spec-first**: every milestone went through `/plan-prd` → PRD → `/plan` → plan → implementation. The operator explicitly asked for this discipline ("if user asks for a new feature describe somethign needs to be added we force user to create a spec first then plan that spec in smaller parts").

2. **Intent routing**: the agent should classify each prompt and route appropriately — feature requests → spec-first flow; questions → query; investigations → ingest more.

3. **Discovery loop**: every "sweep the plan" produced 5–10 new findings (J1-J9, G1-G8, etc.) that made the plan more robust. Operator named this explicitly ("similar to /goal claude command"): iterative convergence where each sweep finds gaps the prior sweep missed.

M#10 ships these as three coordinated features:

- **`/brain spec "<intent>"`** — new verb that orchestrates ECC's `plan-prd` → `plan` → optional `santa-loop` into a guided spec-then-plan-then-execute flow. Cousin of M#5 (query) and M#6 (lint); the spec equivalent.
- **Intent-routing behavioral update** — the codebrain meta-skill (`skills/behavioral/codebrain/SKILL.md`) gains a "Prompt-intent routing" section telling the agent: when operator's prompt expresses feature intent (verbs: `add`, `build`, `create`, `implement`, `let me`, `we should`), suggest `/brain spec <intent>` BEFORE jumping to code. Default agent behavior changes; operator can override with explicit "just do it" / `--no-spec` flags.
- **Discovery-loop skill** — `skills/core/discovery-loop/SKILL.md` codifies the iterative-sweep pattern. Used by `/brain spec` Step Sp4, by `/brain lint` (post-MVP integration), and as a standalone pattern operators can invoke during planning.

After M#10: when an operator says "let's add user authentication", the agent doesn't immediately edit files. It suggests `/brain spec "add user authentication"`, runs the PRD → plan → sweep loop, presents the converged plan, asks for approval, THEN implements.

## Patterns to Mirror

| Category | Source | Pattern |
|---|---|---|
| Slash-command verb wiring | M#5 query + M#6 lint + M#7 learn | Add `/brain spec` to dispatch table; add `## When $ARGUMENTS starts with spec` procedure section |
| Orchestrator-only agent | M#3c planner + M#5 query | `agents/spec-orchestrator/spec-orchestrator.md` — tools `[Read, Glob, Grep, Bash]`; orchestrates ECC skills + codebrain procedures, doesn't write code directly |
| Behavioral-skill update | M#1's `skills/behavioral/codebrain/SKILL.md` | Add "Prompt-intent routing" section with the verb-matching heuristics + the suggest-`/brain spec` instruction |
| Discovery-loop codification | This session's organic sweep pattern (J1-J9, G1-G8, etc.) | `skills/core/discovery-loop/SKILL.md` — defines convergence criteria, sweep round structure, halting condition |
| Bridge to ECC | M#9's expert_skills bridge pattern | `/brain spec` invokes `ecc:plan-prd`, `ecc:plan`, optionally `ecc:santa-loop` as Bash/Skill calls; codebrain orchestrates, ECC does the heavy lifting |

## Files to Change

| File | Action | Why |
|---|---|---|
| `agents/brain/spec-orchestrator.md` (NEW) | CREATE | Seventh agent (M#10 ships before M#11's cred-registrar per the v0.2 ordering). "Spec Orchestrator" pattern. Tools `[Read, Glob, Grep, Bash]` — no writes. Procedure: invoke ECC's `plan-prd` for the PRD, then `plan` for the implementation plan, optionally `santa-loop` for adversarial review, present converged spec+plan to operator. Path matches the convention established by the six existing `agents/brain/*` files. |
| `skills/core/spec/SKILL.md` (NEW) | CREATE | Defines the `/brain spec` contract — input (intent string), output (PRD path + plan path + convergence report), bridge to ECC, when to use vs `/brain query` (questions) vs `/brain ingest` (exploration). |
| `skills/core/discovery-loop/SKILL.md` (NEW) | CREATE | The discovery-loop pattern. When to invoke; sweep round structure (read existing plan + question every assumption + surface gaps + revise); convergence criteria (sweep produces <3 new findings → converged); max iterations (5). Used by `/brain spec` Step Sp4; reusable standalone. |
| `commands/brain/spec.md` (NEW) | CREATE | The full `/brain spec` procedure (Sp0–Sp7) ships as its own per-verb file under M#12's namespaced layout. Frontmatter: `description: codebrain — spec-orchestrate an intent into a converged plan`. |
| `commands/codebrain/spec.md` (NEW) | CREATE | Alias mirror; byte-identical procedure body. |
| `commands/brain.md` | UPDATE (help text only) | Add `/brain:spec "<intent>"` row to the dispatch help table (post-M#12 this file is the help disambiguator, not a procedure host). |
| `commands/codebrain.md` | UPDATE (help text only) | Same in the alias disambiguator. |
| `skills/behavioral/codebrain/SKILL.md` | UPDATE | Add "Prompt-intent routing" section instructing the agent to suggest `/brain:spec` when prompts express feature intent |
| `tests/e2e-test.sh` | UPDATE | T38: spec procedure structural shape (in `commands/brain/spec.md`); intent-routing keywords in behavioral skill; discovery-loop skill exists with convergence criteria; **alias parity assertion targets the per-verb file pair** (`commands/brain/spec.md` ↔ `commands/codebrain/spec.md`); npm pack |
| `.claude/prds/codebrain.prd.md` | UPDATE | Flip M#10 row `pending` → `complete` |

**M#10d file paths (post-M#12 layout)**:

| File | Action | Why |
|---|---|---|
| `skills/ingestion/page-format/templates/code-page.md` | UPDATE | Add optional `superseded_by:` / `supersedes:` frontmatter fields. (Path unaffected by M#12 — skill template, not slash command.) |
| `skills/ingestion/concept-extraction/templates/concept-page.md` | UPDATE | Same frontmatter addition for concept pages. |
| `commands/brain/query.md` | UPDATE | M#10d Task 8: query Q4 skips `superseded_by` pages, follows pointer to replacement. (Post-M#12, this lives in the per-verb file.) |
| `commands/brain/lint.md` | UPDATE | M#10d Task 8: L3/L4 checks for superseded pages still linked + asymmetric supersession. |
| `commands/brain/ingest.md` | UPDATE | M#10d Task 9: append narrative entry to `.brain/CHANGELOG.md` on each ingest. Mirrors how Step 6 currently updates index/status/log/llms.txt. |
| `commands/codebrain/{query,lint,ingest}.md` | UPDATE | Alias parity for each per-verb file pair. |
| `scripts/init.js` | UPDATE | M#10d Task 9: scaffold `.brain/CHANGELOG.md` alongside the other top-level brain files; also update the `.brain/llms.txt` starter scaffold to list CHANGELOG.md under `## Top-level`. |
| `skills/behavioral/wiki-reading-principles/SKILL.md` (NEW) | CREATE | M#10d Task 10: behavioral-constraint skill with 3-tier always/ask/never structure. Tier `behavioral`. |

## Sub-milestone split (recommended)

M#10 is large enough that a 4-way split mirrors how M#3 was sub-split in v0.1 (M#3a/b/c shipped together with M#3d as a v0.1.0 add-on):

- **M#10a — `/brain spec` verb + spec-orchestrator agent**: the verb works end-to-end via ECC bridge; spec-orchestrator agent ships; no intent-routing yet (operator must explicitly invoke `/brain spec`)
- **M#10b — Discovery-loop skill**: codifies the convergence pattern; integrated into `/brain spec` Step Sp4; reusable standalone
- **M#10c — Intent routing**: behavioral skill update + the heuristic that makes the agent suggest `/brain spec` on feature-intent prompts; the most behavior-changing part of M#10; ships last so operators see it after the spec verb is proven
- **M#10d — Agent-readability hardening** (new): `supersedes`/`superseded_by` frontmatter (pink-elephant fix), `.brain/CHANGELOG.md` (compound learning made visible), `skills/behavioral/wiki-reading-principles/SKILL.md` (3-tier always/ask/never). Independent of M#10a–c; can ship in any order. Driven by external research; see "Evidence base."

Each sub-milestone is its own commit. M#10 is "complete" when all four ship. M#10d can ship standalone before M#10a if operators want the smaller readability wins first.

## Tasks

### M#10a (minimum viable)

1. `agents/spec-orchestrator/spec-orchestrator.md` — new agent. Frontmatter merged-format with `pattern: Orchestrator` (or reuse `Planner`). Tools `[Read, Glob, Grep, Bash]`. Rules: NEVER write code directly; ALWAYS delegate spec writing to ECC's plan-prd; ALWAYS present the converged plan for operator approval before implementation.

2. `skills/core/spec/SKILL.md` — tier `core`. Defines when to use `/brain spec` (feature requests, architectural questions, exploratory ideas), how it works (invoke plan-prd → plan → optional santa-loop), when NOT to use it (simple lookups → use `/brain query`; pure exploration → use `/brain ingest`).

3. `commands/brain.md` `## When $ARGUMENTS starts with spec` procedure (Sp0–Sp7):
   - **Sp0**: parse `<intent>` arg + optional flags (`--no-sweep`, `--reuse-prd <path>`, `--yes`)
   - **Sp1**: preconditions (`.brain/` exists; cwd is a project)
   - **Sp2**: invoke `ecc:plan-prd` with the intent → produces a PRD at `.claude/prds/<slug>.prd.md`
   - **Sp3**: invoke `ecc:plan` on that PRD → produces a plan at `.claude/plans/<slug>.plan.md`
   - **Sp4**: optionally invoke `ecc:santa-loop` (or M#10b's discovery loop) for convergence → revised plan
   - **Sp5**: present converged spec + plan to operator; ask for approval / modifications / cancel
   - **Sp6**: on approval, the agent proceeds with implementation against the plan (delegates to operator's normal workflow — codebrain doesn't write code)
   - **Sp7**: structured report + log entry

### M#10b (discovery-loop skill)

4. `skills/core/discovery-loop/SKILL.md`:
   - **When activated**: invoked by `/brain spec` Step Sp4; can be invoked standalone via "sweep this plan" trigger phrase
   - **Sweep round**: re-read the artifact (spec OR plan); for each section, question every assumption; surface gaps; list 5–10 findings; revise the artifact incorporating findings
   - **Convergence criteria**: sweep round produces <3 new findings → converged. OR max iterations (5) reached.
   - **Loop algorithm**:
     ```
     iteration = 0
     while iteration < 5:
       findings = sweep(artifact)
       if len(findings) < 3:
         return artifact  # converged
       artifact = revise(artifact, findings)
       iteration += 1
     return artifact  # max iterations
     ```
   - **Examples**: 1 example from this session's actual sweep findings (J1-J9 or G1-G8); show the convergence in action

### M#10c (intent routing)

5. Update `skills/behavioral/codebrain/SKILL.md` — add a new section:

   ```
   ## Prompt-intent routing (M#10c)

   Classify every operator prompt at the start of the response. If the prompt
   expresses feature intent (verbs: add, build, create, implement, let me,
   we should, can you make), do NOT immediately edit files. Instead, suggest:

     I think this calls for /brain spec "<paraphrased intent>" first —
     that runs a PRD → plan → convergence loop so we don't skip past gaps.
     Want me to start there, or did you want me to jump straight to code?

   Operator overrides:
     - "just do it" / "skip the spec" — proceed without /brain spec
     - "use /brain spec" / "yes" — invoke /brain spec
     - explicit /brain spec <intent> from the operator — invoke directly

   For non-feature intents (questions, lookups, exploration, refactor,
   debugging), do NOT suggest /brain spec — these have their own verbs
   (/brain query, /brain ingest, /brain lint) or are normal coding work.
   ```

6. Update `commands/brain.md` (and codebrain.md alias) to mention `/brain spec` in the dispatch help text + the no-args help block.

7. **Tests (T38)** — assertions for: spec procedure with Sp0-Sp7 steps; spec-orchestrator agent exists with proper frontmatter; discovery-loop skill exists with convergence criteria; behavioral skill has "Prompt-intent routing" section with the trigger verb list; alias parity; npm pack.

### M#10d (agent-readability hardening from external research)

Three small additions that share the thesis "operator-curated conventions beat inferred content." Cited evidence in "Evidence base" above. Ship as one sub-milestone since the three additions interlock: the supersedes frontmatter feeds the CHANGELOG entries; the reading-principles skill tells agents how to interpret both.

#### Task 8 — `supersedes` / `superseded_by` frontmatter (pink-elephant fix)

Pages drift out of relevance during code refactors. Tier-3 staleness today *flags* stale pages but doesn't *isolate* them — the pink-elephant research (Eric Ma, 2026-03) shows the mere mention of a deprecated pattern anchors the model's reasoning. This task adds explicit isolation.

- Update `skills/ingestion/page-format/templates/code-page.md` and the concept-page template: add two optional frontmatter fields:
  - `superseded_by: <slug or path>` — set on the old page when a new page replaces it
  - `supersedes: [<slug>, <slug>, ...]` — set on the new page listing what it replaced
- Update `commands/brain.md` `/brain query` Q4 ("Read pages") step: SKIP any page with `superseded_by` set; instead follow the pointer and load the replacement. Log a one-liner in the answer's "Pages consulted" footer: `(superseded: <old> → <new>)`.
- Update `commands/brain.md` `/brain lint` L3 (Defects): new check — "Superseded pages still linked from non-superseded pages" — report broken-by-deprecation links.
- Update `commands/brain.md` `/brain lint` L4 (Gaps): new check — "Page declares `superseded_by:` but target page does not declare matching `supersedes:`" — flag asymmetric supersession.
- Mirror to `commands/codebrain.md` for alias parity.
- Tests: page-format template has the new fields documented; query Q4 skips superseded pages; lint L3/L4 checks present; alias parity; reciprocity (every `supersedes:` entry has a matching `superseded_by:` on the referenced page).

#### Task 9 — `.brain/CHANGELOG.md` (compound learning made visible)

The observer agent (M#7) already captures continuous-learning observations to XDG storage. The `.brain/log.md` captures per-event activity. Neither surfaces the *narrative* of how the brain has accumulated knowledge over time, which is the compound-learning thesis (Carson, Huntley). This task adds a curated, human-readable changelog.

- Update `scripts/init.js` `scaffoldBrainDir`: write a starter `.brain/CHANGELOG.md` with header and one line for the init event.
- Update `commands/brain.md` Step 7 of `/brain ingest <file>` (and L5 of linker): append a one-line entry to `.brain/CHANGELOG.md` summarizing the ingest's *narrative* impact — not just "ingested src/auth.ts" but "extended auth surface coverage (Tenant, AuthFlow concepts created)". The summary line is the same single-line summary the agent writes to `llms.txt` for the page, prefixed with the date.
- Update `commands/brain.md` `/brain learn consolidate` (M#7's Le6): append a CHANGELOG entry summarizing the consolidation — `## [YYYY-MM-DD] consolidate | <N> new instincts: <comma-separated names>`.
- Update `commands/brain.md` `/brain lint` L7: NO CHANGELOG entry from lint (read-only operation; CHANGELOG tracks knowledge growth, not health-checks).
- `CHANGELOG.md` format: append-only, reverse-chronological newest-first sections by month, plain markdown bullets. The agent never deletes or reorders prior entries.
- Mirror to `commands/codebrain.md` for alias parity.
- Tests: init scaffolds CHANGELOG.md; ingest appends entries; consolidate appends entries; lint does NOT append; reverse-chronological order is preserved; alias parity.

#### Task 10 — `skills/behavioral/wiki-reading-principles/SKILL.md` (3-tier always/ask/never)

Codebrain installs behavioral skills for agent conduct (`skills/behavioral/codebrain`) but has nothing telling installed agents *how to read the brain*. The 3-tier always/ask/never structure (Jonathan Vila's MCP architecture guide, 2026-03-31; Karpathy's four-principle behavioral spec, 2026-05-14) beats prose for instructing LLM behavior.

- Create `skills/behavioral/wiki-reading-principles/SKILL.md` with frontmatter:
  ```yaml
  ---
  name: wiki-reading-principles
  description: How an agent should read the codebrain wiki. Behavioral-constraint skill — applies to ALL sessions where .brain/ is present.
  origin: codebrain
  version: 0.1.0
  tier: behavioral
  pattern: Behavioral-Constraint
  related_skills: [behavioral/codebrain]
  ---
  ```
- Body uses the always/ask/never structure:
  ```markdown
  ## ALWAYS

  - Start any wiki-grounded answer by reading `.brain/llms.txt` for routing
  - Cite pages by `[[code/<path>]]` / `[[concepts/<slug>]]` wikilinks in your responses
  - When a page has `superseded_by:` set, follow the pointer instead of using the page
  - Treat `.brain/log.md` and `.brain/CHANGELOG.md` as authoritative for chronological context

  ## ASK

  - Before contradicting a claim in a non-stale FRESH page, surface the conflict to the operator
  - Before editing a `.brain/` page directly (vs re-running `/brain ingest`), confirm the operator wants a manual edit
  - Before treating a STALE page's content as current, confirm the operator wants it refreshed first

  ## NEVER

  - Edit a code page without re-reading the source file it mirrors (the source is canonical; the page is a projection)
  - Add new content to a page with `superseded_by:` set — that page is frozen by convention
  - Cite raw `.brain/log.md` activity entries as authoritative semantic content — they're an audit trail, not knowledge
  - Bypass the codebrain hook system by manually editing `.brain/.codebrain-version` or `.codebrain-*` state files
  ```
- Update `scripts/init.js` to ensure this skill ships in the npm package (it will by virtue of `skills/` whitelist already in `package.json`, but verify with `npm pack --dry-run`).
- Update `commands/brain.md` `## Dispatch` table preamble (the part that runs before verb routing) to add: "Before responding, ensure you have read the behavioral skill `skills/behavioral/wiki-reading-principles/SKILL.md` — it defines the always/ask/never structure for engaging with `.brain/`."
- Tests: skill exists with proper frontmatter; tier is `behavioral`; pattern is `Behavioral-Constraint`; body contains all three section headers (ALWAYS, ASK, NEVER); npm pack includes the file; brain.md preamble references it.

11. **PRD update + push** — M#10 row complete. Update PRD's "v0.2 Roadmap" section to:
   - Note the M#10 → M#9 ordering recommendation
   - Cite the agentctx-idea research as the empirical source for M#10d (mirrors M#7 → v0.1-baseline.md "Operator-discovered gaps" linkage)

## Validation

```bash
# E2E
bash tests/e2e-test.sh
# Expect: ~800 passes (~644 v0.1.2 baseline + ~80 T38 from M#10a-c + ~30 T38d from M#10d + ~50 from any intervening M#12/M#11 if shipped first), 0 failures
# See "Cross-plan test-count walk-forward" section of M#12 plan for the cumulative count across the v0.2 sequence.

# Spec procedure wired (post-M#12 per-verb layout)
test -f commands/brain/spec.md
test -f commands/codebrain/spec.md
for sp in Sp0 Sp1 Sp2 Sp3 Sp4 Sp5 Sp6 Sp7; do
  grep -qF "**$sp" commands/brain/spec.md
done

# Alias parity (procedure bodies byte-identical)
body_brain=$(awk '/^# \//{flag=1; next} flag' commands/brain/spec.md)
body_cb=$(awk '/^# \//{flag=1; next} flag' commands/codebrain/spec.md)
[ "$body_brain" = "$body_cb" ]

# Intent routing in behavioral skill
grep -qF 'Prompt-intent routing' skills/behavioral/codebrain/SKILL.md

# Discovery-loop skill exists
test -f skills/core/discovery-loop/SKILL.md
grep -qF 'Convergence criteria' skills/core/discovery-loop/SKILL.md

# M#10d — supersedes frontmatter + CHANGELOG + reading-principles
grep -qF 'superseded_by' skills/ingestion/page-format/templates/code-page.md
grep -qF 'supersedes' skills/ingestion/page-format/templates/code-page.md
test -f skills/behavioral/wiki-reading-principles/SKILL.md
grep -qF '## ALWAYS' skills/behavioral/wiki-reading-principles/SKILL.md
grep -qF '## ASK' skills/behavioral/wiki-reading-principles/SKILL.md
grep -qF '## NEVER' skills/behavioral/wiki-reading-principles/SKILL.md
# CHANGELOG scaffolded by init
( cd "$(mktemp -d)" && git init -q && node "$CB" init >/dev/null )
# Then verify .brain/CHANGELOG.md exists in that scratch dir

# Manual smoke (post-commit):
#   Operator types: "let's add user authentication"
#   → Agent responds: "I think this calls for /brain spec ... want me to start there?"
#   Operator types: yes
#   → Agent invokes /brain spec; produces PRD + plan + (with discovery-loop) converged plan; presents for approval
```

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Operators hate the intent routing (feels like the agent is gatekeeping their requests) | High | Frame as a SUGGESTION not an interruption; operator's "just do it" override is one phrase; default behavior is "ask once then defer to operator" |
| ECC's `plan-prd` and `plan` may not be invokable from a slash-command body (cross-plugin skill orchestration is M#9's territory) | High | M#10 implementation should follow M#9 — Tasks 1-2 of M#9 (probe + activation mechanism) are prerequisites for M#10's Bash-orchestration of ECC skills |
| Discovery-loop convergence criteria (sweep produces <3 findings) is arbitrary | Med | Stake-in-ground; v0.2 dogfood evidence will refine. Document the heuristic + invite operator override via `--convergence-threshold N` flag (post-MVP) |
| `/brain spec` produces PRD + plan files that proliferate in `.claude/prds/` and `.claude/plans/` | Low | They're already there; codebrain just adds more. Lint pass (M#6 or post-MVP) can surface stale specs. |
| Behavioral-skill update changes default agent behavior across ALL sessions | High | Phase the rollout — initially the intent-routing is OPT-IN via a `.brain/.codebrain-intent-routing-state` toggle file (mirroring M#7's learn toggle pattern). Default off; operator enables when comfortable. v1.0 may flip default. |
| The 4-way M#10 split balloons into 4 separate v0.2 milestones | Med | Acknowledged; if operator wants only spec verb without intent routing, M#10a ships standalone and the others defer. M#10d is the smallest sub-milestone and a natural "ship-first" candidate. |
| M#10d's wiki-reading-principles behavioral skill conflicts with existing `behavioral/codebrain` | Low | They're complementary: codebrain skill is general agent identity; wiki-reading-principles is wiki-specific conduct. Declare `related_skills: [behavioral/codebrain]` for explicit linkage. |
| M#10d's `supersedes:` frontmatter not adopted by operators (they just edit pages in place instead) | Med | Acceptable in v0.2 — the feature is opt-in. If usage stays low after 90 days, deprecate. Adoption can be encouraged by `/brain lint` surfacing "page replaced 80% of another page" as a suggestion to set the frontmatter. |

## Acceptance (provisional)

- [ ] All sub-milestones complete (M#10a, M#10b, M#10c, M#10d)
- [ ] Validation passes (~800 e2e — ~770 from M#10a–c plus ~30 from M#10d)
- [ ] M#10 row in PRD → complete
- [ ] No regression on prior tests
- [ ] (Operator) Manual smoke: "let's add user auth" prompt elicits the intent-routing suggestion; `/brain spec` runs end-to-end + produces a converged plan
- [ ] (Operator) M#10d smoke: refactor a code file → re-ingest creates a new code page → set `superseded_by:` on the old page → `/brain query` no longer reads the old page; `.brain/CHANGELOG.md` shows the narrative entry; reading-principles skill is present in the npm pack

---

**This plan is a v0.2 DRAFT — the most ambitious post-MVP work.** Refinement before implementation:

- Sweep + decompose into M#10a / M#10b / M#10c / M#10d — each sub-milestone gets its own plan
- Resolve the prerequisite dependency on M#9 (cross-plugin skill orchestration is the load-bearing primitive M#10 needs)
- Test the intent-routing behavior on at least 3 dogfood operators before defaulting it on
- Verify ECC's `plan-prd`, `plan`, `santa-loop` skill names + invocation contracts are stable enough to bridge to
- Consider whether the intent-routing belongs in codebrain at all vs. in an ECC-side skill that codebrain consumes (could be `ecc:intent-routing` and codebrain just bridges to it via M#9's expert_skills mechanism — even cleaner)
