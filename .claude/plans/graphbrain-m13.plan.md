# Plan: graphbrain — Milestone #13 (Stack-aware skill recommendations, agent-driven)

**Source PRD**: `.claude/prds/graphbrain.prd.md` (v0.2 Roadmap section — to be amended in this milestone)
**Selected Milestone**: #13 — Operator-pain follow-up. graphbrain detects the stack at init time but doesn't connect that detection to the actual stack-specific code-writing expertise the operator needs. Fresh installs are wiki-shaped but offer no immediate uplift for prompts like "implement auth in Next.js."
**Complexity**: Small (M#13a, shipped v1.0.7) → Medium (M#13b, slash-command for auto-install) → Large (M#13c, port graphbrain-old SDLC + community, deferred to v1.1).
**Status**: **M#13a SHIPPED in v1.0.7** (agent-driven recommendations). M#13b DRAFT (agent-driven auto-install verb). M#13c DEFERRED to v1.1.

## Sweep findings (recorded post-recon, before implementation)

1. **5 broken ECC bridges in shipped v0.2 code**: our `detected/{react,typescript,vue,rails,flask}/SKILL.md` declared `expert_skills:` pointing to `ecc:react-patterns`, `ecc:typescript-patterns`, `ecc:vue-patterns`, `ecc:rails-patterns`, `ecc:flask-patterns` — **none of these exist** in ECC's actual catalog (verified by enumerating `ECC/skills/`). The bridge probe at /brain:ingest Step 4b.3 would just report them as unavailable. **FIXED in v1.0.7** — removed from registry.json + per-skill SKILL.md files.

2. **ECC's real surface for our stacks** (post-audit, 233 skills in `ECC/skills/`): `nextjs-turbopack`, `nestjs-patterns`, `backend-patterns`, `django-patterns`, `django-security`, `fastapi-patterns`, `springboot-patterns`, `springboot-security`, `python-patterns`, `golang-patterns`, `docker-patterns`, `deployment-patterns`. NO react / vue / typescript / rails / flask skills — for those stacks, recommendations come from PatternsDev/skills (react, vue, javascript) or no external source.

3. **graphbrain-old SDLC skill format is NOT v1.x-compatible**: sample inspection of `skills-registry/core/requirements/SKILL.md` shows frontmatter `name: sdlc-requirements`, `metadata: { phase, pattern }`, `paths: [glob]`, `trigger_phrases:`, `license:` — different from graphbrain v1.x's merged format. "Port verbatim" is wrong; M#13c needs frontmatter rewrites + body rewrites (community agents also reference `.ctx/` paths which would break in `.brain/`). **Defers M#13c to v1.1** — substantial new authoring, not a copy job.

4. **patterns.dev install target is user-global by default**: their `npx skills add ...` writes to `~/.claude/skills/<name>/SKILL.md`. Mixed with graphbrain's plugin tree at `.claude/plugins/graphbrain/` (project-local), this is fine — different paths, no conflict. The recommendation print block tells the operator about the install scope so they're not surprised.

5. **Architectural shift mid-implementation (M#13a)**: the original plan put stack detection + recommendation printing in `scripts/init.js` (imperative, runs at npm-install time). Operator pushback: graphbrain is a Claude-Code-extending package; smart decisions should be **agent-driven**, not imperative. Reverted the imperative-detection helper. Recommendations now surface via `commands/brain/init.md` Step 4c — Claude reads the catalog, applies LLM judgment to THIS repo's specifics (e.g., is package.json's "main" a CLI or web app entry point?), filters / dedupes / prioritizes, and prints the block in Step 7 output. **`init.js` stays focused on file scaffolding.** This shapes M#13b too (auto-install is also agent-driven, not a CLI flag).

## Summary

Operator observation (verbatim): "when we do brain:init we are detecting repo code what tech stack it has at that time we should make sure any future changes or features should use specific skills of that tech stack for example react next js even if you found docker or yml deployment files in init we should be able to get front end devops skill input in a place where they are always invoked for future prompts."

Plus follow-up: "what are we using? we should use claude llm capabilities to detect and make decisions — why are you having init js file?"

Current state (v1.0.7, after M#13a):
- `npx graphbrain init` scaffolds files + plugin tree. **No detection, no recommendations** — that's not its job.
- `/brain:init` (Claude-driven) does Step 4 (detect) + **Step 4c (recommend)** + Step 5+ (populate overview/log/etc.). Recommendations are dynamic — Claude picks what fits this repo, not a hardcoded algorithm.

M#13 closes the loop in three coordinated pieces:

1. ✅ **M#13a — Recommendation catalog + agent-driven print** (shipped v1.0.7): extended `stack-detection.json` with `recommended_skills[]` per stack (patterns.dev + ECC sources, verified against ECC's real surface). Added Step 4c to `commands/brain/init.md` describing the agent procedure. Step 7 report template includes the `Recommended skills:` block.

2. **M#13b — Agent-driven auto-install** (DRAFT — see Sub-milestone split): a new slash command `/brain:install-recommended` (or `/brain:init --install-recommended` flag) that takes the recommendations from Step 4c and executes the install commands. Agent-driven so Claude can confirm with the operator, handle per-install failures, log to `.brain/log.md`. NOT a CLI flag in init.js.

3. **M#13c — Port graphbrain-old SDLC skills + community agents** (DEFERRED to v1.1): six new `skills/sdlc/{requirements,design,implementation,testing,deployment,maintenance}/SKILL.md` + four `agents/community/{code-reviewer,debugger,goap-planner,refactorer}.md`. Substantial frontmatter + body rewrites required (graphbrain-old's format isn't v1.x-compatible). Out of scope for v1.0.x.

## Evidence base

Three sources researched (May 2026):

1. **PatternsDev/skills** (https://github.com/PatternsDev/skills) — 58 agent-optimized Claude Code skills across javascript/, react/, vue/. Install via `npx skills add PatternsDev/skills/<framework>` or `npx skills add PatternsDev/skills --skill <skill-name>`. Files land at `~/.claude/skills/`. Skills are pure SKILL.md (prose + code, no images). Activation is description-based.
2. **graphbrain-old** (`/Users/dev/Desktop/Project/OSS/idea/graphbrain/`) — previous incarnation. Had `skills-registry/{behavioral,ingestion,core,detected,available}/` + `agents-registry/{brain,sdlc,community}/`. **Key insight: had a `core/` SDLC tier** with 6 phase skills. graphbrain v1.x's `core/` is per-verb (`core/init`, `core/ingest`, etc.) — distinct concept.
3. **ECC** (`.claude-plugin/plugin.json` + skills tree, 233 skills audited) — graphbrain already bridges via M#9-prereq probe. M#13 adds **recommendations** at init time + (M#13b) install execution.

## Patterns to Mirror

| Category | Source | Pattern |
|---|---|---|
| Recommendation map per stack | This milestone's convention | Extend each entry in `stack-detection.json` with `recommended_skills: [{ source, package, install_command, description }]` |
| Agent-driven recommendation procedure | M#2's `/brain:init` Step 4 (detection) | Step 4c "Stack-specific skill recommendations" — agent reads each detected stack's `recommended_skills`, applies LLM judgment to THIS repo's specifics, dedupes, formats the block, appends to Step 7 report |
| Agent-driven auto-install (M#13b) | M#3a single-file ingest's cost-gate pattern; M#11's confirmation gates | NEW slash command `/brain:install-recommended` or flag `/brain:init --install-recommended`. Procedure: re-run detection, confirm with operator, exec `Bash: npx -y skills add ...` per recommendation, log per-install outcome to `.brain/log.md`. Not in init.js. |
| SDLC tier extension (M#13c, deferred) | graphbrain-old's `skills-registry/core/{requirements,...}/` | New top-level `skills/sdlc/{requirements,design,implementation,testing,deployment,maintenance}/SKILL.md` with v1.x-compatible frontmatter. Always-loaded tier. |
| Community agents (M#13c, deferred) | graphbrain-old's `agents-registry/community/` | `agents/community/<name>.md` with v1.x frontmatter (`tools`, `description`, `pattern`, `trigger_phrases`, `max_iterations`). Body rewritten for `.brain/` (not `.ctx/`). |

## Files Changed in M#13a (shipped v1.0.7)

| File | Change |
|---|---|
| `skills/core/init/templates/stack-detection.json` | Added `recommended_skills[]` to 18 high-priority stacks. Each entry shaped `{ source: "patterns.dev" \| "ecc", package, install_command, description }`. Verified ECC packages against ECC's real catalog. |
| `commands/brain/init.md` | Added **Step 4c — Stack-specific skill recommendations**. Defines the agent procedure: read catalog, dedupe by (source, package), apply LLM judgment for THIS repo, format block. Step 7 report template gains `Recommended skills:` section. |
| `skills/registry.json` | Removed 5 broken ECC bridges (ecc:react-patterns, ecc:typescript-patterns, ecc:vue-patterns, ecc:rails-patterns, ecc:flask-patterns — none exist in ECC's catalog). |
| `skills/detected/{vue,rails,flask}/SKILL.md` | `expert_skills:` changed from `[ecc:vue-patterns]` (etc.) → `[]`. |
| `tests/e2e-test.sh` | T45 updated (broken-bridge expectations replaced with verified-bridge expectations). T49 added — asserts agent-side contract (Step 4c exists; init.js does NOT contain imperative detection; both source types documented; Step 7 report has the recommendations block). |
| `scripts/init.js` | **Briefly extended then reverted** during M#13a development (architectural pushback). init.js stays focused on file scaffolding; no detection, no recommendations. |
| `package.json` / `.claude-plugin/plugin.json` | 1.0.6 → 1.0.7. |

## Files to Change in M#13b (draft)

| File | Action | Why |
|---|---|---|
| `commands/brain/install-recommended.md` (NEW) **OR** `commands/brain/init.md` (UPDATE with `--install-recommended` flag) | CREATE / UPDATE | New agent procedure for auto-install. Reads recommendations from `stack-detection.json` (same source as Step 4c), prompts operator confirmation (per-install or batched, gated by `--yes`), shells out via `Bash: npx -y skills add ...` per patterns.dev entry, logs outcomes. ECC entries: print install-ECC-plugin instructions (we can't install ECC for the operator — they install it via Claude Code's plugin marketplace). |
| `commands/brain.md` (dispatcher) | UPDATE | Add new verb to dispatch table + help block (if M#13b ships as a separate verb). OR document the `--install-recommended` flag for `/brain:init`. |
| `agents/brain/install-orchestrator.md` (NEW) — OR reuse spec-orchestrator | CREATE | (if dedicated agent makes sense) Handles the per-install confirmation + retry logic + error recovery. Tools: `[Read, Bash]`. Pattern: Orchestrator. |
| `tests/e2e-test.sh` | UPDATE | T50: assert the new slash command exists with the procedure shape. T51: smoke-mock — assert the agent procedure parses recommendations correctly + emits the right `npx skills add` commands (without actually executing). |

## Files to Change in M#13c (deferred to v1.1)

| File | Action |
|---|---|
| `skills/sdlc/requirements/SKILL.md` (NEW) | Port from graphbrain-old `skills-registry/core/requirements/SKILL.md`. Rewrite frontmatter (merged format). Refresh body to remove `.ctx/` references; use `.brain/` paths. |
| `skills/sdlc/design/SKILL.md` (NEW) | Same. |
| `skills/sdlc/implementation/SKILL.md` (NEW) | Same. |
| `skills/sdlc/testing/SKILL.md` (NEW) | Same. |
| `skills/sdlc/deployment/SKILL.md` (NEW) | Same. The "if YAML deploy files detected → deployment skill" thread from operator's ask. |
| `skills/sdlc/maintenance/SKILL.md` (NEW) | Same. |
| `agents/community/{code-reviewer,debugger,goap-planner,refactorer}.md` (NEW × 4) | Port from graphbrain-old `agents-registry/community/<name>/AGENT.md`. Rewrite frontmatter to v1.x merged format. Refresh body. |
| `skills/registry.json` | Add 6 SDLC entries + 4 community agents. |
| `package.json` `files:` whitelist | Already covers `skills/` + `agents/` recursively — no change. |

## Sub-milestone split

- ✅ **M#13a — Recommendation catalog + agent-driven print** (SHIPPED v1.0.7): catalog extension + Step 4c in `/brain:init` + verified ECC bridges. Operator sees recommendations during `/brain:init`; manually copies + runs the install commands. **No third-party shell-out from graphbrain; operator chooses.**

- **M#13b — Agent-driven auto-install** (DRAFT): graphbrain executes the install commands on operator's behalf, gated by confirmation. Lives as a new slash verb (`/brain:install-recommended`) OR a flag on `/brain:init`. Agent-driven by design — operator can pick subset, agent handles per-install retry/fallback, agent logs to `.brain/log.md`. NOT a CLI flag in init.js.

- **M#13c — Port graphbrain-old SDLC + community** (DEFERRED v1.1): substantial frontmatter + body rewrites; out of scope for v1.0.x; revisit after operator dogfood shows whether the SDLC layer adds value over ECC's coverage.

## M#13b — design questions (resolve before implementation)

1. **New verb vs. flag**: `/brain:install-recommended` (new verb) vs `/brain:init --install-recommended` (flag on existing verb).
   - New verb: cleaner — install is its own operation; `/brain:init` stays focused on the existing scaffold-populate-detect-recommend flow.
   - Flag: less surface; init-and-install in one shot.
   - **Recommendation: new verb**. Operators often want to install LATER (after reading recommendations + deciding), not as part of init.

2. **Auto-install scope**: only patterns.dev (executable `npx skills add ...`) or also try ECC?
   - patterns.dev installs are simple shell-outs.
   - ECC is a Claude Code plugin install — different mechanism (operator runs `/plugin install ecc` or installs from marketplace UI). graphbrain shouldn't try to script this.
   - **Recommendation: only patterns.dev auto-installs**. For ECC, print the manual install instructions.

3. **Confirmation UX**: per-skill prompt or one batched confirm?
   - Per-skill: clear opt-in/out per package; slow for many recommendations.
   - Batched: faster; operator can `--yes` to skip; risk of installing unwanted skills if operator clicks through.
   - **Recommendation: batched with `--yes` shortcut + cost gate** (mirror `/brain:ingest` folder Step 4 pattern — if more than 5 installs, require explicit ack unless `--yes`).

4. **Log target**: `.brain/log.md` activity history (per-event audit trail) and `.brain/CHANGELOG.md` (compound-learning narrative) — both? Just log.md?
   - **Recommendation: both**. log.md gets `## [YYYY-MM-DD] install-recommended | <N> installed, <K> failed` (audit trail). CHANGELOG.md gets a single narrative entry summarizing the install batch.

5. **What if the operator already has the skill installed**?
   - `npx skills add` would either no-op or overwrite — depends on patterns.dev's CLI. Test behavior in M#13b.
   - **Recommendation: ship the cost gate first; explore overwrite UX in v1.1 once we have dogfood evidence**.

## Validation (current — post-M#13a)

```bash
# E2E
bash tests/e2e-test.sh
# Expected: 965 / 965 pass (M#13a's T45 update + T49 contract added).

# Catalog has recommendations on major stacks (T49)
node -e "
  const j = require('skills/core/init/templates/stack-detection.json');
  const must_have = ['react', 'vue', 'nextjs', 'nodejs', 'python', 'django', 'go', 'docker'];
  for (const name of must_have) {
    const s = j.stacks.find(x => x.name === name);
    if (!Array.isArray(s.recommended_skills) || s.recommended_skills.length === 0) {
      throw new Error('missing recommendations for ' + name);
    }
  }
"

# Step 4c exists in /brain:init procedure (T49)
grep -qF '**Step 4c — Stack-specific skill recommendations' commands/brain/init.md

# init.js does NOT contain imperative detection (T49, architecture compliance)
! grep -q 'function detectStacks' scripts/init.js

# Broken ECC bridges removed (T45)
node -e "
  const r = require('skills/registry.json');
  for (const [k, v] of Object.entries(r.skills)) {
    for (const b of (v.expert_skills || [])) {
      const broken = ['ecc:react-patterns','ecc:typescript-patterns','ecc:vue-patterns','ecc:rails-patterns','ecc:flask-patterns'];
      if (broken.includes(b)) throw new Error('broken bridge still declared in ' + k + ': ' + b);
    }
  }
"

# Manual smoke (post-commit):
#   In a React + TypeScript repo, run /brain:init.
#   Step 7 output includes "Recommended skills for this stack:" block with:
#     - patterns.dev (https://github.com/PatternsDev/skills):
#         React design + rendering patterns (15 skills)
#         $ npx -y skills add PatternsDev/skills/react
#         JS design patterns (27 skills)
#         $ npx -y skills add PatternsDev/skills/javascript
#     - ECC plugin (auto-bridges once installed):
#         (no react/typescript ECC skills today; operator may install ECC for backend coverage)
#   Operator copy-pastes the install commands and runs them.
#   On the next Claude Code prompt mentioning a React feature, the skills are loaded.
```

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| PatternsDev/skills package format changes / breaks | Med | We document recommendation commands; we don't depend on patterns.dev's internal layout. CLI command shape is in stack-detection.json and easy to update. |
| ECC skill names change | Med | Plan acknowledges. Already burnt once (5 broken bridges in v0.2 → fixed in v1.0.7). v1.x mitigation: every PR that adds an ECC recommendation MUST cite the actual ECC skill path it verified against. |
| Operator runs auto-install (M#13b) blindly + ends up with 20+ skills they don't want | Med | M#13b cost gate (if more than 5 installs would happen, require explicit confirmation unless `--yes`). Mirrors `/brain:ingest` folder Step 4 pattern. |
| graphbrain-old SDLC content (M#13c) duplicates ECC's coverage | High | M#13c deferred to v1.1 specifically because of this. Operator dogfood at v1.0.7 + v1.0.8 will show whether SDLC tier adds value. If not, drop M#13c entirely. |
| Recommendation catalog (stack-detection.json) becomes a security vector — a malicious PR could add a recommendation to install a hostile package | Low (today) → Med (as repo grows) | All recommendations live in graphbrain's own repo; PR review catches additions. Document the trust model in PRD. Long-term: signed recommendation manifest? |
| Operator confused by "recommendations" vs "auto-installed" (M#13a only prints; M#13b actually installs) | Low | M#13b ships under a separate verb (`/brain:install-recommended`) so the operation is explicit. Default (`/brain:init`) is recommend-only. |
| Auto-install (M#13b) fails partway → repo in mixed state | Low | Per-install failures don't abort the batch; final summary lists which succeeded + which failed + manual fallback commands. |

## Acceptance

**M#13a — shipped v1.0.7**:
- ✅ `stack-detection.json` has `recommended_skills[]` for 18 major stacks
- ✅ Each recommendation entry shaped `{ source, package, install_command, description }`
- ✅ ECC entries reference only verified-existing ECC skills (audited against ECC's 233-skill catalog)
- ✅ `commands/brain/init.md` Step 4c describes the agent procedure
- ✅ Step 7 report template includes the `Recommended skills:` block
- ✅ `scripts/init.js` has NO imperative stack-detection logic (architecture compliance — Claude-driven)
- ✅ 5 broken ECC bridges removed from registry.json + per-skill SKILL.md
- ✅ E2E: 965 / 965 pass (T45 updated, T49 added)

**M#13b — provisional acceptance (when shipped)**:
- [ ] `/brain:install-recommended` (or equivalent flag) procedure exists in `commands/brain/`
- [ ] Agent re-derives recommendations from `stack-detection.json` + applies LLM judgment for relevance
- [ ] Per-install confirmation gate (`--yes` opt-out) + cost gate at >5 installs
- [ ] Bash exec per patterns.dev entry; ECC prints instructions
- [ ] Per-install outcomes logged to `.brain/log.md`; batch summary to `.brain/CHANGELOG.md`
- [ ] T50/T51 cover the procedure shape + smoke-mock of the install execution

**M#13c — provisional acceptance (v1.1)**:
- [ ] 6 SDLC SKILL.md files at `skills/sdlc/{requirements,design,implementation,testing,deployment,maintenance}/SKILL.md` with v1.x-format frontmatter
- [ ] 4 community agents at `agents/community/{code-reviewer,debugger,goap-planner,refactorer}.md` with v1.x-format frontmatter
- [ ] All references to `.ctx/` rewritten to `.brain/`
- [ ] Registry + npm pack updated; T52 covers presence + frontmatter shape
- [ ] (Operator-validated) SDLC skills actually add value over ECC's existing coverage — if not, drop M#13c

## Open questions (mostly resolved; one remains)

- ✅ **Architecture: imperative vs agent-driven** — resolved during M#13a development. Agent-driven (Claude reads catalog + applies LLM judgment + prints). `scripts/init.js` stays focused on scaffolding.
- ✅ **Recommendation catalog tier vs flat** — kept flat in stack-detection.json (consistent with the existing catalog shape).
- ✅ **ECC skill names** — audited and verified against ECC's real catalog (233 skills enumerated). Only verified skills referenced.
- **Open — Tier placement for M#13c SDLC skills** — `skills/sdlc/` (new top-level tier) vs `skills/core/sdlc/` (nested under per-verb core). **Recommendation: new top-level `skills/sdlc/` tier** for cleaner separation. Resolve before M#13c starts.
- ✅ **`--install-skills` vs `--with-recommended` naming** — moot; we're not putting the flag in init.js. New slash verb `/brain:install-recommended` (recommended).
- ✅ **Per-project vs user-global install** — moot; that's patterns.dev's choice (their CLI installs to `~/.claude/skills/`). graphbrain just relays the install command.

---

**M#13 status (v1.0.7)**: M#13a shipped; M#13b is the next ship-target; M#13c remains v1.1+ pending operator dogfood evidence.
