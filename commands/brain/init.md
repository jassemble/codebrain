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
Next:
  /brain:ingest <file>     single-file ingest
  /brain:ingest <folder>   folder ingest + concept-page linking
  /brain:ingest            tiered auto-prioritize across the whole codebase
  /brain:query "..."       once pages exist, ask a question
```

If you encountered any failures during the procedure, replace the success report with a `FAILED at Step <N>: <reason>` line and exit. Do not partially complete and report success.

