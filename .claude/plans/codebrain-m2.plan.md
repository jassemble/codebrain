# Plan: codebrain — Milestone #2 (Init + schema scaffolding)

**Source PRD**: `.claude/prds/codebrain.prd.md`
**Selected Milestone**: #2 — Init + schema scaffolding
**Complexity**: Medium — first real LLM-agent skill, mostly content + thin wiring (no new runtime code; commands and templates only)

## Summary

Make `/brain init` (the slash command, invoked by an LLM agent inside Claude Code) do real work: replace the M#1 placeholder schema block in CLAUDE.md with the full codebrain conventions block, populate `.brain/overview.md` with a project-aware starter digest, detect the tech stack and report it, and append a grep-parseable log entry. This is the first agent-driven skill — distinct from M#1's npm-side `scripts/init.js` which scaffolds the empty skeleton.

User flow after M#2 lands:
```
npx codebrain init      # M#1, once per repo — file-system scaffold
# (restart Claude Code)
/brain init             # M#2, agent-driven — populates content + detects stack
/brain ingest src/      # M#3 (not yet implemented)
```

## Patterns to Mirror

| Category | Source | Pattern |
|---|---|---|
| SKILL.md frontmatter + body | `skills/behavioral/codebrain/SKILL.md:1-9` | merged ECC + graphbrain frontmatter (`name`, `description`, `origin`, `version`, `tier`, `pattern`, `related_skills`); body sections "When to Activate", "How It Works", "Examples" |
| Slash-command verb dispatch | `commands/brain.md:11-23` | `$ARGUMENTS` parsed as `<verb> [args...]`; routing table per verb. M#2 replaces ONLY the `init` row; other verbs keep their Milestone-N stubs. |
| Managed-region template-merge | `scripts/init.js:166-201` (`appendClaudeMdManagedRegion`) | begin/end markers; if markers present + not `--force`, SKIP; if `--force`, splice replacement between markers; preserve user content outside markers |
| Page frontmatter shape | `scripts/init.js:148-156` (`frontmatter` helper) + PRD Design Decision frontmatter spec | `kind:`, `status:`, `created:`, optional `source:`/`source_hash:`/`sources:`; Dataview-compatible YAML |
| Tier-aware skill location | `skills/README.md` (5-tier spec) | this skill lands under `skills/core/init/` (always-available; not stack-detected, not opt-in) |
| Tech-stack detection rules | `skills/README.md` (the `detect:` spec — established M#1) | JSON array of `{file_exists, contains, glob}` rules; logical AND within an array; produces `name → matched? → install detected/<name>` |
| Tests | `tests/e2e-test.sh` (graphbrain pass/fail-counter style) | bash, structural assertions, no LLM calls, <5s runtime; the agent-behavior parts of M#2 are not bash-testable (skill bodies are read by the LLM at runtime) — we assert file shape only |

**Patterns we are NOT mirroring (intentional):**
- graphbrain's `phase{1,2,3,4}-*.sh` scripts — codebrain's init is agent-driven, not a 4-phase bash pipeline.
- ECC's full plugin-discovered skill auto-loading — codebrain is npm-distributed (Design Decision #28); the slash command body itself carries the load-bearing instructions, the SKILL.md is documentation + discovery.

## Files to Change

| File | Action | Why |
|---|---|---|
| `skills/core/init/SKILL.md` | CREATE | The skill definition: when/why/how the agent invokes init; entry point for skill discovery |
| `skills/core/init/templates/claude-md-schema.md` | CREATE | The **verbatim** ~120-line schema block the agent writes between `<!-- codebrain:begin -->` and `<!-- codebrain:end -->` in the user's CLAUDE.md (replacing M#1's placeholder) |
| `skills/core/init/templates/overview-starter.md` | CREATE | Starter content for `.brain/overview.md`. Sections: Project Purpose / Codebase Structure / Key Patterns / Active State / Recent Activity. Each section starts with an instruction comment telling the agent what to populate |
| `skills/core/init/templates/stack-detection.json` | CREATE | JSON catalog of stack signals — array of `{ name, signals: [...], skill: "detected/<name>" }`. Agent reads → matches → reports `Detected: react, typescript` and notes "no detected/ skills installed yet (Milestone #3)" |
| `commands/brain.md` | UPDATE | Replace the `init` row in the dispatch table with full agent instructions (inlined; the slash command body is the load-bearing contract). Other verbs remain Milestone-N stubs. |
| `commands/codebrain.md` | UPDATE | Mirror brain.md changes; alias body stays identical to brain.md |
| `tests/e2e-test.sh` | UPDATE | Add T10–T13 (structural assertions for new files + frontmatter parseability + JSON shape + init-stub-removed check) |
| `.claude/prds/codebrain.prd.md` | UPDATE | M#2 row in Delivery Milestones table: `pending` → `in-progress`; `Plan` → link to this file |
| `package.json` | NO CHANGE | Version stays at `0.1.0` for now; bump to `0.2.0` only when we decide to release |
| `scripts/init.js` | NO CHANGE | The npm-side scaffolder doesn't need to know about M#2's skill — it copies the entire `skills/` tree (via the `files:` whitelist), so the new files ship automatically once committed |

**Files explicitly NOT touched in Milestone #2:**
- `agents/brain/ingester.md` — Milestone #3 (when ingest needs an agent)
- `skills/detected/{react,python,go,typescript}/` — Milestone #3 (M#2 detects but doesn't install; the detected skills themselves are M#3's deliverable)
- `hooks/` — Milestone #4
- README / CLAUDE.md / LICENSE — no changes needed

## Tasks

### Task 1: skills/core/init/SKILL.md

- **Action**: Create with frontmatter:
  ```yaml
  ---
  name: init
  description: Populate the codebrain wiki — write the full schema block to CLAUDE.md, customize .brain/overview.md with a project digest, detect tech stack, log the init event. Distinct from `npx codebrain init` which scaffolds skeleton files; this is the LLM-agent-driven content-population step that runs inside Claude Code.
  origin: codebrain
  version: 0.1.0
  tier: core
  pattern: Generator
  related_skills: [behavioral/codebrain]
  ---
  ```
  Body sections (per ECC/graphbrain convention):
  - **When to Activate** — operator runs `/brain init` or types trigger phrases: "initialize codebrain", "set up the brain", "populate .brain/"
  - **How It Works** — 8-step procedure (preconditions check → read repo signals → detect stack → read templates → merge schema block into CLAUDE.md → customize and write overview.md → append log entry → report)
  - **Prerequisites** — `.brain/` directory must exist (M#1's `npx codebrain init` must have run); managed-region markers must exist in CLAUDE.md
  - **Examples** — `/brain init` (normal); `/brain init --force` (refresh the schema block even if managed region is current)
  - **Cross-references** — link to `skills/behavioral/codebrain/SKILL.md` for the meta-skill; link to templates in `./templates/`
- **Mirror**: `skills/behavioral/codebrain/SKILL.md:1-9` (frontmatter shape); `skills/README.md` (tier+pattern fields)
- **Validate**: `head -12 skills/core/init/SKILL.md | grep -q '^---$'`; all 7 frontmatter fields present

### Task 2: skills/core/init/templates/claude-md-schema.md

- **Action**: Write the verbatim ~120-line schema block that the agent will splice between `<!-- codebrain:begin -->` and `<!-- codebrain:end -->` in the user's CLAUDE.md. Hard cap: 150 lines (per PRD Design Decision #7 page-cap discipline applied to the schema block — it must not dominate the user's CLAUDE.md). Sections:
  - **One-paragraph intro** — what `.brain/` is + the rule "operator reads, agent writes"
  - **Vault layout** — tree diagram of `.brain/{code,concepts,decisions}/` + top-level `.md` files; one-line purpose per directory
  - **Page-type taxonomy** — frontmatter spec: `kind:` (code/concept/decision/overview/index/log/status) + `status:` (UNENRICHED/FRESH/STALE/RESYNCED/VERIFIED) + `source:`/`source_hash:` (for code pages) + `sources:` (optional for concept pages — PRD Design Decision #10 tier 2)
  - **Operations** — one-liner each for `/brain {init,ingest,query,lint,learn,status}`
  - **Staleness model** — 4-tier brief (wikilink reverse-lookup via hook + optional `sources:` frontmatter + lint contradiction-check + query-time refresh — PRD Design Decision #10)
  - **Wikilink convention** — `[[code/src/path/file.md]]` for source mirrors; `[[concepts/<name>.md]]` for cross-cutting concepts; `[[decisions/<adr>.md]]` for decisions
  - **Prompt-defense reference rule** (PRD Design Decision #20) — single line: "Agents in this repo should `Read the Prompt Defense Baseline section of CLAUDE.md before acting.` rather than re-copying the baseline."
- **Mirror**: `reference/claude-code-conventions.md` (style; concise + canonical)
- **Validate**: `wc -l skills/core/init/templates/claude-md-schema.md` ≤ 150

### Task 3: skills/core/init/templates/overview-starter.md

- **Action**: Create as a template with frontmatter `kind: overview, status: UNENRICHED, created: <agent fills in>` and body sections, each prefaced with an `<!-- AGENT: populate this section by ... -->` instruction comment:
  - **Project Purpose** — agent infers from package.json description, README.md tagline, top-level comments
  - **Codebase Structure** — agent generates a 1-level directory tree with one-line purpose per top-level entry
  - **Key Patterns** — initially empty with `_will be populated as Milestone #3 ingest learns the codebase_` placeholder
  - **Active State** — `_initialized YYYY-MM-DD via /brain init_` plus current stack: line
  - **Recent Activity** — empty; the log.md is canonical; this section gets populated by M#3+ ingests
- **Mirror**: `scripts/init.js:124-145` (the M#1 skeleton-file format with frontmatter + section headers)
- **Validate**: starts with `---\n` frontmatter; contains at least the 5 section headers

### Task 4: skills/core/init/templates/stack-detection.json

- **Action**: JSON file with the structure:
  ```json
  {
    "version": "0.1.0",
    "stacks": [
      {
        "name": "nodejs",
        "signals": [{ "file_exists": "package.json" }],
        "detected_skill": "detected/nodejs"
      },
      {
        "name": "react",
        "signals": [{ "file_exists": "package.json", "contains": "\"react\"" }],
        "detected_skill": "detected/react"
      },
      {
        "name": "typescript",
        "signals": [{ "file_exists": "tsconfig.json" }],
        "detected_skill": "detected/typescript"
      },
      {
        "name": "python",
        "signals": [{ "file_exists": "pyproject.toml" }],
        "detected_skill": "detected/python"
      },
      {
        "name": "go",
        "signals": [{ "file_exists": "go.mod" }],
        "detected_skill": "detected/go"
      },
      {
        "name": "rust",
        "signals": [{ "file_exists": "Cargo.toml" }],
        "detected_skill": "detected/rust"
      }
    ]
  }
  ```
  This is the **catalog** the agent reads at runtime. Detection logic (read each file, match signals, produce a list) is in the agent instructions (Task 5), not in JSON. The agent reports "Detected: react, typescript, nodejs" and notes "no `detected/` skills installed yet (Milestone #3)" — M#3 will create the actual `skills/detected/<name>/SKILL.md` files.
- **Mirror**: `skills/registry.json` (JSON shape) + `skills/README.md` detect-rule spec
- **Validate**: `node -e "require('./skills/core/init/templates/stack-detection.json')"`; required keys present (`version`, `stacks`); each stack entry has `name`, `signals`, `detected_skill`

### Task 5: Update commands/brain.md — replace `init` stub with agent instructions

- **Action**: In the dispatch table, replace the `init` row with a reference to the inline instructions block below it. Add a new section after the dispatch table:

  ```markdown
  ## When `$ARGUMENTS` is `init`

  You are the codebrain init agent. Run this procedure:

  **Step 1 — Preconditions**: Verify `.brain/` exists in cwd. If not, print:
    `error: .brain/ not found. Run \`npx codebrain init\` first to scaffold the skeleton, then re-run \`/brain init\`.`
    and stop.

  **Step 2 — Read templates**: Read three files from the codebrain npm package:
    `skills/core/init/templates/claude-md-schema.md`
    `skills/core/init/templates/overview-starter.md`
    `skills/core/init/templates/stack-detection.json`

  **Step 3 — Schema block**: Read `<cwd>/CLAUDE.md`. Find `<!-- codebrain:begin -->` and `<!-- codebrain:end -->` markers.
    - If both present: replace the content between them with the contents of `claude-md-schema.md` (preserve everything outside the markers).
    - If markers missing: print error explaining to re-run `npx codebrain init` (which writes the markers) and stop.
    - If markers present + content between them is **already** the schema block (compare): SKIP unless operator passed `--force`.

  **Step 4 — Detect stack**: For each stack in `stack-detection.json`, evaluate the signals against the user's cwd:
    - `file_exists`: target file is present
    - `contains`: target file is present AND its content contains the substring
    - `dir_exists`: target directory is present
    - `glob`: at least one file matches the glob (relative to cwd)
    All signals in a stack's `signals` array must match (AND). Collect the list of matched stacks.

  **Step 5 — Populate overview.md**: Read `<cwd>/.brain/overview.md` (M#1 wrote a minimal skeleton).
    - Take `overview-starter.md` as the new template.
    - For each `<!-- AGENT: ... -->` instruction comment, do what it says — fill in Project Purpose from package.json description / README.md / top-level comments; generate Codebase Structure as a 1-level dir tree with one-line purposes; set Active State to today's date + detected stack list.
    - Update frontmatter: `status: FRESH` (was UNENRICHED), `last_ingested: <today>`, `ingested_by: <model-name-if-known>`.
    - Write back to `.brain/overview.md`.

  **Step 6 — Log**: Append to `<cwd>/.brain/log.md` under `## Activity History`:
    `## [YYYY-MM-DD] init | /brain init populated schema block + overview; detected: <stack-list>`
    Date format: ISO YYYY-MM-DD per PRD Design Decision #15.

  **Step 7 — Report**: Print a structured report:
    ```
    /brain init complete (v0.1.0)
      Schema block:   refreshed | unchanged
      overview.md:    populated (Project Purpose, Codebase Structure, Active State)
      Detected stack: react, typescript, nodejs
        Note: no `detected/` skills installed yet — coming in Milestone #3.
      Logged:         .brain/log.md
    Next: try `/brain ingest src/` (Milestone #3 — not yet implemented).
    ```
  ```

  Other verbs (`ingest`, `query`, `lint`, `learn`, `status`) stay as their current Milestone-N stubs.

- **Mirror**: `commands/brain.md:1-58` (existing structure); `scripts/init.js:166-201` (managed-region splice pattern)
- **Validate**: `! grep -q 'Milestone #2.*not yet implemented' commands/brain.md`; other verb stubs still present

### Task 6: Update commands/codebrain.md (alias)

- **Action**: Copy Task 5's changes verbatim — only the slash-command name differs because the file name differs (and we already have the alias-note line at the top). Concretely: the "When `$ARGUMENTS` is `init`" section is identical between the two files.
- **Mirror**: M#1 alias-equality pattern
- **Validate**: `diff <(sed -n '/When `\$ARGUMENTS` is `init`/,$p' commands/brain.md) <(sed -n '/When `\$ARGUMENTS` is `init`/,$p' commands/codebrain.md)` is empty (modulo any intentional alias-only note)

### Task 7: Update tests/e2e-test.sh — assertions for M#2 surface

- **Action**: Add a new test section after Test 9:

  ```bash
  # === Test 10: M#2 skill surface ============================================

  for f in \
    "$CODEBRAIN_ROOT/skills/core/init/SKILL.md" \
    "$CODEBRAIN_ROOT/skills/core/init/templates/claude-md-schema.md" \
    "$CODEBRAIN_ROOT/skills/core/init/templates/overview-starter.md" \
    "$CODEBRAIN_ROOT/skills/core/init/templates/stack-detection.json"
  do
    [ -f "$f" ] && ok "T10: $f exists" || nope "T10: $f missing"
  done

  head -1 "$CODEBRAIN_ROOT/skills/core/init/SKILL.md" | grep -q '^---$' \
    && ok "T10: SKILL.md starts with frontmatter" \
    || nope "T10: SKILL.md missing frontmatter"

  node -e "require('$CODEBRAIN_ROOT/skills/core/init/templates/stack-detection.json')" \
    && ok "T10: stack-detection.json parses" \
    || nope "T10: stack-detection.json invalid JSON"

  schema_lines=$(wc -l < "$CODEBRAIN_ROOT/skills/core/init/templates/claude-md-schema.md")
  [ "$schema_lines" -le 150 ] && ok "T10: schema block ≤150 lines ($schema_lines)" || nope "T10: schema block too long ($schema_lines lines)"

  # === Test 11: init verb is no longer a stub ================================

  ! grep -q 'Milestone #2.*not yet implemented' "$CODEBRAIN_ROOT/commands/brain.md" \
    && ok "T11: brain.md init verb is no longer stubbed" \
    || nope "T11: brain.md init verb still says Milestone #2 not yet implemented"

  ! grep -q 'Milestone #2.*not yet implemented' "$CODEBRAIN_ROOT/commands/codebrain.md" \
    && ok "T11: codebrain.md init verb is no longer stubbed" \
    || nope "T11: codebrain.md init verb still says Milestone #2 not yet implemented"

  # But other verb stubs still present (M#3+)
  for milestone in 3 5 6 7; do
    grep -q "Milestone #${milestone}.*not yet implemented" "$CODEBRAIN_ROOT/commands/brain.md" \
      && ok "T11: brain.md still stubs Milestone #${milestone}" \
      || nope "T11: brain.md missing stub for Milestone #${milestone}"
  done

  # === Test 12: alias parity for the init section ============================

  brain_init=$(sed -n '/When `\$ARGUMENTS` is `init`/,$p' "$CODEBRAIN_ROOT/commands/brain.md")
  cb_init=$(sed -n '/When `\$ARGUMENTS` is `init`/,$p' "$CODEBRAIN_ROOT/commands/codebrain.md")
  [ "$brain_init" = "$cb_init" ] && ok "T12: brain.md and codebrain.md init section match" || nope "T12: alias drift in init section"

  # === Test 13: npm pack includes new templates ==============================

  pack_list=$(cd "$CODEBRAIN_ROOT" && npm pack --dry-run 2>&1)
  echo "$pack_list" | grep -q 'skills/core/init/SKILL.md' && ok "T13: SKILL.md in npm pack" || nope "T13: SKILL.md missing from npm pack"
  echo "$pack_list" | grep -q 'skills/core/init/templates/claude-md-schema.md' && ok "T13: schema template in npm pack" || nope "T13: schema template missing from npm pack"
  echo "$pack_list" | grep -q 'skills/core/init/templates/stack-detection.json' && ok "T13: stack-detection.json in npm pack" || nope "T13: stack-detection missing from npm pack"
  ```
- **Mirror**: existing T1–T9 style in `tests/e2e-test.sh`
- **Validate**: `bash tests/e2e-test.sh` exits 0; total count goes from 43 → ~58 (~15 new assertions); runtime still <5s

### Task 8: PRD update — M#2 row → in-progress

- **Action**: Edit `.claude/prds/codebrain.prd.md`: in the Delivery Milestones table, change the M#2 row's `Status` from `pending` to `in-progress` and `Plan` from `—` to `[.claude/plans/codebrain-m2.plan.md](.claude/plans/codebrain-m2.plan.md)`
- **Mirror**: M#1 PRD update pattern
- **Validate**: `grep "Init + schema" .claude/prds/codebrain.prd.md` shows the updated row

## Validation

```bash
# 1. E2E test (combined M#1 + M#2 surface)
bash tests/e2e-test.sh
# Expect: ~58 passes, 0 failures, <5s

# 2. New files exist with correct shape
test -f skills/core/init/SKILL.md
test -f skills/core/init/templates/claude-md-schema.md
test -f skills/core/init/templates/overview-starter.md
test -f skills/core/init/templates/stack-detection.json
head -1 skills/core/init/SKILL.md | grep -q '^---$'
node -e "require('./skills/core/init/templates/stack-detection.json')"

# 3. Schema block respects ≤150-line cap
test "$(wc -l < skills/core/init/templates/claude-md-schema.md)" -le 150

# 4. init verb is no longer a Milestone #2 stub
! grep -q 'Milestone #2.*not yet implemented' commands/brain.md
! grep -q 'Milestone #2.*not yet implemented' commands/codebrain.md

# But Milestones #3, #5, #6, #7 are still stubs
grep -q 'Milestone #3.*not yet implemented' commands/brain.md
grep -q 'Milestone #5.*not yet implemented' commands/brain.md
grep -q 'Milestone #6.*not yet implemented' commands/brain.md
grep -q 'Milestone #7.*not yet implemented' commands/brain.md

# 5. brain.md and codebrain.md init sections agree
diff <(sed -n '/When `$ARGUMENTS` is `init`/,$p' commands/brain.md) \
     <(sed -n '/When `$ARGUMENTS` is `init`/,$p' commands/codebrain.md)
# Expect: empty diff

# 6. npm pack ships the new files
npm pack --dry-run | grep -E 'skills/core/init/(SKILL\.md|templates/)'

# 7. Manual smoke test (operator)
# In a Claude Code session inside a repo that already ran `npx codebrain init`:
#   /brain init             → schema block refreshed, overview.md populated, stack reported, log appended
#   /brain init             → second run reports SKIP (idempotent)
#   /brain init --force     → forces refresh even if managed region is current
#   /brain init (in a repo without .brain/) → error explains to run `npx codebrain init` first
```

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Schema block exceeds 150-line cap | Med | Task 2 author self-edits during writing; T10 asserts the cap |
| Stack detection misclassifies (e.g., Python repo with package.json from a Node toolchain) | Med | Detect AND report all matched stacks; agent says "Detected: python (strong), nodejs (weak — package.json found in tooling/)" rather than picking one; operator can correct |
| `/brain init` runs before `npx codebrain init` (no `.brain/`) | Low | Task 5 Step 1: explicit precondition check with helpful error message |
| LLM ignores the verbatim template and writes its own schema block | Med | Template is read as a file then written verbatim; instruction emphasizes "write the file content verbatim into the managed region — do not paraphrase". Lint (M#6) will catch drift. |
| Skill auto-discovery doesn't work from npm-installed location | Low | The slash command body in `commands/brain.md` is the load-bearing contract — it's read by Claude Code via the `.claude/commands/` install path. SKILL.md is documentation. If skill auto-discovery fails, the slash command still works. |
| Idempotency check in Step 3 produces a false-positive SKIP when minor formatting differs | Med | Compare content trimmed; if doubt, prompt the operator before overwriting; `--force` always overwrites |
| Templates ship in npm but agent can't find them at runtime in the npm-installed location | Med | T13 asserts they're in `npm pack`; M#1's `files:` whitelist already includes `skills/` recursively; if Claude Code can't find them, document the path in the agent instructions (Step 2 says "from the codebrain npm package" — explicit) |
| Agent populates overview.md but ignores frontmatter status transition | Low | Step 5 explicitly lists frontmatter updates; M#6 lint catches stale status fields |
| Alias drift between brain.md and codebrain.md (init section) | Low | T12 asserts the init sections are byte-identical |

## Acceptance

- [ ] All 8 tasks complete
- [ ] Validation §1 (e2e test, ~58 assertions) passes; runtime <5s
- [ ] Validation §2 (files exist with correct shape) passes
- [ ] Validation §3 (schema block ≤150 lines) passes
- [ ] Validation §4 (init no longer stubbed; other verbs still stubbed) passes
- [ ] Validation §5 (alias parity) passes
- [ ] Validation §6 (npm pack includes new files) passes
- [ ] PRD M#2 row updated to in-progress with plan link
- [ ] Patterns mirrored from M#1's shipped artifacts and existing skill/template conventions — not reinvented
- [ ] No regression: all 43 existing M#1 tests still pass
- [ ] (Optional) Manual smoke test on a real Claude Code session against a dogfood repo (e.g., one of graphify/graphbrain/ECC); deferred to acceptance call
