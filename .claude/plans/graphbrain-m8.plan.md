# Plan: graphbrain — Milestone #8 (Dogfood + measure)

**Source PRD**: `.claude/prds/graphbrain.prd.md`
**Selected Milestone**: #8 — Dogfood + measure
**Complexity**: Small-to-Medium — no new agents/skills; ships a validation harness + a dogfood install runner + a validation-report template; honest about what can be automated vs what requires a real Claude Code session
**Status**: READY — 6 sweep findings (H1–H6) inline

## Summary

Validate whether graphbrain v0.1 actually works as the PRD claims. Two-part deliverable:

1. **Automatable now** (this session): static install validation on graphbrain itself; verify the scaffold is correct, hooks land in the right shape, npm pack ships the right files, the slash-command surface dispatches correctly.
2. **Manual follow-up** (requires real Claude Code sessions): the LLM-driven measurements — token reduction on structural questions, freshness drift over days of editing, wikilink precision via sampled review. These need real agent sessions, real time, and real edits — not bash-testable in one shot.

The validation report template (`.claude/validation/v0.1-baseline.md`) gets populated as the operator accumulates evidence. M#8 ships the framework + the static baseline; the cross-repo + LLM-driven validations are documented as follow-up steps for the operator.

After M#8 ships, graphbrain v0.1 is **publishable to npm** — the framework can collect evidence over time, but the codebase itself is feature-complete + validated as far as bash can validate.

## Patterns to Mirror (from shipped M#1–M#6)

| Category | Source | Pattern |
|---|---|---|
| Static validation script style | `tests/e2e-test.sh` | bash, pass/fail counters, structural assertions, fast (<5s) |
| Manual-procedure documentation | `commands/brain.md` (Q0–Q7 / L0–L7 numbered steps) | Numbered steps the operator follows; preconditions; expected outputs |
| Report shape | `commands/brain.md` Q7 (query report) / L7 (lint report) | Structured sections + grep-parseable summary lines |
| Cross-platform bash | `tests/e2e-test.sh` awk-not-head-n-minus-1 fix | Same constraints apply to dogfood scripts |

## Sweep Findings (H1–H6, folded in)

- **H1 — Dogfood on graphbrain itself first**: the most honest test. If graphbrain can't usefully ingest its own scaffold, it's not ready for any other repo. M#8's automatable portion runs against the graphbrain repo at `/Users/dev/Desktop/Project/OSS/idea/graphbrain/`.
- **H2 — Don't mix automated + manual in one script**: keep `scripts/dogfood/install-validate.sh` (automatable) separate from `scripts/dogfood/MANUAL-MEASUREMENTS.md` (operator procedure). Cleanly separates what bash can verify from what needs an LLM-in-the-loop session.
- **H3 — The validation report is a template, not a finished doc**: ship `.claude/validation/v0.1-baseline.md` with sections + placeholders + instructions for what to measure. The operator fills it in as evidence arrives. Mirrors how PRDs ship with "TBD — needs validation via X" markers.
- **H4 — Measure only what we know how to measure**: don't invent metrics. PRD §Success Metrics lists 6 items. M#8 codifies the measurement procedure for each one — automatable static checks for some (e.g., scaffold completeness can be measured now), operator-procedure for the LLM-driven ones (e.g., token reduction A/B).
- **H5 — The 3 target repos are explicit**: PRD says "3 sample repos (graphbrain itself + 2 OSS targets)". The 2 OSS targets are the natural choices given context: graphify and graphbrain at `/Users/dev/Desktop/Project/OSS/idea/{graphify,graphbrain}/`. ECC is also a reasonable target but is larger. Pick graphify + graphbrain as the 2 OSS targets; document both.
- **H6 — `validate` CLI verb deferred to post-MVP**: tempting to add `npx graphbrain validate` that runs the static checks. Defer — it duplicates the bash script's purpose without adding much value for v0.1. The bash scripts ship as documented entry points.

## Files to Change

| File | Action | Why |
|---|---|---|
| `scripts/dogfood/install-validate.sh` | CREATE | Bash script: runs `node bin/graphbrain.js init` in a tmp clone of graphbrain itself, asserts the scaffold is correct, hooks land in `.claude/settings.local.json` with proper `graphbrain:*` ids, expected files present. Effectively a "real-world install" test on top of the e2e test. |
| `scripts/dogfood/static-baseline.sh` | CREATE | Bash script: gathers static measurements that don't require a Claude Code session: line counts per shipped file, frontmatter validity across all agents/skills, npm pack contents summary, surface area per agent pattern. Outputs `.claude/validation/v0.1-static-baseline.md` for the validation report. |
| `scripts/dogfood/MANUAL-MEASUREMENTS.md` | CREATE | Operator procedure: documented step-by-step for running the LLM-driven measurements — token-reduction A/B, freshness drift, wikilink precision sampling. Numbered like a procedure section. Includes the canned questions for the 10-question A/B. |
| `.claude/validation/v0.1-baseline.md` | CREATE | Validation-report template. Sections per PRD success metric. Pre-filled with status `pending` and instructions per section. Gets populated by the operator as measurements come in. |
| `tests/e2e-test.sh` | UPDATE | T30 — dogfood scripts exist + are executable + reference the right paths. T31 — `install-validate.sh` runs successfully against graphbrain (smoke). T32 — `static-baseline.sh` runs successfully and produces a valid report file. |
| `.claude/prds/graphbrain.prd.md` | UPDATE | M#8 row → `complete` (the framework ships); add a footnote that full validation is operator-driven over time. |
| `README.md` | UPDATE | Add a "Dogfood + validate" section pointing operators at `scripts/dogfood/MANUAL-MEASUREMENTS.md` and the baseline report. |

**Not in M#8 (intentional):**
- `npx graphbrain validate` CLI verb (H6 — defer)
- Cross-repo benchmarking infrastructure (post-MVP)
- Continuous measurement reporting (post-MVP)
- Per-repo validation reports for graphify/graphbrain/ECC (operator runs MANUAL-MEASUREMENTS.md on each)

## Tasks

### Task 1: scripts/dogfood/install-validate.sh

Bash script with the standard test harness pattern (pass/fail counter, `ok`/`nope` helpers). Steps:

- Create a tmpdir; copy graphbrain into it (or clone — `git clone $CODEBRAIN_ROOT $TMPDIR` keeps it git-aware)
- Create a "fake user repo" tmpdir with `.git/` so the project-dir guard passes
- Run `node $CODEBRAIN_COPY/bin/graphbrain.js init` from the fake user repo
- Assert the full scaffold (already covered by T1-T7 in e2e-test.sh — but rerun here AGAINST the actual install path, not a unit fixture)
- Specifically assert:
  - `.brain/` complete (code/, concepts/, decisions/, .graphbrain-version, the 5 .md files)
  - `.claude/commands/brain.md` + `graphbrain.md` present + match the source templates byte-for-byte
  - `.claude/settings.local.json` has both `graphbrain:` hook entries with correct shape
  - `CLAUDE.md` has the managed-region markers
- Print summary; exit 0 on success, 1 on failure
- Runtime <5s

### Task 2: scripts/dogfood/static-baseline.sh

Bash + node script. Gathers measurements that don't need an LLM:

```
=== graphbrain v0.1.0 static baseline ===

Date: <ISO>
Repo SHA: <git rev-parse HEAD>

## Shipped artifacts
  bin/graphbrain.js:               <line count>
  scripts/init.js:                <line count>
  scripts/hooks/stale-detect.js:  <line count>
  scripts/hooks/verified-guard.js: <line count>
  scripts/hooks/lib/page-io.js:   <line count>
  commands/brain.md:              <line count>
  commands/graphbrain.md:          <line count>
  Total source LOC:               <sum>

## Agents
  Total: <count>
  By pattern:
    Meta:       <count>
    Generator:  <count> [names]
    Reviewer:   <count> [names]
    Planner:    <count> [names]
    Researcher: <count> [names]
    Verifier:   <count> [names]
    Observer:   <count> [names — currently 0]

## Skills
  Total: <count>
  By tier:
    behavioral: <count> [names]
    ingestion:  <count> [names]
    core:       <count> [names]
    detected:   <count> [names]
    available:  <count> [names]

## Templates
  Total: <count>
  Per-skill: <names>

## Plugin / npm package
  package.json version: <semver>
  files: whitelist count: <count>
  npm pack --dry-run: total files / total kB

## Slash commands surface
  /brain verbs implemented: [list]
  /brain verbs stubbed: [list with milestone tags]

## Hooks
  PreToolUse graphbrain entries: <count> [ids]
  PostToolUse graphbrain entries: <count> [ids]

## Test coverage
  e2e-test.sh assertions: <count>
  Test runtime: <seconds>
```

Outputs to `.claude/validation/v0.1-static-baseline.md`.

### Task 3: scripts/dogfood/MANUAL-MEASUREMENTS.md

Operator procedure document (markdown, not a script). Numbered steps the operator follows in a real Claude Code session.

Sections:

**M1 — Token-reduction A/B (10 questions × 3 repos = 30 measurements)**

- Repos: graphbrain (this one), graphify (`/Users/dev/Desktop/Project/OSS/idea/graphify`), graphbrain (`/Users/dev/Desktop/Project/OSS/idea/graphbrain`)
- For each repo:
  1. `npx graphbrain init`
  2. `/brain init`
  3. `/brain ingest src/` (or appropriate path)
  4. Run each of the 10 canned questions BOTH ways:
     - **Baseline (grep+read)**: operator pastes the question to a fresh Claude Code session in the repo; agent uses grep + Read to answer; record token cost via `/cost` or session metrics
     - **With brain**: operator pastes the question with prefix "Use /brain query"; agent invokes M#5 procedure; record token cost
  5. Compute reduction: `(baseline - brain) / baseline × 100`
- Target: ≥50% reduction on average
- Canned questions (cross-cutting + structural mix):
  1. "What does this codebase do?"
  2. "How does authentication work end-to-end?"
  3. "What does <pick a file> export?"
  4. "Where do we touch <pick an integration / library>?"
  5. "What's the role of <pick a module>?"
  6. "What are the main entry points?"
  7. "What are the key data structures / domain entities?"
  8. "Where would I add a new <pick a feature>?"
  9. "What conventions does this codebase follow?"
  10. "What's the error-handling pattern?"

**M2 — Freshness drift (≥7 days of typical agent work)**

- After M1's ingest: leave the brain in place
- Do normal coding work for a week (edits via Claude Code sessions; hook auto-flips STALE)
- After 7 days: run `/brain lint`; count true-stale pages
- Target: < 5% of total pages are true-stale

**M3 — Wikilink precision (manual sample)**

- After M1's ingest: sample 100 random wikilinks from `.brain/**/*.md`
- For each, manually verify:
  - The target page exists (lint already catches this)
  - The relationship described matches the source code reality (does `[[code/auth.ts]] — issues JWTs` actually correspond to a file that issues JWTs?)
- Target: ≥90% precision

**M4 — Time-to-first-value (wall-clock)**

- Fresh machine (or remove `.brain/`, `.claude/commands/brain*`, settings.local.json graphbrain entries)
- Stopwatch start
- `npx graphbrain init`
- `/brain init`
- `/brain ingest src/<the most important file or folder>`
- `/brain query "what does this codebase do?"`
- Stopwatch stop when operator has the answer
- Target: < 5 minutes

**M5 — Continuous-learning lift (TBD — Milestone #7 dependency)**

- M#7 ships the observer agent + XDG instinct store. M#8's M5 measurement can't run until M#7 ships.
- Document as `pending Milestone #7`.

Each section ends with: "Record your measurement in `.claude/validation/v0.1-baseline.md` under section <X>."

### Task 4: .claude/validation/v0.1-baseline.md

Report template. Pre-populated with structure + status placeholders the operator updates as evidence arrives. Sections mirror the PRD's Success Metrics table.

Template content:
- Header (date, graphbrain version, summary status)
- Static baseline (filled in by `static-baseline.sh`)
- Per-metric sections (M1–M5 from the manual procedure), each with:
  - Target (from PRD)
  - Status: `pending | in-progress | met | missed`
  - Measurement (filled in as evidence arrives)
  - Notes
- Overall verdict (filled in when ≥4 metrics are measured)

### Task 5: tests/e2e-test.sh — T30 + T31 + T32

**T30 — Dogfood scripts exist:**
- `scripts/dogfood/install-validate.sh` exists + is executable + has shebang
- `scripts/dogfood/static-baseline.sh` exists + is executable + has shebang
- `scripts/dogfood/MANUAL-MEASUREMENTS.md` exists; contains all M1-M5 section headers
- `.claude/validation/v0.1-baseline.md` exists; contains all per-metric sections

**T31 — Install-validate runs successfully:**
- Run `bash scripts/dogfood/install-validate.sh`; assert exit 0
- Runtime <10s (slightly higher than e2e because it does a full install)

**T32 — Static-baseline runs successfully:**
- Run `bash scripts/dogfood/static-baseline.sh`; assert exit 0
- Assert the output file `.claude/validation/v0.1-static-baseline.md` was created
- Assert key sections present in the output

### Task 6: README.md update

Add a section after Roadmap:

```markdown
## Dogfood + validate

Graphbrain ships with a validation harness for measuring whether the wiki delivers on its claims.

**Static checks** (automated, run anytime):
```
bash scripts/dogfood/install-validate.sh   # validates clean install
bash scripts/dogfood/static-baseline.sh    # gathers shipped-artifact metrics
```

**LLM-driven measurements** (operator procedure, requires real Claude Code sessions):
See `scripts/dogfood/MANUAL-MEASUREMENTS.md` for the step-by-step.

Results land in `.claude/validation/v0.1-baseline.md` — a living report you fill as evidence accumulates.
```

### Task 7: PRD update — M#8 → complete

`.claude/prds/graphbrain.prd.md` M#8 row → `complete` with plan link. Add footnote: "Validation framework ships; full LLM-driven validation is operator-driven over time via scripts/dogfood/MANUAL-MEASUREMENTS.md."

## Validation

```bash
# 1. E2E (combined M#1-M#6 + M#8)
bash tests/e2e-test.sh
# Expect: ~450 passes, 0 failures, <10s (install-validate adds time)

# 2. Dogfood scripts run
bash scripts/dogfood/install-validate.sh && echo "install OK"
bash scripts/dogfood/static-baseline.sh && echo "baseline OK"
test -f .claude/validation/v0.1-static-baseline.md

# 3. Manual procedure document is complete
for section in M1 M2 M3 M4 M5; do
  grep -q "^## ${section}" scripts/dogfood/MANUAL-MEASUREMENTS.md
done

# 4. Validation report template
for metric in 'Token reduction' 'Stale-page detection' 'Wiki freshness' 'Time-to-first-value' 'Wikilink precision' 'Continuous-learning lift'; do
  grep -qF "$metric" .claude/validation/v0.1-baseline.md
done

# 5. npm pack includes the new scripts (so operators of the npm package can dogfood too)
npm pack --dry-run | grep -q 'scripts/dogfood/install-validate.sh'
npm pack --dry-run | grep -q 'scripts/dogfood/MANUAL-MEASUREMENTS.md'
```

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Operator skips manual measurements; v0.1 ships without validation evidence | High | The README explicitly calls out the dogfood section + points at the manual procedure; the validation report template literally has `pending` in every operator-driven section, making the gap visible |
| Static baseline becomes outdated as codebase evolves | Med | Script regenerates on demand; rerun before any release |
| Install-validate fails on operator's machine due to platform differences | Low | Uses same bash patterns as e2e-test.sh (already cross-platform-tested); same `awk` instead of `head -n -1` discipline |
| `.claude/validation/` directory is gitignored or not committed | Low | Add to commit explicitly; validation reports ARE source-of-truth historical data, like ADRs |
| Operator measurements diverge wildly across repos (e.g., graphbrain shows 60% token reduction, graphify shows 20%) | Possible | Report each repo separately in the baseline; the AVERAGE matters less than the per-repo number. Repos with poor results are signals for M#3d-style stack-aware improvements. |

## Acceptance

- [ ] All 7 tasks complete
- [ ] Validation §1 (e2e ~450 with T30-T32) passes
- [ ] Validation §2 (dogfood scripts run successfully) passes
- [ ] Validation §3 (manual procedure complete with M1-M5) passes
- [ ] Validation §4 (report template has all 6 metric sections) passes
- [ ] Validation §5 (npm pack ships dogfood scripts) passes
- [ ] PRD M#8 row → complete with footnote about operator-driven validation
- [ ] README mentions Dogfood + validate
- [ ] No regression: 432 prior tests pass; total ~450 after T30-T32 (≈18 new)
