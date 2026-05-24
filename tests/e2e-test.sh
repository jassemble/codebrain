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

# === Test 20: M#4 — hook scripts exist + CLI verb dispatches =================

for f in \
  "$CODEBRAIN_ROOT/scripts/hooks/stale-detect.js" \
  "$CODEBRAIN_ROOT/scripts/hooks/verified-guard.js" \
  "$CODEBRAIN_ROOT/scripts/hooks/lib/page-io.js"
do
  [ -f "$f" ] && ok "T20: $(basename "$f") exists" || nope "T20: $(basename "$f") missing"
done

# Shebangs on the hook entry scripts (lib is a library — no shebang needed)
head -1 "$CODEBRAIN_ROOT/scripts/hooks/stale-detect.js" | grep -q '^#!/usr/bin/env node$' \
  && ok "T20: stale-detect.js has Node shebang" \
  || nope "T20: stale-detect.js missing/wrong shebang"

head -1 "$CODEBRAIN_ROOT/scripts/hooks/verified-guard.js" | grep -q '^#!/usr/bin/env node$' \
  && ok "T20: verified-guard.js has Node shebang" \
  || nope "T20: verified-guard.js missing/wrong shebang"

# bin/codebrain.js hook verb dispatches
hook_help="$(node "$CB" hook 2>&1)"
echo "$hook_help" | grep -q 'stale-detect' \
  && ok "T20: 'codebrain hook' help lists stale-detect" \
  || nope "T20: 'codebrain hook' help missing stale-detect"

echo "$hook_help" | grep -q 'verified-guard' \
  && ok "T20: 'codebrain hook' help lists verified-guard" \
  || nope "T20: 'codebrain hook' help missing verified-guard"

bogus_rc=$( ( node "$CB" hook bogus-name </dev/null >/dev/null 2>&1 ); echo $? )
[ "$bogus_rc" -eq 1 ] && ok "T20: 'codebrain hook bogus-name' exits 1" || nope "T20: bogus subcommand exit was $bogus_rc"

# Sanity: stale-detect in an empty dir with no .brain/ exits 0 silently
empty_dir="$(mktemp -d)"
rc=$( ( cd "$empty_dir" && echo '{"tool_input":{"file_path":"foo.ts"}}' | node "$CB" hook stale-detect >/dev/null 2>&1 ); echo $? )
[ "$rc" -eq 0 ] && ok "T20: stale-detect in non-codebrain dir exits 0 silently" || nope "T20: stale-detect non-codebrain dir exit was $rc"

# Help text mentions hook
help_out="$(node "$CB" help 2>&1)"
echo "$help_out" | grep -q 'codebrain hook' \
  && ok "T20: 'codebrain help' mentions hook verb" \
  || nope "T20: help missing hook verb"

# === Test 21: M#4 — init.js writes the codebrain hook entries ================

# Run init in a tmpdir + verify settings.local.json gets the two codebrain entries
T21_REPO="$(setup_user_repo)"
( cd "$T21_REPO" && HOME="$HOME" node "$CB" init >/dev/null 2>&1 )

# PreToolUse: codebrain:pre:verified-guard
node -e "
  const j = require('$T21_REPO/.claude/settings.local.json');
  const pre = (j.hooks && j.hooks.PreToolUse) || [];
  const guard = pre.find(e => e && e.id === 'codebrain:pre:verified-guard');
  if (!guard) { console.error('verified-guard entry missing'); process.exit(1); }
  if (!guard.hooks || !guard.hooks[0] || !guard.hooks[0].command.includes('codebrain hook verified-guard')) {
    console.error('verified-guard command wrong:', JSON.stringify(guard.hooks)); process.exit(1);
  }
  if (guard.matcher !== 'Edit|Write|MultiEdit') { console.error('verified-guard matcher wrong'); process.exit(1); }
  process.exit(0);
" 2>/dev/null && ok "T21: settings.local.json has codebrain:pre:verified-guard with correct shape" || nope "T21: verified-guard entry incorrect"

# PostToolUse: codebrain:post:stale-detect
node -e "
  const j = require('$T21_REPO/.claude/settings.local.json');
  const post = (j.hooks && j.hooks.PostToolUse) || [];
  const stale = post.find(e => e && e.id === 'codebrain:post:stale-detect');
  if (!stale) { console.error('stale-detect entry missing'); process.exit(1); }
  if (!stale.hooks[0].command.includes('codebrain hook stale-detect')) {
    console.error('stale-detect command wrong'); process.exit(1);
  }
  process.exit(0);
" 2>/dev/null && ok "T21: settings.local.json has codebrain:post:stale-detect with correct shape" || nope "T21: stale-detect entry incorrect"

# Re-init: no duplication of codebrain hooks
( cd "$T21_REPO" && HOME="$HOME" node "$CB" init >/dev/null 2>&1 )
codebrain_hook_count=$(node -e "
  const j = require('$T21_REPO/.claude/settings.local.json');
  const all = Object.values(j.hooks || {}).flat();
  console.log(all.filter(e => e && typeof e.id === 'string' && e.id.startsWith('codebrain:')).length);
" 2>/dev/null)
[ "$codebrain_hook_count" = "2" ] && ok "T21: re-init keeps exactly 2 codebrain hooks (no duplication)" || nope "T21: codebrain hook count after re-init was $codebrain_hook_count (expected 2)"

# Pre-existing non-codebrain hook + stale codebrain entry → init preserves non-codebrain + cleans codebrain
T21B_REPO="$(setup_user_repo)"
mkdir -p "$T21B_REPO/.claude"
cat > "$T21B_REPO/.claude/settings.local.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [{ "type": "command", "command": "echo user" }], "id": "user:my-hook" },
      { "matcher": "Edit", "hooks": [], "id": "codebrain:stale-from-old-version" }
    ]
  }
}
JSON
( cd "$T21B_REPO" && HOME="$HOME" node "$CB" init >/dev/null 2>&1 )
node -e "
  const j = require('$T21B_REPO/.claude/settings.local.json');
  const pre = (j.hooks && j.hooks.PreToolUse) || [];
  const user = pre.find(e => e.id === 'user:my-hook');
  const stale = pre.find(e => e.id === 'codebrain:stale-from-old-version');
  const guard = pre.find(e => e.id === 'codebrain:pre:verified-guard');
  if (!user) { console.error('user:my-hook lost'); process.exit(1); }
  if (stale) { console.error('codebrain:stale-from-old-version not removed'); process.exit(1); }
  if (!guard) { console.error('codebrain:pre:verified-guard not added'); process.exit(1); }
  process.exit(0);
" 2>/dev/null && ok "T21: init preserves user hooks + removes stale codebrain entries + adds current" || nope "T21: id-prefix ownership broken"

# === Test 22: M#4 — hook script behavior on fixture .brain/ ==================

# Fixture: a fake brain with one code page and one concept page referencing the source
T22_DIR="$(mktemp -d)"
mkdir -p "$T22_DIR/.brain/code/src" "$T22_DIR/.brain/concepts" "$T22_DIR/src"
echo '0.1.0' > "$T22_DIR/.brain/.codebrain-version"
echo 'export function foo() {}' > "$T22_DIR/src/auth.ts"

# Fake code page (FRESH)
cat > "$T22_DIR/.brain/code/src/auth.ts.md" <<'EOF'
---
kind: code
status: FRESH
source: src/auth.ts
source_hash: git:abc1234
last_ingested: 2026-05-24
ingested_by: claude-test
tokens: 100
---

# src/auth.ts

## Purpose
Test fixture.
EOF

# Fake concept page with wikilink to the code page
cat > "$T22_DIR/.brain/concepts/auth-flow.md" <<'EOF'
---
kind: concept
status: FRESH
name: auth-flow
last_ingested: 2026-05-24
ingested_by: claude-test
tokens: 80
sources:
  - path: src/auth.ts
    hash: git:abc1234
---

# Auth flow

## Definition
A concept referencing [[code/src/auth.ts]] via wikilink AND via sources frontmatter.

## Spans
- [[code/src/auth.ts]] — the auth module

## Examples
_(none)_

## Related
_(none yet)_
EOF

# (a) stale-detect: flip both pages on edit of src/auth.ts
( cd "$T22_DIR" && echo '{"tool_input":{"file_path":"src/auth.ts"}}' | node "$CB" hook stale-detect >/dev/null 2>&1 )
grep -q '^status: STALE$' "$T22_DIR/.brain/code/src/auth.ts.md" \
  && ok "T22: stale-detect flipped code page to STALE on source edit" \
  || nope "T22: stale-detect didn't flip code page"

grep -q '^status: STALE$' "$T22_DIR/.brain/concepts/auth-flow.md" \
  && ok "T22: stale-detect flipped concept page to STALE (referenced source)" \
  || nope "T22: stale-detect didn't flip concept page via wikilink/sources"

# (b) stale-detect: untracked source → no changes
T22B_DIR="$(mktemp -d)"
mkdir -p "$T22B_DIR/.brain/code"
echo '0.1.0' > "$T22B_DIR/.brain/.codebrain-version"
rc=$( ( cd "$T22B_DIR" && echo '{"tool_input":{"file_path":"src/other.ts"}}' | node "$CB" hook stale-detect >/dev/null 2>&1 ); echo $? )
[ "$rc" -eq 0 ] && ok "T22: stale-detect on untracked source exits 0" || nope "T22: stale-detect untracked exit was $rc"

# (c) verified-guard: VERIFIED page, no --force → exit 2
T22C_DIR="$(mktemp -d)"
mkdir -p "$T22C_DIR/.brain/code/src"
echo '0.1.0' > "$T22C_DIR/.brain/.codebrain-version"
cat > "$T22C_DIR/.brain/code/src/locked.ts.md" <<'EOF'
---
kind: code
status: VERIFIED
source: src/locked.ts
source_hash: git:xxxxx
last_ingested: 2026-05-24
ingested_by: claude-test
tokens: 50
---

# src/locked.ts

## Purpose
Protected.
EOF
rc=$( ( cd "$T22C_DIR" && echo '{"tool_input":{"file_path":".brain/code/src/locked.ts.md"}}' | node "$CB" hook verified-guard 2>/dev/null ); echo $? )
[ "$rc" -eq 2 ] && ok "T22: verified-guard blocks VERIFIED page without --force (exit 2)" || nope "T22: verified-guard exit was $rc (expected 2)"

# (d) verified-guard: same page with --force → exit 0
rc=$( ( cd "$T22C_DIR" && echo '{"tool_input":{"file_path":".brain/code/src/locked.ts.md","args":"--force"}}' | node "$CB" hook verified-guard 2>/dev/null ); echo $? )
[ "$rc" -eq 0 ] && ok "T22: verified-guard allows VERIFIED page when --force in payload" || nope "T22: verified-guard --force not honored (exit $rc)"

# (e) verified-guard: target outside .brain/ → exit 0
rc=$( ( cd "$T22C_DIR" && echo '{"tool_input":{"file_path":"src/locked.ts"}}' | node "$CB" hook verified-guard 2>/dev/null ); echo $? )
[ "$rc" -eq 0 ] && ok "T22: verified-guard ignores files outside .brain/" || nope "T22: verified-guard wrongly cared about non-.brain/ path"

# (f) verified-guard: FRESH page → exit 0
T22F_DIR="$(mktemp -d)"
mkdir -p "$T22F_DIR/.brain/code/src"
echo '0.1.0' > "$T22F_DIR/.brain/.codebrain-version"
cat > "$T22F_DIR/.brain/code/src/free.ts.md" <<'EOF'
---
kind: code
status: FRESH
source: src/free.ts
source_hash: git:yyyyy
last_ingested: 2026-05-24
ingested_by: claude-test
tokens: 50
---

# src/free.ts

## Purpose
Open.
EOF
rc=$( ( cd "$T22F_DIR" && echo '{"tool_input":{"file_path":".brain/code/src/free.ts.md"}}' | node "$CB" hook verified-guard 2>/dev/null ); echo $? )
[ "$rc" -eq 0 ] && ok "T22: verified-guard allows non-VERIFIED .brain/ pages" || nope "T22: verified-guard wrongly blocked FRESH page"

# (g) npm pack includes new files
pack_list="$(cd "$CODEBRAIN_ROOT" && npm pack --dry-run 2>&1)"
echo "$pack_list" | grep -q 'scripts/hooks/stale-detect.js' \
  && ok "T22: stale-detect.js in npm pack" \
  || nope "T22: stale-detect.js missing from npm pack"

echo "$pack_list" | grep -q 'scripts/hooks/verified-guard.js' \
  && ok "T22: verified-guard.js in npm pack" \
  || nope "T22: verified-guard.js missing from npm pack"

echo "$pack_list" | grep -q 'scripts/hooks/lib/page-io.js' \
  && ok "T22: lib/page-io.js in npm pack" \
  || nope "T22: lib/page-io.js missing from npm pack"

# === Test 23: M#3d — 4 detected/* skills + 4 templates =======================

for stack in react python go typescript; do
  skill_file="$CODEBRAIN_ROOT/skills/detected/${stack}/SKILL.md"
  template_file="$CODEBRAIN_ROOT/skills/detected/${stack}/templates/code-page-${stack}-extras.md"

  [ -f "$skill_file" ] && ok "T23: detected/${stack}/SKILL.md exists" || nope "T23: detected/${stack}/SKILL.md missing"
  [ -f "$template_file" ] && ok "T23: detected/${stack}/templates/code-page-${stack}-extras.md exists" || nope "T23: detected/${stack} template missing"

  # Frontmatter shape
  head -1 "$skill_file" | grep -q '^---$' \
    && ok "T23: detected/${stack} SKILL.md starts with frontmatter" \
    || nope "T23: detected/${stack} SKILL.md missing frontmatter"

  # All 7 base fields + detect + applies_to_extensions
  for field in name description origin version tier pattern related_skills detect applies_to_extensions; do
    grep -q "^${field}:" "$skill_file" \
      && ok "T23: detected/${stack} SKILL.md has '${field}' field" \
      || nope "T23: detected/${stack} SKILL.md missing '${field}' field"
  done

  grep -q "^tier: detected$" "$skill_file" \
    && ok "T23: detected/${stack} is tier:detected" \
    || nope "T23: detected/${stack} wrong tier"

  # Template has ≥4 AGENT directives
  directives=$(grep -c 'AGENT:' "$template_file" || true)
  [ "$directives" -ge 4 ] \
    && ok "T23: detected/${stack} template has ≥4 AGENT directives ($directives)" \
    || nope "T23: detected/${stack} template only $directives AGENT directives (need ≥4)"
done

# npm pack includes all 8 new files
pack_list="$(cd "$CODEBRAIN_ROOT" && npm pack --dry-run 2>&1)"
for stack in react python go typescript; do
  echo "$pack_list" | grep -q "skills/detected/${stack}/SKILL.md" \
    && ok "T23: detected/${stack} SKILL.md in npm pack" \
    || nope "T23: detected/${stack} SKILL.md missing from npm pack"

  echo "$pack_list" | grep -q "skills/detected/${stack}/templates/code-page-${stack}-extras.md" \
    && ok "T23: detected/${stack} template in npm pack" \
    || nope "T23: detected/${stack} template missing from npm pack"
done

# === Test 24: M#3d — registry.json populated ================================

node -e "
  const r = require('$CODEBRAIN_ROOT/skills/registry.json');
  const expected = ['detected/react', 'detected/typescript', 'detected/python', 'detected/go'];
  for (const k of expected) {
    if (!r.skills[k]) { console.error('missing skill:', k); process.exit(1); }
    if (r.skills[k].tier !== 'detected') { console.error('wrong tier:', k); process.exit(1); }
    if (!Array.isArray(r.skills[k].detect)) { console.error('detect not array:', k); process.exit(1); }
    if (!Array.isArray(r.skills[k].applies_to_extensions)) { console.error('applies_to_extensions not array:', k); process.exit(1); }
    if (r.skills[k].applies_to_extensions.length === 0) { console.error('applies_to_extensions empty:', k); process.exit(1); }
  }
  process.exit(0);
" 2>/dev/null \
  && ok "T24: registry.json has 4 detected entries with correct shape" \
  || nope "T24: registry.json detected entries malformed or missing"

# Specific applies_to_extensions assertions
node -e "
  const r = require('$CODEBRAIN_ROOT/skills/registry.json');
  if (!r.skills['detected/react'].applies_to_extensions.includes('.tsx')) { console.error('react missing .tsx'); process.exit(1); }
  if (!r.skills['detected/typescript'].applies_to_extensions.includes('.tsx')) { console.error('typescript missing .tsx'); process.exit(1); }
  if (!r.skills['detected/python'].applies_to_extensions.includes('.py')) { console.error('python missing .py'); process.exit(1); }
  if (!r.skills['detected/go'].applies_to_extensions.includes('.go')) { console.error('go missing .go'); process.exit(1); }
  process.exit(0);
" 2>/dev/null \
  && ok "T24: registry.json applies_to_extensions are correct per stack" \
  || nope "T24: applies_to_extensions assignments wrong"

# README.md documents applies_to_extensions
grep -qF 'applies_to_extensions' "$CODEBRAIN_ROOT/skills/README.md" \
  && ok "T24: skills/README.md documents applies_to_extensions field" \
  || nope "T24: skills/README.md missing applies_to_extensions docs"

# === Test 25: M#3d — brain.md Step 4b + alias parity ========================

grep -qF 'Step 4b — Stack-aware extras' "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T25: brain.md has Step 4b (Stack-aware extras)" \
  || nope "T25: brain.md missing Step 4b"

# All 4 detected sub-sections present
for stack in react typescript python go; do
  grep -qF "detected/${stack} extras" "$CODEBRAIN_ROOT/commands/brain.md" \
    && ok "T25: brain.md Step 4b has detected/${stack} sub-section" \
    || nope "T25: brain.md Step 4b missing detected/${stack} sub-section"
done

# Critical sections per stack present in the inlined block
for section in 'Component' 'Hooks' 'Effects' 'Public API' 'Dunder methods' 'Receivers' 'Build tags' 'Types & Interfaces' 'Generics'; do
  grep -qF "$section" "$CODEBRAIN_ROOT/commands/brain.md" \
    && ok "T25: brain.md Step 4b inlines '$section' section" \
    || nope "T25: brain.md Step 4b missing '$section' section"
done

# Alias parity — Step 4b through end of Step 5 boundary
brain_4b=$(awk '/^\*\*Step 4b — Stack-aware extras\*\*/{flag=1} /^\*\*Step 5 — Write the page\*\*/{flag=0} flag' "$CODEBRAIN_ROOT/commands/brain.md")
cb_4b=$(awk '/^\*\*Step 4b — Stack-aware extras\*\*/{flag=1} /^\*\*Step 5 — Write the page\*\*/{flag=0} flag' "$CODEBRAIN_ROOT/commands/codebrain.md")
if [ "$brain_4b" = "$cb_4b" ] && [ -n "$brain_4b" ]; then
  ok "T25: brain.md and codebrain.md Step 4b byte-identical"
else
  nope "T25: alias drift in Step 4b"
fi

# === Test 26: M#5 — query agent + core/query skill ==========================

[ -f "$CODEBRAIN_ROOT/agents/brain/query.md" ] \
  && ok "T26: query.md agent exists" \
  || nope "T26: query.md agent missing"

head -1 "$CODEBRAIN_ROOT/agents/brain/query.md" | grep -q '^---$' \
  && ok "T26: query.md starts with frontmatter" \
  || nope "T26: query.md missing frontmatter"

for field in name description tools model pattern trigger_phrases max_iterations; do
  grep -q "^${field}:" "$CODEBRAIN_ROOT/agents/brain/query.md" \
    && ok "T26: query.md has '${field}' field" \
    || nope "T26: query.md missing '${field}' field"
done

grep -q "^pattern: Researcher$" "$CODEBRAIN_ROOT/agents/brain/query.md" \
  && ok "T26: query.md pattern is Researcher" \
  || nope "T26: query.md wrong pattern"

# Critical: query has NO write tools (Edit/Write/MultiEdit) — delegates to ingester
grep -E "^tools:.*\b(Edit|Write|MultiEdit)\b" "$CODEBRAIN_ROOT/agents/brain/query.md" >/dev/null \
  && nope "T26: query.md tools include Edit/Write/MultiEdit (delegate-to-ingester violated)" \
  || ok "T26: query.md tools list excludes Edit/Write/MultiEdit (delegate-to-ingester)"

grep -q '^## Rules' "$CODEBRAIN_ROOT/agents/brain/query.md" \
  && ok "T26: query.md has Rules section" \
  || nope "T26: query.md missing Rules section"

grep -q 'Read the Prompt Defense Baseline' "$CODEBRAIN_ROOT/agents/brain/query.md" \
  && ok "T26: query.md has prompt-defense reference" \
  || nope "T26: query.md missing prompt-defense reference"

query_rules=$(grep -cE '^- \*\*(NEVER|ALWAYS)' "$CODEBRAIN_ROOT/agents/brain/query.md" || true)
[ "$query_rules" -ge 9 ] \
  && ok "T26: query.md has ≥9 self-enforcing rules ($query_rules)" \
  || nope "T26: query.md only $query_rules rules (need ≥9)"

# query SKILL
[ -f "$CODEBRAIN_ROOT/skills/core/query/SKILL.md" ] \
  && ok "T26: core/query SKILL.md exists" \
  || nope "T26: core/query SKILL.md missing"

head -1 "$CODEBRAIN_ROOT/skills/core/query/SKILL.md" | grep -q '^---$' \
  && ok "T26: core/query SKILL.md starts with frontmatter" \
  || nope "T26: core/query SKILL.md missing frontmatter"

for field in name description origin version tier pattern related_skills; do
  grep -q "^${field}:" "$CODEBRAIN_ROOT/skills/core/query/SKILL.md" \
    && ok "T26: core/query SKILL.md has '${field}' field" \
    || nope "T26: core/query SKILL.md missing '${field}' field"
done

grep -q "^tier: core$" "$CODEBRAIN_ROOT/skills/core/query/SKILL.md" \
  && ok "T26: core/query is tier:core" \
  || nope "T26: core/query wrong tier"

# Required body sections
for section in 'When to Activate' 'Output Contract' 'Candidate-Selection Criteria' 'Freshness Model' 'Citation Format' 'Page-Cap Discipline' 'Examples'; do
  grep -qF "$section" "$CODEBRAIN_ROOT/skills/core/query/SKILL.md" \
    && ok "T26: core/query SKILL.md has '$section' section" \
    || nope "T26: core/query SKILL.md missing '$section' section"
done

# npm pack inclusion
pack_list="$(cd "$CODEBRAIN_ROOT" && npm pack --dry-run 2>&1)"
echo "$pack_list" | grep -q 'agents/brain/query.md' \
  && ok "T26: query.md in npm pack" \
  || nope "T26: query.md missing from npm pack"

echo "$pack_list" | grep -q 'skills/core/query/SKILL.md' \
  && ok "T26: core/query SKILL.md in npm pack" \
  || nope "T26: core/query SKILL.md missing from npm pack"

# === Test 27: M#5 — query procedure wiring ==================================

grep -qF '**implemented (M#5)**' "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T27: brain.md query wired (M#5)" \
  || nope "T27: brain.md query not wired"

grep -qF '## When `$ARGUMENTS` starts with `query`' "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T27: brain.md has query procedure section" \
  || nope "T27: brain.md missing query procedure"

# Step headers Q0-Q7
for q in 'Q0 — Argument parsing' 'Q1 — Preconditions' 'Q2 — Read the index' 'Q3 — Select 1' 'Q4 — Freshness check' 'Q5 — Refresh STALE' 'Q6 — Read the candidate' 'Q7 — Output'; do
  grep -qF "$q" "$CODEBRAIN_ROOT/commands/brain.md" \
    && ok "T27: brain.md query procedure has '$q'" \
    || nope "T27: brain.md query procedure missing '$q'"
done

# Critical keywords/concepts
for needle in 'pointer-first' 'hash compare' 'promote' '[[code/' 'src/api/auth.ts:42' 'NEVER fabricate'; do
  grep -qF "$needle" "$CODEBRAIN_ROOT/commands/brain.md" \
    && ok "T27: brain.md query procedure mentions '$needle'" \
    || nope "T27: brain.md query procedure missing '$needle'"
done

# Flags documented
grep -qF -- '--thorough' "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T27: brain.md query procedure documents --thorough" \
  || nope "T27: brain.md query procedure missing --thorough"

grep -qF -- '--no-refresh' "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T27: brain.md query procedure documents --no-refresh" \
  || nope "T27: brain.md query procedure missing --no-refresh"

# Log prefix
grep -qF '[YYYY-MM-DD] query |' "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T27: brain.md query procedure documents grep-parseable log prefix" \
  || nope "T27: brain.md query procedure missing log prefix"

# Alias parity for query section
brain_query=$(awk '/^## When `\$ARGUMENTS` starts with `query`$/{flag=1} flag' "$CODEBRAIN_ROOT/commands/brain.md")
cb_query=$(awk '/^## When `\$ARGUMENTS` starts with `query`$/{flag=1} flag' "$CODEBRAIN_ROOT/commands/codebrain.md")
if [ "$brain_query" = "$cb_query" ] && [ -n "$brain_query" ]; then
  ok "T27: brain.md and codebrain.md query procedure byte-identical"
else
  nope "T27: alias drift in query procedure"
fi

# === Summary ==================================================================

total=$((pass+fail))
echo ""
echo "Summary: $pass / $total passed, $fail failed"
[ $fail -eq 0 ] && exit 0 || exit 1
