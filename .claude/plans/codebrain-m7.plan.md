# Plan: codebrain — Milestone #7 (Continuous-learning observer)

**Source PRD**: `.claude/prds/codebrain.prd.md`
**Selected Milestone**: #7 — Continuous-learning observer
**Complexity**: Medium-to-Large — sixth and final agent pattern (Observer); first XDG-persisted state; new PreToolUse hook for fast observation; deterministic consolidation for v0.1 (LLM-driven distillation deferred)
**Status**: READY — 9 sweep findings (J1–J9) inline

## Summary

The continuous-learning loop. After M#7, when `learn` is toggled on for a project:

1. **PostToolUse hook** (`codebrain:pre:observe`) fires on every Edit/Read/Write/Bash/etc. tool call, appends a minimal observation record (`{ts, tool, path?, status}`) to `<XDG>/projects/<git-hash>/observations.jsonl`. Fast (<100ms), async, no LLM, exits 0 always.
2. **Operator periodically runs** `/brain learn consolidate` — the observer agent reads accumulated observations, applies **deterministic** pattern counting (frequency ≥3 → instinct), writes `<XDG>/projects/<git-hash>/instincts.jsonl`. LLM-driven distillation is a v0.2 enhancement.
3. **Operator views** `/brain learn status` (per-project) or `/brain status` (project dashboard) — counts of observations, instincts, top patterns.
4. **Future v0.2** `--llm-distill` flag adds LLM-based pattern recognition on top.

After M#7 ships, **codebrain v0.1 is feature-complete**: 6 agent patterns, 5 skill tiers, 4-tier staleness, complete ingest/query/lint/learn loop, dogfood-validated.

## Patterns to Mirror

| Category | Source | Pattern |
|---|---|---|
| Hook script shape | `scripts/hooks/stale-detect.js` (M#4) | Shebang + stdin JSON read + exit-0-always + stderr-with-[codebrain]-prefix-on-errors |
| Hook subcommand dispatch | `bin/codebrain.js` HOOK_SUBCOMMANDS (M#4) | Add `observe` to the existing array; `npx codebrain hook observe` is the install-time invocation |
| Hook entry in init.js | `scripts/init.js` codebrainOwnedHooks (M#4) | Add a third entry: `codebrain:pre:observe` with `matcher: "*"`, `async: true`, `timeout: 10` |
| Shared helper library | `scripts/hooks/lib/page-io.js` (M#4) | Pattern: small CommonJS module under `scripts/hooks/lib/`; expose narrow API; mirror M#4's atomic-write + path-discovery patterns |
| Agent file format | `agents/brain/{ingester,linker,planner,query,verifier}.md` | Merged frontmatter; Rules section; prompt-defense reference; orchestration-only tools (NO Edit/Write/MultiEdit for the observer) |
| Slash-command procedure section | `commands/brain.md` (5 prior procedures) | Numbered steps (Le0–Le7 for learn, S0–S3 for status); explicit preconditions; structured report |
| Skill placement | `skills/core/{init,query,lint}/` | `skills/core/learn/` — fourth and final core/* skill |
| Tests | T20-T22 (M#4 hook behavior) + T26-T29 | T33 (observer + learn skill structural shape); T34 (init.js writes new hook); T35 (observe hook behavior on fixture + slash-command procedure wiring) |

## Sweep Findings (J1–J9, folded in)

- **J1 — Per-project toggle file**: `.brain/.codebrain-learn-state` containing literal `on` or `off`. **Default `off`** per PRD Design Decision #4 (continuous-learning is opt-in). The observe hook reads this file each invocation; if `off` or missing → exits silently. Operator changes state via `/brain learn on` and `/brain learn off`.
- **J2 — Observation record format**: jsonl (one JSON object per line), fields `{ts: <ISO timestamp>, tool: <tool-name>, path?: <relative path if file-tool>, status: <exit-code-or-"ok">}`. **Minimal data only** — no tool output, no prompts, no file content. Privacy by design.
- **J3 — Project-hash for XDG path**: SHA-256 of `git remote get-url origin` (first 12 chars). If no remote: SHA-256 of cwd path. Same scheme as ECC v2.1 for consistency. Path: `<XDG_DATA_HOME or ~/.local/share>/codebrain/projects/<hash>/`.
- **J4 — Consolidation is deterministic in v0.1**: count tool-use patterns (e.g., "Edit on src/api/*.ts" appearing 12 times in last week). Promote any pattern with frequency ≥3 to an instinct. NO LLM call. Each instinct is a JSON object: `{id, pattern, frequency, confidence: <freq>/<total>, first_seen, last_seen}`. **v0.2 adds `--llm-distill` flag** for ECC-style Haiku-driven smart distillation.
- **J5 — Observer agent has NO mutation tools** — `tools: [Read, Grep, Bash]`. Bash is for reading the jsonl files (since they're outside `.brain/`, in XDG path); no Write/Edit/MultiEdit. Consolidation writes happen via the slash-command body's procedure (which uses Bash redirects + delegated invocation patterns), NOT via the agent's tool list.
- **J6 — Privacy explicit in 3 places**: observer SKILL.md "Privacy" section; observe.js hook script comments; slash-command body's `learn on` procedure prints a privacy notice before flipping the toggle.
- **J7 — Sixth and final agent pattern**: Observer. Completes the roster: Meta (codebrain), Generator (ingester, detected/*), Reviewer (linker, page-format, concept-extraction), Planner (planner), Researcher (query), Verifier (verifier), Observer (observer). All 7 used.
- **J8 — `/brain status` is separate from `/brain learn status`**: `/brain status` is the project dashboard (page counts, hooks installed, last sync, recent activity). `/brain learn status` is the learn-subsystem-specific view (observation count, instinct count, top patterns, toggle state). Both ship in M#7. Two procedure sections.
- **J9 — Export/import deferred to v0.2**: ECC v2.1 has `/instinct-export` + `/instinct-import` + `/promote` (project→global). M#7 ships the LOCAL learning loop; sharing/promotion is post-MVP. Documented in the skill's "Future work" section.

## Files to Change

| File | Action | Why |
|---|---|---|
| `scripts/hooks/observe.js` | CREATE | PostToolUse hook (technically PreToolUse for observation breadth); reads stdin JSON, checks toggle file, appends minimal record to XDG observations.jsonl. Fast (<100ms), exits 0 always. |
| `scripts/hooks/lib/observations.js` | CREATE | Shared helper: project-hash computation (git remote → SHA-256), XDG path resolution, atomic jsonl append, jsonl read + parse. Mirrors `lib/page-io.js` pattern from M#4. |
| `bin/codebrain.js` | UPDATE | Add `observe` to `HOOK_SUBCOMMANDS`; updates help text |
| `scripts/init.js` | UPDATE | Add third entry to `codebrainOwnedHooks`: PreToolUse `codebrain:pre:observe` with `matcher: "*"`, `async: true`, `timeout: 10`. Hook entries are partitioned by id-prefix per M#1's merge logic — adding doesn't disturb the M#4 entries. |
| `agents/observers/observer.md` | CREATE | Sixth agent. Observer pattern. Tools `[Read, Grep, Bash]` — NO mutation. 10 rules: never-collect-PII, never-write-to-brain, always-respect-toggle, etc. |
| `skills/core/learn/SKILL.md` | CREATE | Defines observation format, instinct format, consolidation policy, privacy stance. Tier: core. |
| `commands/brain.md` | UPDATE | Replace M#7 `learn` stub + `status` stub with two procedure sections: `## When $ARGUMENTS starts with learn` (Le0–Le7 with subcommands on/off/status/consolidate) + `## When $ARGUMENTS is just status` (S0–S3). |
| `commands/codebrain.md` | UPDATE | Alias parity. |
| `tests/e2e-test.sh` | UPDATE | T33 (observer + learn skill structural shape); T34 (init.js writes observe hook entry with correct id); T35 (observe.js exists + dispatches + reads toggle correctly on fixture; both new procedure sections present + alias parity). |
| `.claude/prds/codebrain.prd.md` | UPDATE | M#7 row → complete. **Codebrain v0.1 is feature-complete after this commit.** |

**Not in M#7 (intentional, deferred to v0.2):**
- `--llm-distill` flag for LLM-driven consolidation (J4)
- `/brain learn export` + `/brain learn import` (J9)
- `/brain learn promote` (project → global instinct migration)
- Background observer daemon (current model: hook collects, operator runs `consolidate` periodically)
- Cross-project instinct correlation
- Observer cost-tracking (token spent on consolidation)

## Tasks

### Task 1: scripts/hooks/lib/observations.js (shared helper)

CommonJS module exposing:

- `projectHash(cwd)` — try `git remote get-url origin`; fall back to cwd path. Returns first 12 chars of SHA-256.
- `xdgProjectDir(cwd)` — returns `<XDG_DATA_HOME>/codebrain/projects/<hash>/`. Creates dir if missing.
- `learnToggleState(cwd)` — reads `<cwd>/.brain/.codebrain-learn-state`. Returns `"on" | "off" | "missing"`.
- `setLearnState(cwd, state)` — atomic-writes the toggle file (temp+rename pattern from M#4).
- `appendObservation(cwd, record)` — appends a JSON object to `<xdg>/observations.jsonl`. Atomic per-line append.
- `readObservations(cwd)` — yields parsed records from `observations.jsonl`. Handles malformed lines gracefully.
- `appendInstinct(cwd, instinct)` — appends to `<xdg>/instincts.jsonl`.
- `readInstincts(cwd)` — yields parsed instincts.

Reuse the atomic-write pattern from `lib/page-io.js`. ~150 lines.

### Task 2: scripts/hooks/observe.js (PreToolUse hook)

Shebang Node script. Pattern matches M#4's stale-detect:

1. Read stdin JSON (Claude Code hook payload)
2. Check `.brain/.codebrain-learn-state` via lib/observations. If `off` or `missing` → exit 0 silently. If `on` → continue.
3. Extract minimal observation: `{ts: Date.now(), tool: payload.tool_name, path: payload.tool_input.file_path || null, status: "ok"}`. **Never** include tool output, prompts, file content.
4. Append via lib/observations.
5. Exit 0 (always — observation must never block tool execution).

~80 lines.

### Task 3: bin/codebrain.js update — add `observe` subcommand

One-line addition to `HOOK_SUBCOMMANDS`:

```javascript
const HOOK_SUBCOMMANDS = ['stale-detect', 'verified-guard', 'observe'];
```

Plus a help-text bullet:
```
codebrain hook observe — PreToolUse: collect minimal tool-use observations
                          (requires per-project /brain learn on toggle)
```

### Task 4: scripts/init.js update — add observe hook entry

Extend `codebrainOwnedHooks`:

```javascript
PreToolUse: [
  // ... existing verified-guard entry ...
  {
    matcher: '*',
    hooks: [
      {
        type: 'command',
        command: 'npx codebrain hook observe',
        async: true,
        timeout: 10,
      },
    ],
    id: 'codebrain:pre:observe',
    description: 'Continuous-learning observer: append minimal tool-use observations to XDG store when /brain learn is on (opt-in per-project)',
  },
],
```

M#1's merge logic preserves the existing verified-guard entry + adds this one. Re-init is idempotent.

### Task 5: agents/observers/observer.md (sixth agent)

Frontmatter:
```yaml
---
name: observer
description: Sixth and final agent — Observer pattern. The first BACKGROUND-style agent in codebrain. Read-only by design. Consolidates accumulated observations from <XDG>/projects/<hash>/observations.jsonl into deterministic instincts in <XDG>/projects/<hash>/instincts.jsonl when /brain learn consolidate is invoked. Privacy by default: never captures tool output, prompts, or file content.
tools: [Read, Grep, Bash]
model: sonnet
pattern: Observer
trigger_phrases:
  - "consolidate observations"
  - "distill instincts"
  - "what has the brain learned"
max_iterations: 5
---
```

Body: persona + prompt-defense reference + procedure pointer (`commands/brain.md` `## When $ARGUMENTS starts with learn`, subcommand `consolidate`) + **Privacy** section (verbatim: "I never read tool outputs, user prompts, or file content. I only consolidate the minimal `{ts, tool, path?, status}` records the observe hook collected. The operator can disable observation per-project with `/brain learn off` at any time.") + `## Rules` (≥10):

- **NEVER read tool outputs, user prompts, or file content** — privacy by design. Only consolidate `{ts, tool, path?, status}` records.
- **NEVER capture PII** — observations exclude any field that could contain user-typed text or secrets.
- **NEVER write to `.brain/`** — instincts live in XDG store; the brain is for codebase knowledge, not behavior.
- **NEVER consolidate without operator command** — the hook is observation-only; consolidation requires explicit `/brain learn consolidate`.
- **NEVER run when toggle is `off`** — check `.brain/.codebrain-learn-state` before reading.
- **NEVER promote a pattern with frequency <3** — under that threshold it's noise.
- **ALWAYS use atomic writes** for instinct mutations (via `lib/observations`).
- **ALWAYS record consolidation events** in `.brain/log.md` with grep-parseable prefix `## [YYYY-MM-DD] consolidate | <N observations → <M instincts>`.
- **ALWAYS deduplicate instincts** by `pattern` field before appending.
- **ALWAYS respect the per-project toggle**: if `.brain/.codebrain-learn-state` is `off`, abort with a notice telling the operator to flip `on` first.

Error recovery: Tier 1 retry / Tier 2 blocked-report. max_iterations 5.

### Task 6: skills/core/learn/SKILL.md (fourth core skill)

Frontmatter `tier: core`, `pattern: Observer`, `related_skills: [behavioral/codebrain, core/lint]`.

Body sections:
- **When to Activate** — `/brain learn {on|off|status|consolidate}` or trigger phrases
- **Observation format** — JSON schema for the jsonl records
- **Instinct format** — JSON schema for instincts
- **Consolidation policy (v0.1)** — deterministic pattern counting; promote ≥3 frequency
- **Privacy** — explicit; what is and isn't captured
- **Toggle semantics** — per-project; default off; flipping does NOT delete history
- **Storage location** — XDG path explanation
- **Future work (v0.2+)** — LLM-driven distillation, export/import, promotion to global

### Task 7: Update commands/brain.md — learn + status procedures

In the dispatch table:
```
| `learn {on\|off\|status\|consolidate}` | **implemented (M#7)** | See "When `$ARGUMENTS` starts with `learn`" section below |
| `status` | **implemented (M#7)** | See "When `$ARGUMENTS` is just `status`" section below |
```

Add `## When $ARGUMENTS starts with learn` section with steps Le0–Le7 + per-subcommand routing:

- **Le0 — Argument parsing**: extract subcommand (`on`, `off`, `status`, `consolidate`)
- **Le1 — Preconditions**: `.brain/` exists; `.codebrain-version` present
- **Le2 — Dispatch to subcommand procedure**:
  - `on`: print privacy notice → write `.brain/.codebrain-learn-state` with content `on` → confirm
  - `off`: write `off` → confirm
  - `status`: read toggle, observation count, instinct count, top 5 patterns; print formatted
  - `consolidate`: invoke the observer agent procedure (Le3–Le7)
- **Le3-Le7** (consolidate-specific): check toggle → read observations.jsonl → count patterns → promote ≥3 → atomic write to instincts.jsonl → log → report

Add `## When $ARGUMENTS is just status` section with S0–S3:

- **S0 — Preconditions** (.brain/ exists)
- **S1 — Gather** (page counts per kind, hooks installed, last log entries, observation count if learn on)
- **S2 — Format the dashboard**
- **S3 — Output**

### Task 8: Update commands/codebrain.md (alias parity)

Mirror Task 7. Test via awk byte-identical.

### Task 9: tests/e2e-test.sh — T33 + T34 + T35

**T33 — Observer agent + learn skill structural shape:**
- Observer agent file exists; frontmatter; `pattern: Observer`; tools list excludes Edit/Write/MultiEdit; ≥10 rules; prompt-defense reference; Privacy section
- core/learn SKILL.md exists; `tier: core`; required body sections (When to Activate, Observation format, Instinct format, Consolidation policy, Privacy, Toggle semantics, Storage location, Future work)
- npm pack includes both

**T34 — init.js writes the observe hook entry:**
- Run init in tmpdir; assert `settings.local.json` PreToolUse contains entry with `id: codebrain:pre:observe`, `matcher: *`, `async: true`, `command` includes `npx codebrain hook observe`
- Total codebrain hooks now: 3 (verified-guard + stale-detect + observe)
- Re-init keeps exactly 3; preserves user hooks

**T35 — observe.js + learn/status procedures:**
- `scripts/hooks/observe.js` exists with shebang
- `scripts/hooks/lib/observations.js` exists
- `bin/codebrain.js hook observe` is a known subcommand
- Fixture test: in a dir without `.brain/.codebrain-learn-state` → observe exits 0 silently; create the file with `off` → still silent; create with `on` + append a record → check observations.jsonl
- Dispatch table: `learn` + `status` both `**implemented (M#7)**`
- Both procedure sections present (`## When $ARGUMENTS starts with learn`, `## When $ARGUMENTS is just status`)
- Critical keywords: `Privacy`, `XDG`, `consolidate`, `instinct`, `pattern`, `toggle`
- Alias parity for both new sections (awk)
- npm pack includes observe.js + observations.js

### Task 10: PRD update — M#7 → complete

`.claude/prds/codebrain.prd.md` M#7 row → `complete`. Add footnote: "Codebrain v0.1 is feature-complete after M#7. All 11 sub-milestones green; 6 agent patterns; 5 skill tiers; 4-tier staleness; complete loop."

## Validation

```bash
# 1. E2E
bash tests/e2e-test.sh
# Expect: ~510 passes, 0 failures, <5s

# 2. New files
test -f scripts/hooks/observe.js
test -f scripts/hooks/lib/observations.js
test -f agents/observers/observer.md
test -f skills/core/learn/SKILL.md

# 3. observe.js wired
node bin/codebrain.js hook 2>&1 | grep -q observe

# 4. Observer agent constraints
grep -q '^pattern: Observer$' agents/observers/observer.md
! grep -E '^tools:.*\b(Edit|Write|MultiEdit)\b' agents/observers/observer.md
grep -q '^## Privacy' skills/core/learn/SKILL.md

# 5. init.js writes 3 codebrain entries (2 existing + 1 new)
node -e "
const init = require('./scripts/init.js');
const t = require('os').tmpdir() + '/cb-m7-' + Date.now();
require('fs').mkdirSync(t + '/.git', { recursive: true });
process.chdir(t);
init([]);
const j = require(t + '/.claude/settings.local.json');
const all = [...(j.hooks.PreToolUse||[]), ...(j.hooks.PostToolUse||[])];
const cb = all.filter(e => e && typeof e.id === 'string' && e.id.startsWith('codebrain:'));
if (cb.length !== 3) { console.error('expected 3 codebrain hooks, got', cb.length); process.exit(1); }
"

# 6. Dispatch table updated
grep -q 'learn.*\*\*implemented (M#7)\*\*' commands/brain.md
grep -q '`status`.*\*\*implemented (M#7)\*\*' commands/brain.md

# 7. Alias parity
diff <(awk '/^## When `\$ARGUMENTS` starts with `learn`$/{flag=1} flag' commands/brain.md) \
     <(awk '/^## When `\$ARGUMENTS` starts with `learn`$/{flag=1} flag' commands/codebrain.md)
diff <(awk '/^## When `\$ARGUMENTS` is just `status`$/{flag=1} flag' commands/brain.md) \
     <(awk '/^## When `\$ARGUMENTS` is just `status`$/{flag=1} flag' commands/codebrain.md)

# 8. npm pack ships new files
npm pack --dry-run | grep -E 'scripts/hooks/(observe|lib/observations)|agents/observers/observer|skills/core/learn'
```

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Observe hook fires too frequently and creates a huge jsonl | Med | Each record is ~100 bytes; 1000 tool calls/day = 100KB/day. Manageable. Future: rotation policy. |
| Toggle file gets out of sync (e.g., copied between repos) | Low | File is per-project under `.brain/`; lives with the repo, not the user. Operator controls. |
| Consolidation deterministic logic produces useless instincts | Med | v0.1 is a stake in the ground; M#7 SKILL.md explicitly documents v0.2's LLM-driven distillation as the upgrade path |
| Privacy fear: operator worries observations capture secrets | High (psychological) | Three layers of documentation (skill, agent, slash-command body); explicit field list; default-off toggle. The hook code is small + auditable. |
| XDG path doesn't exist on Windows | Low | `os.homedir()` works cross-platform; `<homedir>/AppData/Local/codebrain/` is the Windows equivalent. Test in T35 if possible. |
| `npx codebrain hook observe` overhead on every tool call | Low | async + timeout: 10 + exits-0-always; hook orchestration is microseconds; observation write is sub-ms. The PostToolUse hook from M#4 already proves this is fine. |
| Alias drift on the two new procedure sections | Low | T35 awk-byte-identical for both |

## Acceptance

- [ ] All 10 tasks complete
- [ ] Validation §1 (e2e ~510) passes
- [ ] Validation §2–§8 pass
- [ ] PRD M#7 row → complete (codebrain v0.1 feature-complete)
- [ ] No regression: 464 prior tests pass; total ~510 after T33-T35 added (~46 new)
- [ ] (Optional) Manual smoke: in a brain-initialized repo, run `/brain learn on`; do some Edit/Read tool calls; run `/brain learn status`; verify observation count > 0
