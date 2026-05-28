# Claude Code conventions — graphbrain's canonical contract

This file documents the shape of every file `scripts/init.js` writes into the user's `.claude/` directory. If Claude Code's conventions change, **update this file first, then update `scripts/init.js` to match**.

Source content distilled from `/Users/dev/Desktop/Project/OSS/idea/ECC/.claude-plugin/PLUGIN_SCHEMA_NOTES.md` (the parts about command and hook shape — **not** the plugin-manifest rules, which don't apply to graphbrain per PRD Design Decision #28) plus ECC's `hooks/hooks.json` and `commands/*.md` patterns.

## Slash-command file format

**Two layouts coexist** (per M#12 — slash-command namespacing):

1. **Top-level commands** at `.claude/commands/<name>.md` → `/<name>`. Example: `commands/brain.md` → `/brain`.
2. **Namespaced commands** at `.claude/commands/<namespace>/<verb>.md` → `/<namespace>:<verb>`. Example: `commands/brain/ingest.md` → `/brain:ingest`. Subdirectories create namespaces; the colon is the separator.

Graphbrain uses **both**:
- Top-level `brain.md` is a thin dispatcher / help disambiguator. It supports the muscle-memory `/brain <verb>` form via a Read-and-execute shim that loads the per-verb file.
- Per-verb files under `commands/brain/<verb>.md` are the canonical procedure location and support the more discoverable `/brain:<verb>` form.

Both invocations produce identical behavior because the dispatcher Read-and-executes the per-verb file. (v0.2.0 dropped the older `/graphbrain` alias — only `/brain` remains.)

**Conventions**:

- Lowercase-with-hyphens file naming (`brain.md`, `code-review.md` — not `Brain.md`, `code_review.md`)
- First line **may** be a version-marker comment (`<!-- graphbrain v0.2.0 -->`). Markdown parsers ignore it; Claude Code does too.
- YAML frontmatter with `description:` required (single line); other fields optional
- Body is free-form markdown. Use `$ARGUMENTS` for argument substitution.
- For namespaced commands, the procedure body lives in the per-verb file; the top-level dispatcher in the same namespace (`brain.md`) should NOT duplicate the procedure — it should reference the per-verb file via "Read `commands/brain/<verb>.md` and execute its procedure."

**Example** (matches graphbrain's `commands/brain.md` template):

```markdown
<!-- graphbrain v0.1.0 -->
---
description: graphbrain — agent-maintained codebase wiki (init, ingest, query, lint, learn, status)
---

# /brain

`$ARGUMENTS` is parsed as `<verb> [args...]`. Route as follows:

| Verb | ... |
```

## Hook entry shape

**Path**: `.claude/settings.local.json` (project-local) or `~/.claude/settings.json` (global).

**Top-level shape**:

```json
{
  "hooks": {
    "PreToolUse": [ ... ],
    "PostToolUse": [ ... ],
    "SessionStart": [ ... ],
    "SessionEnd": [ ... ],
    "Stop": [ ... ],
    "PreCompact": [ ... ],
    "UserPromptSubmit": [ ... ]
  }
}
```

**Per-phase array entry shape**:

```json
{
  "matcher": "Bash|Edit|Write|MultiEdit",
  "hooks": [
    {
      "type": "command",
      "command": "<shell command to execute>",
      "async": true,
      "timeout": 10
    }
  ],
  "description": "<short description>",
  "id": "graphbrain:pre:edit-write:stale-detect"
}
```

**Required fields per entry**:

- `matcher` — tool name pattern (regex-like, pipe-separated alternation)
- `hooks` — array of hook actions (almost always one `type: command` entry)
- `id` — **graphbrain's ownership marker** (see "Hooks ownership" below)
- `description` — operator-facing label

**Optional fields**:

- `async: true` — fire-and-forget; don't block tool execution
- `timeout: <seconds>` — bound execution time (default 30s)

## Hooks ownership (graphbrain's contract — Design Decision #32)

graphbrain owns **only** hook entries whose `id` field starts with `graphbrain:`. Examples:

- `graphbrain:pre:edit-write:stale-detect`
- `graphbrain:pre:bash:guardrail-block-verified`
- `graphbrain:post:observe:learn`

**Init's merge behavior** (`scripts/init.js`):

1. Read the user's existing `settings.local.json`. Partition each phase array into `[graphbrain-owned]` (id starts with `graphbrain:`) and `[other]` (everything else)
2. Discard `[graphbrain-owned]`
3. Append graphbrain's current hooks **after** `[other]`, preserving non-graphbrain ordering

Result: re-running `init` after a graphbrain upgrade always reflects the new version's hooks; non-graphbrain hooks (user's own, ECC's, other tools') are untouched. This is also the foundation for `graphbrain uninstall` (post-MVP).

## Skill file format

**Path**: `~/.claude/skills/<tier>/<name>/SKILL.md` (graphbrain uses tiered subdirectories — see `../skills/README.md`).

**Frontmatter**: see `../skills/README.md` for graphbrain's merged ECC + graphbrain shape.

**Body sections** (per ECC convention): When to Activate, How It Works, Examples, plus skill-specific sections.

## Agent file format

**Path**: `~/.claude/agents/<category>/<name>.md` (graphbrain uses category subdirectories — see `../agents/README.md`).

**Frontmatter**: see `../agents/README.md` for graphbrain's merged ECC + graphbrain shape.

**Body**: persona/role paragraph + `## Rules` section (self-enforcing) + optional sections.

## Settings file precedence

| File | Scope | Precedence |
|---|---|---|
| `<repo>/.claude/settings.local.json` | This repo only | **Highest** |
| `<repo>/.claude/settings.json` | This repo (intended for commit) | Middle |
| `~/.claude/settings.json` | User global | **Lowest** |

graphbrain writes to **`settings.local.json`** (not committed; per-project; project-local by default per Design Decision #31). Operator can manually move graphbrain entries to `settings.json` if they want them tracked in git.

## Forbidden patterns

These look correct but are rejected by Claude Code:

- String values where arrays are expected in plugin manifests (irrelevant for graphbrain — we're not a plugin per Design Decision #28, but the same constraint applies to any future ECC-compatible artifact we might produce)
- Adding an `agents` field to a plugin manifest (auto-discovered by convention)
- Adding a `hooks` field to a plugin manifest when `hooks/hooks.json` exists (duplicate-load error)
- Writing hook entries WITHOUT an `id` field — without one, graphbrain can't tell them apart from user hooks on a future re-init

## Why this file exists

graphbrain ships zero plugin scaffolding (no `.claude-plugin/`, no `plugin.json`, no `marketplace.json`) — but the *knowledge* about how Claude Code parses commands, hooks, skills, and agents is exactly what `scripts/init.js` depends on. This file is the bridge: a single canonical place to update when Claude Code conventions evolve, so init.js's merge logic stays correct.
