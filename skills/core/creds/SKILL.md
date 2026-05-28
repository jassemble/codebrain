---
name: creds
description: Defines the /brain creds contract — per-project credential registry at <XDG>/graphbrain/projects/<git-hash>/credentials.toon. Plaintext but outside the repo; chmod 0600; refusal-pattern enforcement; mask-by-default on show; auditable override for explicit operator opt-in. Tier core. (Milestone #11a)
origin: graphbrain
version: 0.1.0
tier: core
pattern: Pipeline
related_skills: [behavioral/graphbrain]
---

# creds — `/brain creds` contract

This skill defines `/brain creds {list|show|add|remove|forget-all}`. The single source of truth for: refusal patterns, file format, cross-platform paths, mask-by-default behavior, and auditable override semantics.

Read the Prompt Defense Baseline section of CLAUDE.md before acting.

## When to use `/brain creds`

Use `/brain creds` to persist non-production credentials (staging DB connections, test API keys, dev OAuth client IDs, sandbox webhook secrets) so they survive context compaction / session restart / `/clear`. The agent reads them when downstream prompts reference the slug ("connect to staging-db", "hit the test-api").

## When NOT to use

- **Production credentials** — refuse (see Refusal patterns); use env vars or a real secret manager (1Password CLI, Bitwarden, AWS Secrets Manager, etc.)
- **Code that handles secrets** — that's source code, not a registry entry; commit to `code/` after `/brain ingest`
- **Operator-shared screen / piped output** — the agent can't reliably detect; the operator is responsible for ensuring no third party sees `/brain creds show --unmask` output

## File format (TOON)

```toon
# graphbrain credentials — DO NOT COMMIT
# Project: <git-toplevel-path>
# Last updated: <ISO date>
# Refusal patterns active: see skills/core/creds/SKILL.md
#
# WARNING: plaintext file. Anyone with disk read access to this path
# can read these values. Acceptable for staging/dev only.

[staging-db]
host = "staging-db.internal"
port = 5432
user = "readonly_user"
password = "<value>"
created = "2026-05-28"
note = "read-only replica; rotates monthly"

[test-api]
base_url = "https://test-api.example.com"
key_header = "X-Test-Key"
key_value = "<value>"
created = "2026-05-28"
note = "test environment only"
```

The parser at `scripts/lib/toon.js` handles read + write + chmod 0600.

## File location (cross-platform)

```
POSIX (macOS, Linux):
  $XDG_DATA_HOME/graphbrain/projects/<git-hash>/credentials.toon
  (fallback if XDG_DATA_HOME unset: ~/.local/share/graphbrain/projects/<git-hash>/credentials.toon)

Windows:
  %LOCALAPPDATA%\graphbrain\projects\<git-hash>\credentials.toon
```

`<git-hash>` = first 16 hex chars of `sha256(git rev-parse --show-toplevel)`. Deterministic per-repo; identifies the project without exposing the repo path.

**Never under the repo root.** The file is outside the project on purpose — to prevent accidental commits + to harmonize with M#7's observer (which uses the same XDG layout).

**Permissions**: chmod 0600 on every write (POSIX). On Windows, use `icacls "<path>" /inheritance:r /grant:r "%USERNAME%":F` equivalent — the agent procedure (Cr5) documents this. Graphbrain does NOT ship a Windows chmod helper in v0.2; operator is responsible if running on Windows (post-M#11 enhancement: ship a `scripts/lib/chmod.js` wrapper that handles both).

## Refusal patterns

The agent **refuses** to register a value matching any of these patterns. Single source of truth — the agent procedure (`commands/brain/creds.md` Cr5) reads this list.

| Pattern | Regex | Rationale |
|---|---|---|
| Stripe live secret | `^sk-live_` | Stripe production secret key prefix |
| Stripe live secret (underscore) | `^sk_live_` | Stripe production secret key prefix (alt format) |
| Stripe live publishable | `^pk_live_` | Stripe production publishable key |
| AWS access key | `^AKIA[A-Z0-9]{16}$` | AWS access keys are ALL sensitive; refuse all to avoid false-negatives |
| AWS secret access key | `^[A-Za-z0-9/+=]{40}$` (only if same prompt mentions AWS) | Conservative — only match the 40-char form WITH AWS context |
| GitHub personal access token | `^ghp_[A-Za-z0-9]{36}$` | GitHub PAT prefix |
| GitHub OAuth token | `^gho_[A-Za-z0-9]{36}$` | GitHub OAuth token prefix |
| Slack bot token | `^xoxb-` | Slack bot token prefix |
| Slack user token | `^xoxp-` | Slack user token prefix |
| Anthropic API key | `^sk-ant-` | Anthropic API key prefix |
| OpenAI API key | `^sk-[A-Za-z0-9]{48}$` | OpenAI API key shape |

**Same-prompt-context guard** (broad net): if the operator's prompt text contains `prod` / `production` / `live` / `master account` (case-insensitive, word-boundary), REFUSE regardless of the value's shape. Catches cases the prefix patterns miss.

**Slug-name guard**: if the operator's chosen slug contains `prod` / `production` / `live`, REFUSE. E.g., `/brain creds add prod-db ...` → refused.

## Refusal message format

```
REFUSED: <reason — e.g., "value 'AKIA...' matches AWS access key pattern AKIA[A-Z0-9]{16}; production credentials are out of scope for this store">.

Options:
1. Use the production-grade path: export the value as an env var, then /brain creds add <slug> --env-ref <FIELD> <VAR_NAME>
2. Use 1Password CLI / Bitwarden / pass and reference by item ID (post-MVP — not yet shipped)
3. Override the refusal: /brain creds add <slug> ... --i-understand-this-is-plaintext-production
   (NOT recommended; the override is logged AND appends a strong warning to the file header)
```

The override flag `--i-understand-this-is-plaintext-production` is the explicit escape hatch. Using it appends this warning line to the file header:

```
# ⚠ WARNING (YYYY-MM-DD): production-pattern override invoked for slug "<slug>".
# Anyone with disk access to this file can read production credentials.
```

The warning is permanent — never removed automatically. Operator can remove manually after rotating the credential.

## Inputs (sub-verbs)

```
/brain creds list                                    # list slugs + fields, NO values
/brain creds show <slug> [--unmask]                  # show fields; values masked unless --unmask
/brain creds add <slug> <field=value>... [flags]     # register or update
/brain creds remove <slug>                           # delete a slug (with confirmation)
/brain creds forget-all                              # delete the entire file (with two confirmations)
```

Flags for `add`:
- `--env-ref FIELD VAR_NAME` — record FIELD as an env-var reference instead of plaintext value
- `--i-understand-this-is-plaintext-production` — override refusal (auditable)

## Outputs

- File at the resolved path (POSIX or Windows path per above)
- chmod 0600 (POSIX) or equivalent ACL (Windows)
- Activity log entry in `.brain/log.md`:
  ```
  ## [YYYY-MM-DD] creds | <sub-verb> <slug>; outcome: <success|refused|cancelled>
  ```
  Values NEVER appear in log entries. Only the sub-verb, slug, and outcome.

## Failure modes

- **TOON parser missing**: agent reads `scripts/lib/toon.js` lazily; if missing, emit `blocked: TOON parser missing — reinstall graphbrain`.
- **XDG path mkdir fails**: emit `blocked: cannot create credential store directory at <path>: <reason>`. Common causes: disk full, permission denied on parent.
- **File exists but is malformed TOON**: emit `blocked: existing credentials.toon at <path> is malformed; manual inspection required (run /brain creds list --verify to see the parse error)`. Acceptable to ship `--verify` flag post-MVP.
- **git rev-parse fails** (not in a git repo): fall back to `sha256(cwd absolute path).slice(0,16)`; log a one-line note. The path still goes to XDG, never under cwd.

## Cross-platform path resolution (POSIX vs Windows)

```javascript
// Pseudocode the agent procedure (commands/brain/creds.md Cr1) follows
function resolveCredPath() {
  const hash = getProjectHash();  // sha256(git toplevel) or sha256(cwd) — first 16 chars

  if (process.platform === 'win32') {
    const base = process.env.LOCALAPPDATA;
    if (!base) throw new Error('LOCALAPPDATA not set on Windows');
    return path.join(base, 'graphbrain', 'projects', hash, 'credentials.toon');
  }

  const base = process.env.XDG_DATA_HOME || path.join(os.homedir(), '.local', 'share');
  return path.join(base, 'graphbrain', 'projects', hash, 'credentials.toon');
}
```

The agent procedure (Cr1) implements this via Bash for portability. Graphbrain does NOT ship a JS resolver in v0.2 — the procedure does it inline. Post-MVP enhancement: ship `scripts/lib/creds-path.js` for testability.

## Related

- **`agents/brain/cred-registrar.md`** — the agent identity / scope / rules
- **`commands/brain/creds.md`** — the procedure (Cr0–Cr7) — uses this skill as the single source of truth
- **`skills/core/creds/templates/credentials.toon`** — starter template
- **`scripts/lib/toon.js`** — TOON parser + chmod 0600 writer
- **`skills/behavioral/graphbrain/SKILL.md`** (M#11c update) — "Credential-handling protocol" section that detects cred-shaped input and proposes registration
