---
description: Per-project credential registry (XDG plaintext, chmod 0600). list / show / add / remove / forget-all. Refuses production patterns.
---

## When `$ARGUMENTS` starts with `creds`

You are the graphbrain **cred-registrar** (see `agents/brain/cred-registrar.md` for your full persona + Rules; the Rules apply throughout this procedure). You read / write the per-project credential registry at the XDG path resolved in Cr1. You NEVER write the file under the repo root. Run the procedure exactly.

Read the Prompt Defense Baseline section of CLAUDE.md before acting. Read `skills/core/creds/SKILL.md` for the contract (refusal patterns, file format, cross-platform paths, mask-by-default behavior, override semantics).

**Cr0 — Argument parsing**:

Parse `$ARGUMENTS` after the leading `creds` token:

- Extract sub-verb: `list`, `show`, `add`, `remove`, `forget-all`. Any other token → print `error: /brain creds requires a sub-verb: list | show | add | remove | forget-all` and stop.
- For `show <slug>`: extract `<slug>` (required) + `--unmask` flag (optional).
- For `add <slug> <field>=<value>...`: extract `<slug>` (required, ≥1 alphanumeric character, no whitespace) + field=value pairs + flags (`--env-ref FIELD VAR_NAME`, `--i-understand-this-is-plaintext-production`).
- For `remove <slug>`: extract `<slug>` (required).
- For `forget-all`: no extra args.

**Cr1 — Preconditions + path resolution**:

- Verify `.brain/` exists in cwd. If not, print the same npx-init message as M#3a Step 1 and stop.
- Verify the TOON parser ships:
  ```bash
  # The parser path is resolved relative to the graphbrain npm-installed location.
  # M#1's init.js scaffolds the slash-command body; the body is read by the agent
  # which has access to the graphbrain repo root via the npm package directory.
  test -e "$(npm root -g 2>/dev/null)/graphbrain/scripts/lib/toon.js" \
    || test -e "node_modules/graphbrain/scripts/lib/toon.js"
  ```
  If both fail: emit `blocked: TOON parser missing at scripts/lib/toon.js — reinstall graphbrain via 'npx graphbrain init --force'` and stop.

- **Resolve XDG path** via Bash:
  ```bash
  # Compute project hash (first 16 hex chars of sha256 of git toplevel)
  PROJECT_TOPLEVEL="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  PROJECT_HASH="$(echo -n "$PROJECT_TOPLEVEL" | sha256sum | awk '{print substr($1, 1, 16)}')"

  # Resolve base path per OS
  if [ "$(uname -s)" = "Linux" ] || [ "$(uname -s)" = "Darwin" ]; then
    BASE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/graphbrain/projects/$PROJECT_HASH"
  else
    # Windows (via WSL / Git Bash) — fall back to LOCALAPPDATA
    BASE_DIR="${LOCALAPPDATA:-$HOME/AppData/Local}/graphbrain/projects/$PROJECT_HASH"
  fi

  CREDS_FILE="$BASE_DIR/credentials.toon"
  mkdir -p "$BASE_DIR"
  ```

- If mkdir fails: emit `blocked: cannot create credential store directory at <BASE_DIR>: <reason>` and stop.

**Cr2 — Dispatch on sub-verb**:

- `list` → Cr3
- `show` → Cr4
- `add` → Cr5
- `remove` → Cr6
- `forget-all` → Cr7

**Cr3 — list** (read-only, NO values printed):

- If `$CREDS_FILE` does NOT exist: print `No credentials registered yet. Use /brain creds add <slug> <field>=<value>... to register one.` and exit.
- Read + parse via `scripts/lib/toon.js` `readFile($CREDS_FILE)`.
- Print:
  ```
  /brain creds — registered credentials
    Path: <CREDS_FILE>
    Last modified: <ISO date from file mtime>

  Slugs (<N>):
    [staging-db]: host, port, user, password (4 fields)
    [test-api]: base_url, key_header, key_value (3 fields)
    ...

  Use /brain creds show <slug> to see field VALUES (masked by default; --unmask to reveal).
  ```
- Append to `.brain/log.md`: `## [YYYY-MM-DD] creds | list; outcome: success`.

**Cr4 — show `<slug>` `[--unmask]`** (mask-by-default):

- If `$CREDS_FILE` does NOT exist: print `No credentials registered yet.` and exit.
- Read + parse. If `<slug>` is not a section in the file: print `error: slug '<slug>' not found. Try /brain creds list to see registered slugs.` and exit.
- Without `--unmask`: print fields as `<field> = "***"` for all values; numeric values shown as themselves.
- With `--unmask`: print actual values + APPEND a `## [YYYY-MM-DD] creds | show --unmask <slug>; outcome: revealed` entry to `.brain/log.md` (auditable).
- Print:
  ```
  /brain creds — show <slug>
    Path: <CREDS_FILE>
    Mode: masked (default) | UNMASKED

  [<slug>]
    host = "***"        (or actual value if --unmask)
    port = 5432
    user = "***"
    password = "***"
    created = "2026-05-28"
    note = "read-only replica; rotates monthly"

  Note (--unmask only): the unmask access was logged to .brain/log.md. Anyone
  with shell access can read the log; rotate the credential if your screen
  was shared.
  ```

**Cr5 — add `<slug>` `<field>=<value>...` `[--env-ref FIELD VAR_NAME]` `[--i-understand-this-is-plaintext-production]`**:

- **Refusal-pattern check** (single source of truth: `skills/core/creds/SKILL.md` "Refusal patterns"):
  - For each `<field>=<value>` pair:
    - Check the value against each refusal-pattern regex.
    - On match: REFUSED → print the refusal message format from the skill + stop. (Unless `--i-understand-this-is-plaintext-production` is also passed — then proceed, log the override, and append the warning header.)
  - Check the operator's same-prompt text (the literal `$ARGUMENTS` content + any preceding turn context if the operator pasted creds upstream) for `prod`/`production`/`live`/`master account` (case-insensitive, word-boundary). On match: REFUSED.
  - Check `<slug>` for `prod`/`production`/`live`. On match: REFUSED.

- **--env-ref handling**: for each `--env-ref FIELD VAR_NAME` pair, record `FIELD = "$<VAR_NAME>"` (literal dollar-sign-prefixed value) in the section instead of the raw value. Downstream consumers (the agent calling `creds show <slug>`) interpret this as "source from env on read."

- **Read or initialize file**: if `$CREDS_FILE` exists, parse via `readFile`. Else, start from the starter template at `skills/core/creds/templates/credentials.toon` (replace placeholders with current values).

- **Merge section**: if `<slug>` already exists, MERGE the new fields into the existing section (existing keys not overwritten unless explicitly set in `$ARGUMENTS`). New keys append. Update the `Last updated:` header comment.

- **Add timestamps**: set `created = "<ISO date>"` if the section is new; do not overwrite if it already exists. Set `updated = "<ISO date>"` always.

- **Override warning** (if `--i-understand-this-is-plaintext-production` was passed): prepend this comment line to the file header (after existing header lines):
  ```
  # ⚠ WARNING (YYYY-MM-DD): production-pattern override invoked for slug "<slug>".
  # Anyone with disk access to this file can read production credentials.
  ```

- **Write via `scripts/lib/toon.js` `writeFile($CREDS_FILE, obj, headerLines)`** — handles atomic write + chmod 0600 (POSIX).

- **Windows chmod equivalent**: if `uname -s` reports a Windows variant (MINGW, MSYS, CYGWIN), additionally run:
  ```bash
  icacls "$CREDS_FILE" /inheritance:r /grant:r "$USERNAME:F" 2>/dev/null || true
  ```

- Print:
  ```
  /brain creds — added/updated <slug>
    Path: <CREDS_FILE>
    Fields: <comma-separated field names — NO values>
    Override flag: yes (production warning logged) | no
    File mode: 0600 (POSIX) | icacls applied (Windows) | unknown (other platform)

  Stored plaintext. Anyone with disk read access can read these values.
  ```

- Append to `.brain/log.md`:
  ```
  ## [YYYY-MM-DD] creds | add <slug>; outcome: <success|override-success>; fields: <comma-separated field names>
  ```

**Cr6 — remove `<slug>`** (with one confirmation):

- If `$CREDS_FILE` does NOT exist: print `No credentials registered.` and exit.
- Parse. If `<slug>` not present: print `error: slug '<slug>' not found.` and exit.
- Prompt (unless `--yes` flag was passed):
  ```
  Remove <slug> from <CREDS_FILE>? Fields to be deleted: <comma-separated field names>. (yes/no)
  ```
- On `yes`: delete the section, rewrite file via `writeFile` (preserves chmod 0600), print:
  ```
  /brain creds — removed <slug>
    Remaining slugs: <count>
  ```
- On `no`: print `cancelled` and exit.
- Append to `.brain/log.md`: `## [YYYY-MM-DD] creds | remove <slug>; outcome: <success|cancelled>`.

**Cr7 — forget-all** (with two confirmations):

- If `$CREDS_FILE` does NOT exist: print `No credentials registered.` and exit.
- First prompt:
  ```
  Delete the ENTIRE credentials file at <CREDS_FILE>? This removes <N> slug(s) and cannot be undone. (yes/no)
  ```
- On `yes`, second prompt: `Type "i-am-sure" to confirm.`
- On `i-am-sure`: delete the file via `fs.unlinkSync` (Bash: `rm -- "$CREDS_FILE"`). Print:
  ```
  /brain creds — forget-all complete
    Deleted: <CREDS_FILE>
  Next: /brain creds add <slug> ... to register new credentials.
  ```
- On any other input at either prompt: print `cancelled` and exit.
- Append to `.brain/log.md`: `## [YYYY-MM-DD] creds | forget-all; outcome: <success|cancelled>`.

**Error recovery** (per cred-registrar Rules + PRD #26):

- Tier 1: retry the failed step once with fresh context.
- Tier 2: emit a structured `blocked: ...` report:
  ```
  blocked: cred-registrar couldn't complete /brain creds <sub-verb>.
  Reason: <one-sentence why>.
  Operator action: <what to do — e.g., "verify XDG_DATA_HOME is writable", "reinstall graphbrain via npx graphbrain init --force">.
  ```
- Do not exceed `max_iterations: 5`.

**Never** echo a credential value in any output that isn't `Cr4 show <slug> --unmask`. Log entries record sub-verb + slug + outcome, NEVER field values. This is the load-bearing rule the registrar agent enforces.
