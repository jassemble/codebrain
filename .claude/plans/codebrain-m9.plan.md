# Plan: codebrain — Milestone #9 (Framework-detection + ECC-bridge full architecture)

**Source PRD**: `.claude/prds/codebrain.prd.md` (v0.2 Roadmap section)
**Selected Milestone**: #9 — Gap B from operator dogfood
**Complexity**: Medium-to-Large — runtime mechanism for bridging to ECC; coverage extension to more frameworks; first cross-plugin skill-loading
**Status**: DRAFT — not yet implementation-ready; refinement expected after operator's v0.1.1 dogfood produces evidence

## Sub-split recommendation (added during v0.2 sweep, 2026-05-28)

M#9 has two distinct halves with different urgency:

- **M#9-prereq** — Tasks 1–3 below: harness-skill-probe mechanism + `Step 4b.3 — Active bridge probe + activation` in the slash-command body + Step 7 report extension. This is the **bridge runtime** — the load-bearing primitive that M#10's `/brain spec` invocation of `ecc:plan-prd`/`plan`/`santa-loop` depends on.
- **M#9-coverage** — Tasks 4–5 below: 8 new `detected/*` skills (vue/rails/flask/koa/hapi/gin/echo/fiber) + `expert_skills:` bridges for the four M#3d skills (react/typescript/python/go). Independent of M#10; can ship any time after M#9-prereq.

**v0.2 master ordering**: M#12 → **M#9-prereq** → M#10 → M#11 → **M#9-coverage**. M#9-prereq ships before M#10 because M#10's spec verb needs the runtime; M#9-coverage ships last because it's bulk-work with no downstream dependency.

M#9 is "complete" when both halves ship; "M#9-prereq complete" is a partial-ship intermediate state that the PRD v0.2 Roadmap should be able to represent.

## Summary

v0.1.1 shipped the **declarative** bridge: `detected/*/SKILL.md` files declare `expert_skills:` arrays; `commands/brain.md` Step 4b.2 documents the contract; `skills/registry.json` carries the bridge targets. But the bridge is documentation-only today — when an agent ingests a NestJS file, the slash-command body INSTRUCTS the agent to "load ecc:nestjs-patterns if available" but provides no runtime mechanism to actually probe + load.

M#9 makes the bridge **operative**:

1. **Runtime skill-probe**: at ingest/query/lint time, the agent (or a helper) checks which `expert_skills:` named by the active `detected/*` skills are actually present in the harness. Output: an "active bridge" report — `[ecc:nestjs-patterns: loaded, ecc:django-patterns: not available]`.
2. **Skill activation**: when an `expert_skill` is present, the agent loads it BEFORE doing the work and applies its patterns throughout. The mechanism varies by harness; for Claude Code with the ECC plugin installed, it's `Skill(skill_id)` tool-call.
3. **Coverage extension**: add detect rules + `detected/*/SKILL.md` for vue, rails, flask, koa, hapi, gin, echo, fiber. Add `expert_skills:` bridges to the four M#3d skills (`react`, `typescript`, `python`, `go`) — these don't declare any bridges in v0.1.1, leaving the ECC pattern skills unused for those stacks.

After M#9: when an operator runs `/brain ingest` on a NestJS codebase with ECC installed, the agent automatically loads `ecc:nestjs-patterns` + applies its guidance during ingest. The page-format extras (v0.1.1) AND the code-writing expertise (M#9) both flow from a single declarative source.

## Patterns to Mirror

| Category | Source | Pattern |
|---|---|---|
| Bridge contract (declarative) | v0.1.1 — `commands/brain.md` Step 4b.2 + `skills/registry.json` `expert_skills:` field | M#9 keeps the contract; adds runtime activation |
| `detected/*` skill shape | M#3d's react/typescript/python/go + v0.1.1's nestjs/nextjs/express/django/fastapi/springboot | Same merged frontmatter; new bridges follow the same shape |
| Slash-command body extension | M#5/M#6/M#7's pattern (numbered steps, structured report, log entry) | Add `Step 4b.3 — Active bridge probe + activation` after Step 4b.2 |
| Skill-probe via Bash | M#5 query's "check ECC skill availability" sketch | Concrete v0.2 implementation: harness-specific command (Bash) → parse → check membership |
| Tests | T36 (v0.1.1) + T17/T25 | T37: bridge activation evidence at ingest time; per-stack assertions; "what loaded" report shape |

## Files to Change

| File | Action | Why |
|---|---|---|
| `commands/brain.md` | UPDATE | Add `Step 4b.3 — Active bridge probe + activation` after Step 4b.2. Procedure: for each `expert_skill` declared by an applying `detected/*`, probe availability via harness-specific command; if available, load the skill BEFORE writing the page; track which loaded for the report. |
| `commands/codebrain.md` | UPDATE | Alias parity for Step 4b.3 |
| `skills/registry.json` | UPDATE | Add `expert_skills:` bridges for the M#3d skills: `detected/react` → `[ecc:react-patterns]` (if/when it exists), `detected/typescript`, `detected/python`, `detected/go`. Add new entries for vue, rails, flask, koa, hapi, gin, echo, fiber. |
| `skills/core/init/templates/stack-detection.json` | UPDATE | Add detect rules for the new frameworks not yet cataloged (koa, hapi, gin, echo, fiber, flask) |
| `skills/detected/{vue,rails,flask,koa,hapi,gin,echo,fiber}/SKILL.md` (NEW × 8) | CREATE | Same schema as v0.1.1's 6 detected skills — frontmatter + bridge declaration + 5 stack-specific extra sections |
| `skills/core/init/templates/claude-md-schema.md` | UPDATE | Add a brief mention of the "Active bridges" report so operators understand which expert skills loaded for their codebase |
| `tests/e2e-test.sh` | UPDATE | T37: assert `Step 4b.3` exists; assert per-stack bridges declared; assert all 8 new detected skills exist + have `expert_skills:`; alias parity; npm pack |
| `.claude/prds/codebrain.prd.md` | UPDATE | Flip M#9 row `pending` → `in-progress` then `complete` when shipped |

## Tasks (provisional — sharpen during a sweep before implementation)

1. **Decide the harness-skill-probe mechanism**. Open question: how does the slash-command body's procedure CONCRETELY check whether `ecc:nestjs-patterns` is available? Options:
   - **(a)** `Bash: claude --list-skills | grep ecc:nestjs-patterns` — assumes a `--list-skills` flag exists (verify; if not, use a different probe)
   - **(b)** `Bash: test -d ~/.claude/skills/ecc/nestjs-patterns` — filesystem probe; harness-specific path
   - **(c)** Hardcode "assume available if ECC plugin is installed" — operator declares via env var or settings flag
   - **(d)** Trial-and-error: try to load the skill via the Skill tool; catch the error
   Resolution required BEFORE implementation.

2. **Add `Step 4b.3 — Active bridge probe + activation`** to `commands/brain.md` (mirror to `codebrain.md`):
   - Input: list of matching `detected/*` skills from Step 4b.1 (already known)
   - For each, read `expert_skills:` from `skills/registry.json` (the agent already has the registry loaded)
   - For each named expert skill, probe availability via the mechanism resolved in Task 1
   - For each available expert skill, INVOKE it via the Skill tool (or equivalent) — load its guidance into context
   - For each unavailable expert skill, note in the report
   - Track `loaded[]` and `unavailable[]` arrays for the Step 7 report

3. **Extend Step 7 report shape** to include the `Active bridges` block:
   ```
   /brain ingest complete
     ...
     Active bridges:
       loaded:      ecc:nestjs-patterns, ecc:typescript-patterns
       unavailable: ecc:react-patterns (declared by detected/react but not present in harness)
   ```

4. **Add `expert_skills:` to the four M#3d skills**:
   - `detected/react` → `[ecc:react-patterns]` (verify it exists; if not, leave empty)
   - `detected/typescript` → `[ecc:typescript-patterns]` or similar
   - `detected/python` → `[ecc:python-patterns]`
   - `detected/go` → `[ecc:golang-patterns]`
   Update both `skills/registry.json` AND each `SKILL.md` file's frontmatter + body bridge section.

5. **Add 8 new detected/* skills** (vue, rails, flask, koa, hapi, gin, echo, fiber):
   - Same template as v0.1.1's 6 framework skills
   - Each declares its `expert_skills:` bridge target (`ecc:<name>-patterns`)
   - Verify each ECC skill actually exists; if not, leave the bridge target documented as "no bridge available yet"

6. **Update `stack-detection.json`** with detect rules for the new frameworks where missing:
   - koa, hapi (`package.json contains`)
   - flask (`pyproject.toml contains "flask"` or `requirements.txt contains "Flask"`)
   - gin, echo, fiber (`go.mod contains`)

7. **Update `claude-md-schema.md`** to document the "Active bridges" report so operators understand the runtime activation evidence.

8. **Tests (T37)** — assertions for: Step 4b.3 present; bridge probe documented; all 8 new detected/* skills exist with frontmatter + expert_skills; per-stack expert_skills targets are correct; M#3d skills now declare expert_skills; alias parity; npm pack includes new files.

9. **PRD update + push** — M#9 row complete.

## Validation

```bash
# E2E
bash tests/e2e-test.sh
# Expect: ~690 passes (625 + ~65 new T37), 0 failures

# Bridge probe documented
grep -qF 'Step 4b.3 — Active bridge probe' commands/brain.md

# All detected/* skills present (10 from v0.1.1 + 8 new = 18 total)
find skills/detected -maxdepth 1 -mindepth 1 -type d | wc -l

# Manual smoke (post-commit):
#   In a NestJS repo with ECC installed:
#     /brain ingest src/users.service.ts
#     → Report shows: "Active bridges: loaded: ecc:nestjs-patterns"
#   In a NestJS repo WITHOUT ECC:
#     /brain ingest src/users.service.ts
#     → Report shows: "Active bridges: loaded: (none); unavailable: ecc:nestjs-patterns"
```

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| The probe mechanism (Task 1) doesn't have a clean primitive in Claude Code | Med | Spike before implementation; if no clean probe exists, fall back to "let the operator declare what's installed via a `.brain/.bridges` config file" |
| ECC's expert skills don't actually map 1:1 to codebrain's detected stacks (e.g., no `ecc:vue-patterns`) | Med | For each declared bridge, verify the ECC skill exists; if not, document as "no bridge available" in the registry |
| Loading multiple ECC skills inflates context per ingest | Med | Skill-loader caches; second invocation cheap; report which loaded so operator can disable noisy ones via `--no-bridge ecc:foo` (post-MVP flag) |
| Operator without ECC sees "unavailable" lines and worries something is broken | Low | Report explicitly says "declared by detected/X but not present in harness — install ECC plugin to enable" with a link |
| Two detected/* skills declare conflicting `expert_skills` (e.g., both nestjs and express applied to one file, both want different backend skills) | Low | Load all; ECC skills are additive (multiple loaded skills compose); contradictions surface at code-write time |
| brain.md size growth | Med | Step 4b.3 adds ~30 lines; well within budget. brain.md at v0.1.1 is ~1200 lines; M#9 brings to ~1230. Manageable. |

## Acceptance (provisional)

- [ ] All tasks complete
- [ ] Validation passes
- [ ] M#9 row in PRD → complete
- [ ] No regression on the 625 v0.1.1 tests
- [ ] (Operator) Manual smoke: NestJS repo with ECC plugin installed sees `Active bridges: loaded: ecc:nestjs-patterns` in `/brain ingest` output

---

**This plan is a v0.2 draft.** Refinement after operator's first v0.1.1 dogfood:
- The probe mechanism (Task 1) is the most important open question — defer implementation until resolved
- ECC skill coverage check (Task 4+5) — confirm which `ecc:<stack>-patterns` skills actually exist before committing to bridge targets
- Coverage priorities — pick the 3 most-needed frameworks for v0.2 instead of all 8 if scope balloons
