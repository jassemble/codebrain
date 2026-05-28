---
name: discovery-loop
description: The convergence-loop pattern — iteratively sweep a plan or document for gaps, surface findings, revise, and stop when the round produces ≤3 new findings. Codifies the sweep behavior organically discovered during the codebrain v0.1 build session. Used by /brain spec Sp4; reusable standalone via the "sweep this plan" / "review for gaps" trigger phrases. Tier core. (Milestone #10b)
origin: codebrain
version: 0.1.0
tier: core
pattern: Pipeline
related_skills: [behavioral/codebrain, core/spec]
---

# discovery-loop — convergence-sweep pattern

This skill codifies the iterative-sweep convergence pattern. Use it when a plan, PRD, or design document needs adversarial review until it stops producing new findings.

## When to activate

Activate this skill when:

1. **`/brain spec` Sp4 invokes it** as a fallback when `ecc:santa-loop` is unavailable (the primary sweep mechanism)
2. **A trigger phrase matches** + operator's intent is clearly review-for-gaps:
   - "sweep this plan"
   - "review for gaps"
   - "find what we missed"
   - "adversarial review"
   - "discovery loop"
3. **The operator explicitly invokes** `discovery-loop` by name

Do NOT activate this skill for:
- Code review (use a dedicated code-review skill — out of scope here)
- Bug hunting in source code (use `/brain query` or normal debugging)
- General Q&A about a plan (use `/brain query`)

## Procedure

The loop runs against ONE input artifact — a plan, PRD, or design document at a known path. The loop terminates on convergence OR max-iterations.

**D0 — Inputs**:

- `artifact_path` — path to the markdown file being swept (e.g., `.claude/plans/<slug>.plan.md`)
- `max_rounds` — default 5; operator may override via `--max-rounds N`
- `convergence_threshold` — default 3; a round producing ≤ this many new findings is considered converged

**D1 — Initialize**:

- Verify `artifact_path` exists and is readable. If not: emit `blocked: discovery-loop input artifact not found: <path>` and stop.
- Initialize `findings_per_round = []` (one entry per completed round).
- Initialize `all_findings = []` (deduped across rounds; used to detect "new" vs "rediscovered").

**D2 — Sweep round** (repeat per round):

For each round (1 through `max_rounds`):

1. **Read** the current `artifact_path` in full (or in chunked sections if it exceeds page-cap thresholds — see `skills/ingestion/page-format/SKILL.md` for the cap reference). Page-cap is informational here, not enforced; the sweep needs to see the whole artifact even if large.

2. **Question every assumption** the artifact makes. For each claim/decision/task in the artifact, ask:
   - Is the rationale stated, or assumed?
   - Are there counterexamples the artifact ignores?
   - Are dependencies declared, or hidden?
   - Is the scope sharply defined, or fuzzy?
   - Are acceptance criteria machine-verifiable, or vague?
   - Are risks acknowledged, or glossed?
   - Are stale references / contradictions present from earlier drafts?

3. **Surface findings** — each finding is a one-line statement of the gap:
   - Severity tag: `BLOCKER` (will cause failure on implementation), `DRIFT` (stale/contradictory), `GAP` (missing element), `QUESTION` (open design decision needing operator input)
   - Brief description
   - Location reference (line number or section heading in the artifact)

4. **Dedupe** against `all_findings`: a finding is "new" only if it's not a paraphrase of one already in `all_findings`. Use semantic comparison — exact text match is too strict; if two findings name the same root cause, treat them as the same finding.

5. **Append new findings to `all_findings`** + record `findings_per_round[round_index] = <new findings count>`.

6. **Revise the artifact** (optional, gated): if `--auto-revise` flag is passed by the caller, the loop edits the artifact in place to address the new findings. Default behavior is to REPORT findings only; the operator (or caller, e.g., `/brain spec` Sp5) decides whether to apply them.

**D3 — Convergence check**:

After each round, check:

- If `findings_per_round[last]` ≤ `convergence_threshold` → **converged**; exit the loop with `status: converged`.
- If round count == `max_rounds` → **max-rounds-reached**; exit with `status: max_rounds (not converged)`.
- Otherwise → continue to next round.

**D4 — Output**:

Return a structured result the caller (e.g., `/brain spec` Sp4) can consume:

```
{
  status: converged | max_rounds | blocked,
  rounds_completed: <N>,
  findings_per_round: [<N0>, <N1>, ...],
  all_findings: [
    { severity: BLOCKER | DRIFT | GAP | QUESTION, description: "...", location: "<section or line>" },
    ...
  ],
  artifact_path: <path>,
  artifact_revised: true | false
}
```

If invoked standalone (not via `/brain spec`), print a human-readable report:

```
discovery-loop sweep complete
  Artifact:         <path>
  Status:           <converged | max_rounds | blocked>
  Rounds:           <N>
  Findings/round:   [<N0>, <N1>, ...]
  Total findings:   <len(all_findings)>

Findings (sorted by severity):
  BLOCKER (<count>):
    - <description> @ <location>
    - ...
  DRIFT (<count>):
    - ...
  GAP (<count>):
    - ...
  QUESTION (<count>):
    - ...

Next: apply findings manually, or re-invoke with --auto-revise.
```

## Convergence criteria

The default `convergence_threshold = 3` is a stake-in-ground from the v0.1 build session — sweep rounds that produced ≤3 new findings were observed to be the inflection point where further rounds yielded diminishing returns. Operators can override via `--convergence-threshold N`.

The `max_rounds = 5` cap exists because in practice, well-designed artifacts converge in 2–3 rounds, and pathological artifacts (broken design, unclear scope) keep producing findings indefinitely. Capping at 5 prevents the loop from running forever; the operator gets a warning when max-rounds is hit, signaling the artifact needs structural rework before sweeping further.

## Severity tags — operational definitions

- **BLOCKER** — the finding describes something that WILL cause incorrect behavior or implementation failure if not fixed. Examples: wrong file path; broken dependency; assertion against nonexistent state.
- **DRIFT** — the finding describes stale or contradictory text in the artifact itself. Examples: a "3-way split" claim alongside 4 sub-milestones; test-count math that doesn't add up; references to renamed files.
- **GAP** — the finding describes a missing task or unstated dependency. Examples: no CLAUDE.md update for a behavior-changing milestone; no test for a new feature; missing files-whitelist verification.
- **QUESTION** — the finding describes an open design decision that needs operator input. Examples: which storage format (TOON vs JSON); which probe mechanism (filesystem vs Skill() vs Bash); whether to default opt-in or opt-out.

## Failure modes

- **Artifact unreadable / malformed**: D1 emits `blocked` + stops. No state mutation.
- **All rounds produce 0 findings**: immediately converged on round 1; this is fine (means the artifact is in good shape). Report it.
- **Findings can't be deduped reliably** (LLM judgment is fuzzy): err on the side of treating findings as DISTINCT — better to over-report than to silently merge real issues.
- **Operator interrupts mid-sweep** (Bash returns non-zero or `--stop` flag is set externally): emit a partial report with `status: interrupted, rounds_completed: <N>` and exit.

## Idempotency

Re-running discovery-loop against the same artifact (without `--auto-revise`) is idempotent and read-only. State accumulates in the caller's invocation context, not on disk. If the caller wants persistence, the caller writes the result to a chosen path (e.g., `/brain spec` Sp7 logs to `.brain/log.md`).

## Related

- **`/brain spec` Sp4** — primary caller; M#10a's spec procedure invokes this skill when `ecc:santa-loop` is unavailable
- **`skills/core/spec/SKILL.md`** — defines the `/brain spec` contract that this skill participates in
- **`skills/behavioral/codebrain/SKILL.md`** — meta-skill that establishes the "Read the Prompt Defense Baseline before acting" rule + general agent conduct
- **`ecc:santa-loop`** (external, ECC plugin) — the primary sweep mechanism; this skill is the codebrain-side fallback when ECC isn't installed
