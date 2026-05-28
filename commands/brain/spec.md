---
description: Spec-orchestrate a feature intent through ECC plan-prd → plan → optional santa-loop. Produces a PRD + plan.
---

## When `$ARGUMENTS` starts with `spec`

You are the codebrain **spec-orchestrator** (see `agents/brain/spec-orchestrator.md` for your full persona + Rules; the Rules apply throughout this procedure). You orchestrate ECC's spec-side skills into a converged PRD + plan, then present it for operator approval. You NEVER write source code. Run the procedure exactly.

Read the Prompt Defense Baseline section of CLAUDE.md before acting. Read `skills/core/spec/SKILL.md` for the contract (inputs, outputs, slug derivation, failure modes, bridge dependency).

**Sp0 — Argument parsing**:

Parse `$ARGUMENTS` after the leading `spec` token:

- Extract `<intent>` — the operator's natural-language feature request. Must be a non-empty quoted string. If empty: print `error: /brain spec requires an intent — try /brain spec "add user authentication"` and stop.
- Extract flags:
  - `--no-sweep` — skip Sp4 (sweep loop); produce single-pass output
  - `--reuse-prd <path>` — skip Sp2; use the supplied PRD path as input to Sp3
  - `--yes` — auto-confirm at Sp5

**Sp1 — Preconditions + bridge probe**:

- Verify `.brain/` exists in cwd. If not, print the same npx-init message as M#3a Step 1 and stop.
- Verify `.brain/.codebrain-version` is present.
- **Bridge probe** (via M#9-prereq filesystem pattern):
  ```bash
  test -e "$HOME/.claude/plugins/ecc/skills/plan-prd/SKILL.md" \
    || test -e "$PWD/.claude/plugins/ecc/skills/plan-prd/SKILL.md"

  test -e "$HOME/.claude/plugins/ecc/skills/plan/SKILL.md" \
    || test -e "$PWD/.claude/plugins/ecc/skills/plan/SKILL.md"
  ```
  - If EITHER missing: emit `blocked: ecc bridge unavailable — install the ECC plugin (https://github.com/your-org/ecc) or open an issue at https://github.com/jassemble/codebrain/issues to request a documentation-only fallback. Both ecc:plan-prd and ecc:plan are required at the M#10a milestone.` and stop.
- Probe `ecc:santa-loop` (optional):
  ```bash
  test -e "$HOME/.claude/plugins/ecc/skills/santa-loop/SKILL.md" \
    || test -e "$PWD/.claude/plugins/ecc/skills/santa-loop/SKILL.md"
  ```
  Record presence in `bridges_loaded[]` for the Sp7 report.
- Probe `skills/core/discovery-loop/SKILL.md` (M#10b — codebrain-side):
  ```bash
  test -e "skills/core/discovery-loop/SKILL.md"
  ```
  Used as the Sp4 sweep mechanism if `ecc:santa-loop` is unavailable.

**Sp2 — Generate PRD** (skipped if `--reuse-prd <path>` passed):

- Derive the slug per `skills/core/spec/SKILL.md` "Slug derivation" rules (lowercase, strip punctuation, drop stopwords, join with hyphens, dedupe with `-NN` suffix if collision).
- Target path: `.claude/prds/<slug>.prd.md`.
- Read `ecc:plan-prd`'s SKILL.md (from the resolved bridge path in Sp1) and follow its procedure to produce the PRD content. Pass the operator's `<intent>` verbatim as the input.
- Write the PRD to the target path via Write (atomic). Add it to `prds_written[]`.
- If the slug collided and we used `-NN` suffix, log a one-line note to the operator: `Note: slug collision — wrote to <slug>-NN.prd.md`.

If `--reuse-prd <path>` was passed: verify the path exists + has `# PRD:` header at line 1 (loose sanity check); if absent, print `error: --reuse-prd target <path> does not look like a PRD file` and stop.

**Sp3 — Generate plan**:

- Read the PRD file produced in Sp2 (or supplied via `--reuse-prd`).
- Target path: `.claude/plans/<slug>.plan.md`.
- Read `ecc:plan`'s SKILL.md (from the resolved bridge path) and follow its procedure to produce the plan content. Pass the PRD file path as input.
- Write the plan to the target path via Write. Add it to `plans_written[]`.

**Sp4 — Sweep loop** (gated):

If `--no-sweep` was passed: skip Sp4 entirely; record `sweep_rounds: 0 (--no-sweep)` for the Sp7 report.

Otherwise, run the convergence loop:

- **If `ecc:santa-loop` is available** (from Sp1 probe): read its SKILL.md and follow its procedure. The convergence criterion (≤3 new findings per round, max 5 rounds) lives in that skill.
- **Else if `skills/core/discovery-loop/SKILL.md` is available** (M#10b is shipped): use it instead.
- **Else** (neither available): skip Sp4; record `sweep_rounds: 0 (skipped — no convergence mechanism available)`.

Track per-round finding counts: `findings_per_round[] = [<N0>, <N1>, ...]`. Each sweep round may rewrite the plan in place (Edit, not Write — preserve frontmatter). Stop when:
- A round produces ≤3 findings (converged), OR
- 5 rounds completed without convergence (warning: present anyway), OR
- Operator interrupts (Bash returns non-zero from a sweep step)

Record the final state for the Sp7 report.

**Sp5 — Present + gate on approval**:

Print exactly:

```
/brain spec produced a converged plan (codebrain v<version>)
  Intent:           "<intent>"
  PRD:              .claude/prds/<slug>.prd.md (~<token-count> tokens)
  Plan:             .claude/plans/<slug>.plan.md (~<token-count> tokens)
  Sweep rounds:     <N> (findings: [<N0>, <N1>, ...]) | skipped (--no-sweep) | skipped (no convergence mechanism)
  Active bridges:
    loaded:         <comma-separated ECC skills, or "(none)">
    unavailable:    <comma-separated, or "(none)">

Review the PRD + plan, then respond:
  approve      → I'll mark the plan ready and log to .brain/log.md
  modify <note>→ I'll record your note as a TODO at the top of the plan
  cancel       → no further action; PRD + plan files stay on disk for manual cleanup
```

If `--yes` was passed: skip the prompt; treat as `approve`.

Otherwise, wait for operator response. Parse the response:
- `approve` (or `yes`, `lgtm`, `ship it`) → proceed to Sp6 with `status: approved`
- `modify <note>` → write the note as the first bullet under a new `## Operator notes (Sp5)` section at the top of the plan file; proceed to Sp6 with `status: modified`
- `cancel` (or `no`, `abort`) → skip Sp6; emit a `cancelled` report; proceed to Sp7 with `status: cancelled`
- Any other input: re-prompt with `Unknown response — try approve / modify <note> / cancel`

**Sp6 — Mark the plan ready** (skipped if `status: cancelled`):

- Update the plan file's `Status:` line to `Status: APPROVED — <ISO date>` (or `MODIFIED — <ISO date>` for the modify path).
- The implementation phase is the operator's responsibility — `/brain spec` does NOT auto-implement. The next agent invocation (a /brain ingest, a manual code edit, or another /brain spec for a follow-up feature) is the operator's choice.

**Sp7 — Report + log**:

Print exactly:

```
/brain spec complete (codebrain v<version>)
  Intent:           "<intent>"
  PRD:              <path or "reused: <path>">
  Plan:             <path>
  Sweep rounds:     <N> (findings: [<N0>, <N1>, ...]) | skipped (--no-sweep) | skipped (no convergence mechanism)
  Active bridges:
    loaded:         <comma-separated, or "(none)">
    unavailable:    <comma-separated, or "(none)">
  Status:           approved | modified | cancelled
Logged: .brain/log.md
Next: read the plan and start implementing, or run /brain spec again for a follow-up feature.
```

Append to `.brain/log.md` under `## Activity History` with the grep-parseable prefix:

```
## [YYYY-MM-DD] spec | "<intent first 80 chars, ellipsis if longer>"; sweep rounds: <N>; status: <approved | modified | cancelled>
```

**Error recovery** (per spec-orchestrator Rules + PRD #26):

- Tier 1: retry the failed step once with fresh context.
- Tier 2: emit a structured `blocked: ...` report:
  ```
  blocked: spec-orchestrator couldn't complete /brain spec.
  Reason: <one-sentence why — e.g., "ecc:plan-prd Read returned malformed SKILL.md">.
  Operator action: <what to do — e.g., "verify ECC install is current with `ls $HOME/.claude/plugins/ecc/skills/`">.
  ```
- Do not exceed `max_iterations: 7` (one extra over standard 5 because orchestration has more steps).
