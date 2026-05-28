# Plan: graphbrain — Milestone #13 (Stack-aware skill recommendation + install bridge)

**Source PRD**: `.claude/prds/graphbrain.prd.md` (v0.2 Roadmap section — to be amended in this milestone)
**Selected Milestone**: #13 — Operator-pain follow-up. graphbrain detects the stack at init time but doesn't connect that detection to the actual stack-specific code-writing expertise the operator needs. Fresh installs are wiki-shaped but offer no immediate uplift for prompts like "implement auth in Next.js."
**Complexity**: Medium — extends `stack-detection.json`, modifies init.js post-detection step, introduces optional auto-install path (shells out to third-party `npx skills`), ports content from graphbrain-old + recommends from PatternsDev/skills + ECC.
**Status**: DRAFT (post-sweep) — most operator-visible v1.x work; sweep findings (below) reshape M#13c. Implementation order: M#13a first (smallest, highest leverage); M#13b second (auto-install gated by `--with-recommended` flag); M#13c **deferred** to v1.1 (port effort is much higher than the original plan estimated).

## Sweep findings (recorded post-recon, before implementation)

1. **5 broken ECC bridges in shipped v0.2 code**: our `detected/{react,typescript,vue,rails,flask}/SKILL.md` declare `expert_skills:` pointing to `ecc:react-patterns`, `ecc:typescript-patterns`, `ecc:vue-patterns`, `ecc:rails-patterns`, `ecc:flask-patterns` — **none of these exist** in ECC's actual catalog (verified by enumerating `ECC/skills/`). The bridge probe at /brain:ingest Step 4b.3 will just report them as unavailable, but the declarations advertise capabilities that won't materialize. **Fix in this milestone** — see M#13a Task 1b.

2. **ECC's real surface for our stacks** (post-audit): `nextjs-turbopack`, `nestjs-patterns`, `backend-patterns`, `django-patterns`, `django-security`, `fastapi-patterns`, `springboot-patterns`, `springboot-security`, `python-patterns`, `golang-patterns`, `docker-patterns`, `deployment-patterns`. NO react / vue / typescript / rails / flask skills — for those stacks, recommendations come from PatternsDev/skills (react, vue, javascript) or no external source.

3. **graphbrain-old SDLC skill format is NOT v1.x-compatible**: sample inspection of `skills-registry/core/requirements/SKILL.md` shows frontmatter `name: sdlc-requirements`, `metadata: { phase, pattern }`, `paths: [glob]`, `trigger_phrases:`, `license:` — different from graphbrain v1.x's merged format. "Port verbatim" is wrong; M#13c needs frontmatter rewrites + body rewrites (community agents also reference `.ctx/` paths which would break in `.brain/`). **Defers M#13c to v1.1** — substantial new authoring, not a copy job.

4. **Plan's original M#13c scope is uncertain value**: ECC has 773 SKILL.md files; the "always-loaded SDLC tier" we'd port from graphbrain-old likely duplicates ECC's coverage. **Recommendation: drop M#13c from this milestone**; revisit if operator dogfood shows the SDLC tier adds value over ECC's catalog.

5. **patterns.dev install target is user-global by default**: their `npx skills add ...` writes to `~/.claude/skills/<name>/SKILL.md`. Mixed with graphbrain's plugin tree at `.claude/plugins/graphbrain/` (project-local), this is fine — different paths, no conflict. But document the distinction in the print block (operator should understand "this command installs globally; available across all your repos").

6. **Tier placement for SDLC**: original open question 1. Now moot (M#13c deferred). If revisited: recommend new top-level `skills/sdlc/` tier (clean separation from `skills/core/` per-verb procedures).

7. **No uninstall path**: PatternsDev/skills' README doesn't document `npx skills remove`. Operator who regrets `--with-recommended` install must hand-clean `~/.claude/skills/`. Document this in the print block + M#13b's confirmation prompt.

## Summary

Operator observation (verbatim): "when we do brain:init we are detecting repo code what tech stack it has at that time we should make sure any future changes or features should use specific skills of that tech stack for example react next js even if you found docker or yml deployment files in init we should be able to get front end devops skill input in a place where they are always invoked for future prompts."

Current state (v1.0.6):
- `npx graphbrain init` detects ~25 stacks (`stack-detection.json` catalog).
- Detected stacks are **REPORTED** to the operator and used internally by `/brain:ingest` Step 4b for page-template extras.
- They are **NOT** connected to any external skill installation. The actual code-writing expertise comes from:
  - ECC's per-framework skills (`ecc:nextjs-turbopack`, `ecc:django-patterns`, etc.) — bridge-probed by graphbrain at ingest time, NOT at init time
  - PatternsDev/skills — completely unknown to graphbrain today
  - graphbrain-old's `skills-registry/core/{requirements,design,implementation,testing,deployment,maintenance}/` SDLC-phase skills — not in graphbrain v1.x at all

Result: a fresh `npx graphbrain init` produces a wiki scaffold + slash commands but no immediate uplift on stack-specific coding prompts. The operator has to know-of-and-manually-install patterns.dev / ECC / etc.

M#13 closes this gap. Three coordinated pieces:

1. **Recommendation map** — extend `stack-detection.json` so each detected stack carries an array of recommended-skill sources (patterns.dev packages, ECC plugin skills, graphbrain-side SDLC skills).
2. **Init.js post-detection step** — after Step 4 (detection), print the recommendations + install commands for the operator. Optional `--install-skills` flag executes them via `npx skills add ...`.
3. **(Optional sub-milestone) Port graphbrain-old's SDLC + community skills** — add `skills/core/{requirements,design,implementation,testing,deployment,maintenance}/SKILL.md` and `agents/community/{code-reviewer,debugger,goap-planner,refactorer}.md` to graphbrain's own ship. These are "always-loaded" regardless of stack.

## Evidence base

Three sources researched (May 2026):

1. **PatternsDev/skills** (https://github.com/PatternsDev/skills) — 58 agent-optimized Claude Code skills across javascript/, react/, vue/. Install via `npx skills add PatternsDev/skills/<framework>` or `npx skills add PatternsDev/skills --skill <skill-name>`. Files land at `~/.claude/skills/`, `.claude/skills/`, `~/.cursor/skills/`, or `~/.codex/skills/`. Skills are pure SKILL.md format (prose + code blocks, no images). Activation is description-based (Claude Code's loader matches the `description:` field against the prompt — no trigger phrases or extension-based activation).
2. **graphbrain-old** (`/Users/dev/Desktop/Project/OSS/idea/graphbrain/`) — previous incarnation. Had `skills-registry/{behavioral,ingestion,core,detected,available}/` tier model + `agents-registry/{brain,sdlc,community}/`. **Key insight: had a `core/` SDLC tier** with 6 phase skills (`requirements`, `design`, `implementation`, `testing`, `deployment`, `maintenance`) — all "always-loaded" regardless of stack. graphbrain v1.x has `core/` but it's per-verb procedures (`core/init`, `core/ingest`, etc.), not SDLC. Distinct tier; complementary.
3. **ECC** (`.claude-plugin/plugin.json` + skills tree) — formal Claude Code plugin. graphbrain already bridges to ECC via the M#9-prereq runtime probe (`~/.claude/plugins/ecc/skills/<name>/SKILL.md`). M#13 doesn't change that bridge — it adds an init-time RECOMMENDATION to install ECC.

## Patterns to Mirror

| Category | Source | Pattern |
|---|---|---|
| Recommendation map per stack | This milestone (new convention) | Extend each entry in `stack-detection.json` with `recommended_skills: [{ source, package, install, description }]` |
| Init-time post-detection step | M#2's `/brain:init` Step 4 (stack detection) — already produces a detected-stacks list | Add Step 4c — "Recommendations": look up each detected stack's `recommended_skills`, format printable block, append to Step 7 report |
| Auto-install via shell-out | PatternsDev/skills' own README — they document `npx skills add ...` as the install command | M#13's optional `--install-skills` flag spawns `npx skills add ...` per recommendation. Bash exec; capture output; log per-install outcome. |
| SDLC tier extension | graphbrain-old's `skills-registry/core/{requirements,...}/` — six SKILL.md files | Port verbatim (or update for v1.x) into graphbrain v1.x's `skills/core/sdlc/{requirements,design,implementation,testing,deployment,maintenance}/SKILL.md`. Always-loaded tier. |
| Community agents | graphbrain-old's `agents-registry/community/{code-reviewer,debugger,goap-planner,refactorer}/` | Same pattern as our `agents/brain/*` — port into `agents/community/<name>.md` with merged-format frontmatter (`tools`, `pattern`, `trigger_phrases`, `max_iterations`). |
| Stack detection (already in place) | `stack-detection.json` catalog (~25 stacks) | M#13 extends entries; doesn't change the detection algorithm |

## Files to Change

| File | Action | Why |
|---|---|---|
| `skills/core/init/templates/stack-detection.json` | UPDATE | Add `recommended_skills: []` array to each stack entry (where applicable). Source-typed objects (patterns.dev / ecc / graphbrain-sdlc). ~25 stacks × 1-3 recommendations each ≈ 50-75 new entries. |
| `scripts/init.js` | UPDATE | After Step 4 (detection): look up recommendations per detected stack, dedupe across stacks, format the printable block, optionally execute via `--install-skills`. Adds ~80 lines. |
| `commands/brain/init.md` | UPDATE | Document Step 4c — "Recommendations" — in the slash-command procedure so the agent invocation of /brain:init also surfaces them. |
| `skills/core/sdlc/requirements/SKILL.md` (NEW) | CREATE | Ported from graphbrain-old `skills-registry/core/requirements/SKILL.md`; refreshed for graphbrain v1.x conventions. |
| `skills/core/sdlc/design/SKILL.md` (NEW) | CREATE | Same. |
| `skills/core/sdlc/implementation/SKILL.md` (NEW) | CREATE | Same. |
| `skills/core/sdlc/testing/SKILL.md` (NEW) | CREATE | Same. |
| `skills/core/sdlc/deployment/SKILL.md` (NEW) | CREATE | Same. Picks up the "if YAML deploy files detected → deployment skill" thread from operator's ask. |
| `skills/core/sdlc/maintenance/SKILL.md` (NEW) | CREATE | Same. |
| `agents/community/code-reviewer.md` (NEW) | CREATE | Port from graphbrain-old. |
| `agents/community/debugger.md` (NEW) | CREATE | Same. |
| `agents/community/goap-planner.md` (NEW) | CREATE | Same. |
| `agents/community/refactorer.md` (NEW) | CREATE | Same. |
| `skills/registry.json` | UPDATE | Add the 6 new SDLC skills + 4 community agents to the registry. |
| `bin/graphbrain.js` | UPDATE | Add `--install-skills` flag parsing + pass through to `init()`. Update help text. |
| `tests/e2e-test.sh` | UPDATE | T49: stack-detection.json has `recommended_skills` for at least the major stacks (react/vue/nextjs/python/go/docker). T50: init prints recommendations block when stacks detect. T51: `--install-skills` executes the install commands (mocked — assert the shell commands invoked match the recommendations, don't actually run npx). T52: new SDLC skills + community agents land in npm pack. |
| `scripts/dogfood/install-validate.sh` | UPDATE | Assert the recommendations block appears in init output when test repo has react/nodejs files. |
| `README.md` | UPDATE | New section: "What graphbrain installs vs. what it recommends." Document the two modes (recommend-only by default, --install-skills for auto). Link to PatternsDev/skills + ECC. |
| `.claude/prds/graphbrain.prd.md` | UPDATE | Append M#13 row to v0.2 Roadmap. |

## Sub-milestone split (recommended)

Three sub-milestones, each independently shippable:

- **M#13a — Recommendation map + print-only mode** (smallest, lowest risk)
  - Extend `stack-detection.json` with `recommended_skills: []` arrays
  - Init.js post-detection step that prints the recommendations
  - Operator manually runs the install commands
  - No third-party shell-out, no new tier
  - Ships value immediately: operator sees what to install

- **M#13b — Optional `--install-skills` auto-execution**
  - `bin/graphbrain.js` parses `--install-skills` flag
  - Init.js shells out to `npx skills add ...` for each patterns.dev recommendation
  - Captures per-install outcome; logs to `.brain/log.md`
  - Confirm-before-install prompt (unless `--yes` also passed)
  - Idempotent: skip if skill already installed

- **M#13c — Port graphbrain-old SDLC skills + community agents**
  - Six new SDLC skills (`skills/core/sdlc/{requirements,design,implementation,testing,deployment,maintenance}/SKILL.md`)
  - Four community agents (`agents/community/{code-reviewer,debugger,goap-planner,refactorer}.md`)
  - Update `skills/registry.json`
  - These become part of graphbrain's "always-loaded" baseline; recommended in every fresh install regardless of stack

Each sub-milestone is its own commit. M#13 is "complete" when all three ship.

## Tasks

### M#13a — recommendation map + print mode

1. **Audit stack-detection.json's 25 stacks.** For each, write a `recommended_skills: []` array. Sources:
   - `source: "patterns.dev"` for stacks where PatternsDev/skills has a matching framework (javascript-derived stacks: react/vue/nextjs/express/koa/hapi/etc.)
   - `source: "ecc"` for stacks where ECC has a matching skill (per the v0.1.1 bridge declarations + M#9-coverage bridges we already shipped)
   - `source: "graphbrain-sdlc"` (always — added to every stack once M#13c ships; pre-M#13c, entries list `core/requirements + core/design + core/implementation` from graphbrain-old)
   - Each entry: `{ source, package, install_command, description, install_size_estimate }`
   - Dedupe `javascript` package across React/Vue/Next/Express/Koa/Hapi/etc. — operator sees it once even if multiple JS stacks detected.

2. **Init.js Step 4c** (new):
   - After Step 4 produces `detectedStacks[]`, look up each stack's `recommended_skills`.
   - Dedupe by `(source, package)` key. Order: patterns.dev first, ECC second, graphbrain-sdlc third.
   - Format printable block:
     ```
     Recommended skills for this stack:

       <description> (<source>):
         $ <install_command>

       ...

     Or re-run with --install-skills to install all automatically.
     ```
   - Append block to Step 7 report output AFTER the standard "Logged: .brain/log.md" line.

3. **Tests (T49)**:
   - `stack-detection.json` has `recommended_skills` for at least the 8 highest-priority stacks: react, vue, nextjs, nodejs, typescript, python, go, docker.
   - For each, at least one recommendation per the rules above.
   - Init output (mock-detection in tmp repo) includes the recommendation block when stacks detect.

### M#13b — auto-install via `--install-skills`

4. **`bin/graphbrain.js` flag parsing**:
   - Recognize `--install-skills` (and `--yes` to skip the per-install confirmation).
   - Pass to `init()` as `opts.installSkills`.
   - Document in help text + the post-install output line "Or run npx graphbrain init --install-skills".

5. **Init.js install execution** (gated by `opts.installSkills`):
   - For each recommendation with a `source: "patterns.dev"` (which has executable commands):
     - Print: `Installing <description>...`
     - Bash exec: `npx -y skills add <package>` with `2>&1` capture
     - On success: log `OK <package> installed` to console + `.brain/log.md`
     - On failure: log `WARN <package> install failed — try manually: <command>` to console + log
     - Do NOT abort on individual install failure; continue.
   - For `source: "ecc"` entries: print instructions (operator must install ECC manually; graphbrain bridges automatically).
   - For `source: "graphbrain-sdlc"`: these are already in graphbrain's own ship — print "already included".

6. **Cost gate**: if more than 5 recommendations would auto-install AND `--yes` is NOT passed, print the list + prompt for confirmation. (Mirrors `/brain:ingest` folder Step 4's cost gate.)

7. **Tests (T50)**:
   - With `--install-skills` flag + a tmp repo containing react files, init runs (mocked) shell calls matching the recommendation commands.
   - Without the flag, no shell-out happens; recommendations are print-only.

### M#13c — port SDLC skills + community agents

8. **SDLC skill files** (`skills/core/sdlc/<name>/SKILL.md`):
   - Read each from graphbrain-old `skills-registry/core/<name>/SKILL.md`.
   - Refresh frontmatter to v1.x merged format (name, description, origin: graphbrain, version, tier: core, pattern, related_skills).
   - Update body for graphbrain v1.x conventions (slash-command references, wikilinks, etc.).
   - Place at `skills/core/sdlc/{requirements,design,implementation,testing,deployment,maintenance}/SKILL.md`.

9. **Community agents** (`agents/community/<name>.md`):
   - Read each from graphbrain-old `agents-registry/community/<name>/`.
   - Refresh frontmatter to merged format (name, description, tools, model, pattern, trigger_phrases, max_iterations).
   - Refresh body for graphbrain v1.x identity.
   - Place at `agents/community/{code-reviewer,debugger,goap-planner,refactorer}.md`.

10. **Update `skills/registry.json`**: add 6 SDLC entries + 4 community-agent entries.

11. **Tests (T51, T52)**:
    - Each new SDLC SKILL.md has required frontmatter fields, `tier: core` (or new `tier: sdlc`?), pattern, related_skills bidirectional.
    - Community agents have required frontmatter (tools, model, pattern, max_iterations).
    - `registry.json` has the 10 new entries.
    - `npm pack` includes all new files.
    - `skills/core/sdlc/deployment/SKILL.md` mentions Docker / Kubernetes / YAML deployment files (so it shows up in deployment-related queries).

12. **PRD + README update**: 
    - PRD: M#13 row in v0.2 Roadmap; cite the operator's tech-stack-recommendation ask + graphbrain-old's SDLC heritage.
    - README: "What graphbrain installs vs. what it recommends" section. Diagram or table showing the 4 layers (built-in graphbrain skills, recommended patterns.dev, recommended ECC bridge, optional community agents).

## Validation

```bash
# E2E
bash tests/e2e-test.sh
# Expect: ~955 passes (944 from v1.0.6 baseline + ~12 new T49/T50/T51/T52 assertions)

# Recommendation map
node -e "
  const j = require('skills/core/init/templates/stack-detection.json');
  const stacksWithRecs = j.stacks.filter(s => Array.isArray(s.recommended_skills) && s.recommended_skills.length > 0);
  console.log('stacks with recommendations:', stacksWithRecs.length, '/', j.stacks.length);
"

# Init prints recommendations
TMPDIR=$(mktemp -d); cd $TMPDIR && git init -q && echo '{"dependencies":{"react":"^18"}}' > package.json
node /path/to/graphbrain.js init | grep -q 'Recommended skills for this stack'

# --install-skills triggers (mocked) shell calls
# (use a mock npx wrapper to assert the right commands fire without actually installing)

# SDLC skills present + ship
ls skills/core/sdlc/{requirements,design,implementation,testing,deployment,maintenance}/SKILL.md
npm pack --dry-run | grep 'skills/core/sdlc/deployment/SKILL.md'

# Community agents
ls agents/community/{code-reviewer,debugger,goap-planner,refactorer}.md

# Manual smoke (post-commit):
#   In a React + TypeScript repo: npx graphbrain init
#   Output ends with:
#     Recommended skills for this stack:
#       React design + rendering patterns (patterns.dev):
#         $ npx skills add PatternsDev/skills/react
#       JS design patterns (patterns.dev):
#         $ npx skills add PatternsDev/skills/javascript
#       (ECC plugin recommended for ecc:react-patterns)
#       SDLC: requirements, design, implementation, testing, deployment, maintenance (already shipped with graphbrain)
#
#   Re-run with --install-skills: those `npx skills add` commands execute.
#   ~/.claude/skills/ or .claude/skills/ now has the patterns.dev skills.
#   On next Claude Code prompt mentioning React: those skills are available.
```

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| PatternsDev/skills package format changes / breaks | Med | We don't depend on their internal structure; we just shell out to `npx skills add`. If their CLI changes, our recommendation commands also change. Document the dependency in PRD. |
| `npx skills add` is slow / errors out / requires network | High | --install-skills failures are per-install (do not abort the rest); print clear "try manually" fallback. Default mode is print-only — operator has zero network dependency unless they opt in. |
| Auto-installed skills proliferate in `~/.claude/skills/` and cause Claude Code skill discovery to slow / get noisy | Med | PatternsDev/skills install to user-global path (`~/.claude/skills/`) by default. Doesn't change graphbrain's plugin tree (which stays at `.claude/plugins/graphbrain/`). Operator can manually remove later. |
| graphbrain-old's SDLC skills are too generic / preachy / don't add value | Med | Sample 1-2 SDLC skills before porting all 6. If they read as filler, refactor / drop. Operator dogfood = best signal. |
| Community agents (code-reviewer, debugger, etc.) overlap with ECC's agent surface | Med | ECC has 60 agents incl. code-review. graphbrain-old's community agents are general-purpose; ECC's are workflow-specific. Document the distinction. M#13c may decide to skip the port and just defer to ECC for these. |
| Recommending external packages creates a supply-chain / security expectation | High | Document explicitly: graphbrain RECOMMENDS, doesn't endorse or vet. Operator-responsibility framing. Refusal-pattern equivalent for "obvious malicious package names" is post-M#13. |
| Adding `recommended_skills` to all 25 stack-detection entries is tedious / error-prone | Low | Spreadsheet first; review for omissions/duplicates; then patch the JSON in one commit. T49 catches missing entries. |
| Operator runs `--install-skills` blindly + ends up with 20+ skills they don't want | Med | Cost gate (M#13b Task 6): if more than 5 installs would happen, require explicit confirmation unless `--yes` passed. Mirrors `/brain:ingest` folder Step 4. |
| `--install-skills` flag becomes a vector for malicious-author recommendation injection in v0.3 (someone PRs a stack-detection entry that recommends a malicious package) | Low | All `recommended_skills` packages live in graphbrain's own repo (stack-detection.json). PR review catches additions. Document the trust model. |

## Acceptance (provisional)

- [ ] All three sub-milestones complete (M#13a, M#13b, M#13c)
- [ ] E2E passes (~955 assertions)
- [ ] M#13 row in PRD → complete
- [ ] No regression on prior tests (existing /brain:ingest, /brain:query, /brain:lint, /brain:learn, /brain:status, /brain:spec, /brain:creds flows)
- [ ] (Operator-validated) Smoke: in a React + TypeScript repo, `npx graphbrain init` prints React + JS patterns.dev recommendations; `--install-skills` actually installs them; on next Claude Code prompt mentioning a React feature, the patterns.dev skills are loaded.
- [ ] (Operator-validated) Smoke: in a Python + Docker repo, `npx graphbrain init` prints SDLC + ECC python recommendations + (no patterns.dev since it's JS-only); the deployment SDLC skill is included regardless of stack.

## Open questions (to resolve before implementation)

1. **What tier do the SDLC skills land in?** graphbrain-old used `core/`. graphbrain v1.x's `core/` is per-verb (`core/init`, `core/spec`, etc.). Options:
   - Add a new `sdlc/` top-level tier: `skills/sdlc/{requirements,...}/SKILL.md`. Cleaner separation.
   - Subdir under `core/`: `skills/core/sdlc/{requirements,...}/SKILL.md`. Less namespace shuffle.
   - Decision needed.

2. **Should `--install-skills` install per-project (`.claude/skills/`) or user-global (`~/.claude/skills/`)?**
   - patterns.dev's default is user-global.
   - Project-local matches graphbrain's preference (per-repo isolation).
   - May need a `--scope=user|project` sub-flag.

3. **For ECC recommendations: do we print instructions only, or attempt to bridge to ECC's marketplace install?**
   - Today: graphbrain's M#9-prereq probes for ECC's skills at runtime. Init-time install isn't needed.
   - M#13 could print "Install ECC plugin: <command>" + describe the bridge contract.
   - No need to auto-execute ECC install — it's a plugin install, different flow.

4. **Recommendation freshness**: stack-detection.json's `recommended_skills` are baked at graphbrain release time. If patterns.dev adds new frameworks (svelte? solid? remix?), graphbrain has to ship a new release to recommend them.
   - Acceptable for v1.x. v2.x could pull a live manifest from a graphbrain-recommendations endpoint.
   - Document as v1.x limitation in the PRD.

5. **Community agents: port from graphbrain-old or skip in favor of ECC**?
   - graphbrain-old's community agents (code-reviewer, debugger, refactorer, goap-planner) are general-purpose; they may overlap with ECC's 60 agents.
   - Operator may want a small, focused set (graphbrain's 7 brain agents + a handful of community agents) vs. a sprawling 60+ catalog.
   - Decision needed before M#13c task 8 starts.

6. **Naming**: `--install-skills` is fine, but `--with-recommended` reads better. Pick before implementing flag parser.

---

**M#13 is a v1.x DRAFT — connects detection to expertise.** The operator's question reveals a real gap: graphbrain detects stacks but doesn't act on the detection at install time. M#13 closes the loop. Refinement before implementation:

- Sample one patterns.dev install end-to-end (`npx -y skills add PatternsDev/skills/react`) in a tmp repo to verify the CLI works as documented.
- Sample one of graphbrain-old's SDLC skills (`core/design/SKILL.md`) — read the content, check whether it adds value vs. ECC's equivalent skill, decide port-or-skip.
- Decide the tier placement question (open question 1).
- Pick the `--install-skills` vs `--with-recommended` naming (open question 6).
- Decide whether to commit to v1.x or defer to v2.0 (M#13 is large; operator may want it in two passes).

Each sub-milestone (M#13a, M#13b, M#13c) is independently shippable. If operator just wants the highest-leverage piece, that's M#13a (recommendations printed at init time — no auto-install, no new tier).
