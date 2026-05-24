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

# === Test 14: M#3a — ingester agent + page-format skill + template ==========

for f in \
  "$CODEBRAIN_ROOT/agents/brain/ingester.md" \
  "$CODEBRAIN_ROOT/skills/ingestion/page-format/SKILL.md" \
  "$CODEBRAIN_ROOT/skills/ingestion/page-format/templates/code-page.md"
do
  [ -f "$f" ] && ok "T14: $(basename "$f") exists" || nope "T14: $(basename "$f") missing"
done

# Ingester agent frontmatter — all 7 merged-frontmatter fields present
head -1 "$CODEBRAIN_ROOT/agents/brain/ingester.md" | grep -q '^---$' \
  && ok "T14: ingester.md starts with YAML frontmatter" \
  || nope "T14: ingester.md missing frontmatter"

for field in name description tools model pattern trigger_phrases max_iterations; do
  grep -q "^${field}:" "$CODEBRAIN_ROOT/agents/brain/ingester.md" \
    && ok "T14: ingester.md has '${field}' field" \
    || nope "T14: ingester.md missing '${field}' field"
done

# max_iterations is an integer
grep -E "^max_iterations: [0-9]+$" "$CODEBRAIN_ROOT/agents/brain/ingester.md" >/dev/null \
  && ok "T14: ingester.md max_iterations is an integer" \
  || nope "T14: ingester.md max_iterations not integer"

# Rules section present + prompt-defense reference + ≥7 NEVER/ALWAYS rules
grep -q '^## Rules' "$CODEBRAIN_ROOT/agents/brain/ingester.md" \
  && ok "T14: ingester.md has Rules section" \
  || nope "T14: ingester.md missing Rules section"

grep -q 'Read the Prompt Defense Baseline' "$CODEBRAIN_ROOT/agents/brain/ingester.md" \
  && ok "T14: ingester.md has prompt-defense reference" \
  || nope "T14: ingester.md missing prompt-defense reference"

rule_count=$(grep -cE '^- \*\*(NEVER|ALWAYS)' "$CODEBRAIN_ROOT/agents/brain/ingester.md" || true)
[ "$rule_count" -ge 7 ] \
  && ok "T14: ingester.md has ≥7 self-enforcing rules ($rule_count)" \
  || nope "T14: ingester.md has only $rule_count rules (need ≥7)"

# page-format SKILL frontmatter — all 7 fields + tier:ingestion
head -1 "$CODEBRAIN_ROOT/skills/ingestion/page-format/SKILL.md" | grep -q '^---$' \
  && ok "T14: page-format SKILL.md starts with frontmatter" \
  || nope "T14: page-format SKILL.md missing frontmatter"

for field in name description origin version tier pattern related_skills; do
  grep -q "^${field}:" "$CODEBRAIN_ROOT/skills/ingestion/page-format/SKILL.md" \
    && ok "T14: page-format SKILL.md has '${field}' field" \
    || nope "T14: page-format SKILL.md missing '${field}' field"
done

grep -q "^tier: ingestion$" "$CODEBRAIN_ROOT/skills/ingestion/page-format/SKILL.md" \
  && ok "T14: page-format is tier:ingestion" \
  || nope "T14: page-format wrong tier"

# code-page template — starts with frontmatter, has 5 sections, ≥10 AGENT instructions
head -1 "$CODEBRAIN_ROOT/skills/ingestion/page-format/templates/code-page.md" | grep -q '^---$' \
  && ok "T14: code-page template starts with frontmatter" \
  || nope "T14: code-page template missing frontmatter"

for section in '## Purpose' '## Exports' '## Imports' '## Key behaviors' '## Cross-references'; do
  grep -qF "$section" "$CODEBRAIN_ROOT/skills/ingestion/page-format/templates/code-page.md" \
    && ok "T14: code-page template has '$section' section" \
    || nope "T14: code-page template missing '$section' section"
done

agent_directive_count=$(grep -c 'AGENT:' "$CODEBRAIN_ROOT/skills/ingestion/page-format/templates/code-page.md" || true)
[ "$agent_directive_count" -ge 10 ] \
  && ok "T14: code-page template has ≥10 AGENT directives ($agent_directive_count)" \
  || nope "T14: code-page template has only $agent_directive_count AGENT directives (need ≥10)"

# === Test 15: M#3a — ingest verb wiring ======================================

# Old single-line M#3 stub is gone
! grep -q '| `ingest` | not implemented | `Milestone #3 (Ingest pipeline)' "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T15: brain.md old M#3 ingest stub is gone" \
  || nope "T15: brain.md old M#3 stub still present"

! grep -q '| `ingest` | not implemented | `Milestone #3 (Ingest pipeline)' "$CODEBRAIN_ROOT/commands/codebrain.md" \
  && ok "T15: codebrain.md old M#3 ingest stub is gone" \
  || nope "T15: codebrain.md old M#3 stub still present"

# Single-file row is wired
grep -q 'ingest <single-file-path>` | \*\*implemented (M#3a)\*\*' "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T15: brain.md single-file ingest wired (M#3a)" \
  || nope "T15: brain.md single-file ingest not wired"

# Folder + no-arg rows still stubbed with correct M#3b/M#3c pointers
grep -q 'Milestone #3b (folder ingest' "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T15: brain.md folder-ingest stubbed → M#3b" \
  || nope "T15: brain.md folder pointer missing"

grep -q 'Milestone #3c (tiered auto-prioritize' "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T15: brain.md no-arg ingest stubbed → M#3c" \
  || nope "T15: brain.md no-arg pointer missing"

# Procedure section present with required headers
grep -qF '## When `$ARGUMENTS` starts with `ingest <file>`' "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T15: brain.md has 'When \$ARGUMENTS starts with ingest <file>' section" \
  || nope "T15: brain.md missing ingest procedure section"

grep -qF 'Step 0 — Argument parsing + path guards' "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T15: brain.md ingest has Step 0 (Argument parsing + path guards)" \
  || nope "T15: brain.md missing Step 0"

grep -qF 'Step 7 — Report' "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T15: brain.md ingest has Step 7 (Report)" \
  || nope "T15: brain.md missing Step 7"

# Critical sweep findings present in procedure
grep -qF 'Out-of-repo guard' "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T15: brain.md has out-of-repo guard" \
  || nope "T15: brain.md missing out-of-repo guard"

grep -qF 'Symlink guard' "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T15: brain.md has symlink guard" \
  || nope "T15: brain.md missing symlink guard"

grep -qF 'Binary-file guard' "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T15: brain.md has binary-file guard" \
  || nope "T15: brain.md missing binary-file guard"

grep -qF 'format-prefixed' "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T15: brain.md mentions format-prefixed source hash" \
  || nope "T15: brain.md missing format-prefixed hash docs"

# Alias parity: ingest procedure section is byte-identical
brain_proc=$(sed -n '/^## When `\$ARGUMENTS` starts with `ingest <file>`$/,$p' "$CODEBRAIN_ROOT/commands/brain.md")
cb_proc=$(sed -n '/^## When `\$ARGUMENTS` starts with `ingest <file>`$/,$p' "$CODEBRAIN_ROOT/commands/codebrain.md")
if [ "$brain_proc" = "$cb_proc" ] && [ -n "$brain_proc" ]; then
  ok "T15: brain.md and codebrain.md ingest procedure byte-identical"
else
  nope "T15: alias drift in ingest procedure"
fi

# npm pack includes new M#3a files
pack_list="$(cd "$CODEBRAIN_ROOT" && npm pack --dry-run 2>&1)"
echo "$pack_list" | grep -q 'agents/brain/ingester.md' \
  && ok "T15: ingester.md in npm pack" \
  || nope "T15: ingester.md missing from npm pack"

echo "$pack_list" | grep -q 'skills/ingestion/page-format/SKILL.md' \
  && ok "T15: page-format SKILL.md in npm pack" \
  || nope "T15: page-format SKILL.md missing from npm pack"

echo "$pack_list" | grep -q 'skills/ingestion/page-format/templates/code-page.md' \
  && ok "T15: code-page template in npm pack" \
  || nope "T15: code-page template missing from npm pack"

# === Test 16: M#3b — linker agent + concept-extraction skill + template =====

for f in \
  "$CODEBRAIN_ROOT/agents/brain/linker.md" \
  "$CODEBRAIN_ROOT/skills/ingestion/concept-extraction/SKILL.md" \
  "$CODEBRAIN_ROOT/skills/ingestion/concept-extraction/templates/concept-page.md"
do
  [ -f "$f" ] && ok "T16: $(basename "$f") exists" || nope "T16: $(basename "$f") missing"
done

# Linker agent frontmatter
head -1 "$CODEBRAIN_ROOT/agents/brain/linker.md" | grep -q '^---$' \
  && ok "T16: linker.md starts with frontmatter" \
  || nope "T16: linker.md missing frontmatter"

for field in name description tools model pattern trigger_phrases max_iterations; do
  grep -q "^${field}:" "$CODEBRAIN_ROOT/agents/brain/linker.md" \
    && ok "T16: linker.md has '${field}' field" \
    || nope "T16: linker.md missing '${field}' field"
done

grep -q "^pattern: Reviewer$" "$CODEBRAIN_ROOT/agents/brain/linker.md" \
  && ok "T16: linker.md pattern is Reviewer" \
  || nope "T16: linker.md wrong pattern"

grep -E "^max_iterations: [0-9]+$" "$CODEBRAIN_ROOT/agents/brain/linker.md" >/dev/null \
  && ok "T16: linker.md max_iterations is integer" \
  || nope "T16: linker.md max_iterations not integer"

grep -q '^## Rules' "$CODEBRAIN_ROOT/agents/brain/linker.md" \
  && ok "T16: linker.md has Rules section" \
  || nope "T16: linker.md missing Rules section"

grep -q 'Read the Prompt Defense Baseline' "$CODEBRAIN_ROOT/agents/brain/linker.md" \
  && ok "T16: linker.md has prompt-defense reference" \
  || nope "T16: linker.md missing prompt-defense reference"

linker_rules=$(grep -cE '^- \*\*(NEVER|ALWAYS)' "$CODEBRAIN_ROOT/agents/brain/linker.md" || true)
[ "$linker_rules" -ge 9 ] \
  && ok "T16: linker.md has ≥9 self-enforcing rules ($linker_rules)" \
  || nope "T16: linker.md only $linker_rules rules (need ≥9)"

# concept-extraction SKILL frontmatter
head -1 "$CODEBRAIN_ROOT/skills/ingestion/concept-extraction/SKILL.md" | grep -q '^---$' \
  && ok "T16: concept-extraction SKILL.md starts with frontmatter" \
  || nope "T16: concept-extraction SKILL.md missing frontmatter"

for field in name description origin version tier pattern related_skills; do
  grep -q "^${field}:" "$CODEBRAIN_ROOT/skills/ingestion/concept-extraction/SKILL.md" \
    && ok "T16: concept-extraction SKILL.md has '${field}' field" \
    || nope "T16: concept-extraction SKILL.md missing '${field}' field"
done

grep -q "^tier: ingestion$" "$CODEBRAIN_ROOT/skills/ingestion/concept-extraction/SKILL.md" \
  && ok "T16: concept-extraction is tier:ingestion" \
  || nope "T16: concept-extraction wrong tier"

grep -q "behavioral/codebrain" "$CODEBRAIN_ROOT/skills/ingestion/concept-extraction/SKILL.md" \
  && grep -q "ingestion/page-format" "$CODEBRAIN_ROOT/skills/ingestion/concept-extraction/SKILL.md" \
  && ok "T16: concept-extraction related_skills lists both expected siblings" \
  || nope "T16: concept-extraction related_skills missing expected entries"

# Concept-extraction body sections (DO extract, DO NOT extract, defer, contract, examples)
for section in 'DO extract' 'DO NOT extract' 'When uncertain' 'Concept-page contract' 'Examples'; do
  grep -qF "$section" "$CODEBRAIN_ROOT/skills/ingestion/concept-extraction/SKILL.md" \
    && ok "T16: concept-extraction has '$section' section" \
    || nope "T16: concept-extraction missing '$section' section"
done

# Concept-page template structure
head -1 "$CODEBRAIN_ROOT/skills/ingestion/concept-extraction/templates/concept-page.md" | grep -q '^---$' \
  && ok "T16: concept-page template starts with frontmatter" \
  || nope "T16: concept-page template missing frontmatter"

for section in '## Definition' '## Spans' '## Examples' '## Related'; do
  grep -qF "$section" "$CODEBRAIN_ROOT/skills/ingestion/concept-extraction/templates/concept-page.md" \
    && ok "T16: concept-page template has '$section' section" \
    || nope "T16: concept-page template missing '$section' section"
done

concept_directives=$(grep -c 'AGENT:' "$CODEBRAIN_ROOT/skills/ingestion/concept-extraction/templates/concept-page.md" || true)
[ "$concept_directives" -ge 8 ] \
  && ok "T16: concept-page template has ≥8 AGENT directives ($concept_directives)" \
  || nope "T16: concept-page template only $concept_directives AGENT directives (need ≥8)"

# Per-source-hash format (B6): sources example shows {path, hash:git:...}
grep -qE 'hash:[[:space:]]*git:' "$CODEBRAIN_ROOT/skills/ingestion/concept-extraction/templates/concept-page.md" \
  && ok "T16: concept-page template documents per-source-hash format" \
  || nope "T16: concept-page template missing per-source-hash format"

# === Test 17: M#3b — folder + linker procedure wiring =======================

grep -q 'ingest <folder/>` | \*\*implemented (M#3b)\*\*' "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T17: brain.md folder dispatch wired (M#3b)" \
  || nope "T17: brain.md folder dispatch not wired"

grep -q 'Milestone #3c (tiered auto-prioritize' "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T17: brain.md no-arg ingest still M#3c stub" \
  || nope "T17: brain.md no-arg pointer missing"

# Folder procedure section
grep -qF '## When `$ARGUMENTS` starts with `ingest <folder>`' "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T17: brain.md has folder-ingest procedure section" \
  || nope "T17: brain.md missing folder-ingest procedure"

# Critical folder procedure elements
for needle in \
  'git ls-files' \
  'Out-of-repo guard' \
  'Cost gate' \
  'auto-confirm threshold' \
  'Skip-and-report'
do
  grep -qF "$needle" "$CODEBRAIN_ROOT/commands/brain.md" \
    && ok "T17: brain.md folder procedure mentions '$needle'" \
    || nope "T17: brain.md folder procedure missing '$needle'"
done

# Linker procedure section
grep -qF '## Linker procedure (invoked after folder ingest)' "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T17: brain.md has linker procedure section" \
  || nope "T17: brain.md missing linker procedure"

# Linker procedure L1-L6
for step in 'L1 — Load inputs' 'L2 — Wire bidirectional' 'L3 — Discover concept' 'L4 — Materialize concept' 'L5 — Update derived files' 'L6 — Linker report'; do
  grep -qF "$step" "$CODEBRAIN_ROOT/commands/brain.md" \
    && ok "T17: brain.md linker procedure has '$step'" \
    || nope "T17: brain.md linker procedure missing '$step'"
done

# Inlined concept-page template + per-source-hash
grep -qF 'kind: concept' "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T17: brain.md linker procedure inlines concept template (kind: concept)" \
  || nope "T17: brain.md linker procedure missing inlined concept template"

# Alias parity: folder section (cross-platform — awk handles the boundary cleanly;
# macOS BSD head rejects `head -n -1`, GNU-only feature)
brain_folder=$(awk '/^## When `\$ARGUMENTS` starts with `ingest <folder>`$/{flag=1; print; next} /^## Linker procedure/{flag=0} flag' "$CODEBRAIN_ROOT/commands/brain.md")
cb_folder=$(awk '/^## When `\$ARGUMENTS` starts with `ingest <folder>`$/{flag=1; print; next} /^## Linker procedure/{flag=0} flag' "$CODEBRAIN_ROOT/commands/codebrain.md")
if [ "$brain_folder" = "$cb_folder" ] && [ -n "$brain_folder" ]; then
  ok "T17: brain.md and codebrain.md folder-ingest procedure byte-identical"
else
  nope "T17: alias drift in folder-ingest procedure"
fi

# Alias parity: linker section
brain_linker=$(sed -n '/^## Linker procedure (invoked after folder ingest)$/,$p' "$CODEBRAIN_ROOT/commands/brain.md")
cb_linker=$(sed -n '/^## Linker procedure (invoked after folder ingest)$/,$p' "$CODEBRAIN_ROOT/commands/codebrain.md")
if [ "$brain_linker" = "$cb_linker" ] && [ -n "$brain_linker" ]; then
  ok "T17: brain.md and codebrain.md linker procedure byte-identical"
else
  nope "T17: alias drift in linker procedure"
fi

# npm pack includes new files
pack_list="$(cd "$CODEBRAIN_ROOT" && npm pack --dry-run 2>&1)"
echo "$pack_list" | grep -q 'agents/brain/linker.md' \
  && ok "T17: linker.md in npm pack" \
  || nope "T17: linker.md missing from npm pack"

echo "$pack_list" | grep -q 'skills/ingestion/concept-extraction/SKILL.md' \
  && ok "T17: concept-extraction SKILL.md in npm pack" \
  || nope "T17: concept-extraction SKILL.md missing from npm pack"

echo "$pack_list" | grep -q 'skills/ingestion/concept-extraction/templates/concept-page.md' \
  && ok "T17: concept-page template in npm pack" \
  || nope "T17: concept-page template missing from npm pack"

# === Test 18: M#3c — planner agent shape ====================================

[ -f "$CODEBRAIN_ROOT/agents/brain/planner.md" ] \
  && ok "T18: planner.md exists" \
  || nope "T18: planner.md missing"

head -1 "$CODEBRAIN_ROOT/agents/brain/planner.md" | grep -q '^---$' \
  && ok "T18: planner.md starts with frontmatter" \
  || nope "T18: planner.md missing frontmatter"

for field in name description tools model pattern trigger_phrases max_iterations; do
  grep -q "^${field}:" "$CODEBRAIN_ROOT/agents/brain/planner.md" \
    && ok "T18: planner.md has '${field}' field" \
    || nope "T18: planner.md missing '${field}' field"
done

grep -q "^pattern: Planner$" "$CODEBRAIN_ROOT/agents/brain/planner.md" \
  && ok "T18: planner.md pattern is Planner" \
  || nope "T18: planner.md wrong pattern"

# Critical: planner is orchestration-only — must NOT have Edit or Write in tools
grep -E "^tools:.*\b(Edit|Write|MultiEdit)\b" "$CODEBRAIN_ROOT/agents/brain/planner.md" >/dev/null \
  && nope "T18: planner.md tools include Edit/Write/MultiEdit (orchestration-only violated)" \
  || ok "T18: planner.md tools list excludes Edit/Write/MultiEdit (orchestration-only)"

grep -q '^## Rules' "$CODEBRAIN_ROOT/agents/brain/planner.md" \
  && ok "T18: planner.md has Rules section" \
  || nope "T18: planner.md missing Rules section"

grep -q 'Read the Prompt Defense Baseline' "$CODEBRAIN_ROOT/agents/brain/planner.md" \
  && ok "T18: planner.md has prompt-defense reference" \
  || nope "T18: planner.md missing prompt-defense reference"

planner_rules=$(grep -cE '^- \*\*(NEVER|ALWAYS)' "$CODEBRAIN_ROOT/agents/brain/planner.md" || true)
[ "$planner_rules" -ge 7 ] \
  && ok "T18: planner.md has ≥7 self-enforcing rules ($planner_rules)" \
  || nope "T18: planner.md only $planner_rules rules (need ≥7)"

# === Test 19: M#3c — no-arg tiered ingest wiring ============================

grep -qF '**implemented (M#3c)**' "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T19: brain.md no-arg ingest wired (M#3c)" \
  || nope "T19: brain.md no-arg ingest not wired"

grep -qF '## When `$ARGUMENTS` is just `ingest`' "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T19: brain.md has tiered-ingest procedure section" \
  || nope "T19: brain.md missing tiered-ingest procedure"

# Step headers T0–T7
for step in 'T0 — Argument parsing' 'T1 — Preconditions' 'T2 — Load stack detection' 'T3 — Walk + filter' 'T4 — Group files into 3 tiers' 'T5 — Present plan' 'T6 — Per-tier loop' 'T7 — Final report'; do
  grep -qF "$step" "$CODEBRAIN_ROOT/commands/brain.md" \
    && ok "T19: brain.md tiered procedure has '$step'" \
    || nope "T19: brain.md tiered procedure missing '$step'"
done

# Tier keywords + heuristics documented
for needle in 'Tier 1' 'Tier 2' 'Tier 3' 'Uncategorized' 'src/**' 'tests/**' 'cost = count'; do
  grep -qF "$needle" "$CODEBRAIN_ROOT/commands/brain.md" \
    && ok "T19: brain.md tiered procedure mentions '$needle'" \
    || nope "T19: brain.md tiered procedure missing '$needle'"
done

# Cancel + --yes paths documented
grep -qF '`cancel`' "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T19: brain.md tiered procedure documents cancel path" \
  || nope "T19: brain.md tiered procedure missing cancel path"

grep -qF -- '--yes' "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T19: brain.md tiered procedure documents --yes path" \
  || nope "T19: brain.md tiered procedure missing --yes path"

# Alias parity (awk for cross-platform)
brain_tiered=$(awk '/^## When `\$ARGUMENTS` is just `ingest`$/{flag=1} flag' "$CODEBRAIN_ROOT/commands/brain.md")
cb_tiered=$(awk '/^## When `\$ARGUMENTS` is just `ingest`$/{flag=1} flag' "$CODEBRAIN_ROOT/commands/codebrain.md")
if [ "$brain_tiered" = "$cb_tiered" ] && [ -n "$brain_tiered" ]; then
  ok "T19: brain.md and codebrain.md tiered-ingest procedure byte-identical"
else
  nope "T19: alias drift in tiered-ingest procedure"
fi

# README onboarding updated (sweep finding C4)
grep -q 'Three-step onboarding' "$CODEBRAIN_ROOT/README.md" \
  && ok "T19: README has Three-step onboarding section" \
  || nope "T19: README missing Three-step onboarding"

grep -qE '/brain ingest[[:space:]]+# tiered' "$CODEBRAIN_ROOT/README.md" \
  && ok "T19: README documents no-arg tiered ingest" \
  || nope "T19: README missing no-arg tiered ingest documentation"

# npm pack includes planner
pack_list="$(cd "$CODEBRAIN_ROOT" && npm pack --dry-run 2>&1)"
echo "$pack_list" | grep -q 'agents/brain/planner.md' \
  && ok "T19: planner.md in npm pack" \
  || nope "T19: planner.md missing from npm pack"

# === Summary ==================================================================

total=$((pass+fail))
echo ""
echo "Summary: $pass / $total passed, $fail failed"
[ $fail -eq 0 ] && exit 0 || exit 1
