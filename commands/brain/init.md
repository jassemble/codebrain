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

**1b-A — Detect**:

```bash
# Glob — exclude node_modules + .git
find .brain .claude CLAUDE.md.bak -name "*.bak" -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null
```

Also check repo root: `CLAUDE.md.bak`.

If zero matches: **skip Step 1b silently** and proceed to Step 2. No output, no log entry.

**1b-B — Classify each pair**:

For each `<path>.bak`:

- Verify the current `<path>` (without `.bak`) exists. If it doesn't (rare — operator deleted the current file but left the .bak), the .bak is orphaned; flag as `orphaned` and offer to either restore from .bak or delete .bak.
- Read both files. Compute their diff.
- Classify the diff into one of:

  | Class | Definition | Default action |
  |---|---|---|
  | `identical` | Files are byte-identical (legacy noise from v1.0.4 and earlier — content-equality check wasn't in atomicWrite yet) | Silently delete `.bak`; no merge needed |
  | `whitespace-only` | Only trailing whitespace, line ending, or final-newline differences | Silently delete `.bak` |
  | `operator-additions` | The .bak has content the current version does NOT, AND that content does NOT correspond to a section graphbrain owns (e.g., a new top-level heading, custom paragraph, or extra entry the operator added) | **Propose MERGE**: take graphbrain's new shipped content + splice in the operator's additions. Preserve operator's work. |
  | `operator-edit-to-graphbrain-content` | The .bak modifies content graphbrain owns (e.g., changed a procedure step's wording, modified an example output, renamed a verb) | **Discard the .bak** (graphbrain's shipped version is canonical). **Warn the operator** so they know what was lost. |
  | `mixed` | Combination of additions AND edits to graphbrain content | Apply additions, discard graphbrain-content edits. Itemize what was kept vs lost. |
  | `unclear` | The diff is too complex / shows refactoring / cross-file moves that you can't classify confidently | **Do NOT auto-merge**. Show the diff to the operator + ask. |

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

**1b-D — Confirmation gate**:

- `yes` → apply all proposed actions
- `no` → leave all .bak files; init proceeds normally to Step 2
- `show-diffs` → print every per-file diff; re-prompt
- `per-file` → walk each .bak with an individual prompt; per-file yes/no/skip

If the operator passed `--yes` on the `/brain:init` invocation: **auto-confirm only the safe classes** (`identical`, `whitespace-only`, `operator-additions`). NEVER auto-confirm `operator-edit-to-graphbrain-content` (data loss warning) or `unclear` (judgment call). For those, fall back to interactive confirmation even with `--yes`.

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

**Step 4 — Detect tech stack**:

- Parse `stack-detection.json`. For each entry in `stacks`, evaluate `signals`:
  - `{ "file_exists": "<path>" }` — match if `<cwd>/<path>` exists as a file
  - `{ "file_exists": "<path>", "contains": "<substring>" }` — match if file exists AND its content contains the substring
  - `{ "dir_exists": "<path>" }` — match if `<cwd>/<path>` exists as a directory
  - `{ "glob": "<pattern>" }` — match if at least one file matches the glob, relative to cwd
- A stack matches only if **all** of its `signals` match (logical AND).
- Collect the matched stack names. Dedupe (e.g., `python` and `python-legacy` both detect Python — report once as `python`).
- This step is reporting-only — `/brain:init` does NOT install `detected/*` skills. Those ship with the graphbrain npm package and are activated automatically by `/brain:ingest` Step 4b when the source file's extension + project signals match.

**Step 4c — Stack-specific skill recommendations (M#13a)**:

For each detected stack from Step 4, the catalog (`stack-detection.json`) carries a `recommended_skills[]` array. Each entry is `{ source, package, install_command, description }`. Sources today:

- `source: "patterns.dev"` — installable via `npx -y skills add PatternsDev/skills/<framework>` (lands at `~/.claude/skills/`, user-global, available across all your repos)
- `source: "ecc"` — graphbrain bridges automatically once the ECC plugin is installed (no direct install command — operator installs ECC once; graphbrain's `/brain:ingest` Step 4b.3 probes for the named skill and loads it when present)

Use Claude's judgment — not a static algorithm — to:

1. **Read the matched stacks' `recommended_skills` arrays** from the catalog.
2. **Dedupe by `(source, package)`** — a Next.js project would otherwise see `patterns.dev/javascript` listed twice (once for `nodejs`, once for `nextjs`).
3. **Filter for relevance to THIS specific repo**: if the operator's `package.json` shows the project is genuinely a CLI tool (not a web app), the React/Vue recommendations may be noise. Lean conservative; only recommend skills that genuinely help on prompts the operator is likely to ask in this codebase. When uncertain, include them — the operator can ignore.
4. **Surface them in the Step 7 report** under a `Recommended skills:` block. Group by source.
5. **Phrase install commands as copy-paste-ready shell lines.** Not abstract instructions.

Skip Step 4c entirely if Step 4 produced zero detected stacks.

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
  Detected stack: <comma-separated list, or "(none detected)">
  Logged:         .brain/log.md

Recommended skills for this stack: <only print this block if Step 4c produced recommendations>
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

