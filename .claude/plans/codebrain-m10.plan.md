# Plan: codebrain — Milestone #10 (Spec-first workflow + intent routing + discovery loop)

**Source PRD**: `.claude/prds/codebrain.prd.md` (v0.2 Roadmap section)
**Selected Milestone**: #10 — Gap C from operator dogfood
**Complexity**: Large — three distinct features in one milestone; introduces a new top-level verb (`/brain spec`); behavioral-skill update changes default agent behavior; codifies a multi-iteration pattern (discovery loop) that's currently implicit
**Status**: DRAFT — most architecturally ambitious v0.2 work; sweep + split into 10a/10b/10c expected before implementation

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
| `agents/spec-orchestrator/spec-orchestrator.md` (NEW) | CREATE | Seventh agent. "Spec Orchestrator" pattern. Tools `[Read, Glob, Grep, Bash]` — no writes. Procedure: invoke ECC's `plan-prd` for the PRD, then `plan` for the implementation plan, optionally `santa-loop` for adversarial review, present converged spec+plan to operator. |
| `skills/core/spec/SKILL.md` (NEW) | CREATE | Defines the `/brain spec` contract — input (intent string), output (PRD path + plan path + convergence report), bridge to ECC, when to use vs `/brain query` (questions) vs `/brain ingest` (exploration). |
| `skills/core/discovery-loop/SKILL.md` (NEW) | CREATE | The discovery-loop pattern. When to invoke; sweep round structure (read existing plan + question every assumption + surface gaps + revise); convergence criteria (sweep produces <3 new findings → converged); max iterations (5). Used by `/brain spec` Step Sp4; reusable standalone. |
| `commands/brain.md` | UPDATE | Add `/brain spec "<intent>"` dispatch row; add `## When $ARGUMENTS starts with spec` procedure section with Steps Sp0-Sp7. |
| `commands/codebrain.md` | UPDATE | Alias parity for spec procedure |
| `skills/behavioral/codebrain/SKILL.md` | UPDATE | Add "Prompt-intent routing" section instructing the agent to suggest `/brain spec` when prompts express feature intent |
| `tests/e2e-test.sh` | UPDATE | T38: spec procedure structural shape; intent-routing keywords in behavioral skill; discovery-loop skill exists with convergence criteria; alias parity; npm pack |
| `.claude/prds/codebrain.prd.md` | UPDATE | Flip M#10 row `pending` → `complete` |

## Sub-milestone split (recommended)

M#10 is large enough that a 3-way split mirrors how we handled M#3 in v0.1:

- **M#10a — `/brain spec` verb + spec-orchestrator agent**: the verb works end-to-end via ECC bridge; spec-orchestrator agent ships; no intent-routing yet (operator must explicitly invoke `/brain spec`)
- **M#10b — Discovery-loop skill**: codifies the convergence pattern; integrated into `/brain spec` Step Sp4; reusable standalone
- **M#10c — Intent routing**: behavioral skill update + the heuristic that makes the agent suggest `/brain spec` on feature-intent prompts; the most behavior-changing part of M#10; ships last so operators see it after the spec verb is proven

Each sub-milestone is its own commit. M#10 is "complete" when all three ship.

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

8. **PRD update + push** — M#10 row complete.

## Validation

```bash
# E2E
bash tests/e2e-test.sh
# Expect: ~770 passes (~690 from M#9 + ~80 from T38), 0 failures

# Spec procedure wired
grep -qF '## When `$ARGUMENTS` starts with `spec`' commands/brain.md
for sp in Sp0 Sp1 Sp2 Sp3 Sp4 Sp5 Sp6 Sp7; do
  grep -qF "**$sp" commands/brain.md
done

# Intent routing in behavioral skill
grep -qF 'Prompt-intent routing' skills/behavioral/codebrain/SKILL.md

# Discovery-loop skill exists
test -f skills/core/discovery-loop/SKILL.md
grep -qF 'Convergence criteria' skills/core/discovery-loop/SKILL.md

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
| The 3-way M#10 split balloons into 3 separate v0.2 milestones | Med | Acknowledged; if operator wants only spec verb without intent routing, M#10a ships standalone and the others defer |

## Acceptance (provisional)

- [ ] All sub-milestones complete (M#10a, M#10b, M#10c)
- [ ] Validation passes (~770 e2e)
- [ ] M#10 row in PRD → complete
- [ ] No regression on prior tests
- [ ] (Operator) Manual smoke: "let's add user auth" prompt elicits the intent-routing suggestion; `/brain spec` runs end-to-end + produces a converged plan

---

**This plan is a v0.2 DRAFT — the most ambitious post-MVP work.** Refinement before implementation:

- Sweep + decompose into M#10a / M#10b / M#10c — each sub-milestone gets its own plan
- Resolve the prerequisite dependency on M#9 (cross-plugin skill orchestration is the load-bearing primitive M#10 needs)
- Test the intent-routing behavior on at least 3 dogfood operators before defaulting it on
- Verify ECC's `plan-prd`, `plan`, `santa-loop` skill names + invocation contracts are stable enough to bridge to
- Consider whether the intent-routing belongs in codebrain at all vs. in an ECC-side skill that codebrain consumes (could be `ecc:intent-routing` and codebrain just bridges to it via M#9's expert_skills mechanism — even cleaner)
