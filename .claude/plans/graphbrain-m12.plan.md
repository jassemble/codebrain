# Plan: graphbrain — Milestone #12 (Slash-command namespacing — `/brain:<verb>`)

**Source PRD**: `.claude/prds/graphbrain.prd.md` (v0.2 Roadmap section — to be amended in this milestone)
**Selected Milestone**: #12 — Architectural refactor; idiomatic Claude Code namespacing
**Complexity**: Medium-to-Large — touches every slash-command file, every E2E assertion that references `commands/brain.md`, and `scripts/init.js` directory-copy logic; behavior-equivalent (no UX semantics change) but ~12-file structural churn
**Status**: DRAFT — refactor; safer to land BEFORE M#10 (`/brain spec`) and M#11 (`/brain creds`) so those verbs ship into the new layout natively

## Summary

Today every graphbrain slash command flows through one of two monolithic files:

- `commands/brain.md` (1183 lines after v0.1.2) — single dispatcher; routes on the first token of `$ARGUMENTS`
- `commands/graphbrain.md` (1183 lines) — byte-identical alias mirror (modulo title/help-text headers)

M#12 splits these into Claude Code's idiomatic per-verb namespace layout:

```
commands/
├── brain/
│   ├── init.md       → /brain:init
│   ├── ingest.md     → /brain:ingest        (internal sub-dispatch on file/folder/no-arg)
│   ├── query.md      → /brain:query
│   ├── lint.md       → /brain:lint
│   ├── learn.md      → /brain:learn         (internal sub-dispatch on on/off/status/consolidate)
│   ├── status.md     → /brain:status
│   ├── spec.md       → /brain:spec          (M#10 lands into this directory)
│   └── creds.md      → /brain:creds         (M#11 lands into this directory)
├── graphbrain/        ← byte-identical mirror per-verb
│   └── (same)
├── brain.md          ← reduced to no-arg help / disambiguator
└── graphbrain.md      ← reduced to no-arg help / disambiguator
```

**Behavior equivalence**: `/brain ingest src/auth.ts` and `/brain:ingest src/auth.ts` produce identical results. The dispatcher form (`/brain <verb>`) remains the user-typed entry point via `commands/brain.md` (now a thin no-arg help command that points users at the namespaced forms); the namespaced form is the canonical procedure location.

**Why now**: M#10 (`/brain spec`) and M#11 (`/brain creds`) each add ~300 lines to `commands/brain.md`. If we restructure after they land, every new verb's procedure has to be split out again. Restructuring before they land means M#10 and M#11 ship into the new layout directly — net less work.

## Patterns to Mirror

| Category | Source | Pattern |
|---|---|---|
| Subdirectory namespacing | Claude Code core convention — `.claude/commands/<dir>/<verb>.md` → `/<dir>:<verb>` | Directory becomes namespace; filename becomes the verb after the colon |
| Skill-extracted shared procedures | M#3a/M#3b each reference `skills/ingestion/page-format/SKILL.md` for the page format spec | The v0.1.2 inline "How to refresh `.brain/llms.txt`" section moves into a new skill — `skills/ingestion/llms-txt/SKILL.md` — so per-verb files reference it rather than duplicating it |
| Alias byte-identity assertion | T36 (Step 4b.2 parity) + T37 (llms.txt refresh section parity) | Generalize: every `commands/brain/<verb>.md` and `commands/graphbrain/<verb>.md` PROCEDURE body is byte-identical (headers/titles may differ) |
| Recursive directory copy in init | `scripts/init.js` `copyTemplate` is currently single-file; needs a `copyDir` helper for the new layout | Atomic per-file write; respect existing `.bak` + .tmp + fsync + rename contract |

## Files to Change

| File | Action | Why |
|---|---|---|
| `commands/brain/init.md` (NEW) | CREATE | Extract `## When $ARGUMENTS is init` (lines ~50–135 of brain.md) into its own file. Frontmatter `description: graphbrain — init the brain in this project`. Procedure body byte-identical with current. |
| `commands/brain/ingest.md` (NEW) | CREATE | Extract single-file + folder + no-arg ingest procedures (lines ~136–690) into one file with internal dispatch on `$ARGUMENTS` shape (mirror the existing single-file/folder/empty fork). |
| `commands/brain/query.md` (NEW) | CREATE | Extract `## When $ARGUMENTS starts with query` (lines ~691–810). |
| `commands/brain/lint.md` (NEW) | CREATE | Extract `## When $ARGUMENTS starts with lint` (lines ~812–952). |
| `commands/brain/learn.md` (NEW) | CREATE | Extract `## When $ARGUMENTS starts with learn` (lines ~953–1078) — preserves the `on/off/status/consolidate` internal dispatch. |
| `commands/brain/status.md` (NEW) | CREATE | Extract `## When $ARGUMENTS is just status` (lines ~1079–1121). |
| `commands/graphbrain/<verb>.md` × 6 (NEW) | CREATE | Byte-identical mirror per verb (modulo header/title divergence as today). |
| `skills/ingestion/llms-txt/SKILL.md` (NEW) | CREATE | New skill extracting v0.1.2's "How to refresh `.brain/llms.txt`" reference section. Tier `ingestion`. Each verb file references it via `Read the skill at skills/ingestion/llms-txt/SKILL.md before refreshing`. Replaces the current inline duplication across brain.md / graphbrain.md. |
| `commands/brain.md` | REDUCE | Becomes a thin help/disambiguator. Only contains: frontmatter + the no-arg help block (current lines 25–46) + a pointer table to `/brain:<verb>` for each verb. Drops ~1100 lines. |
| `commands/graphbrain.md` | REDUCE | Same reduction. |
| `scripts/init.js` | UPDATE | `copyTemplate` calls split into per-file copies for the new layout; add a `copyDir` helper that walks `commands/brain/` and `commands/graphbrain/` and emits an atomic write per file. Preserves the version marker on every file. |
| `tests/e2e-test.sh` | UPDATE | T1: assert per-verb files copied; T12/T25/T36/T37 parity assertions generalize to "every per-verb file pair is byte-identical in body"; new T40 covers the namespacing structure end-to-end. |
| `scripts/dogfood/install-validate.sh` | UPDATE | Mirrors T1's per-verb file copy assertion; loops over the verb list. |
| `package.json` | UPDATE | `files:` whitelist already includes `commands/` recursively; no change. Bump 0.1.2 → 0.2.0 (this is a structural change worth a minor bump). |
| `reference/claude-code-conventions.md` | UPDATE | Document the new layout as the canonical contract `init.js` produces. The previous monolithic-dispatcher pattern is removed; the new per-verb pattern is the only documented contract. |
| `.claude/prds/graphbrain.prd.md` | UPDATE | v0.2 Roadmap: add M#12 row; note the M#12 → M#10 → M#11 ordering (M#12 lands first so M#10 and M#11 ship into the new layout natively) |

## Sub-milestone split (recommended)

3-way split mirrors how we handled M#3 in v0.1:

- **M#12a — Extract shared procedures into skills** (prep, no behavior change): pull v0.1.2's "How to refresh `.brain/llms.txt`" out of brain.md/graphbrain.md into a new `skills/ingestion/llms-txt/SKILL.md`. Update the three callsites (M#3a Step 6, M#3b L5, lint L7) to reference the skill instead of the inline section. Tests still pass; structure unchanged.
- **M#12b — Split + mirror** (the bulk): move every verb procedure to `commands/brain/<verb>.md` and `commands/graphbrain/<verb>.md`. Reduce top-level `brain.md` and `graphbrain.md` to no-arg help disambiguators. Add `init.js` directory-copy support. Update tests.
- **M#12c — Reference docs + tooling polish**: update `reference/claude-code-conventions.md` + `scripts/dogfood/install-validate.sh` + PRD v0.2 row.

Each sub-milestone is its own commit. M#12 is "complete" when all three ship.

## Tasks

### M#12a — extract shared procedures (prep)

1. Create `skills/ingestion/llms-txt/SKILL.md`:
   - Frontmatter: `name: llms-txt`, `tier: ingestion`, `pattern: Generator`, `related_skills: [behavioral/graphbrain, ingestion/page-format]`
   - Body: lift the v0.1.2 "How to refresh `.brain/llms.txt`" section verbatim from `commands/brain.md` (currently at bottom, ~line 1130). Single source of truth.

2. Update `commands/brain.md` and `commands/graphbrain.md`:
   - At each of the three callsites (M#3a Step 6, M#3b L5, `/brain lint` L7), replace the inline reference with: "Refresh `.brain/llms.txt` per the procedure in `skills/ingestion/llms-txt/SKILL.md`. Read that skill before refreshing."
   - Delete the bottom-of-file "## How to refresh `.brain/llms.txt`" section entirely (now lives in the skill).

3. Update `tests/e2e-test.sh` T37: replace "brain.md has refresh procedure section" with "skills/ingestion/llms-txt/SKILL.md exists with proper frontmatter and the refresh procedure"; preserve the byte-identity assertion across brain.md/graphbrain.md (now trivial since the section was removed).

4. Tests pass — M#12a is behaviorally inert; only single-source-of-truth + alias-drift surface improves.

### M#12b — split + mirror (the bulk)

5. Create the six per-verb files under `commands/brain/`:
   - `init.md`, `ingest.md`, `query.md`, `lint.md`, `learn.md`, `status.md`
   - Each has frontmatter (description per-verb), a version-marker comment line, and the procedure body lifted verbatim from the corresponding `## When ...` section of `brain.md`.
   - Preserve internal dispatch where the verb has sub-modes: `ingest.md` keeps the file-vs-folder-vs-no-arg fork; `learn.md` keeps the `on/off/status/consolidate` fork.

6. Mirror to `commands/graphbrain/` — byte-identical body, frontmatter description swaps `/brain:` for `/graphbrain:`.

7. Reduce `commands/brain.md` to a thin help disambiguator:
   - Frontmatter unchanged
   - Body: only the no-arg help block (which now lists `/brain:<verb>` as the canonical invocation alongside `/brain <verb>` for muscle-memory)
   - Drop all `## When $ARGUMENTS ...` sections (they live in the per-verb files now)
   - Drop the "## How to refresh `.brain/llms.txt`" section (already moved in M#12a)
   - Final size: ~80 lines (was 1183)

8. Reduce `commands/graphbrain.md` symmetrically.

9. Decide on the legacy dispatcher behavior:
   - **Option B1**: `commands/brain.md` retains the dispatcher logic so `/brain ingest src/auth.ts` still works exactly as today. Body re-emits the per-verb file's procedure via "Read `commands/brain/<verb>.md` and execute its procedure with `$ARGUMENTS` shifted left by one token." This preserves muscle memory.
   - **Option B2**: `commands/brain.md` becomes pure help; `/brain ingest src/auth.ts` prints "use `/brain:ingest src/auth.ts`" and stops. Breaks muscle memory; cleaner.
   - **Recommended: B1** for v0.2; revisit B2 for v1.0 once operators have rewired muscle memory. The "Read the per-verb file" indirection is one extra agent step but no extra cost since the per-verb file is small.

10. Update `scripts/init.js`:
    - Add `copyDir(srcRel, destAbs, opts)` helper that walks a source directory and copies every file via the existing atomic-write contract.
    - Replace the two `copyTemplate('commands/brain.md', ...)` and `copyTemplate('commands/graphbrain.md', ...)` calls with: copy the two top-level files PLUS `copyDir('commands/brain', ...)` PLUS `copyDir('commands/graphbrain', ...)`.
    - Idempotent: re-running with the same version produces SKIPs.

11. Update `tests/e2e-test.sh`:
    - T1: assert each per-verb file in both directories exists with version marker.
    - T12 (alias parity for init): assert `commands/brain/init.md` and `commands/graphbrain/init.md` procedure bodies are byte-identical.
    - T25 (Step 4b alias parity): now lives within `commands/brain/ingest.md`; same assertion against the new file path.
    - T36 (Step 4b.2 parity): same as T25.
    - T37 (llms.txt wiring): the per-verb references via the skill (M#12a); assertion becomes "ingest.md and lint.md both reference skills/ingestion/llms-txt/SKILL.md".
    - **New T40**: structural validation of the namespacing — for each verb in `{init, ingest, query, lint, learn, status}`, both `commands/brain/<verb>.md` and `commands/graphbrain/<verb>.md` exist + have frontmatter + version marker + identical procedure body.

### M#12c — reference docs + tooling polish

12. Update `reference/claude-code-conventions.md`: document the new per-verb layout as the canonical contract. The old monolithic-dispatcher pattern is gone; the new layout replaces it.

13. Update `scripts/dogfood/install-validate.sh`: assert each per-verb file copies in (loop over verb list). Replace the two-file byte-for-byte checks with a per-verb loop.

14. Update `.claude/prds/graphbrain.prd.md`: append M#12 row to v0.2 Roadmap; note the ordering (M#12 before M#10 before M#11).

15. Bump `package.json` 0.1.2 → 0.2.0 — this is a structural change worth the minor bump. (Once committed, M#10 and M#11 implementations target 0.2.0 + as their baseline.)

## Validation

```bash
# E2E
bash tests/e2e-test.sh
# Expect: ~660 passes (~644 + ~20 T40 namespacing assertions − ~5 removed obsolete monolith assertions), 0 failures

# Per-verb files exist + version marker on each
for v in init ingest query lint learn status; do
  test -f "commands/brain/$v.md"
  test -f "commands/graphbrain/$v.md"
  head -1 "commands/brain/$v.md" | grep -qF "graphbrain v"
done

# Byte-identical procedure bodies (alias parity)
for v in init ingest query lint learn status; do
  body_brain=$(awk '/^# \//{flag=1; next} flag' "commands/brain/$v.md")
  body_cb=$(awk '/^# \//{flag=1; next} flag' "commands/graphbrain/$v.md")
  [ "$body_brain" = "$body_cb" ]
done

# llms-txt skill exists
test -f skills/ingestion/llms-txt/SKILL.md
grep -qF 'tier: ingestion' skills/ingestion/llms-txt/SKILL.md

# init.js scaffolds the new layout
( cd "$(mktemp -d)" && git init -q && node "$CB" init >/dev/null )
# Then verify .claude/commands/brain/ingest.md exists etc.

# npm pack: still 59-ish files, no regression
npm pack --dry-run | grep -q 'commands/brain/ingest.md'
npm pack --dry-run | grep -q 'commands/graphbrain/ingest.md'
```

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Existing users have `.claude/commands/brain.md` from v0.1.x; `init` overwrites it, but the per-verb files in `.claude/commands/brain/` are new — operator's old single-file install lingers if init isn't run with `--force` | Med | Init detects v0.1.x layout (presence of monolithic `brain.md` without `brain/` subdir) and emits a one-line `WARN: legacy single-file layout detected; re-run with --force to migrate.` Operator chooses when to migrate. |
| Claude Code's namespace separator changes upstream (e.g., from `:` to `/`) | Low | Graphbrain doesn't control the separator. If Anthropic changes it, the SKILL.md docs update; the file structure on disk is unchanged. |
| Internal sub-dispatch in `/brain:ingest` (file/folder/no-arg) and `/brain:learn` (on/off/status/consolidate) is less discoverable than full namespacing (e.g., `/brain:ingest:file`) | Med | Documented trade-off. Full namespacing-down (`/brain:learn:on`) is overkill: most operators just type `/brain learn on`. The sub-mode lives in the per-verb file body. If discoverability becomes a real complaint, M#13 can sub-namespace. |
| The "Read `commands/brain/<verb>.md`" indirection in the legacy dispatcher (Task 9 / Option B1) adds an agent step | Low | One extra Read of a ~150-line file. Negligible token cost. Removed entirely in v1.0 (B2). |
| E2E test churn — many existing assertions reference `commands/brain.md` line numbers / sections | High | Refactor all at once in M#12b. Use `grep`-based assertions (insensitive to line numbers) wherever possible. Document the search patterns in a comment block at the top of T40. |
| Operators write custom slash commands under `.claude/commands/brain/<custom>.md` that conflict with future graphbrain verbs | Low | Document the `commands/brain/` namespace as graphbrain-owned. Future M#9-style runtime probe could detect conflicts; out of scope for M#12. |
| Decision fatigue: the legacy dispatcher (B1) preserves muscle memory but lives alongside the namespaced form, creating two paths to the same outcome | Low | Acceptable for v0.2 — both work, operators self-select. v1.0 may sunset the dispatcher. |
| `scripts/init.js` `copyDir` helper introduces bugs in the atomic-write contract | Med | Implement `copyDir` as a loop over `copyTemplate`. The existing `copyTemplate` already has the .bak/.tmp/fsync/rename contract; reuse it per-file rather than rewriting. Cost: one mkdir + one copyTemplate call per file. |

## Acceptance (provisional)

- [ ] All three sub-milestones complete (M#12a, M#12b, M#12c)
- [ ] E2E passes (~660 assertions)
- [ ] M#12 row in PRD → complete
- [ ] No regression on prior tests (`/brain ingest`, `/brain query`, `/brain lint`, `/brain learn`, `/brain status` all still work via the legacy dispatcher path AND via `/brain:<verb>`)
- [ ] (Operator-validated) Smoke: `/brain ingest src/auth.ts` works exactly as today; `/brain:ingest src/auth.ts` produces identical output; both produce identical `.brain/code/src/auth.ts.md`
- [ ] (Operator-validated) Autocomplete: typing `/brain:` in Claude Code's command palette shows all six namespaced verbs
- [ ] M#10 and M#11 plans updated to ship into the new layout (`commands/brain/spec.md`, `commands/brain/creds.md`) — M#12 is a hard prerequisite for both

## Ordering note (v0.2 master sequence)

After this plan revision, the v0.2 milestone order becomes:

1. **M#12** (this — slash-command namespacing) — refactor first; smaller diffs for M#10/M#11 when they land
2. **M#10** (spec-first + intent-routing + discovery loop + agent-readability hardening) — ships `commands/brain/spec.md` into M#12's layout
3. **M#11** (credential registry) — ships `commands/brain/creds.md` into M#12's layout
4. **M#9** (framework-bridge runtime) — last; refines an already-shipping declarative pattern

M#12's prep work (M#12a — extract shared procedures into skills) is a no-behavior-change ship and could land BEFORE M#12b/c if operators want incremental movement. M#12a alone reduces alias-drift surface area.

---

**M#12 is a v0.2 DRAFT — architectural refactor.** Refinement before implementation:

- Confirm the legacy dispatcher behavior (Task 9 — Option B1 vs B2). B1 is recommended for muscle-memory preservation; B2 is cleaner long-term.
- Test the Claude Code autocomplete behavior on a real install — does `/brain:` actually surface the six namespaced verbs, or does the IDE only autocomplete top-level files? Worth a 5-minute dogfood spike before committing to M#12b.
- Decide whether `commands/brain/ingest.md` keeps the internal file/folder/no-arg dispatch or splits further into `commands/brain/ingest-file.md` etc. Recommended: keep internal; the file isn't large.
- Verify that `npm pack` correctly includes subdirectories under `commands/` (it should, per the `files: ["commands/"]` entry, but worth a manual `npm pack --dry-run | grep 'commands/brain/'` after M#12b).
