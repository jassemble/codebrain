<!-- graphbrain v1.0.0 -->
---
description: codebrain — brain dashboard (Milestone #7)
---

## When `$ARGUMENTS` is just `status`

The project dashboard. Read-only.

**S0 — Preconditions**: `.brain/` exists; `.brain/.codebrain-version` present. (If not: same npx-init message.)

**S1 — Gather**:

- Page counts per kind: walk `.brain/code/`, `.brain/concepts/`, `.brain/decisions/`; count `.md` files.
- Hooks installed: read `.claude/settings.local.json`; count entries with `id` starting `codebrain:`.
- Last 5 log entries: `tail -5 .brain/log.md | grep "^## \["` (grep-parseable per PRD #15).
- Learn state: read `.brain/.codebrain-learn-state` (default `missing` → display as `off (default)`).
- Observation count + instinct count: only if learn state is `on`, query the XDG paths (use `wc -l` via Bash, gracefully no-op if files don't exist).
- Intent-routing state (M#10c): read `.brain/.codebrain-intent-routing-state` (default `missing` → display as `off (default)`). Malformed → `off (malformed)`.

**S2 — Format the dashboard**:

```
codebrain status (v<version>)

Vault:
  Code pages:        <count>
  Concept pages:     <count>
  Decision pages:    <count>
  Total:             <sum>

Hooks installed:     <count> [codebrain:pre:verified-guard, codebrain:pre:observe, codebrain:post:stale-detect]

Learn:
  Toggle:            <on | off | missing>
  Observations:      <count or "n/a — learn off">
  Instincts:         <count or "n/a — learn off">

Intent routing:      <on | off (default) | off (malformed)>

Recent activity (last 5 entries from .brain/log.md):
  <entry 1>
  <entry 2>
  ...

Next: /brain query "..."  or  /brain lint  or  /brain learn status
```

**S3 — Output**: print the dashboard. No log entry (status is a query, not an event).

**Error recovery**: same Tier 1/2 pattern; `max_iterations: 5`.
