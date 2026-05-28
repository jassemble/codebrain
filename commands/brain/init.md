---
description: Scaffold .brain/overview.md + the CLAUDE.md schema block. Detects your tech stack. Run once per repo.
---

## When `$ARGUMENTS` is `init`

You are the graphbrain init agent. Run this procedure exactly. If any step's preconditions fail, emit a clear error and stop — do not improvise.

**Step 1 — Preconditions**:

- Verify `.brain/` exists in cwd. If not, print this and stop:
  ```
  error: .brain/ not found in this repo.

  Run `npx graphbrain init` first — that scaffolds the .brain/ skeleton.
  Then restart Claude Code (or open a new session) and re-run /brain init.
  ```
- Read `.brain/.graphbrain-version` to confirm M#1's scaffold is present. If missing, print a similar error.
- Read `CLAUDE.md` from cwd. Locate `<!-- graphbrain:begin -->` and `<!-- graphbrain:end -->`. If either marker is missing, print and stop:
  ```
  error: CLAUDE.md is missing the graphbrain managed-region markers.
  Re-run `npx graphbrain init --force` to rewrite the markers, then retry /brain init.
  ```

**Step 1b — `.bak` reconciliation** (v1.0.9):

After preconditions, BEFORE any scaffolding or schema changes, check whether the previous `npx graphbrain init --force` run left `.bak` files. These are atomic-write safety backups created when graphbrain overwrote an existing file during an upgrade. Without this step they accumulate as silent litter; with this step the agent uses LLM judgment to merge operator edits intelligently and clear the backups.

**1b-A — Detect + pre-classify (v1.0.13 — delegates to a Node helper)**:

Run the `.bak` classifier helper. It finds every `*.bak` under cwd, resolves identical / whitespace-only diffs straight away (no LLM judgment needed), and for the rest emits structured diff data (`added_in_current`, `removed_from_current`, with `version_only` flags) the LLM uses to assign the final class.

```bash
HELPER_DIR=$([ -d .claude/plugins/graphbrain/scripts/lib ] \
  && echo .claude/plugins/graphbrain/scripts/lib \
  || echo "$HOME/.claude/plugins/graphbrain/scripts/lib")
node "$HELPER_DIR/classify-baks.js" .
```

Output shape:

```json
{
  "count": 4,
  "files": [
    { "path": "...", "classification": "identical", "version_only": true, "summary": "byte-identical" },
    { "path": "...", "classification": "whitespace-only", "version_only": true, "summary": "EOL diff only" },
    { "path": "...", "classification": "needs-llm-review", "version_only": true,
      "summary": "version-stamp / date / hash differences only — no semantic content at risk",
      "diff": { "added_in_current": { "count": 1, "version_only": true, "preview": ["v1.0.12"] },
                "removed_from_current": { "count": 1, "version_only": true, "preview": ["v1.0.11"] } } },
    { "path": "...", "classification": "needs-llm-review", "version_only": false,
      "diff": { ... operator-content lines ... } }
  ]
}
```

If `count == 0`: **skip Step 1b silently** and proceed to Step 2.

**1b-B — Assign final classes**:

For each file in `files[]`:

- `classification: "identical"` → final class `identical` (safe, auto-delete in 1b-E).
- `classification: "whitespace-only"` → final class `whitespace-only` (safe, auto-delete).
- `classification: "orphaned"` → ask operator: restore from .bak or delete .bak.
- `classification: "needs-llm-review"` → apply LLM judgment to the structured diff:

  | Final class | Diff signal | Default action |
  |---|---|---|
  | `operator-additions` (version-only) | both `added_in_current.version_only` and `removed_from_current.version_only` are true (i.e., the only diff is graphbrain bumping its own stamps) | Silently delete `.bak` — no operator content at risk |
  | `operator-additions` (real content) | `removed_from_current` has semantic prose / non-version lines | **Propose MERGE**: graphbrain's shipped content + splice in operator additions. Preserve operator's work. |
  | `operator-edit-to-graphbrain-content` | `added_in_current` shows graphbrain rewrote prose the operator had modified | **Discard the .bak** (graphbrain's shipped version is canonical). **Warn the operator**. |
  | `mixed` | Both `added_in_current` and `removed_from_current` carry semantic content | Apply additions, discard graphbrain-content edits. Itemize what was kept vs lost. |
  | `unclear` | Diff is too complex (cross-section refactoring, lines moved) for confident classification | **Do NOT auto-merge**. Show the diff to the operator + ask. |

**1b-C — Propose**:

Print a structured plan the operator can review before applying:

```
Found <N> .bak files from a previous --force upgrade. Proposed reconciliation:

  .brain/overview.md.bak
    Class: operator-additions
    • Operator added "## Team conventions" section (12 lines) → PRESERVE
    • Graphbrain rewrote "Active State" → use new structure (operator did not edit this part)
    Action: MERGE new shipped content + operator's "Team conventions" section
    
  .brain/log.md.bak
    Class: identical
    Action: DELETE (no operator edits)
    
  .claude/plugins/graphbrain/skills/core/init/SKILL.md.bak
    Class: operator-edit-to-graphbrain-content
    • Operator modified Step 4 wording → DISCARD (graphbrain owns this)
    Warning: you'll lose your edits to Step 4. If you want a custom init flow,
             override via .claude/skills/<your-name>/SKILL.md instead of editing
             the plugin tree.
    Action: DELETE .bak (keep current shipped content)
    
  CLAUDE.md.bak
    Class: unclear
    The diff includes both managed-region changes and outside-marker edits.
    Recommend: review manually. Diff below.
    Action: KEEP .bak — operator decides
    [show diff]

Apply? (yes/no/show-diffs/per-file)
```

**1b-D — Confirmation gate** (v1.0.12 — auto-confirm safe classes by default):

The reconciliation runs in **auto mode** by default — safe classes (no operator-data loss possible) apply immediately without a prompt. Only the classes that risk losing operator content or require human judgment trigger a confirmation:

| Class | Default behavior | Operator content at risk? |
|---|---|---|
| `identical` | Auto-delete `.bak` silently | No (bytes equal) |
| `whitespace-only` | Auto-delete `.bak` silently | No (trivial diff) |
| `operator-additions` (version-only: the only `.bak` content not in current is a version stamp / timestamp / hash that graphbrain itself bumped) | Auto-delete `.bak` silently | No (graphbrain owns those lines) |
| `operator-additions` (real content: section, paragraph, or named heading the operator wrote) | **PROMPT** before merging | Yes (need confirmation that the proposed merge is right) |
| `operator-edit-to-graphbrain-content` | **PROMPT** with data-loss warning | Yes (discard means losing operator work) |
| `mixed` | **PROMPT** with itemized kept/lost list | Yes |
| `unclear` | Skip — leave `.bak` in place | Yes |

Determining "version-only" for the `operator-additions` class: the diff lines added in the .bak only match these patterns: a version number (`v?\d+\.\d+\.\d+`), an ISO date (`\d{4}-\d{2}-\d{2}`), a git hash prefix (`git:[a-f0-9]+`), or whitespace. If any added line carries semantic prose, treat as real content and prompt.

**Auto-mode output** (silent unless something needs a prompt):

```
.bak reconciliation: <S> auto-applied (safe), <P> need confirmation, <K> kept as unclear.
```

If `<P> == 0` and `<K> == 0`, suppress the prompt entirely and proceed to Step 2.

**Prompt path** (only when `<P> > 0`):

```
Apply? (yes/no/show-diffs/per-file)
```

- `yes` → apply the prompted actions
- `no` → skip the prompted actions; safe-class .bak files were already cleaned
- `show-diffs` → print every per-file diff; re-prompt
- `per-file` → walk each prompted .bak individually; per-file yes/no/skip

**Flag overrides**:

- `/brain:init --yes` — also auto-confirm the prompted classes EXCEPT `operator-edit-to-graphbrain-content` and `unclear` (data-loss + judgment guard remains). The operator gets a non-interactive run.
- `/brain:init --interactive` — opt back into the pre-v1.0.12 behavior: prompt for ALL classes, including the safe ones. Useful when the operator wants to audit even the version-stamp bumps.

**1b-E — Apply**:

For each accepted action:

- `identical` / `whitespace-only`: `Bash: rm <path>.bak`
- `operator-additions` (MERGE): Write the merged content to `<path>` using the Write tool; then `Bash: rm <path>.bak`
- `operator-edit-to-graphbrain-content` (DISCARD): `Bash: rm <path>.bak`. Print the warning prominently.
- `unclear` (KEEP): no-op, .bak stays.

**1b-F — Log**:

Append to `.brain/log.md` under `## Activity History`:

```
## [YYYY-MM-DD] reconcile | <K> .bak processed: <I> merged, <D> deleted, <W> warnings, <U> kept-as-unclear
```

If any `operator-edit-to-graphbrain-content` was discarded, additionally log a per-file note:

```
   - DISCARDED edit in <path>: <one-line summary of what operator lost>
```

**1b-G — Continue**:

Proceed to Step 2 (read templates). The rest of /brain:init is unchanged.

**Error recovery**: if any merge fails (Write tool errors, disk full, etc.), abort that single file's reconciliation (leave .bak intact for operator manual handling); continue with the others. Do not abort the whole init.

**Step 2 — Read templates** (locate them in the installed graphbrain npm package; the slash-command file you are reading was copied from `commands/brain.md` in that package, and the templates live alongside it under `skills/core/init/templates/`):

- `skills/core/init/templates/claude-md-schema.md` — the verbatim schema block
- `skills/core/init/templates/overview-starter.md` — the overview template with `<!-- AGENT: ... -->` instruction comments
- `skills/core/init/templates/stack-detection.json` — the stack-signal catalog

If you cannot locate these template files, ask the operator to run `npm root -g` (for global installs) or to point you at the graphbrain package directory. Do not improvise the templates — the verbatim content is the contract.

**Step 3 — Splice schema block into CLAUDE.md**:

- Read `<cwd>/CLAUDE.md` in full.
- Extract the content between `<!-- graphbrain:begin -->` and `<!-- graphbrain:end -->`.
- Compare to the content of `claude-md-schema.md` (trimmed).
- If they match AND `$ARGUMENTS` does not contain `--force`: emit `SKIP CLAUDE.md (schema block already current)` and continue to Step 4.
- Otherwise: write the file with the new content between the markers (preserve everything outside the markers). This is the only modification to CLAUDE.md.
- Use a write strategy that preserves the file's existing line endings and final-newline state.

**Step 4 — Detect tech stack** (v1.0.13 — delegates to a Node helper):

Run the subtree-aware detection helper. It walks the cwd root + every immediate non-excluded subdir, evaluates `stack-detection.json` signals per subtree, writes `<cwd>/.brain/.graphbrain-stacks.json`, and prints the same JSON to stdout. This is the same procedure pre-v1.0.13 described in 4a/4b/4c (subtree enumerate → signal match → persist) — folded into a deterministic Node script so it doesn't burn LLM tokens.

Resolve the helper directory once (project-local plugin tree preferred; fall back to global):

```bash
HELPER_DIR=$([ -d .claude/plugins/graphbrain/scripts/lib ] \
  && echo .claude/plugins/graphbrain/scripts/lib \
  || echo "$HOME/.claude/plugins/graphbrain/scripts/lib")
```

Then invoke:

```bash
node "$HELPER_DIR/detect-stacks.js" .
```

The helper writes `.brain/.graphbrain-stacks.json` and emits the same JSON. Read its stdout. The shape is:

```json
{
  "version": "1.0.13",
  "generated": "<YYYY-MM-DD>",
  "subtrees": [
    { "path": "",       "stacks": ["nodejs"] },
    { "path": "server", "stacks": ["nodejs", "typescript", "nestjs"] },
    { "path": "client", "stacks": ["nodejs", "typescript", "react", "vite"] }
  ]
}
```

`.brain/.graphbrain-stacks.json` is the **load-bearing contract** read by `/brain:ingest` Step 4b to pick the right detected-tier skills per file (subtree-routed, not cwd-routed). Without it, ingest falls back to cwd-only detection.

For Step 4e (recommendations) and Step 7 (report), use the **union of stacks across all subtrees**, deduped. The per-subtree breakdown is only consumed by `/brain:ingest`.

If the helper exits non-zero or is missing (rare — operator deleted the plugin tree), fall back to the inline subtree procedure: walk subdirs, match signals from the catalog at `.claude/plugins/graphbrain/skills/core/init/templates/stack-detection.json`, persist the same JSON shape. The fallback is the v1.0.12 prompt-side procedure.

This step is reporting-only — `/brain:init` does NOT install `detected/*` skills. Those ship with the graphbrain npm package and are activated automatically by `/brain:ingest` Step 4b when the source file's owning subtree's stack set matches.

**Step 4e — Stack-specific skill recommendations** (formerly Step 4c; renamed v1.0.12 to make room for the subtree-aware detection sub-steps above):

Operate on the **union of stacks across all subtrees** computed in Step 4d. For each detected stack, the catalog (`stack-detection.json`) carries a `recommended_skills[]` array. Each entry is `{ source, package, install_command, description }`. Sources today:

- `source: "patterns.dev"` — installable via `npx -y skills add PatternsDev/skills/<framework>` (lands at `~/.claude/skills/`, user-global, available across all your repos)
- `source: "ecc"` — graphbrain bridges automatically once the ECC plugin is installed (no direct install command — operator installs ECC once; graphbrain's `/brain:ingest` Step 4b.3 probes for the named skill and loads it when present)

Use Claude's judgment — not a static algorithm — to:

1. **Read the matched stacks' `recommended_skills` arrays** from the catalog.
2. **Dedupe by `(source, package)`** — a Next.js project would otherwise see `patterns.dev/javascript` listed twice (once for `nodejs`, once for `nextjs`).
3. **Filter for relevance to THIS specific repo**: if the operator's `package.json` shows the project is genuinely a CLI tool (not a web app), the React/Vue recommendations may be noise. Lean conservative; only recommend skills that genuinely help on prompts the operator is likely to ask in this codebase. When uncertain, include them — the operator can ignore.
4. **Surface them in the Step 7 report** under a `Recommended skills:` block. Group by source.
5. **Phrase install commands as copy-paste-ready shell lines.** Not abstract instructions.

Skip Step 4e entirely if Step 4d produced zero detected stacks across all subtrees.

This step is **agent-driven by design** — you (the LLM agent) make the judgment call on relevance, not a hardcoded JSON catalog. The catalog provides the candidates; you pick the ones that actually fit this repo.

**Step 5 — Populate overview.md**:

- Read `<cwd>/.brain/overview.md` (M#1 wrote a minimal skeleton).
- Use `overview-starter.md` as the new content template.
- For each `<!-- AGENT: ... -->` instruction comment in the template, follow its directive:
  - **Project Purpose** — infer from `package.json` description, `pyproject.toml` description, `README.md` tagline (first paragraph after H1), or top-level comments. If no signal: write the literal fallback the template specifies. Do not invent.
  - **Codebase Structure** — generate a 1-level dir tree of cwd's top-level entries (skip `.git`, `node_modules`, `.venv`, `__pycache__`, `dist`, `build`, `.brain`, `.claude`). Format as a bullet list with a one-line purpose per entry.
  - **Key Patterns** — write the exact placeholder line the template specifies; do not invent patterns at init time.
  - **Active State** — fill in: `Initialized: <today ISO YYYY-MM-DD>`, `Graphbrain version: <from .brain/.graphbrain-version>`, `Detected stack: <comma-separated list from Step 4>`, `Pages: <count from .brain/{code,concepts,decisions}>`, `Last ingest: never (run /brain ingest <path> to begin)`.
  - **Recent Activity** — exact placeholder line per template.
- Update the frontmatter: replace `<!-- AGENT: ... -->` placeholders in `created`, `last_ingested`, `ingested_by` with today's ISO date and your model identifier. Change `status: UNENRICHED` to `status: FRESH`.
- Write the result to `<cwd>/.brain/overview.md`. If the file already has populated content (not just M#1's skeleton) and `$ARGUMENTS` does not contain `--force`: emit `SKIP .brain/overview.md (already populated)` rather than overwrite.

**Step 6 — Log**:

- Append to `<cwd>/.brain/log.md` under the `## Activity History` section heading. Use the grep-parseable prefix from PRD Design Decision #15:
  ```
  ## [YYYY-MM-DD] init | /brain init populated schema block + overview; detected: <comma-separated stacks>
  ```
- Today's date in ISO format.

**Step 7 — Report**:

Print exactly:

```
/brain:init complete (graphbrain v<version-from-.graphbrain-version>)
  Schema block:   <refreshed | unchanged>
  overview.md:    <populated | unchanged>
  Detected stacks (per subtree):
    <subtree-path or "(root)">: <comma-separated list, or "(none)">
    <next subtree>:             <stacks>
    ...
  Stacks map:     .brain/.graphbrain-stacks.json
  Logged:         .brain/log.md

Recommended skills for this stack: <only print this block if Step 4e produced recommendations>
  patterns.dev (installs to ~/.claude/skills/, user-global):
    <description>
    $ <install_command>
    ...
  ECC plugin (auto-bridges once installed):
    <description>
    → <package>
    ...

Next:
  /brain:ingest <file>     single-file ingest
  /brain:ingest <folder>   folder ingest + concept-page linking
  /brain:ingest            tiered auto-prioritize across the whole codebase
  /brain:query "..."       once pages exist, ask a question
```

If you encountered any failures during the procedure, replace the success report with a `FAILED at Step <N>: <reason>` line and exit. Do not partially complete and report success.

