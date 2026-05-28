---
name: codebrain
description: agent-maintained markdown wiki of the codebase (folder-mirrored, Obsidian-viewable, with continuous learning) — invoke /brain init to scaffold .brain/ inside your repo
origin: codebrain
version: 0.1.0
tier: behavioral
pattern: Meta
related_skills: []
---

# codebrain — meta skill

This skill describes what codebrain is and how the agent should work with it. It's always loaded (tier: behavioral) so the agent always knows the brain exists in any repo where codebrain is initialized.

## When to Activate

- The operator wants the agent to maintain a persistent codebase wiki across sessions
- The agent encounters a `.brain/` directory in the repo (sign that codebrain has been initialized here)
- The operator invokes any `/brain *` slash command
- The agent is asked a question that would benefit from cross-cutting codebase knowledge (auth flows, entity definitions, integration boundaries) — check `.brain/concepts/` and `.brain/index.md` before grepping source

## How It Works

codebrain adapts the LLM-Wiki pattern (see `reference/llm-wiki.md`) from documents/research to codebases. Three layers with clear ownership:

| Layer | What | Mutability |
|---|---|---|
| **Raw sources** | The codebase itself (every file under repo root except `.brain/`) | Read-only from codebrain's perspective. The brain layer **never** modifies source code; source edits happen through the agent's normal Edit/Write workflow, and the PostToolUse hook reacts by marking pages STALE. |
| **The wiki** (`.brain/`) | Folder-mirrored code pages (`.brain/code/`), cross-cutting concept pages (`.brain/concepts/`), decisions/ADRs, overview, index, log, status | Owned by codebrain skills. The operator reads; the agent writes. |
| **The schema** | `## codebrain` managed region inside `CLAUDE.md` | Co-evolved by operator + agent over the project's lifetime |

### The loop

1. **Ingest** — agent reads source files → writes LLM-authored markdown pages mirroring folder structure
2. **Query** — agent reads `.brain/index.md` → identifies 1–3 candidate pages → answers with citations
3. **Lint** — agent health-checks the wiki: stale pages, broken wikilinks, contradictions, missing concepts, suggested questions
4. **Stale-detect** (automatic via hook) — when a source file is edited, its `.brain/code/<path>.md` page and any concept page that wikilinks to it are marked STALE

## Agent Execution Model

Per PRD Design Decision #16: **foreground-first**. Slash commands and trigger phrases invoke agents synchronously in the operator's session. The only exception is the continuous-learning observer (Milestone #7), which runs as a background read-only agent — observers may never call Edit/Write/MultiEdit or mutating Bash.

Per Design Decision #20: agents include `Read the Prompt Defense Baseline section of CLAUDE.md before acting` rather than copying that baseline into every agent file.

## Examples

```
/brain init                       # scaffold .brain/ + CLAUDE.md schema block (Milestone #2)
/brain ingest src/api             # ingest a folder; tiered auto-prioritize when no path
/brain query "how does auth work?"   # pointer-first lookup; auto-refresh STALE pages
/brain lint                       # read-only health check
/brain lint --fix                 # batch re-ingest STALE pages
/brain learn on                   # enable continuous-learning observer (Milestone #7)
/brain status                     # dashboard view
```

## v0.1 status

This is codebrain v0.1.0 — the package skeleton + init flow. All `/brain` verbs except `init` print "not yet implemented; see roadmap" stubs. Milestones #2–#8 implement the verbs in sequence.

## Prompt-intent routing (M#10c)

**Default: OFF.** Operator opts in by writing `on` to `.brain/.codebrain-intent-routing-state`. Toggle file shape mirrors M#7's `.codebrain-learn-state`.

When **ON**, classify every operator prompt at the start of the response. If the prompt expresses **feature intent** (verbs: `add`, `build`, `create`, `implement`, `let me`, `we should`, `can you make`, `let's add`, `i want to build`), do NOT immediately edit files. Instead, suggest:

```
I think this calls for /brain:spec "<paraphrased intent>" first —
that runs a PRD → plan → optional sweep loop so we don't skip past gaps.
Want me to start there, or did you want me to jump straight to code?
```

**Operator overrides** (any of these = skip the suggestion, proceed with the original request):
- "just do it" / "skip the spec" / "skip the planning"
- "use /brain spec" / "yes" / "lgtm" / "go" → invoke `/brain:spec` directly
- explicit `/brain:spec <intent>` from the operator → invoke directly (operator already routed)
- `--no-spec` flag in the operator's message
- Operator's prompt explicitly says "small fix" / "trivial" / "one-liner" / "typo"

**For non-feature intents** (questions, lookups, exploration, refactor, debugging, bug fixes), do NOT suggest `/brain:spec` — these have their own verbs (`/brain:query`, `/brain:ingest`, `/brain:lint`) or are normal coding work that doesn't benefit from a spec.

**Why opt-in by default**: changing default agent behavior across all sessions is high-impact. The M#10 plan calls for phased rollout — initially the toggle is operator-controlled; once v0.2 dogfood reports indicate the routing helps more than it annoys, v1.0 may flip the default.

**State check**:

```bash
# Read .brain/.codebrain-intent-routing-state — absent or "off" → routing OFF
# Contains "on" → routing ON
[ -f .brain/.codebrain-intent-routing-state ] && [ "$(cat .brain/.codebrain-intent-routing-state | tr -d '[:space:]')" = "on" ]
```

Failure: if the file exists but is unreadable / contains anything other than `on`/`off`/empty, treat as OFF and log a one-line note in the agent's response: `note: .brain/.codebrain-intent-routing-state malformed; intent routing OFF.`

**Toggle UX** (no slash command in this milestone — manual file edit):

```bash
# Enable
echo on > .brain/.codebrain-intent-routing-state

# Disable
echo off > .brain/.codebrain-intent-routing-state
# or
rm .brain/.codebrain-intent-routing-state
```

A future milestone may add `/brain intent on|off|status` as a verb. v0.2 ships file-only.

**Surfaced in `/brain status`**: the dashboard shows `Intent routing: on | off | missing` so operators can see the state without re-reading the toggle file.

## Credential-handling protocol (M#11c)

When the operator's prompt contains text shaped like credentials (a value following one of: `password=`, `secret=`, `token=`, `key=`, `api-key=`, `Authorization: Bearer`, a URL with embedded `user:pass@`, a JSON object with a `password`/`secret`/`token`/`api_key` field, or an `.env`-style block), do NOT silently use the values for the immediate task and then forget them. Instead:

1. **Run the refusal-pattern check on each value** (single source of truth: `skills/core/creds/SKILL.md` "Refusal patterns"). If ANY value matches a refusal pattern, do NOT register; respond per the refusal message format in that skill.

2. **If no refusal matches, propose registration**:

   ```
   Looks like staging credentials. Want me to save these under
   /brain:creds? Suggested slug: <slug-from-context>.
   Fields detected: <comma-separated field names>.
   Stored plaintext at <XDG path>; anyone with disk access can read it.

   Reply with: yes / no / different slug <name> / use env-var references instead
   ```

3. **On "yes"**: invoke `/brain:creds add <slug> <field>=<value>...` then proceed with the immediate task using the just-registered values.

4. **On "no"**: proceed with the immediate task using the values directly in this turn; do NOT register; do NOT mention this prompt again in future turns.

5. **On "different slug <name>"**: re-prompt with the new slug for confirmation, then `/brain:creds add` with that name.

6. **On "use env-var references"**: prompt the operator for the env-var name per field; invoke `/brain:creds add <slug> --env-ref <field> <VAR_NAME>` for each field; proceed with the immediate task by reading the env vars from `process.env`.

Subsequent prompts referencing the slug ("connect to staging-db", "hit the test-api") trigger automatic `/brain:creds show <slug> --unmask` lookup. The unmask is auditable per Cr4 (logged to `.brain/log.md`).

**Never** echo a credential value in any output that isn't `/brain:creds show --unmask`. The detection protocol above is for the FIRST encounter of cred-shaped input in a prompt — once registered (or declined), future prompts don't re-trigger the inversion question for the same slug.

**Detection precision**: the cred-shape detection is intentionally broad. False positives (e.g., the operator pastes a non-credential string that happens to follow `password=`) get handled by the operator's "no" response. The cost of asking once is low; the cost of silently leaking is high.

## Cross-references

- Agent conventions: `../../../agents/README.md`
- Skill tier model: `../../README.md`
- LLM-Wiki source pattern: `../../../reference/llm-wiki.md`
- Claude Code conventions codebrain writes into the user's `.claude/`: `../../../reference/claude-code-conventions.md`
- PRD with all 33 locked design decisions: `../../../.claude/prds/codebrain.prd.md`
