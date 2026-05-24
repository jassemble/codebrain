#!/usr/bin/env bash
# codebrain E2E install test. Pure structural validation; no LLM calls; <5s runtime.
# Covers PRD Design Decisions #28, #31, #32, #33.

set -u
set -o pipefail

# Locate the codebrain source directory (the parent of tests/).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEBRAIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CB="$CODEBRAIN_ROOT/bin/codebrain.js"

pass=0
fail=0

ok()   { pass=$((pass+1)); echo "PASS: $*"; }
nope() { fail=$((fail+1)); echo "FAIL: $*"; }

# Capture stderr/stdout silently for assertions on exit code.
run_silent() { "$@" >/dev/null 2>&1; }

# === Test 1: scaffold + version marker + commands + CLAUDE.md region =========

setup_user_repo() {
  local d
  d="$(mktemp -d)"
  ( cd "$d" && git init -q . ) || true
  echo "$d"
}

USER_REPO="$(setup_user_repo)"
( cd "$USER_REPO" && HOME="$HOME" node "$CB" init >/dev/null 2>&1 )
rc=$?
[ $rc -eq 0 ] && ok "T1: init exits 0 in a project dir" || nope "T1: init exit code was $rc"

# .brain scaffold
for d in code concepts decisions; do
  [ -d "$USER_REPO/.brain/$d" ] && ok "T1: .brain/$d/ exists" || nope "T1: .brain/$d/ missing"
done
for f in index.md log.md overview.md decisions.md status.md; do
  [ -f "$USER_REPO/.brain/$f" ] && ok "T1: .brain/$f exists" || nope "T1: .brain/$f missing"
  head -1 "$USER_REPO/.brain/$f" 2>/dev/null | grep -q '^---$' \
    && ok "T1: .brain/$f starts with frontmatter" \
    || nope "T1: .brain/$f missing frontmatter"
done

# .codebrain-version marker (PRD #33)
[ -f "$USER_REPO/.brain/.codebrain-version" ] && ok "T1: .codebrain-version marker present" || nope "T1: .codebrain-version missing"
grep -q '^0\.1\.0$' "$USER_REPO/.brain/.codebrain-version" 2>/dev/null \
  && ok "T1: .codebrain-version contains 0.1.0" \
  || nope "T1: .codebrain-version content wrong"

# Slash-command templates with version marker
for v in brain codebrain; do
  f="$USER_REPO/.claude/commands/$v.md"
  [ -f "$f" ] && ok "T1: .claude/commands/$v.md present" || nope "T1: .claude/commands/$v.md missing"
  head -1 "$f" 2>/dev/null | grep -q 'codebrain v0\.1\.0' \
    && ok "T1: $v.md has version marker" \
    || nope "T1: $v.md missing version marker"
done

# settings.local.json valid JSON
sj="$USER_REPO/.claude/settings.local.json"
[ -f "$sj" ] && ok "T1: settings.local.json written" || nope "T1: settings.local.json missing"
node -e "require('$sj')" 2>/dev/null && ok "T1: settings.local.json parses as JSON" || nope "T1: settings.local.json malformed"

# CLAUDE.md managed region
cm="$USER_REPO/CLAUDE.md"
[ -f "$cm" ] && ok "T1: CLAUDE.md created" || nope "T1: CLAUDE.md missing"
grep -q '<!-- codebrain:begin -->' "$cm" 2>/dev/null && ok "T1: CLAUDE.md has begin marker" || nope "T1: CLAUDE.md missing begin marker"
grep -q '<!-- codebrain:end -->' "$cm" 2>/dev/null && ok "T1: CLAUDE.md has end marker" || nope "T1: CLAUDE.md missing end marker"

# === Test 2: hooks ownership — non-codebrain hooks preserved =================

USER_REPO2="$(setup_user_repo)"
mkdir -p "$USER_REPO2/.claude"
cat > "$USER_REPO2/.claude/settings.local.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [{ "type": "command", "command": "echo hi" }], "id": "user:pre:my-hook", "description": "user's own hook" }
    ]
  }
}
JSON

( cd "$USER_REPO2" && HOME="$HOME" node "$CB" init >/dev/null 2>&1 )
node -e "
  const j = require('$USER_REPO2/.claude/settings.local.json');
  const arr = (j.hooks && j.hooks.PreToolUse) || [];
  const userHook = arr.find(e => e.id === 'user:pre:my-hook');
  if (!userHook) { console.error('user hook missing'); process.exit(1); }
  process.exit(0);
" 2>/dev/null && ok "T2: non-codebrain user:pre:my-hook preserved after init" || nope "T2: user hook lost"

# === Test 3: re-init non-duplication (idempotency) ===========================

# Count codebrain-owned entries before and after a second init.
USER_REPO3="$(setup_user_repo)"
( cd "$USER_REPO3" && HOME="$HOME" node "$CB" init >/dev/null 2>&1 )
count_before=$(node -e "
  const j = require('$USER_REPO3/.claude/settings.local.json');
  const hooks = j.hooks || {};
  let n = 0;
  for (const k of Object.keys(hooks)) {
    n += (hooks[k] || []).filter(e => e && typeof e.id === 'string' && e.id.startsWith('codebrain:')).length;
  }
  console.log(n);
" 2>/dev/null)

( cd "$USER_REPO3" && HOME="$HOME" node "$CB" init >/dev/null 2>&1 )
count_after=$(node -e "
  const j = require('$USER_REPO3/.claude/settings.local.json');
  const hooks = j.hooks || {};
  let n = 0;
  for (const k of Object.keys(hooks)) {
    n += (hooks[k] || []).filter(e => e && typeof e.id === 'string' && e.id.startsWith('codebrain:')).length;
  }
  console.log(n);
" 2>/dev/null)

[ "$count_before" = "$count_after" ] && ok "T3: re-init does not duplicate codebrain hooks ($count_before == $count_after)" || nope "T3: hook count drifted ($count_before -> $count_after)"

# Second init should emit SKIP lines for most files.
second_run="$(cd "$USER_REPO3" && HOME="$HOME" node "$CB" init 2>&1)"
echo "$second_run" | grep -q 'SKIP' && ok "T3: second init emits at least one SKIP" || nope "T3: idempotency not signaled"

# === Test 4: dry-run safety ==================================================

USER_REPO4="$(setup_user_repo)"
( cd "$USER_REPO4" && HOME="$HOME" node "$CB" init --dry-run >/dev/null 2>&1 )
[ ! -d "$USER_REPO4/.brain" ] && ok "T4: --dry-run did not create .brain/" || nope "T4: --dry-run wrote .brain/"
[ ! -d "$USER_REPO4/.claude" ] && ok "T4: --dry-run did not create .claude/" || nope "T4: --dry-run wrote .claude/"
[ ! -f "$USER_REPO4/CLAUDE.md" ] && ok "T4: --dry-run did not write CLAUDE.md" || nope "T4: --dry-run wrote CLAUDE.md"

# === Test 5: project-dir guard refuses to run in random cwd ==================

NON_PROJECT="$(mktemp -d)"
( cd "$NON_PROJECT" && HOME="$HOME" node "$CB" init >/dev/null 2>&1 )
rc=$?
[ $rc -eq 1 ] && ok "T5: init refuses non-project dir without --global (exit 1)" || nope "T5: init in non-project dir exited $rc (expected 1)"
[ ! -d "$NON_PROJECT/.brain" ] && ok "T5: nothing written in non-project dir" || nope "T5: init polluted non-project dir"

# === Test 6: Claude Code presence soft-check =================================

USER_REPO6="$(setup_user_repo)"
FAKE_HOME="$(mktemp -d)"   # no .claude/ inside
out="$(cd "$USER_REPO6" && HOME="$FAKE_HOME" node "$CB" init 2>&1)"
rc=$?
[ $rc -eq 0 ] && ok "T6: init succeeds even when ~/.claude missing" || nope "T6: init exit $rc when ~/.claude missing"
echo "$out" | grep -q "WARN" && ok "T6: init emits WARN when ~/.claude missing" || nope "T6: missing WARN for absent ~/.claude"

# === Test 7: backup is written when init actually modifies a file ============
# Seed with a STALE codebrain entry that init must remove — guaranteed write.
# (A file with only non-codebrain hooks would be a no-op under idempotency, no .bak.)

USER_REPO7="$(setup_user_repo)"
mkdir -p "$USER_REPO7/.claude"
cat > "$USER_REPO7/.claude/settings.local.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "X", "hooks": [], "id": "user:foo" },
      { "matcher": "Edit", "hooks": [], "id": "codebrain:stale-from-old-version" }
    ]
  }
}
JSON
( cd "$USER_REPO7" && HOME="$HOME" node "$CB" init >/dev/null 2>&1 )
[ -f "$USER_REPO7/.claude/settings.local.json.bak" ] && ok "T7: .bak written when settings.local.json is modified" || nope "T7: .bak missing"

# And confirm the stale codebrain entry was removed but the user entry survived.
node -e "
  const j = require('$USER_REPO7/.claude/settings.local.json');
  const arr = (j.hooks && j.hooks.PreToolUse) || [];
  const stale = arr.find(e => e.id === 'codebrain:stale-from-old-version');
  const user = arr.find(e => e.id === 'user:foo');
  if (stale) { console.error('stale codebrain entry not removed'); process.exit(1); }
  if (!user) { console.error('user entry lost'); process.exit(1); }
  process.exit(0);
" 2>/dev/null && ok "T7: stale codebrain entry removed, user entry survived" || nope "T7: ownership swap incorrect"

# === Test 8: CLI verbs =======================================================

vers="$(node "$CB" version 2>&1)"
[ "$vers" = "0.1.0" ] && ok "T8: 'codebrain version' prints 0.1.0" || nope "T8: version output was '$vers'"

help_out="$(node "$CB" help 2>&1)"
echo "$help_out" | grep -q 'codebrain' && ok "T8: 'codebrain help' prints usage" || nope "T8: help missing"

update_out="$(node "$CB" update 2>&1)"
echo "$update_out" | grep -q 'not yet implemented' && ok "T8: 'codebrain update' prints deferred message" || nope "T8: update stub missing"

uninstall_out="$(node "$CB" uninstall 2>&1)"
echo "$uninstall_out" | grep -q 'not yet implemented' && ok "T8: 'codebrain uninstall' prints deferred message" || nope "T8: uninstall stub missing"

bogus_rc=$( ( node "$CB" bogus-verb >/dev/null 2>&1 ); echo $? )
[ "$bogus_rc" -eq 1 ] && ok "T8: unknown verb exits 1" || nope "T8: unknown verb exit was $bogus_rc"

# === Test 9: package.json files whitelist holds ==============================
# (Light check: confirm package.json parses and files key is an array.)

node -e "
  const p = require('$CODEBRAIN_ROOT/package.json');
  if (!Array.isArray(p.files)) { console.error('files not an array'); process.exit(1); }
  if (!p.bin || !p.bin.codebrain) { console.error('bin.codebrain missing'); process.exit(1); }
  if (p.license !== 'MIT') { console.error('license not MIT'); process.exit(1); }
  process.exit(0);
" 2>/dev/null && ok "T9: package.json shape valid" || nope "T9: package.json shape invalid"

# === Test 10: M#2 skill surface ==============================================

for f in \
  "$CODEBRAIN_ROOT/skills/core/init/SKILL.md" \
  "$CODEBRAIN_ROOT/skills/core/init/templates/claude-md-schema.md" \
  "$CODEBRAIN_ROOT/skills/core/init/templates/overview-starter.md" \
  "$CODEBRAIN_ROOT/skills/core/init/templates/stack-detection.json"
do
  [ -f "$f" ] && ok "T10: $(basename "$f") exists" || nope "T10: $(basename "$f") missing"
done

head -1 "$CODEBRAIN_ROOT/skills/core/init/SKILL.md" | grep -q '^---$' \
  && ok "T10: init SKILL.md starts with YAML frontmatter" \
  || nope "T10: init SKILL.md missing frontmatter"

# Check all 7 required frontmatter fields present
for field in name description origin version tier pattern related_skills; do
  grep -q "^${field}:" "$CODEBRAIN_ROOT/skills/core/init/SKILL.md" \
    && ok "T10: init SKILL.md has '${field}' field" \
    || nope "T10: init SKILL.md missing '${field}' field"
done

# tier:core is required
grep -q "^tier: core$" "$CODEBRAIN_ROOT/skills/core/init/SKILL.md" \
  && ok "T10: init SKILL.md is tier:core" \
  || nope "T10: init SKILL.md wrong tier"

# stack-detection.json parses with expected shape
node -e "
  const j = require('$CODEBRAIN_ROOT/skills/core/init/templates/stack-detection.json');
  if (!j.version) { console.error('missing version'); process.exit(1); }
  if (!Array.isArray(j.stacks)) { console.error('stacks not an array'); process.exit(1); }
  for (const s of j.stacks) {
    if (!s.name || !Array.isArray(s.signals) || !s.detected_skill) {
      console.error('bad stack entry: ' + JSON.stringify(s));
      process.exit(1);
    }
  }
  if (j.stacks.length < 5) { console.error('stack catalog too small'); process.exit(1); }
  process.exit(0);
" 2>/dev/null \
  && ok "T10: stack-detection.json shape valid (≥5 stacks, each with name/signals/detected_skill)" \
  || nope "T10: stack-detection.json invalid shape"

# Schema block respects ≤150-line cap (PRD Design Decision #7)
schema_lines=$(wc -l < "$CODEBRAIN_ROOT/skills/core/init/templates/claude-md-schema.md")
[ "$schema_lines" -le 150 ] && ok "T10: schema block ≤150 lines ($schema_lines)" || nope "T10: schema block too long ($schema_lines lines)"

# overview-starter.md has AGENT instruction comments
grep -q "AGENT:" "$CODEBRAIN_ROOT/skills/core/init/templates/overview-starter.md" \
  && ok "T10: overview-starter.md has AGENT instructions" \
  || nope "T10: overview-starter.md missing AGENT instructions"

# === Test 11: init verb no longer stubbed; other verbs still stubbed =========

! grep -q 'init.*Milestone #2.*not yet implemented' "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T11: brain.md init verb no longer stubbed as 'Milestone #2 not yet implemented'" \
  || nope "T11: brain.md init still stubbed"

! grep -q 'init.*Milestone #2.*not yet implemented' "$CODEBRAIN_ROOT/commands/codebrain.md" \
  && ok "T11: codebrain.md init verb no longer stubbed" \
  || nope "T11: codebrain.md init still stubbed"

# Other Milestone-N verbs ARE still stubbed
for milestone in 3 5 6 7; do
  grep -q "Milestone #${milestone}" "$CODEBRAIN_ROOT/commands/brain.md" \
    && ok "T11: brain.md still has Milestone #${milestone} content (stubs preserved)" \
    || nope "T11: brain.md missing Milestone #${milestone} stub"
done

# brain.md has the full When-init procedure
grep -q "When \`\$ARGUMENTS\` is \`init\`" "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T11: brain.md has 'When \$ARGUMENTS is init' section" \
  || nope "T11: brain.md missing init agent procedure section"

grep -q "Step 1 — Preconditions" "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T11: brain.md has Step 1 (Preconditions)" \
  || nope "T11: brain.md missing Step 1"

grep -q "Step 7 — Report" "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T11: brain.md has Step 7 (Report)" \
  || nope "T11: brain.md missing Step 7"

# === Test 12: alias parity — init agent procedure identical between brain.md
# and codebrain.md. (The /brand-specific help text above the procedure
# intentionally differs — brain.md says "/brain ..." and codebrain.md says
# "/codebrain ..." — so we compare only the H2 procedure section, anchored at
# the section header, to end of file.)

brain_proc=$(sed -n '/^## When `\$ARGUMENTS` is `init`$/,$p' "$CODEBRAIN_ROOT/commands/brain.md")
cb_proc=$(sed -n '/^## When `\$ARGUMENTS` is `init`$/,$p' "$CODEBRAIN_ROOT/commands/codebrain.md")
if [ "$brain_proc" = "$cb_proc" ] && [ -n "$brain_proc" ]; then
  ok "T12: brain.md and codebrain.md init agent procedure is byte-identical"
else
  nope "T12: alias drift in init agent procedure"
fi

# === Test 13: npm pack includes new M#2 templates ============================

pack_list="$(cd "$CODEBRAIN_ROOT" && npm pack --dry-run 2>&1)"
echo "$pack_list" | grep -q 'skills/core/init/SKILL.md' \
  && ok "T13: SKILL.md in npm pack" \
  || nope "T13: SKILL.md missing from npm pack"

echo "$pack_list" | grep -q 'skills/core/init/templates/claude-md-schema.md' \
  && ok "T13: claude-md-schema.md in npm pack" \
  || nope "T13: schema template missing from npm pack"

echo "$pack_list" | grep -q 'skills/core/init/templates/overview-starter.md' \
  && ok "T13: overview-starter.md in npm pack" \
  || nope "T13: overview template missing from npm pack"

echo "$pack_list" | grep -q 'skills/core/init/templates/stack-detection.json' \
  && ok "T13: stack-detection.json in npm pack" \
  || nope "T13: stack-detection.json missing from npm pack"

# === Summary ==================================================================

total=$((pass+fail))
echo ""
echo "Summary: $pass / $total passed, $fail failed"
[ $fail -eq 0 ] && exit 0 || exit 1
