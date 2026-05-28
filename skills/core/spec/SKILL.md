---
name: spec
description: Defines the /brain spec contract — given an operator intent, orchestrate ECC's plan-prd → plan → optional santa-loop into a converged spec + plan. Tier core. Cousin of core/query, core/lint, core/learn — adds the spec verb to the codebrain surface.
origin: codebrain
version: 0.1.0
tier: core
pattern: Orchestrator
related_skills: [behavioral/codebrain, ingestion/page-format]
---

# spec — `/brain spec` contract

This skill defines the `/brain spec "<intent>"` verb. When to use it, what it produces, and how it bridges to ECC's spec-side skills.

## When to use `/brain spec`

Use `/brain spec` when the operator's prompt expresses **feature intent** — the operator wants a NEW capability designed, planned, and built. Verbs that suggest feature intent: `add`, `build`, `create`, `implement`, `let me`, `we should`, `can you make`.

`/brain spec` orchestrates a three-phase flow:

1. **Specify** (via `ecc:plan-prd`): produce a PRD at `.claude/prds/<slug>.prd.md` capturing user experience, success criteria, scope, and design decisions.
2. **Plan** (via `ecc:plan`): produce a plan at `.claude/plans/<slug>.plan.md` decomposing the PRD into ordered tasks with patterns-to-mirror + risks + acceptance.
3. **Sweep** (optional, via `ecc:santa-loop` or M#10b's `skills/core/discovery-loop/SKILL.md`): iteratively refine the plan until convergence (≤3 new findings per sweep round). Default ON; opt out via `--no-sweep`.

Then the agent **presents** the converged spec + plan to the operator for approval before any implementation begins.

## When NOT to use `/brain spec`

- **Questions** about the codebase → use `/brain query`
- **Exploration** of existing code → use `/brain ingest`
- **Health-checks** of the wiki → use `/brain lint`
- **Small bug fixes** (one symptom, one fix, no architectural decision) → proceed normally, no spec needed
- **Refactors** that don't add new capability → proceed normally

The threshold: would the work benefit from a written spec a future contributor could read? If yes, use `/brain spec`. If no, skip.

## Inputs

```
/brain spec "<intent>" [--no-sweep] [--reuse-prd <path>] [--yes]
```

- `<intent>` — required; a 1-sentence-or-paragraph description of the feature
- `--no-sweep` — skip the convergence loop (Sp4); produce single-pass PRD + plan
- `--reuse-prd <path>` — skip Sp2 (PRD generation); use the supplied PRD path as input to Sp3 (plan generation). Operator-friendly for iterating on the plan without regenerating the PRD.
- `--yes` — auto-confirm at Sp5 (skip the approval prompt); use only in scripted/CI contexts. Default is to require operator confirmation.

## Outputs

- **PRD file** at `.claude/prds/<slug>.prd.md` (skipped if `--reuse-prd` passed)
- **Plan file** at `.claude/plans/<slug>.plan.md`
- **Convergence report** (printed to console + appended to `.brain/log.md`):

  ```
  /brain spec converged (codebrain v<version>)
    Intent:           <intent verbatim>
    PRD:              .claude/prds/<slug>.prd.md (~<token-count> tokens)
    Plan:             .claude/plans/<slug>.plan.md (~<token-count> tokens)
    Sweep rounds:     <N> (or "skipped — --no-sweep" or "skipped — discovery-loop not available")
    Findings/round:   [<N0>, <N1>, <N2>, ...]  ← convergence trace
    Active bridges:
      loaded:         <comma-separated, or "(none)">
      unavailable:    <comma-separated, or "(none)">
    Status:           awaiting operator approval (Sp5)
  Next: respond approve / modify / cancel at the Sp5 prompt.
  ```

- **`.brain/log.md` entry** (grep-parseable prefix per PRD #15):

  ```
  ## [YYYY-MM-DD] spec | "<intent first 80 chars>"; sweep rounds: <N>; status: <approved | modified | cancelled | awaiting>
  ```

## Slug derivation

The `<slug>` for the PRD + plan filenames is derived from the intent:

1. Lowercase the intent
2. Strip punctuation
3. Take the first 6–8 most-meaningful tokens (skip stopwords: `a`, `an`, `the`, `for`, `to`, `we`, `should`, `let`, `me`, `can`, `you`)
4. Join with hyphens

Example: `/brain spec "let's add user authentication with OAuth"` → slug `add-user-authentication-oauth`.

If the slug is already used in `.claude/prds/`, append `-<NN>` (e.g., `-02`).

## Bridge dependency (M#9-prereq)

`/brain spec` relies on the M#9-prereq filesystem-probe pattern to load ECC's spec-side skills. Probe paths (Sp1):

```bash
test -e "$HOME/.claude/plugins/ecc/skills/plan-prd/SKILL.md" \
  || test -e "$PWD/.claude/plugins/ecc/skills/plan-prd/SKILL.md"

test -e "$HOME/.claude/plugins/ecc/skills/plan/SKILL.md" \
  || test -e "$PWD/.claude/plugins/ecc/skills/plan/SKILL.md"
```

If either is missing, Sp1 emits a `blocked: ecc bridge unavailable — install the ECC plugin or rerun with --documentation-only` report and stops. The `--documentation-only` flag (post-MVP) would let the orchestrator write a stub PRD + plan template the operator fills in by hand.

`ecc:santa-loop` is treated identically but is optional — its absence falls through to M#10b's `skills/core/discovery-loop/SKILL.md` (if available) or skips Sp4 entirely.

## Failure modes

- **ECC not installed** → blocked at Sp1; operator instruction: install ECC or pass a future `--documentation-only` flag.
- **Intent ambiguous** (e.g., `/brain spec "auth"`) → Sp2 prompts the operator for clarification before invoking `ecc:plan-prd`. Operator can re-issue with a fuller intent or proceed with the ambiguous intent (ECC's plan-prd will produce a generic PRD).
- **Sweep loop diverges** (each round produces >3 findings) → Sp4 caps at 5 rounds; if convergence not reached, present the latest plan with a warning: `Sweep did not converge in 5 rounds — review for unresolved issues.`
- **Operator declines at Sp5** → emit a clean `cancelled` report; the PRD + plan files remain on disk (operator can iterate or delete manually). No `.brain/log.md` cancellation cleanup beyond the activity-history entry.

## Related verbs + skills

- **`/brain query`** — answers questions about the existing codebase; complementary, not redundant
- **`/brain ingest`** — extends the wiki with new pages; M#10a does NOT auto-trigger this, but the converged plan may instruct the operator to run it
- **`skills/core/discovery-loop/SKILL.md`** (M#10b) — codifies the Sp4 sweep loop as a reusable skill; M#10a's Sp4 references this skill if shipped
- **`skills/behavioral/codebrain/SKILL.md`** (updated in M#10c with "Prompt-intent routing") — the upstream trigger that suggests `/brain spec` when operator intent matches
- **`agents/brain/spec-orchestrator.md`** — the agent's identity, scope, rules
