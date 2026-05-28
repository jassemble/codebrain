#!/usr/bin/env bash
# graphbrain dogfood — install-validate.sh
#
# Real-world install test. Runs `node bin/graphbrain.js init` against a
# tmp-staged copy of graphbrain itself, in a fake user repo. Verifies the
# full scaffold + hook merge + slash-command copy + CLAUDE.md managed
# region land correctly. Standalone variant of the e2e suite's T1 — but
# specifically against the install path operators will see.
#
# Runs in <10s; no LLM calls; no network.

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEBRAIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CB="$CODEBRAIN_ROOT/bin/graphbrain.js"

pass=0
fail=0

CB_VERSION="$(node -p "require('$CODEBRAIN_ROOT/package.json').version")"

ok()   { pass=$((pass+1)); echo "PASS: $*"; }
nope() { fail=$((fail+1)); echo "FAIL: $*"; }

# Setup: tmpdir simulating a user repo with .git/ so the project-dir guard passes
USER_REPO="$(mktemp -d)"
( cd "$USER_REPO" && git init -q . ) >/dev/null 2>&1 || true
ok "dogfood: staged user repo at $USER_REPO"

# Run install
out="$(cd "$USER_REPO" && HOME="$HOME" node "$CB" init 2>&1)"
rc=$?
[ $rc -eq 0 ] && ok "dogfood: graphbrain init exits 0" || nope "dogfood: graphbrain init exit was $rc"

# .brain scaffold
for d in code concepts decisions; do
  [ -d "$USER_REPO/.brain/$d" ] && ok "dogfood: .brain/$d/ exists" || nope "dogfood: .brain/$d/ missing"
done

for f in index.md log.md overview.md decisions.md status.md .graphbrain-version llms.txt; do
  [ -f "$USER_REPO/.brain/$f" ] && ok "dogfood: .brain/$f exists" || nope "dogfood: .brain/$f missing"
done

# Version marker
grep -qF "$CB_VERSION" "$USER_REPO/.brain/.graphbrain-version" 2>/dev/null \
  && ok "dogfood: .graphbrain-version is $CB_VERSION" \
  || nope "dogfood: .graphbrain-version content wrong (expected $CB_VERSION)"

# Per-verb namespaced files (M#12b)
for verb in init ingest query lint learn status spec creds; do
  dst="$USER_REPO/.claude/commands/brain/$verb.md"
  [ -f "$dst" ] && ok "dogfood: .claude/commands/brain/$verb.md copied" || nope "dogfood: .claude/commands/brain/$verb.md missing"
done

# Top-level dispatcher copied + matches source byte-for-byte
src="$CODEBRAIN_ROOT/commands/brain.md"
dst="$USER_REPO/.claude/commands/brain.md"
[ -f "$dst" ] && ok "dogfood: .claude/commands/brain.md copied" || nope "dogfood: .claude/commands/brain.md missing"
if [ -f "$src" ] && [ -f "$dst" ]; then
  diff -q "$src" "$dst" >/dev/null 2>&1 \
    && ok "dogfood: .claude/commands/brain.md matches source byte-for-byte" \
    || nope "dogfood: .claude/commands/brain.md differs from source"
fi

# settings.local.json: graphbrain hook entries land in correct shape
sj="$USER_REPO/.claude/settings.local.json"
[ -f "$sj" ] && ok "dogfood: .claude/settings.local.json written" || nope "dogfood: settings.local.json missing"

node -e "
  const j = require('$sj');
  const pre = (j.hooks && j.hooks.PreToolUse) || [];
  const post = (j.hooks && j.hooks.PostToolUse) || [];
  const guard = pre.find(e => e && e.id === 'graphbrain:pre:verified-guard');
  const stale = post.find(e => e && e.id === 'graphbrain:post:stale-detect');
  if (!guard) { console.error('graphbrain:pre:verified-guard missing'); process.exit(1); }
  if (!stale) { console.error('graphbrain:post:stale-detect missing'); process.exit(1); }
  if (guard.matcher !== 'Edit|Write|MultiEdit') { console.error('verified-guard matcher wrong'); process.exit(1); }
  if (stale.matcher !== 'Edit|Write|MultiEdit') { console.error('stale-detect matcher wrong'); process.exit(1); }
  process.exit(0);
" 2>/dev/null \
  && ok "dogfood: both graphbrain hook entries present with correct shape" \
  || nope "dogfood: hook entries malformed"

# CLAUDE.md managed region
cm="$USER_REPO/CLAUDE.md"
[ -f "$cm" ] && ok "dogfood: CLAUDE.md created" || nope "dogfood: CLAUDE.md missing"
grep -q '<!-- graphbrain:begin -->' "$cm" 2>/dev/null && ok "dogfood: CLAUDE.md has begin marker" || nope "dogfood: CLAUDE.md missing begin marker"
grep -q '<!-- graphbrain:end -->' "$cm" 2>/dev/null && ok "dogfood: CLAUDE.md has end marker" || nope "dogfood: CLAUDE.md missing end marker"

# Idempotency: second run should produce only SKIPs
second_run="$(cd "$USER_REPO" && HOME="$HOME" node "$CB" init 2>&1)"
echo "$second_run" | grep -q 'SKIP' && ok "dogfood: second init produces SKIP lines (idempotent)" || nope "dogfood: idempotency broken"

# Total
total=$((pass+fail))
echo ""
echo "Dogfood install-validate summary: $pass / $total passed, $fail failed"
[ $fail -eq 0 ] && exit 0 || exit 1
