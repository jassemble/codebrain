---
description: Toggle the continuous-learning observer (on/off/status) + run the consolidator (consolidate).
---

## When `$ARGUMENTS` starts with `learn`

You are operating the continuous-learning subsystem (see `agents/observers/observer.md` for the consolidator agent; see `skills/core/learn/SKILL.md` for the full contract — observation format, instinct format, privacy stance). Run the procedure exactly for the requested subcommand.

**Le0 — Argument parsing**:

- Extract the subcommand from `$ARGUMENTS`: `on`, `off`, `status`, `consolidate`, or `auto-refresh <on|off|status>` (v1.0.15).
- Any other token → print `error: /brain learn requires a subcommand: on | off | status | consolidate | auto-refresh <on|off|status>` and stop.

**Le1 — Preconditions**:

- Verify `.brain/` exists in cwd. If not, print the same npx-init message as M#3a Step 1 and stop.
- Verify `.brain/.graphbrain-version` is present.

**Le2 — Dispatch**:

- `on` → proceed to Le3 (toggle on)
- `off` → proceed to Le4 (toggle off)
- `status` → proceed to Le5 (status report)
- `consolidate` → proceed to Le6 (consolidator agent)
- `auto-refresh <on|off|status>` → proceed to Le8 (v1.0.15 — auto-refresh wiki on stale)

---

**Le3 — `learn on` (toggle on)**:

1. Print the privacy notice EXACTLY (verbatim — operators rely on this):
   ```
   [Privacy notice — graphbrain v<version>]
   Graphbrain will now collect minimal observations of your tool use in this repo:
     - Captured fields: timestamp, tool name, relative path (if applicable), status
     - NOT captured: tool outputs, prompts, file contents, stderr, stdout
     - Storage: <XDG_DATA_HOME or ~/.local/share>/graphbrain/projects/<git-hash>/observations.jsonl
     - Disable anytime: /brain learn off
   ```
2. Atomic-write `.brain/.graphbrain-learn-state` with content `on\n` (use `Bash: printf "on\n" > .brain/.graphbrain-learn-state`).
3. Append to `.brain/log.md`:
   ```
   ## [YYYY-MM-DD] learn | toggled on
   ```
4. Print: `Toggle written: .brain/.graphbrain-learn-state = on`

---

**Le4 — `learn off` (toggle off)**:

1. Atomic-write `.brain/.graphbrain-learn-state` with content `off\n`.
2. Append to `.brain/log.md`:
   ```
   ## [YYYY-MM-DD] learn | toggled off
   ```
3. Print:
   ```
   Toggle written: .brain/.graphbrain-learn-state = off
   Existing observations and instincts in ~/.local/share/graphbrain/projects/<hash>/ are preserved.
   To purge them, manually delete that directory.
   ```

---

**Le5 — `learn status` (per-project learn dashboard)**:

1. Read toggle state (`on`/`off`/`missing`).
2. Read `<XDG>/projects/<git-hash>/observations.jsonl` via `Bash: cat ~/.local/share/graphbrain/projects/$(... project hash computation ...)/observations.jsonl 2>/dev/null` — count lines (= observation count).
3. Read `<XDG>/projects/<git-hash>/instincts.jsonl` similarly — count lines (= instinct count).
4. Compute top 5 patterns from instincts (sort by frequency desc; take 5).
5. Print:
   ```
   /brain learn status (graphbrain v<version>)
     Toggle:             <on | off | missing (default off)>
     Observations:       <count> (since <oldest ts as YYYY-MM-DD>)
     Instincts:          <count>
     Top 5 patterns:
       <pattern>          <freq> (<pct>%)
       ...
     XDG store:          <path>
     Last consolidation: <YYYY-MM-DD from .brain/log.md "consolidate" entry, or "never">
   ```

---

**Le6 — `learn consolidate` (observer agent)**:

You are now acting as the observer agent. Follow the observer's procedure exactly:

1. **Toggle check**: read `.brain/.graphbrain-learn-state`. If NOT `on`: print `error: cannot consolidate while toggle is off or missing. Run /brain learn on first.` and stop.

2. **Read observations**: load `<XDG>/projects/<git-hash>/observations.jsonl` via `Bash` + a small Node one-liner that uses `scripts/hooks/lib/observations.readObservations(cwd)`. Get an array of records.

3. **Count patterns**: group by `(tool, path-prefix-up-to-second-segment)`:
   - For `path: "src/api/auth.ts"`, the prefix-up-to-second-segment is `src/api`
   - For `path: "package.json"` (single segment), the prefix is `package.json` itself (or `.` for null path)
   - Build a map: `{ "Edit:src/api": { freq: 17, first_seen: ..., last_seen: ... }, ... }`

4. **Promote to instincts**: any pattern with `frequency >= 3` becomes an instinct. Compute `id = SHA-256(pattern).slice(0, 12)`. Total observations = sum of all pattern frequencies; per-instinct `confidence = frequency / total`.

5. **Merge with existing**: read `instincts.jsonl`; build an existing-id set. For each new instinct: if `id` already exists, update the existing record's `frequency`/`confidence`/`last_seen` (sum frequencies; recompute confidence; max last_seen). If new, append.

6. **Atomic write**: rewrite the entire instincts.jsonl with the merged set (use temp+rename pattern via Bash, or call `lib/observations.appendInstinct` for each new/updated). Acceptable for v0.1 to rewrite the whole file each consolidation; file is small.

7. **Log**: append to `.brain/log.md`:
   ```
   ## [YYYY-MM-DD] consolidate | <N> observations → <M> new instincts + <K> updated; toggle: on
   ```

8. **CHANGELOG entry** (M#10d): if `<M>` new instincts > 0, append a one-line narrative entry to `.brain/CHANGELOG.md` under the current month's `## YYYY-MM` heading (create heading if absent):
   ```
   - <YYYY-MM-DD>: consolidate | <M> new instincts: <comma-separated instinct names or first 5 + "...">
   ```
   Skip if `<M>` is 0 (no new compound learning to surface). Lint (M#6) skips CHANGELOG entries (read-only).

**Le7 — Report**:

For `consolidate`, print:
```
/brain learn consolidate complete
  Observations read:    <N>
  Patterns found:       <M total patterns, including those below threshold>
  Instincts new:        <K>
  Instincts updated:    <U>
  Threshold (v0.1):     frequency ≥ 3
  Logged:               .brain/log.md
  Storage:              <XDG>/projects/<git-hash>/
```

For other subcommands, the report is the toggle-confirmation or status output from Le3-Le5.

---

**Le8 — `learn auto-refresh <on|off|status>`** (v1.0.15):

Controls the auto-refresh hook: when source files are edited, the wiki pages mirroring them go STALE, and on the operator's next prompt the `auto-refresh-prompt` UserPromptSubmit hook prepends a refresh-first directive. Default state is **on** (missing file → on).

- `auto-refresh on`:
  1. Atomic-write `.brain/.graphbrain-auto-refresh-state` with content `on\n`.
  2. Append to `.brain/log.md`: `## [YYYY-MM-DD] learn | auto-refresh toggled on`.
  3. Print: `Toggle written: .brain/.graphbrain-auto-refresh-state = on`. Add a one-line explainer: `Edits to source files will queue corresponding wiki pages for refresh on your next prompt.`

- `auto-refresh off`:
  1. Atomic-write `.brain/.graphbrain-auto-refresh-state` with content `off\n`.
  2. Append to `.brain/log.md`: `## [YYYY-MM-DD] learn | auto-refresh toggled off`.
  3. Print: `Toggle written: .brain/.graphbrain-auto-refresh-state = off`. Add: `Pages will still be marked STALE by the PostToolUse hook; refresh manually via /brain:ingest <path> or /brain:lint --fix.`

- `auto-refresh status`:
  1. Read `.brain/.graphbrain-auto-refresh-state` (`on`/`off`/missing → display as `on (default)`).
  2. Read `.brain/.refresh-queue` if present; count queued paths.
  3. Print:
     ```
     /brain learn auto-refresh status (graphbrain v<version>)
       Toggle:        <on | off | on (default)>
       Queue depth:   <count> path(s) waiting for next prompt
       Queue file:    .brain/.refresh-queue
     ```
  4. If queue depth > 0, also print: `Next prompt will trigger refresh of: <comma-list of first 5 paths, +N more if longer>`.

This toggle is **independent** of the continuous-learning observer (Le3/Le4) — `/brain:learn auto-refresh off` does not disable observation; `/brain:learn off` does not disable auto-refresh.

---

**Error recovery** (per observer Rules + PRD #26): Tier 1 retry once; Tier 2 emit:
```
blocked: learn <subcommand> couldn't complete.
Reason: <one-sentence why>.
Operator action: <what — e.g., "run /brain learn on first" or "check XDG_DATA_HOME permissions">.
```

