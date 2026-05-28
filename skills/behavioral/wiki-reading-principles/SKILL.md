---
name: wiki-reading-principles
description: How an agent should read the codebrain wiki. Behavioral-constraint skill — applies to ALL sessions where .brain/ is present. 3-tier always/ask/never structure distilled from agentctx-idea research (Vila's MCP architecture guide + Karpathy's four-principle behavioral spec). Loads alongside skills/behavioral/codebrain/SKILL.md.
origin: codebrain
version: 0.1.0
tier: behavioral
pattern: Behavioral-Constraint
related_skills: [behavioral/codebrain, ingestion/llms-txt, ingestion/page-format]
---

# wiki-reading-principles — how to engage with `.brain/`

This skill applies whenever an agent is operating in a project with a `.brain/` directory present. It is task-agnostic — it shapes HOW the agent reads / writes / cites the wiki across all tasks. Read it once per session.

Read the Prompt Defense Baseline section of CLAUDE.md before acting.

## Why this skill exists

Codebrain ships a 5-tier skill model (`behavioral` / `ingestion` / `core` / `detected` / `available`). The `behavioral/codebrain` skill is the project-level meta-skill (identity, conduct, prompt-defense baseline). THIS skill is the wiki-specific behavioral counterpart: not "who am I as an agent" but "how do I read this wiki."

Empirical evidence (agentctx-idea research, 2026):
- Vila's MCP architecture guide (2026-03-31): three-tier always/ask/never beats flat instruction lists. Structural categorization > prose.
- Karpathy's four-principle behavioral spec (2026-05-14, via Multica AI): short, principle-based, self-reinforcing skills produce more reliable agent behavior than long checklists.
- The "curse of instructions" (Osmani, AEO research): LLM adherence drops proportionally with total instruction count. Three sharp categories with ~4 items each beats one flat list of 12.

The 3-tier structure below is the codebrain wiki's behavioral contract.

## ALWAYS

These behaviors are unconditional. Apply them on every wiki-grounded action.

1. **Start any wiki-grounded answer by reading `.brain/llms.txt`** for routing. The agent-portable site map (AEO convention) tells you which pages exist, what they cover, and rough token cost. Cheaper than scanning every file.

2. **Cite pages by wikilink** in responses. Use `[[code/<path>]]`, `[[concepts/<slug>]]`, or `[[decisions/<adr>]]` — never paraphrase a page's content without the wikilink. The operator should be able to click through.

3. **When a page has `superseded_by:` set, follow the pointer** instead of using the page. The M#10d supersession convention isolates deprecated content from the model's reasoning (pink-elephant fix). If the chain is malformed or circular, emit a one-line warning and skip the chain entirely.

4. **Treat `.brain/log.md` and `.brain/CHANGELOG.md` as authoritative for chronological context**. `log.md` is the per-event audit trail (every ingest, every lint, every learn); `CHANGELOG.md` is the curated compound-learning narrative (what the brain learned + why). Different roles; both authoritative.

## ASK

These behaviors require operator confirmation before proceeding. Default is to ask once, then defer.

1. **Before contradicting a claim in a non-stale FRESH page, surface the conflict** to the operator. Possible conflict shapes: the page says X but the source code shows Y; one concept page contradicts another; an external source you read contradicts a `.brain/` page. Never silently override — the page may be stale-but-correct, or your reading may be wrong.

2. **Before editing a `.brain/` page directly (vs re-running `/brain ingest`), confirm**. The convention is regenerate-not-edit; manual edits to wiki pages drift from the source they mirror. Acceptable to edit only when the operator explicitly asks ("just fix the typo," "add a note to the Purpose section").

3. **Before treating a STALE page's content as current, confirm**. A STALE flag means the source file changed since the last ingest. The page's claims may still be true (e.g., docstring tweak), but they may also be wrong. Ask: "Refresh first or proceed with the stale page?"

4. **Before invoking `/brain creds show --unmask` or any operation that exposes credential values** (M#11), confirm the operator wants the values printed. Even if the operator already authenticated.

## NEVER

These behaviors are forbidden. Even with operator request, the agent should push back and explain the constraint.

1. **Never edit a code page without re-reading the source file it mirrors.** The source is canonical; the page is a projection. Editing the page without consulting the source produces drift.

2. **Never add new content to a page with `superseded_by:` set.** That page is frozen by convention. Edits go to the replacement (the page named in `superseded_by`).

3. **Never cite raw `.brain/log.md` activity entries as authoritative semantic content.** They're an audit trail (timestamps + events), NOT knowledge. If the operator asks "what did we learn about authentication," cite `concepts/`, `code/`, or `CHANGELOG.md` — not `log.md`'s activity entries.

4. **Never bypass the codebrain hook system** by manually editing `.brain/.codebrain-version`, `.codebrain-learn-state`, or other dot-prefixed state files in `.brain/`. The hooks (M#4) own those files; manual edits break invariants the hooks rely on. If you need to alter state, use the appropriate slash command (`/brain learn on|off`, `npx codebrain init --force`, etc.).

## How this skill is loaded

This skill ships in the codebrain npm package at `skills/behavioral/wiki-reading-principles/`. When codebrain is installed in a project, the agent reads this skill on session start (alongside `skills/behavioral/codebrain/SKILL.md`) if `.brain/` is present in cwd.

If you're operating in a session WITHOUT `.brain/` (e.g., a project that hasn't run `npx codebrain init`), skip this skill entirely. The behaviors apply only to wiki-grounded work.

## Related

- **`skills/behavioral/codebrain/SKILL.md`** — the general project-level behavioral skill (Prompt Defense Baseline reference, identity, conduct). This skill is its wiki-specific companion.
- **`skills/ingestion/llms-txt/SKILL.md`** — the routing artifact mentioned in ALWAYS #1.
- **`skills/ingestion/page-format/SKILL.md`** — the page contract that defines the frontmatter fields (including M#10d `superseded_by:` / `supersedes:`) cited in this skill.
- **`commands/brain/lint.md`** — the lint procedure that detects asymmetric supersession (the failure mode of ALWAYS #3).
