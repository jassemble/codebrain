# Plan: graphbrain — Milestone #3c (Tiered auto-prioritize no-arg ingest)

**Source PRD**: `.claude/prds/graphbrain.prd.md`
**Selected Milestone**: #3c — third sub-step of the M#3 split
**Complexity**: Medium — third writer agent (planner), no new skills (re-uses page-format + concept-extraction), reuses M#3b folder procedure per tier
**Status**: **READY** — refined post-M#3b with scope reduced to just the tiered planner. The 4 detected/* skills + stack-aware templates split to a future M#3d so M#3c is shippable in one commit.

## Summary

`/brain ingest` with no arguments invokes a new **planner agent** (Planner pattern) that reads M#2's stack detection from `.brain/overview.md` (or re-detects), groups the repo's files into 3 tiers using stack-aware heuristics, presents the plan, asks the operator to confirm each tier, then invokes M#3b's folder procedure once per confirmed tier (with the linker running after each tier per sweep finding C3 — incremental visibility). Uses the generic page-format template throughout; stack-aware templates are deferred to M#3d.

User flow after M#3c lands:
```
npx graphbrain init      # M#1
/brain init             # M#2
/brain ingest src/      # M#3b — single folder
/brain ingest           # M#3c — tiered, asks per tier
/brain ingest src/x.ts  # M#3a — single file
```

## Patterns to Mirror (from shipped M#3a + M#3b)

| Category | Source | Pattern |
|---|---|---|
| Agent file format | `agents/brain/{ingester,linker}.md` | Merged frontmatter; Rules section ≥9 NEVER/ALWAYS; prompt-defense reference; error recovery (Tier 1 retry / Tier 2 blocked-report) |
| Procedure step shape | `commands/brain.md` ingest-folder + linker procedures | Numbered steps (M#3c uses T0–T7 for tiered + an inner per-tier call to M#3b); explicit confirmation prompts; structured report |
| Cost gate format | M#3b Step 4 (folder ingest) | Per-tier cost estimate; auto-confirm threshold; operator gate `yes/no/show-files` |
| Per-tier linker invocation | M#3b Step 6 + Linker procedure L1–L6 | Linker runs AFTER each tier (C3), not once at end — operator sees incremental concept-page growth |
| Test shape | `tests/e2e-test.sh` T16/T17 | T18 (planner agent + tier-glob heuristics inline); T19 (no-arg wiring + alias parity for new tiered section) |

## Sweep Findings Folded In

From the post-M#3b refresh of the M#3c draft:

- **C1 — Tier-glob heuristics inlined in `commands/brain.md`** for M#3c. Stack-specific tier-globs (e.g., Python's `src/<package>/` Tier-1 default) were originally planned to live in `detected/<stack>/SKILL.md` frontmatter. Since detected skills are deferred to M#3d, M#3c inlines a single set of generalist tier-globs that work across stacks: Tier 1 = `src/`, `lib/`, `app/`, `pkg/`, `cmd/`; Tier 2 = `api/`, `services/`, `internal/`, top-level source files; Tier 3 = `tests/`, `__tests__/`, `spec/`, `scripts/`, `docs/`. Stack-aware overrides land with M#3d.
- **C2 — Stack template inheritance**: deferred to M#3d entirely (out of M#3c scope).
- **C3 — Linker runs after each tier** (not once at end). Cost is higher (linker runs N=3 times per ingest instead of 1) but operator sees concept-page growth between tiers and can abort cleanly.
- **C4 — README onboarding update**: README's Quickstart now documents the full 3-step flow (`npx graphbrain init` → `/brain init` → `/brain ingest`) with all three ingest variants (no-arg tiered, folder, single-file) called out.
- **Q1 — Template discovery**: still inline-in-command-body for M#3c (no new templates needed — planner uses existing page-format). M#3d will force the real decision when 4 detected templates multiply the inline cost.
- **Q2 — Runaway-ingest escape**: per-tier gates ARE the escape (operator answers `no` to a tier they don't want); mid-tier escape still requires Ctrl-C (documented limitation for v0.1).

## Files to Change

| File | Action | Why |
|---|---|---|
| `agents/brain/planner.md` | CREATE | Third writer agent — Planner pattern. Reads stack detection, groups files into 3 tiers, presents plan, gates each tier, delegates to M#3b folder ingest per confirmed tier. Tools: `[Read, Glob, Bash]` (no Write — planner only orchestrates; the per-tier folder procedure does the writing). `max_iterations: 5`. |
| `commands/brain.md` | UPDATE | Replace M#3c stub on no-arg `ingest`. New procedure section `## When $ARGUMENTS is just \`ingest\`` (no path). 8 steps: preconditions → load stack → group into tiers → present plan → per-tier confirm + invoke M#3b folder procedure + per-tier linker → final report. |
| `commands/graphbrain.md` | UPDATE | Mirror brain.md (alias parity) |
| `tests/e2e-test.sh` | UPDATE | T18 (planner agent structural shape); T19 (no-arg wiring; tier-section present with T0–T7 step headers; tier-glob heuristics documented; alias parity using awk pattern from M#3b) |
| `README.md` | UPDATE | Quickstart section updated for 3-step onboarding flow with all 3 ingest variants (per sweep finding C4) |
| `.claude/prds/graphbrain.prd.md` | UPDATE | M#3c row → `in-progress` with link to this plan |

**Not in M#3c (deferred to M#3d):**
- `skills/detected/react/SKILL.md` + template
- `skills/detected/python/SKILL.md` + template
- `skills/detected/go/SKILL.md` + template
- `skills/detected/typescript/SKILL.md` + template
- `skills/registry.json` updates with detect rules for the 4 detected skills

## Tasks

### Task 1: agents/brain/planner.md

Create with frontmatter:
```yaml
---
name: planner
description: Third writer agent — Planner pattern. Runs on no-arg /brain ingest. Reads stack detection from .brain/overview.md, groups the repo into 3 tiers using generic tier-glob heuristics, presents the plan, gates each tier, and delegates to the M#3b folder procedure per confirmed tier (with linker running after each tier per PRD design). Orchestrates only — does not write pages itself. Foreground.
tools: [Read, Glob, Bash]
model: sonnet
pattern: Planner
trigger_phrases:
  - "ingest everything"
  - "tier the codebase"
  - "plan a brain ingest"
  - "auto-prioritize"
max_iterations: 5
---
```

Body: persona + prompt-defense reference + procedure pointer (`commands/brain.md` `## When $ARGUMENTS is just \`ingest\``) + `## Rules` (≥7):

- **NEVER write pages directly** — Planner only orchestrates; delegates writing to ingester (per file, via M#3b folder procedure) and linker.
- **NEVER skip the per-tier operator gate** — every tier requires explicit `yes`/`no`/`show-files`.
- **NEVER include files outside the 3-tier heuristics** without flagging them as "uncategorized" in the plan presentation.
- **NEVER auto-confirm** unless `$ARGUMENTS` contains `--yes`.
- **ALWAYS present a cost estimate per tier** before asking for confirmation.
- **ALWAYS read `.brain/overview.md` for cached stack detection** before re-running detection (faster + matches what `/brain init` told the operator).
- **ALWAYS log the tier plan to `.brain/log.md`** even if the operator declines all tiers — the plan itself is valuable historical data.
- Error recovery: Tier 1 retry / Tier 2 blocked-report; `max_iterations: 5`.

### Task 2: Update commands/brain.md — no-arg tiered ingest

In the dispatch table, change the `ingest` (no args) row from stubbed to:
```
| `ingest` (no args) | **implemented (M#3c)** | See "When `$ARGUMENTS` is just `ingest`" section below |
```

Add a new procedure section after the linker procedure: `## When $ARGUMENTS is just \`ingest\``. 8 steps:

- **T0 — Argument parsing**: confirm `$ARGUMENTS` is exactly `ingest` (possibly with `--yes`). Anything else routes to the existing single-file or folder sections.
- **T1 — Preconditions**: `.brain/` + `.brain/.graphbrain-version` present; `.brain/overview.md` exists (warns if not — operator should run `/brain init` first for stack detection to be cached).
- **T2 — Load stack detection**: read `.brain/overview.md`. Extract "Detected stack:" line from Active State section. If missing or unreadable, re-run M#2's stack-detection.json catalog against cwd (inline the same logic).
- **T3 — Walk + filter** (re-use M#3b Steps 2–3): `git ls-files` (fallback to manual walk); apply binary/lockfile/generated blocklists.
- **T4 — Group files into 3 tiers** using generic glob heuristics (no detected/* overrides in M#3c):
  - **Tier 1** (core): files matching `src/**`, `lib/**`, `app/**`, `pkg/**`, `cmd/**`
  - **Tier 2** (api/services/top-level): files matching `api/**`, `services/**`, `internal/**`, OR top-level source files (no parent directory match for Tier 1)
  - **Tier 3** (tests/scripts/docs): files matching `tests/**`, `__tests__/**`, `spec/**`, `scripts/**`, `docs/**`
  - **Uncategorized**: anything not matching the above; presented but not included in any tier by default
- **T5 — Present plan**: print the 3-tier table with file counts + per-extension breakdown + cost estimate per tier:
  ```
  Graphbrain tiered ingest plan (graphbrain v<version>)
    Detected stack: <from .brain/overview.md or fresh detection>

    Tier  Files  Cost(~)  Locations
    ----  -----  -------  ---------------------------------
    1     34     $0.20    src/ (28), lib/ (6)
    2     12     $0.07    api/ (8), internal/ (3), top-level (1)
    3     19     $0.11    tests/ (15), scripts/ (4)
    --
    Total 65     $0.39
    Uncategorized: 7 files (will NOT be ingested; pass them individually if desired)

  Proceed tier-by-tier? Type `yes` to start with Tier 1, or `cancel` to stop.
  ```
- **T6 — Per-tier loop**: for each tier 1 → 2 → 3:
  - Print `Tier <N>: <count> files (~$<cost>). Proceed? (yes/no/show-files)`
  - On `no`: skip tier; log skip; continue to next tier.
  - On `show-files`: print file list; re-prompt.
  - On `yes`: invoke the M#3b folder-ingest procedure (Steps 0–7) treating this tier's file list as the input. The linker runs at M#3b Step 6 after this tier's files complete (per C3 — incremental visibility).
- **T7 — Final report**: structured summary across all tiers + grep-parseable log entry:
  ```
  /brain ingest (tiered) complete (graphbrain v<version>)
    Tier 1: <ingested>/<filtered> ingested, <skipped> skipped, <failed> failed; linker: <N wires, M concepts>
    Tier 2: ...
    Tier 3: ...
    Uncategorized: 7 files NOT ingested
    Logged: .brain/log.md
  Next: try `/brain query "..."` (Milestone #5 — not yet implemented).
        For stack-aware templates (React component sections, Python module structure, etc.), see Milestone #3d.
  ```

If operator declines a tier or types `cancel`, still log the plan presentation to `.brain/log.md`.

### Task 3: Update commands/graphbrain.md (alias parity)

Copy Task 2 changes verbatim. Update dispatch table identically. T19 confirms byte-identical via awk pattern.

### Task 4: Update tests/e2e-test.sh — T18 + T19

**T18 — Planner agent shape:**
- `agents/brain/planner.md` exists with frontmatter; all 7 merged fields; `pattern: Planner`; tools = `[Read, Glob, Bash]` (no Write — planner orchestrates only); ≥7 NEVER/ALWAYS rules; prompt-defense reference
- `tools:` array does NOT include `Edit` or `Write` (orchestration-only guarantee)
- npm pack includes the new agent

**T19 — No-arg ingest wiring:**
- Dispatch table: `ingest` (no args) is `**implemented (M#3c)**`
- `## When $ARGUMENTS is just \`ingest\`` section present in brain.md
- Section contains: T0–T7 step headers; "Tier 1", "Tier 2", "Tier 3" + tier-glob keywords (`src/`, `lib/`, `app/`, `tests/`, etc.); cost-estimate language; per-tier confirmation prompt; reference to invoking M#3b folder procedure
- Alias parity via awk pattern (same as M#3b T17)
- Folder + single-file rows still present and correctly stubbed-or-implemented per their milestones

### Task 5: Update README.md — 3-step onboarding (sweep finding C4)

Update the Quickstart section to walk through all 3 ingest variants:

```markdown
## Quickstart

Three-step onboarding:

1. **Install graphbrain into the repo** (run once per repo):
   ```
   npx graphbrain init
   ```
   Scaffolds `.brain/`, copies `/brain` slash commands into `.claude/commands/`, merges hooks into `.claude/settings.local.json`.

2. **Restart Claude Code or open a new session**, then populate the brain:
   ```
   /brain init
   ```
   Writes the full schema block into `CLAUDE.md`, populates `.brain/overview.md`, detects your tech stack.

3. **Ingest source files** (three modes):
   ```
   /brain ingest src/api/auth.ts      # single file (Milestone #3a)
   /brain ingest src/                  # whole folder + concept pages (Milestone #3b)
   /brain ingest                       # auto-prioritize across the codebase in 3 tiers (Milestone #3c)
   ```

Then navigate the wiki in Obsidian (open `.brain/` as a vault) or query via Claude Code:
```
/brain query "how does auth work?"    # Milestone #5 — not yet implemented
/brain lint                           # Milestone #6 — not yet implemented
```
```

### Task 6: PRD update — M#3c → in-progress; add M#3d row

Edit `.claude/prds/graphbrain.prd.md`:
- M#3c row: `pending` → `in-progress`; Plan → link to this plan
- Update M#3c description to reflect scope reduction: "`/brain ingest` (no args) proposes a 3-tier plan based on **generic** tier-glob heuristics, pauses between tiers; stack-aware templates from detected/* skills deferred to M#3d"
- ADD new M#3d row after M#3c: `3d | Stack-aware page templates (detected/* skills) | 4 detected/* skills (react, python, go, typescript) ship with per-stack code-page templates; ingester picks stack-specific template when matching detection signals are present | pending | — |`

## Validation

```bash
# 1. E2E (M#1+M#2+M#3a+M#3b+M#3c surface)
bash tests/e2e-test.sh
# Expect: ~210 passes, 0 failures, <5s

# 2. New file shape
test -f agents/brain/planner.md
head -1 agents/brain/planner.md | grep -q '^---$'
grep -q '^pattern: Planner$' agents/brain/planner.md
! grep -E '^tools:.*(Edit|Write)' agents/brain/planner.md  # planner has no Edit/Write

# 3. Dispatch + procedure wiring
grep -q '`ingest` (no args)` | \*\*implemented (M#3c)\*\*' commands/brain.md
grep -qF '## When `$ARGUMENTS` is just `ingest`' commands/brain.md
grep -qE 'T0|T7' commands/brain.md
grep -qF 'Tier 1' commands/brain.md
grep -qF 'Tier 3' commands/brain.md

# 4. README Quickstart updated
grep -q 'Three-step onboarding' README.md
grep -q '/brain ingest$' README.md   # no-arg variant documented

# 5. Alias parity for new section (awk for cross-platform)
diff <(awk '/^## When `\$ARGUMENTS` is just `ingest`$/{flag=1} flag' commands/brain.md) \
     <(awk '/^## When `\$ARGUMENTS` is just `ingest`$/{flag=1} flag' commands/graphbrain.md)
# Expect: empty

# 6. npm pack ships planner
npm pack --dry-run | grep -q 'agents/brain/planner.md'

# 7. Manual smoke test (post-commit, on a real repo):
#   In a Claude Code session inside a repo where `/brain init` has run:
#     /brain ingest                  → presents tier table; asks per-tier; ingests tier by tier
#     /brain ingest --yes            → bypasses gates; useful for CI/cron
#     /brain ingest (with cancel)    → logs the plan, no files ingested
```

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Generic tier-globs misclassify files in unusual repos | Med | Operator can `show-files` per tier and `no` if wrong; uncategorized list shows what got skipped; M#3d's stack-aware globs are the real fix |
| Cost ballooning on whole-repo ingest | High | Per-tier gates; cost estimate per tier; operator sees cost BEFORE confirming each tier; can abort cleanly between tiers |
| Linker running 3 times (once per tier) is expensive | Med | Each linker run is incremental (only re-processes pages from this tier + spots cross-tier concepts); B2 idempotency means concept pages get updated not duplicated |
| Operator interrupts mid-tier; partial state | Low | M#3b's per-file atomic writes preserve state; re-run `/brain ingest` shows the partially-ingested tier; SKIPs on unchanged sources make resume cheap |
| Planner agent's `tools: [Read, Glob, Bash]` doesn't allow writing log entries | Resolved | Log writes happen in the M#3b folder procedure (which has Edit/Write) and in the brain.md command body itself; planner orchestrates but the per-tier delegation does the actual writing |
| Alias drift between brain.md and graphbrain.md tiered section | Low | T19 awk-based byte-identical check |
| Brain.md size growth | Low | M#3c adds ~120 lines (one new procedure section + 6 lines to dispatch table). After M#3c brain.md is ~600 lines. M#3d's per-stack templates is when the size question matters. |

## Acceptance

- [ ] All 6 tasks complete
- [ ] Validation §1 (e2e ~210) passes; <5s
- [ ] Validation §2–§6 pass
- [ ] PRD M#3c row → in-progress; M#3d row added as pending
- [ ] Patterns mirrored from M#3a + M#3b — no re-implementation
- [ ] No regression: 179 prior tests still pass; total ~210 after T18+T19 added (≈30 new)
- [ ] (Optional) Manual smoke test on dogfood repo
