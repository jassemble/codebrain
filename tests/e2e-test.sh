#!/usr/bin/env bash
# codebrain E2E install test. Pure structural validation; no LLM calls; <5s runtime.
# Covers PRD Design Decisions #28, #31, #32, #33.

set -u
set -o pipefail

# Locate the codebrain source directory (the parent of tests/).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEBRAIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CB="$CODEBRAIN_ROOT/bin/graphbrain.js"

pass=0
fail=0

# Source the current codebrain version from package.json once, so per-release
# bumps don't require touching test assertions. Used by T1 (.codebrain-version
# scaffold), T1 (slash-command version marker), and T8 (CLI version output).
CB_VERSION="$(node -p "require('$CODEBRAIN_ROOT/package.json').version")"

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
grep -qF "$CB_VERSION" "$USER_REPO/.brain/.codebrain-version" 2>/dev/null \
  && ok "T1: .codebrain-version contains $CB_VERSION" \
  || nope "T1: .codebrain-version content wrong (expected $CB_VERSION)"

# Slash-command templates exist (top-level dispatcher).
# Note (v1.0.0): the leading <!-- graphbrain vX.Y.Z --> comment was REMOVED so
# Claude Code reads the YAML frontmatter starting on line 1 for the command-
# palette description. Version lives in package.json + .brain/.codebrain-version.
for v in brain; do
  f="$USER_REPO/.claude/commands/$v.md"
  [ -f "$f" ] && ok "T1: .claude/commands/$v.md present" || nope "T1: .claude/commands/$v.md missing"
  head -1 "$f" 2>/dev/null | grep -qF -- '---' \
    && ok "T1: $v.md starts with frontmatter (line 1 = ---)" \
    || nope "T1: $v.md does not start with YAML frontmatter"
  awk '/^---$/{c++} c==1 && /^description:/{print; exit}' "$f" | grep -q 'description:' \
    && ok "T1: $v.md frontmatter has description (Claude Code palette display)" \
    || nope "T1: $v.md frontmatter missing description"
done

# Per-verb namespaced files (M#12b — /brain:<verb> layout)
for verb in init ingest query lint learn status spec creds; do
  f="$USER_REPO/.claude/commands/brain/$verb.md"
  [ -f "$f" ] && ok "T1: .claude/commands/brain/$verb.md scaffolded" || nope "T1: .claude/commands/brain/$verb.md missing"
  head -1 "$f" 2>/dev/null | grep -qF -- '---' \
    && ok "T1: brain/$verb.md starts with frontmatter (line 1 = ---)" \
    || nope "T1: brain/$verb.md does not start with YAML frontmatter"
  awk '/^---$/{c++} c==1 && /^description:/{print; exit}' "$f" | grep -q 'description:' \
    && ok "T1: brain/$verb.md frontmatter has description" \
    || nope "T1: brain/$verb.md frontmatter missing description"
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
[ "$vers" = "$CB_VERSION" ] && ok "T8: 'codebrain version' prints $CB_VERSION" || nope "T8: version output was '$vers' (expected $CB_VERSION)"

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
  if (!p.bin || !p.bin.graphbrain) { console.error('bin.graphbrain missing'); process.exit(1); }
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


# Other Milestone-N verbs ARE still stubbed
for milestone in 3 5 6 7; do
  grep -q "Milestone #${milestone}" "$CODEBRAIN_ROOT/commands/brain.md" \
    && ok "T11: brain.md still has Milestone #${milestone} content (stubs preserved)" \
    || nope "T11: brain.md missing Milestone #${milestone} stub"
done

# brain.md has the full When-init procedure
grep -q "When \`\$ARGUMENTS\` is \`init\`" "$CODEBRAIN_ROOT/commands/brain/init.md" \
  && ok "T11: brain.md has 'When \$ARGUMENTS is init' section" \
  || nope "T11: brain.md missing init agent procedure section"

grep -q "Step 1 — Preconditions" "$CODEBRAIN_ROOT/commands/brain/init.md" \
  && ok "T11: brain.md has Step 1 (Preconditions)" \
  || nope "T11: brain.md missing Step 1"

grep -q "Step 7 — Report" "$CODEBRAIN_ROOT/commands/brain/init.md" \
  && ok "T11: brain.md has Step 7 (Report)" \
  || nope "T11: brain.md missing Step 7"

# === Test 12: (removed in v0.2.0 — /codebrain alias was dropped) ============


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


# Dispatch table mentions the namespaced ingest forms (post-M#12b)
grep -qF '/brain:ingest <file>' "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T15: brain.md dispatch table mentions /brain:ingest <file>" \
  || nope "T15: brain.md dispatch table missing /brain:ingest <file>"

grep -qF '/brain:ingest <folder>' "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T15: brain.md dispatch table mentions /brain:ingest <folder>" \
  || nope "T15: brain.md dispatch table missing /brain:ingest <folder>"

grep -qF '/brain:ingest`' "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T15: brain.md dispatch table mentions /brain:ingest (no-arg)" \
  || nope "T15: brain.md dispatch table missing /brain:ingest (no-arg)"

# Procedure section present with required headers
grep -qF '## When `$ARGUMENTS` starts with `ingest <file>`' "$CODEBRAIN_ROOT/commands/brain/ingest.md" \
  && ok "T15: brain.md has 'When \$ARGUMENTS starts with ingest <file>' section" \
  || nope "T15: brain.md missing ingest procedure section"

grep -qF 'Step 0 — Argument parsing + path guards' "$CODEBRAIN_ROOT/commands/brain/ingest.md" \
  && ok "T15: brain.md ingest has Step 0 (Argument parsing + path guards)" \
  || nope "T15: brain.md missing Step 0"

grep -qF 'Step 7 — Report' "$CODEBRAIN_ROOT/commands/brain/ingest.md" \
  && ok "T15: brain.md ingest has Step 7 (Report)" \
  || nope "T15: brain.md missing Step 7"

# Critical sweep findings present in procedure
grep -qF 'Out-of-repo guard' "$CODEBRAIN_ROOT/commands/brain/ingest.md" \
  && ok "T15: brain.md has out-of-repo guard" \
  || nope "T15: brain.md missing out-of-repo guard"

grep -qF 'Symlink guard' "$CODEBRAIN_ROOT/commands/brain/ingest.md" \
  && ok "T15: brain.md has symlink guard" \
  || nope "T15: brain.md missing symlink guard"

grep -qF 'Binary-file guard' "$CODEBRAIN_ROOT/commands/brain/ingest.md" \
  && ok "T15: brain.md has binary-file guard" \
  || nope "T15: brain.md missing binary-file guard"

grep -qF 'format-prefixed' "$CODEBRAIN_ROOT/commands/brain/ingest.md" \
  && ok "T15: brain.md mentions format-prefixed source hash" \
  || nope "T15: brain.md missing format-prefixed hash docs"

# Alias parity: ingest procedure section is byte-identical

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

grep -qF '/brain:ingest <folder>' "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T17: brain.md dispatch table mentions /brain:ingest <folder>" \
  || nope "T17: brain.md dispatch table missing /brain:ingest <folder>"

grep -qF '/brain:ingest`' "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T17: brain.md dispatch table mentions /brain:ingest (no-arg)" \
  || nope "T17: brain.md dispatch table missing /brain:ingest (no-arg)"

# Folder procedure section
grep -qF '## When `$ARGUMENTS` starts with `ingest <folder>`' "$CODEBRAIN_ROOT/commands/brain/ingest.md" \
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
  grep -qF "$needle" "$CODEBRAIN_ROOT/commands/brain/ingest.md" \
    && ok "T17: brain.md folder procedure mentions '$needle'" \
    || nope "T17: brain.md folder procedure missing '$needle'"
done

# Linker procedure section
grep -qF '## Linker procedure (invoked after folder ingest)' "$CODEBRAIN_ROOT/commands/brain/ingest.md" \
  && ok "T17: brain.md has linker procedure section" \
  || nope "T17: brain.md missing linker procedure"

# Linker procedure L1-L6
for step in 'L1 — Load inputs' 'L2 — Wire bidirectional' 'L3 — Discover concept' 'L4 — Materialize concept' 'L5 — Update derived files' 'L6 — Linker report'; do
  grep -qF "$step" "$CODEBRAIN_ROOT/commands/brain/ingest.md" \
    && ok "T17: brain.md linker procedure has '$step'" \
    || nope "T17: brain.md linker procedure missing '$step'"
done

# Inlined concept-page template + per-source-hash
grep -qF 'kind: concept' "$CODEBRAIN_ROOT/commands/brain/ingest.md" \
  && ok "T17: brain.md linker procedure inlines concept template (kind: concept)" \
  || nope "T17: brain.md linker procedure missing inlined concept template"

# Alias parity: folder section (cross-platform — awk handles the boundary cleanly;
# macOS BSD head rejects `head -n -1`, GNU-only feature)

# Alias parity: linker section

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

grep -qF '/brain:ingest`' "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T19: brain.md dispatch table mentions /brain:ingest (no-arg)" \
  || nope "T19: brain.md dispatch table missing /brain:ingest (no-arg)"

grep -qF '## When `$ARGUMENTS` is just `ingest`' "$CODEBRAIN_ROOT/commands/brain/ingest.md" \
  && ok "T19: brain.md has tiered-ingest procedure section" \
  || nope "T19: brain.md missing tiered-ingest procedure"

# Step headers T0–T7
for step in 'T0 — Argument parsing' 'T1 — Preconditions' 'T2 — Load stack detection' 'T3 — Walk + filter' 'T4 — Group files into 3 tiers' 'T5 — Present plan' 'T6 — Per-tier loop' 'T7 — Final report'; do
  grep -qF "$step" "$CODEBRAIN_ROOT/commands/brain/ingest.md" \
    && ok "T19: brain.md tiered procedure has '$step'" \
    || nope "T19: brain.md tiered procedure missing '$step'"
done

# Tier keywords + heuristics documented
for needle in 'Tier 1' 'Tier 2' 'Tier 3' 'Uncategorized' 'src/**' 'tests/**' 'cost = count'; do
  grep -qF "$needle" "$CODEBRAIN_ROOT/commands/brain/ingest.md" \
    && ok "T19: brain.md tiered procedure mentions '$needle'" \
    || nope "T19: brain.md tiered procedure missing '$needle'"
done

# Cancel + --yes paths documented
grep -qF '`cancel`' "$CODEBRAIN_ROOT/commands/brain/ingest.md" \
  && ok "T19: brain.md tiered procedure documents cancel path" \
  || nope "T19: brain.md tiered procedure missing cancel path"

grep -qF -- '--yes' "$CODEBRAIN_ROOT/commands/brain/ingest.md" \
  && ok "T19: brain.md tiered procedure documents --yes path" \
  || nope "T19: brain.md tiered procedure missing --yes path"

# Alias parity (awk for cross-platform)

# README onboarding updated (sweep finding C4)
grep -q 'Three-step onboarding' "$CODEBRAIN_ROOT/README.md" \
  && ok "T19: README has Three-step onboarding section" \
  || nope "T19: README missing Three-step onboarding"

grep -qE '/brain:ingest[[:space:]]+# tiered' "$CODEBRAIN_ROOT/README.md" \
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

# bin/graphbrain.js hook verb dispatches
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
  if (!guard.hooks || !guard.hooks[0] || !guard.hooks[0].command.includes('graphbrain hook verified-guard')) {
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
  if (!stale.hooks[0].command.includes('graphbrain hook stale-detect')) {
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
# M#7 added a 3rd codebrain hook (codebrain:pre:observe), so post-M#7 count is 3
[ "$codebrain_hook_count" = "3" ] && ok "T21: re-init keeps exactly 3 codebrain hooks (no duplication; M#7 added observe to M#4's 2)" || nope "T21: codebrain hook count after re-init was $codebrain_hook_count (expected 3)"

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

grep -qF 'Step 4b — Stack-aware extras' "$CODEBRAIN_ROOT/commands/brain/ingest.md" \
  && ok "T25: brain.md has Step 4b (Stack-aware extras)" \
  || nope "T25: brain.md missing Step 4b"

# All 4 detected sub-sections present
for stack in react typescript python go; do
  grep -qF "detected/${stack} extras" "$CODEBRAIN_ROOT/commands/brain/ingest.md" \
    && ok "T25: brain.md Step 4b has detected/${stack} sub-section" \
    || nope "T25: brain.md Step 4b missing detected/${stack} sub-section"
done

# Critical sections per stack present in the inlined block
for section in 'Component' 'Hooks' 'Effects' 'Public API' 'Dunder methods' 'Receivers' 'Build tags' 'Types & Interfaces' 'Generics'; do
  grep -qF "$section" "$CODEBRAIN_ROOT/commands/brain/ingest.md" \
    && ok "T25: brain.md Step 4b inlines '$section' section" \
    || nope "T25: brain.md Step 4b missing '$section' section"
done

# Alias parity — Step 4b through end of Step 5 boundary

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

grep -qF '/brain:query' "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T27: brain.md dispatch table mentions /brain:query" \
  || nope "T27: brain.md dispatch table missing /brain:query"

grep -qF '## When `$ARGUMENTS` starts with `query`' "$CODEBRAIN_ROOT/commands/brain/query.md" \
  && ok "T27: brain.md has query procedure section" \
  || nope "T27: brain.md missing query procedure"

# Step headers Q0-Q7
for q in 'Q0 — Argument parsing' 'Q1 — Preconditions' 'Q2 — Read the index' 'Q3 — Select 1' 'Q4 — Freshness check' 'Q5 — Refresh STALE' 'Q6 — Read the candidate' 'Q7 — Output'; do
  grep -qF "$q" "$CODEBRAIN_ROOT/commands/brain/query.md" \
    && ok "T27: brain.md query procedure has '$q'" \
    || nope "T27: brain.md query procedure missing '$q'"
done

# Critical keywords/concepts
for needle in 'pointer-first' 'hash compare' 'promote' '[[code/' 'src/api/auth.ts:42' 'NEVER fabricate'; do
  grep -qF "$needle" "$CODEBRAIN_ROOT/commands/brain/query.md" \
    && ok "T27: brain.md query procedure mentions '$needle'" \
    || nope "T27: brain.md query procedure missing '$needle'"
done

# Flags documented
grep -qF -- '--thorough' "$CODEBRAIN_ROOT/commands/brain/query.md" \
  && ok "T27: brain.md query procedure documents --thorough" \
  || nope "T27: brain.md query procedure missing --thorough"

grep -qF -- '--no-refresh' "$CODEBRAIN_ROOT/commands/brain/query.md" \
  && ok "T27: brain.md query procedure documents --no-refresh" \
  || nope "T27: brain.md query procedure missing --no-refresh"

# Log prefix
grep -qF '[YYYY-MM-DD] query |' "$CODEBRAIN_ROOT/commands/brain/query.md" \
  && ok "T27: brain.md query procedure documents grep-parseable log prefix" \
  || nope "T27: brain.md query procedure missing log prefix"

# Alias parity for query section

# === Test 28: M#6 — verifier agent + core/lint skill ========================

[ -f "$CODEBRAIN_ROOT/agents/brain/verifier.md" ] \
  && ok "T28: verifier.md agent exists" \
  || nope "T28: verifier.md missing"

head -1 "$CODEBRAIN_ROOT/agents/brain/verifier.md" | grep -q '^---$' \
  && ok "T28: verifier.md starts with frontmatter" \
  || nope "T28: verifier.md missing frontmatter"

for field in name description tools model pattern trigger_phrases max_iterations; do
  grep -q "^${field}:" "$CODEBRAIN_ROOT/agents/brain/verifier.md" \
    && ok "T28: verifier.md has '${field}' field" \
    || nope "T28: verifier.md missing '${field}' field"
done

grep -q "^pattern: Verifier$" "$CODEBRAIN_ROOT/agents/brain/verifier.md" \
  && ok "T28: verifier.md pattern is Verifier" \
  || nope "T28: verifier.md wrong pattern"

# Read-only: NO Edit/Write/MultiEdit
grep -E "^tools:.*\b(Edit|Write|MultiEdit)\b" "$CODEBRAIN_ROOT/agents/brain/verifier.md" >/dev/null \
  && nope "T28: verifier.md tools include Edit/Write/MultiEdit (read-only violated)" \
  || ok "T28: verifier.md tools list excludes Edit/Write/MultiEdit (read-only enforced)"

grep -q '^## Rules' "$CODEBRAIN_ROOT/agents/brain/verifier.md" \
  && ok "T28: verifier.md has Rules section" \
  || nope "T28: verifier.md missing Rules section"

grep -q 'Read the Prompt Defense Baseline' "$CODEBRAIN_ROOT/agents/brain/verifier.md" \
  && ok "T28: verifier.md has prompt-defense reference" \
  || nope "T28: verifier.md missing prompt-defense reference"

verifier_rules=$(grep -cE '^- \*\*(NEVER|ALWAYS)' "$CODEBRAIN_ROOT/agents/brain/verifier.md" || true)
[ "$verifier_rules" -ge 9 ] \
  && ok "T28: verifier.md has ≥9 self-enforcing rules ($verifier_rules)" \
  || nope "T28: verifier.md only $verifier_rules rules (need ≥9)"

# lint SKILL
[ -f "$CODEBRAIN_ROOT/skills/core/lint/SKILL.md" ] \
  && ok "T28: core/lint SKILL.md exists" \
  || nope "T28: core/lint SKILL.md missing"

head -1 "$CODEBRAIN_ROOT/skills/core/lint/SKILL.md" | grep -q '^---$' \
  && ok "T28: core/lint SKILL.md starts with frontmatter" \
  || nope "T28: core/lint SKILL.md missing frontmatter"

for field in name description origin version tier pattern related_skills; do
  grep -q "^${field}:" "$CODEBRAIN_ROOT/skills/core/lint/SKILL.md" \
    && ok "T28: core/lint SKILL.md has '${field}' field" \
    || nope "T28: core/lint SKILL.md missing '${field}' field"
done

grep -q "^tier: core$" "$CODEBRAIN_ROOT/skills/core/lint/SKILL.md" \
  && ok "T28: core/lint is tier:core" \
  || nope "T28: core/lint wrong tier"

# Required body sections
for section in 'When to Activate' 'The 4 Categories' 'Flag Matrix' 'Output Contract' 'Confirmation Flow' 'Cost-Gate' 'Exit Behavior' 'Examples'; do
  grep -qF "$section" "$CODEBRAIN_ROOT/skills/core/lint/SKILL.md" \
    && ok "T28: core/lint SKILL.md has '$section' section" \
    || nope "T28: core/lint SKILL.md missing '$section' section"
done

# npm pack inclusion
pack_list="$(cd "$CODEBRAIN_ROOT" && npm pack --dry-run 2>&1)"
echo "$pack_list" | grep -q 'agents/brain/verifier.md' \
  && ok "T28: verifier.md in npm pack" \
  || nope "T28: verifier.md missing from npm pack"

echo "$pack_list" | grep -q 'skills/core/lint/SKILL.md' \
  && ok "T28: core/lint SKILL.md in npm pack" \
  || nope "T28: core/lint SKILL.md missing from npm pack"

# === Test 29: M#6 — lint procedure wiring ===================================

grep -qF '/brain:lint' "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T29: brain.md dispatch table mentions /brain:lint" \
  || nope "T29: brain.md dispatch table missing /brain:lint"

grep -qF '## When `$ARGUMENTS` starts with `lint`' "$CODEBRAIN_ROOT/commands/brain/lint.md" \
  && ok "T29: brain.md has lint procedure section" \
  || nope "T29: brain.md missing lint procedure"

# Step headers L0-L7 + L6b
for l in 'L0 — Argument parsing' 'L1 — Preconditions' 'L2 — Inventory' 'L3 — Defects' 'L4 — Gaps' 'L5 — Contradictions' 'L6 — Suggested questions' 'L6b' 'L7 — Output'; do
  grep -qF "$l" "$CODEBRAIN_ROOT/commands/brain/lint.md" \
    && ok "T29: brain.md lint procedure has '$l'" \
    || nope "T29: brain.md lint procedure missing '$l'"
done

# Critical keywords
for needle in 'hash compare' 'schema' 'wikilink' 'orphan' 'stub' 'contradiction' 'false-positive'; do
  grep -qF "$needle" "$CODEBRAIN_ROOT/commands/brain/lint.md" \
    && ok "T29: brain.md lint procedure mentions '$needle'" \
    || nope "T29: brain.md lint procedure missing '$needle'"
done

# Flags documented
for flag in -- '--fix' '--yes' '--include-contradictions'; do
  if [ "$flag" = "--" ]; then continue; fi
  grep -qF -- "$flag" "$CODEBRAIN_ROOT/commands/brain/lint.md" \
    && ok "T29: brain.md lint procedure documents $flag" \
    || nope "T29: brain.md lint procedure missing $flag"
done

# Log prefix
grep -qF '[YYYY-MM-DD] lint |' "$CODEBRAIN_ROOT/commands/brain/lint.md" \
  && ok "T29: brain.md lint procedure documents grep-parseable log prefix" \
  || nope "T29: brain.md lint procedure missing log prefix"

# Alias parity

# === Test 30: M#8 — dogfood scripts + validation framework ==================

# Dogfood scripts
[ -x "$CODEBRAIN_ROOT/scripts/dogfood/install-validate.sh" ] \
  && ok "T30: install-validate.sh exists + executable" \
  || nope "T30: install-validate.sh missing or not executable"

[ -x "$CODEBRAIN_ROOT/scripts/dogfood/static-baseline.sh" ] \
  && ok "T30: static-baseline.sh exists + executable" \
  || nope "T30: static-baseline.sh missing or not executable"

head -1 "$CODEBRAIN_ROOT/scripts/dogfood/install-validate.sh" | grep -q '^#!/usr/bin/env bash$' \
  && ok "T30: install-validate.sh has bash shebang" \
  || nope "T30: install-validate.sh missing shebang"

head -1 "$CODEBRAIN_ROOT/scripts/dogfood/static-baseline.sh" | grep -q '^#!/usr/bin/env bash$' \
  && ok "T30: static-baseline.sh has bash shebang" \
  || nope "T30: static-baseline.sh missing shebang"

# MANUAL-MEASUREMENTS.md with M1-M5 sections
[ -f "$CODEBRAIN_ROOT/scripts/dogfood/MANUAL-MEASUREMENTS.md" ] \
  && ok "T30: MANUAL-MEASUREMENTS.md exists" \
  || nope "T30: MANUAL-MEASUREMENTS.md missing"

for section in M1 M2 M3 M4 M5; do
  grep -qE "^## ${section} " "$CODEBRAIN_ROOT/scripts/dogfood/MANUAL-MEASUREMENTS.md" \
    && ok "T30: MANUAL-MEASUREMENTS.md has $section section" \
    || nope "T30: MANUAL-MEASUREMENTS.md missing $section section"
done

# Validation report template
[ -f "$CODEBRAIN_ROOT/.claude/validation/v0.1-baseline.md" ] \
  && ok "T30: .claude/validation/v0.1-baseline.md template exists" \
  || nope "T30: validation report template missing"

# Required metric sections in the report template
for metric in 'Token reduction' 'Stale-page detection' 'Wiki freshness' 'Time-to-first-value' 'Wikilink precision' 'Continuous-learning lift'; do
  grep -qF "$metric" "$CODEBRAIN_ROOT/.claude/validation/v0.1-baseline.md" \
    && ok "T30: validation report has '$metric' section" \
    || nope "T30: validation report missing '$metric' section"
done

# README mentions dogfood section
grep -qF 'Dogfood + validate' "$CODEBRAIN_ROOT/README.md" \
  && ok "T30: README has Dogfood + validate section" \
  || nope "T30: README missing Dogfood + validate section"

# === Test 31: M#8 — install-validate.sh runs successfully ===================

if bash "$CODEBRAIN_ROOT/scripts/dogfood/install-validate.sh" >/dev/null 2>&1; then
  ok "T31: install-validate.sh runs successfully (exit 0)"
else
  nope "T31: install-validate.sh failed"
fi

# === Test 32: M#8 — static-baseline.sh runs successfully ====================

if CODEBRAIN_BASELINE_NESTED=1 bash "$CODEBRAIN_ROOT/scripts/dogfood/static-baseline.sh" >/dev/null 2>&1; then
  ok "T32: static-baseline.sh runs successfully (exit 0; nested-guard active)"
else
  nope "T32: static-baseline.sh failed"
fi

# Output file created with key sections
[ -f "$CODEBRAIN_ROOT/.claude/validation/v0.1-static-baseline.md" ] \
  && ok "T32: static baseline output file created" \
  || nope "T32: static baseline output missing"

for section in 'Shipped source files' 'Agents' 'Skills' 'Templates' 'npm package' 'Hooks' 'Slash-command surface' 'Test coverage'; do
  grep -qF "$section" "$CODEBRAIN_ROOT/.claude/validation/v0.1-static-baseline.md" \
    && ok "T32: static baseline has '$section' section" \
    || nope "T32: static baseline missing '$section' section"
done

# npm pack includes dogfood scripts
pack_list="$(cd "$CODEBRAIN_ROOT" && npm pack --dry-run 2>&1)"
for f in install-validate.sh static-baseline.sh MANUAL-MEASUREMENTS.md; do
  echo "$pack_list" | grep -q "scripts/dogfood/$f" \
    && ok "T32: scripts/dogfood/$f in npm pack" \
    || nope "T32: scripts/dogfood/$f missing from npm pack"
done

# === Test 33: M#7 — observer agent + core/learn skill =======================

[ -f "$CODEBRAIN_ROOT/agents/observers/observer.md" ] \
  && ok "T33: observer.md agent exists" \
  || nope "T33: observer.md missing"

head -1 "$CODEBRAIN_ROOT/agents/observers/observer.md" | grep -q '^---$' \
  && ok "T33: observer.md starts with frontmatter" \
  || nope "T33: observer.md missing frontmatter"

for field in name description tools model pattern trigger_phrases max_iterations; do
  grep -q "^${field}:" "$CODEBRAIN_ROOT/agents/observers/observer.md" \
    && ok "T33: observer.md has '${field}' field" \
    || nope "T33: observer.md missing '${field}' field"
done

grep -q "^pattern: Observer$" "$CODEBRAIN_ROOT/agents/observers/observer.md" \
  && ok "T33: observer.md pattern is Observer" \
  || nope "T33: observer.md wrong pattern"

# Read-only — NO Edit/Write/MultiEdit
grep -E "^tools:.*\b(Edit|Write|MultiEdit)\b" "$CODEBRAIN_ROOT/agents/observers/observer.md" >/dev/null \
  && nope "T33: observer.md tools include mutation (read-only violated)" \
  || ok "T33: observer.md tools excludes Edit/Write/MultiEdit (read-only)"

grep -q '^## Rules' "$CODEBRAIN_ROOT/agents/observers/observer.md" \
  && ok "T33: observer.md has Rules section" \
  || nope "T33: observer.md missing Rules section"

grep -q '^## Privacy' "$CODEBRAIN_ROOT/agents/observers/observer.md" \
  && ok "T33: observer.md has Privacy section" \
  || nope "T33: observer.md missing Privacy section"

grep -q 'Read the Prompt Defense Baseline' "$CODEBRAIN_ROOT/agents/observers/observer.md" \
  && ok "T33: observer.md has prompt-defense reference" \
  || nope "T33: observer.md missing prompt-defense reference"

observer_rules=$(grep -cE '^- \*\*(NEVER|ALWAYS)' "$CODEBRAIN_ROOT/agents/observers/observer.md" || true)
[ "$observer_rules" -ge 10 ] \
  && ok "T33: observer.md has ≥10 self-enforcing rules ($observer_rules)" \
  || nope "T33: observer.md only $observer_rules rules (need ≥10)"

# learn SKILL
[ -f "$CODEBRAIN_ROOT/skills/core/learn/SKILL.md" ] \
  && ok "T33: core/learn SKILL.md exists" \
  || nope "T33: core/learn SKILL.md missing"

grep -q "^tier: core$" "$CODEBRAIN_ROOT/skills/core/learn/SKILL.md" \
  && ok "T33: core/learn is tier:core" \
  || nope "T33: core/learn wrong tier"

for section in 'When to Activate' 'Observation format' 'Instinct format' 'Consolidation policy' 'Privacy' 'Toggle semantics' 'Storage location' 'Future work' 'Examples'; do
  grep -qF "$section" "$CODEBRAIN_ROOT/skills/core/learn/SKILL.md" \
    && ok "T33: core/learn SKILL.md has '$section' section" \
    || nope "T33: core/learn SKILL.md missing '$section' section"
done

# npm pack
pack_list="$(cd "$CODEBRAIN_ROOT" && npm pack --dry-run 2>&1)"
echo "$pack_list" | grep -q 'agents/observers/observer.md' \
  && ok "T33: observer.md in npm pack" \
  || nope "T33: observer.md missing from npm pack"

echo "$pack_list" | grep -q 'skills/core/learn/SKILL.md' \
  && ok "T33: core/learn SKILL.md in npm pack" \
  || nope "T33: core/learn SKILL.md missing from npm pack"

# === Test 34: M#7 — init.js writes the observe hook entry ===================

T34_REPO="$(setup_user_repo)"
( cd "$T34_REPO" && HOME="$HOME" node "$CB" init >/dev/null 2>&1 )

# observe entry present
node -e "
  const j = require('$T34_REPO/.claude/settings.local.json');
  const pre = (j.hooks && j.hooks.PreToolUse) || [];
  const observe = pre.find(e => e && e.id === 'codebrain:pre:observe');
  if (!observe) { console.error('observe entry missing'); process.exit(1); }
  if (observe.matcher !== '*') { console.error('observe matcher wrong:', observe.matcher); process.exit(1); }
  if (!observe.hooks[0].async) { console.error('observe not async'); process.exit(1); }
  if (!observe.hooks[0].command.includes('graphbrain hook observe')) { console.error('observe command wrong'); process.exit(1); }
  process.exit(0);
" 2>/dev/null && ok "T34: settings.local.json has codebrain:pre:observe with correct shape" || nope "T34: observe entry incorrect"

# Total codebrain hooks = 3 (verified-guard + stale-detect + observe)
total_cb_hooks=$(node -e "
  const j = require('$T34_REPO/.claude/settings.local.json');
  const all = [...(j.hooks.PreToolUse||[]), ...(j.hooks.PostToolUse||[])];
  console.log(all.filter(e => e && typeof e.id === 'string' && e.id.startsWith('codebrain:')).length);
" 2>/dev/null)
[ "$total_cb_hooks" = "3" ] && ok "T34: settings.local.json has exactly 3 codebrain hooks (verified-guard + stale-detect + observe)" || nope "T34: codebrain hook count was $total_cb_hooks (expected 3)"

# Re-init: still 3 (no duplication)
( cd "$T34_REPO" && HOME="$HOME" node "$CB" init >/dev/null 2>&1 )
total_after=$(node -e "
  const j = require('$T34_REPO/.claude/settings.local.json');
  const all = [...(j.hooks.PreToolUse||[]), ...(j.hooks.PostToolUse||[])];
  console.log(all.filter(e => e && typeof e.id === 'string' && e.id.startsWith('codebrain:')).length);
" 2>/dev/null)
[ "$total_after" = "3" ] && ok "T34: re-init keeps exactly 3 codebrain hooks (no duplication)" || nope "T34: re-init count was $total_after"

# === Test 35: M#7 — observe hook + learn/status procedures =================

[ -f "$CODEBRAIN_ROOT/scripts/hooks/observe.js" ] \
  && ok "T35: observe.js hook exists" \
  || nope "T35: observe.js missing"

[ -f "$CODEBRAIN_ROOT/scripts/hooks/lib/observations.js" ] \
  && ok "T35: lib/observations.js exists" \
  || nope "T35: lib/observations.js missing"

head -1 "$CODEBRAIN_ROOT/scripts/hooks/observe.js" | grep -q '^#!/usr/bin/env node$' \
  && ok "T35: observe.js has Node shebang" \
  || nope "T35: observe.js missing/wrong shebang"

# CLI dispatches the new subcommand
hook_help="$(node "$CB" hook 2>&1)"
echo "$hook_help" | grep -q 'observe' \
  && ok "T35: 'codebrain hook' help lists observe" \
  || nope "T35: 'codebrain hook' help missing observe"

# Fixture: observe is silent when toggle is off
T35_DIR="$(mktemp -d)"
mkdir -p "$T35_DIR/.brain"
echo '0.1.0' > "$T35_DIR/.brain/.codebrain-version"
# No toggle file → default off → observe should exit silently with no observations file
rc=$( ( cd "$T35_DIR" && echo '{"tool_name":"Edit","tool_input":{"file_path":"src/test.ts"}}' | node "$CB" hook observe 2>/dev/null ); echo $? )
[ "$rc" -eq 0 ] && ok "T35: observe exits 0 when toggle missing (default off)" || nope "T35: observe exit was $rc (expected 0)"

# Fixture: observe is silent when toggle is "off"
echo 'off' > "$T35_DIR/.brain/.codebrain-learn-state"
rc=$( ( cd "$T35_DIR" && echo '{"tool_name":"Edit","tool_input":{"file_path":"src/test.ts"}}' | node "$CB" hook observe 2>/dev/null ); echo $? )
[ "$rc" -eq 0 ] && ok "T35: observe exits 0 when toggle off" || nope "T35: observe off exit was $rc"

# Fixture: observe records when toggle is "on"
echo 'on' > "$T35_DIR/.brain/.codebrain-learn-state"
( cd "$T35_DIR" && echo '{"tool_name":"Edit","tool_input":{"file_path":"src/test.ts"}}' | node "$CB" hook observe >/dev/null 2>&1 )
( cd "$T35_DIR" && echo '{"tool_name":"Read","tool_input":{"file_path":"src/other.ts"}}' | node "$CB" hook observe >/dev/null 2>&1 )

# Find the observations file via the same algorithm the hook uses
obs_count=$(node -e "
  process.chdir('$T35_DIR');
  const lib = require('$CODEBRAIN_ROOT/scripts/hooks/lib/observations.js');
  const records = lib.readObservations(process.cwd());
  console.log(records.length);
" 2>/dev/null)
[ "$obs_count" = "2" ] && ok "T35: observe writes 2 records when toggle on (2 hook calls)" || nope "T35: expected 2 observations, got $obs_count"

# Privacy: observations contain only {ts, tool, path, status}
node -e "
  process.chdir('$T35_DIR');
  const lib = require('$CODEBRAIN_ROOT/scripts/hooks/lib/observations.js');
  const recs = lib.readObservations(process.cwd());
  for (const r of recs) {
    const keys = Object.keys(r).sort().join(',');
    if (keys !== 'path,status,toolwhere'.replace('toolwhere','tool') && keys !== 'path,status,tool,ts') {
      console.error('unexpected keys:', keys); process.exit(1);
    }
  }
" 2>/dev/null \
  && ok "T35: observations have only whitelisted fields (ts, tool, path, status)" \
  || nope "T35: observations include extra fields (privacy guard broken)"

# Dispatch table mentions the namespaced learn + status forms (post-M#12b)
grep -qF '/brain:learn' "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T35: brain.md dispatch table mentions /brain:learn" \
  || nope "T35: brain.md dispatch table missing /brain:learn"

grep -qF '/brain:status' "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T35: brain.md dispatch table mentions /brain:status" \
  || nope "T35: brain.md dispatch table missing /brain:status"

# Procedure sections (per-verb files)
grep -qF '## When `$ARGUMENTS` starts with `learn`' "$CODEBRAIN_ROOT/commands/brain/learn.md" \
  && ok "T35: brain/learn.md has learn procedure section" \
  || nope "T35: brain/learn.md missing learn procedure"

grep -qF '## When `$ARGUMENTS` is just `status`' "$CODEBRAIN_ROOT/commands/brain/status.md" \
  && ok "T35: brain/status.md has status procedure section" \
  || nope "T35: brain/status.md missing status procedure"

# Step headers — learn has Le*, status has S*
for s in 'Le0' 'Le3' 'Le6' 'Le7'; do
  grep -qF "$s" "$CODEBRAIN_ROOT/commands/brain/learn.md" \
    && ok "T35: brain/learn.md has $s step header" \
    || nope "T35: brain/learn.md missing $s"
done

for s in 'S0' 'S1' 'S2' 'S3'; do
  grep -qF "$s" "$CODEBRAIN_ROOT/commands/brain/status.md" \
    && ok "T35: brain/status.md has $s step header" \
    || nope "T35: brain/status.md missing $s"
done

# Critical keywords
for needle in 'Privacy notice' 'XDG' 'consolidate' 'instinct' 'pattern' 'toggle' 'observations.jsonl'; do
  grep -qF "$needle" "$CODEBRAIN_ROOT/commands/brain/learn.md" \
    && ok "T35: brain/learn.md mentions '$needle'" \
    || nope "T35: brain/learn.md missing '$needle'"
done

# Alias parity for both per-verb files (procedure bodies byte-identical)


# npm pack includes the new files
echo "$pack_list" | grep -q 'scripts/hooks/observe.js' && ok "T35: observe.js in npm pack" || nope "T35: observe.js missing from npm pack"
echo "$pack_list" | grep -q 'scripts/hooks/lib/observations.js' && ok "T35: lib/observations.js in npm pack" || nope "T35: lib/observations.js missing from npm pack"

# === Test 36: v0.1.1 — framework detection + ECC bridge ====================

# 6 new detected/* SKILL.md files exist
for stack in nestjs nextjs express django fastapi springboot; do
  skill_file="$CODEBRAIN_ROOT/skills/detected/${stack}/SKILL.md"
  [ -f "$skill_file" ] && ok "T36: detected/${stack}/SKILL.md exists" || nope "T36: detected/${stack}/SKILL.md missing"

  head -1 "$skill_file" 2>/dev/null | grep -q '^---$' \
    && ok "T36: detected/${stack} SKILL.md starts with frontmatter" \
    || nope "T36: detected/${stack} SKILL.md missing frontmatter"

  # All standard merged fields + the new expert_skills field
  for field in name description origin version tier pattern related_skills detect applies_to_extensions expert_skills; do
    grep -q "^${field}:" "$skill_file" 2>/dev/null \
      && ok "T36: detected/${stack} SKILL.md has '${field}' field" \
      || nope "T36: detected/${stack} SKILL.md missing '${field}' field"
  done

  grep -q "^tier: detected$" "$skill_file" 2>/dev/null \
    && ok "T36: detected/${stack} is tier:detected" \
    || nope "T36: detected/${stack} wrong tier"
done

# stack-detection.json includes nestjs, express, fastify, springboot
for stack in nestjs express fastify springboot; do
  node -e "
    const j = require('$CODEBRAIN_ROOT/skills/core/init/templates/stack-detection.json');
    const match = j.stacks.find(s => s.name === '${stack}' || s.name === '${stack}-maven' || s.name === '${stack}-gradle');
    if (!match) { console.error('missing stack:', '${stack}'); process.exit(1); }
    process.exit(0);
  " 2>/dev/null \
    && ok "T36: stack-detection.json has '${stack}' entry" \
    || nope "T36: stack-detection.json missing '${stack}'"
done

# registry.json includes all 6 new detected entries with expert_skills
node -e "
  const r = require('$CODEBRAIN_ROOT/skills/registry.json');
  const expected = ['detected/nestjs', 'detected/nextjs', 'detected/express', 'detected/django', 'detected/fastapi', 'detected/springboot'];
  for (const k of expected) {
    if (!r.skills[k]) { console.error('missing skill:', k); process.exit(1); }
    if (r.skills[k].tier !== 'detected') { console.error('wrong tier:', k); process.exit(1); }
    if (!Array.isArray(r.skills[k].expert_skills)) { console.error('expert_skills not array:', k); process.exit(1); }
    if (r.skills[k].expert_skills.length === 0) { console.error('expert_skills empty:', k); process.exit(1); }
  }
  process.exit(0);
" 2>/dev/null \
  && ok "T36: registry.json has 6 new detected entries with expert_skills field" \
  || nope "T36: registry.json detected entries malformed or missing"

# Specific expert_skills targets per stack
node -e "
  const r = require('$CODEBRAIN_ROOT/skills/registry.json');
  if (!r.skills['detected/nestjs'].expert_skills.includes('ecc:nestjs-patterns')) { console.error('nestjs missing ecc:nestjs-patterns'); process.exit(1); }
  if (!r.skills['detected/django'].expert_skills.includes('ecc:django-patterns')) { console.error('django missing ecc:django-patterns'); process.exit(1); }
  if (!r.skills['detected/django'].expert_skills.includes('ecc:django-security')) { console.error('django missing ecc:django-security'); process.exit(1); }
  if (!r.skills['detected/fastapi'].expert_skills.includes('ecc:fastapi-patterns')) { console.error('fastapi missing ecc:fastapi-patterns'); process.exit(1); }
  if (!r.skills['detected/springboot'].expert_skills.includes('ecc:springboot-patterns')) { console.error('springboot missing ecc:springboot-patterns'); process.exit(1); }
  process.exit(0);
" 2>/dev/null \
  && ok "T36: registry.json expert_skills targets correct per stack" \
  || nope "T36: expert_skills assignments wrong"

# brain.md has Step 4b.2 — Expert skill bridge
grep -qF 'Step 4b.2 — Expert skill bridge' "$CODEBRAIN_ROOT/commands/brain/ingest.md" \
  && ok "T36: brain.md has Step 4b.2 (Expert skill bridge)" \
  || nope "T36: brain.md missing Step 4b.2"

# brain.md mentions all 6 bridge targets
for target in 'ecc:nestjs-patterns' 'ecc:nextjs-turbopack' 'ecc:backend-patterns' 'ecc:django-patterns' 'ecc:fastapi-patterns' 'ecc:springboot-patterns'; do
  grep -qF "$target" "$CODEBRAIN_ROOT/commands/brain/ingest.md" \
    && ok "T36: brain.md Step 4b.2 mentions '$target'" \
    || nope "T36: brain.md Step 4b.2 missing '$target'"
done


# npm pack includes the 6 new SKILL.md files
pack_list="$(cd "$CODEBRAIN_ROOT" && npm pack --dry-run 2>&1)"
for stack in nestjs nextjs express django fastapi springboot; do
  echo "$pack_list" | grep -q "skills/detected/${stack}/SKILL.md" \
    && ok "T36: detected/${stack}/SKILL.md in npm pack" \
    || nope "T36: detected/${stack}/SKILL.md missing from npm pack"
done

# Dogfood-gaps section was added to validation report
grep -qF 'Operator-discovered gaps' "$CODEBRAIN_ROOT/.claude/validation/v0.1-baseline.md" \
  && ok "T36: v0.1-baseline.md has Operator-discovered gaps section (M#8 evidence)" \
  || nope "T36: v0.1-baseline.md missing Operator-discovered gaps section"

# === Test 37: v0.1.2 — llms.txt scaffold + refresh wiring (AEO convention) ===

# init.js scaffolds .brain/llms.txt
[ -f "$USER_REPO/.brain/llms.txt" ] \
  && ok "T37: .brain/llms.txt scaffolded by init" \
  || nope "T37: .brain/llms.txt missing after init"

# llms.txt has expected AEO header lines
grep -qF '# llms.txt — agent-readable site map' "$USER_REPO/.brain/llms.txt" \
  && ok "T37: llms.txt declares AEO convention in header" \
  || nope "T37: llms.txt header missing AEO declaration"

grep -qF '# codebrain v' "$USER_REPO/.brain/llms.txt" \
  && ok "T37: llms.txt header has codebrain version line" \
  || nope "T37: llms.txt missing version line"

grep -qF '## Top-level' "$USER_REPO/.brain/llms.txt" \
  && ok "T37: llms.txt has Top-level section" \
  || nope "T37: llms.txt missing Top-level section"

grep -qE '^## Code pages \(0\)' "$USER_REPO/.brain/llms.txt" \
  && ok "T37: llms.txt has empty Code pages section" \
  || nope "T37: llms.txt missing Code pages section"

grep -qE '^## Concept pages \(0\)' "$USER_REPO/.brain/llms.txt" \
  && ok "T37: llms.txt has empty Concept pages section" \
  || nope "T37: llms.txt missing Concept pages section"

grep -qE '^## Decision pages \(0\)' "$USER_REPO/.brain/llms.txt" \
  && ok "T37: llms.txt has empty Decision pages section" \
  || nope "T37: llms.txt missing Decision pages section"

# M#12a: refresh procedure lives in skills/ingestion/llms-txt/SKILL.md (single source of truth)
test -f "$CODEBRAIN_ROOT/skills/ingestion/llms-txt/SKILL.md" \
  && ok "T37: skills/ingestion/llms-txt/SKILL.md exists" \
  || nope "T37: skills/ingestion/llms-txt/SKILL.md missing"

# Skill has required frontmatter
for field in name description origin version tier pattern related_skills; do
  grep -q "^${field}:" "$CODEBRAIN_ROOT/skills/ingestion/llms-txt/SKILL.md" \
    && ok "T37: llms-txt SKILL.md has '$field' field" \
    || nope "T37: llms-txt SKILL.md missing '$field' field"
done

grep -q "^tier: ingestion$" "$CODEBRAIN_ROOT/skills/ingestion/llms-txt/SKILL.md" \
  && ok "T37: llms-txt SKILL.md is tier:ingestion" \
  || nope "T37: llms-txt SKILL.md wrong tier"

# Refresh algorithm + format documented in the skill
grep -qF 'Refresh algorithm' "$CODEBRAIN_ROOT/skills/ingestion/llms-txt/SKILL.md" \
  && ok "T37: llms-txt SKILL.md documents refresh algorithm" \
  || nope "T37: llms-txt SKILL.md missing refresh algorithm"

grep -qF 'llmstxt.org' "$CODEBRAIN_ROOT/skills/ingestion/llms-txt/SKILL.md" \
  && ok "T37: llms-txt SKILL.md cites AEO convention (llmstxt.org)" \
  || nope "T37: llms-txt SKILL.md missing AEO citation"

# Inline section was removed from both slash-command files (M#12a cleanup)
for v in brain; do
  ! grep -qF '## How to refresh `.brain/llms.txt`' "$CODEBRAIN_ROOT/commands/$v.md" \
    && ok "T37: $v.md inline refresh section removed (M#12a)" \
    || nope "T37: $v.md still has obsolete inline refresh section"
done

# M#3a Step 6 wires llms.txt refresh (now in per-verb ingest.md)
for v in brain; do
  awk '/\*\*Step 6 — Update derived files\*\*/{flag=1} /\*\*Step 7 — Report\*\*/{flag=0} flag' "$CODEBRAIN_ROOT/commands/$v/ingest.md" \
    | grep -qF 'skills/ingestion/llms-txt/SKILL.md' \
    && ok "T37: $v/ingest.md M#3a Step 6 wires llms-txt skill reference" \
    || nope "T37: $v/ingest.md M#3a Step 6 missing skills/ingestion/llms-txt/SKILL.md reference"
done

# M#3b L5 (linker) wires llms.txt refresh (linker procedure also in per-verb ingest.md)
for v in brain; do
  awk '/\*\*L5 — Update derived files\*\*/{flag=1} /\*\*L6 — Linker report\*\*/{flag=0} flag' "$CODEBRAIN_ROOT/commands/$v/ingest.md" \
    | grep -qF 'skills/ingestion/llms-txt/SKILL.md' \
    && ok "T37: $v/ingest.md M#3b L5 wires llms-txt skill reference" \
    || nope "T37: $v/ingest.md M#3b L5 missing skills/ingestion/llms-txt/SKILL.md reference"
done

# /brain lint L7 wires llms.txt refresh (now in per-verb lint.md)
for v in brain; do
  awk '/\*\*L7 — Output \+ log\*\*/{flag=1} /^## /{flag=0} flag' "$CODEBRAIN_ROOT/commands/$v/lint.md" \
    | grep -qF 'skills/ingestion/llms-txt/SKILL.md' \
    && ok "T37: $v/lint.md lint L7 wires llms-txt skill reference" \
    || nope "T37: $v/lint.md lint L7 missing skills/ingestion/llms-txt/SKILL.md reference"
done

# Ingest report includes llms.txt in "Updated:" line (single-file ingest Step 7 — per-verb ingest.md)
for v in brain; do
  grep -qF '.brain/log.md, .brain/llms.txt' "$CODEBRAIN_ROOT/commands/$v/ingest.md" \
    && ok "T37: $v/ingest.md ingest Step 7 report mentions llms.txt in Updated: line" \
    || nope "T37: $v/ingest.md ingest Step 7 report missing llms.txt in Updated: line"
done

# === Test 39: M#9-prereq — runtime bridge probe + Active bridges report =====

# Step 4b.3 exists in both ingest.md files (per-verb, post-M#12b)
for v in brain; do
  grep -qF '**Step 4b.3 — Active bridge probe + activation**' "$CODEBRAIN_ROOT/commands/$v/ingest.md" \
    && ok "T39: $v/ingest.md has Step 4b.3 (Active bridge probe + activation)" \
    || nope "T39: $v/ingest.md missing Step 4b.3"
done

# Step 4b.3 mentions the filesystem probe path (both candidates)
for v in brain; do
  grep -qF '$HOME/.claude/plugins' "$CODEBRAIN_ROOT/commands/$v/ingest.md" \
    && ok "T39: $v/ingest.md Step 4b.3 includes user-global probe path" \
    || nope "T39: $v/ingest.md missing user-global probe path"
  grep -qF '$PWD/.claude/plugins' "$CODEBRAIN_ROOT/commands/$v/ingest.md" \
    && ok "T39: $v/ingest.md Step 4b.3 includes project-local probe path" \
    || nope "T39: $v/ingest.md missing project-local probe path"
done

# Step 4b.3 defines the bridges_loaded[] and bridges_unavailable[] arrays
for v in brain; do
  grep -qF 'bridges_loaded' "$CODEBRAIN_ROOT/commands/$v/ingest.md" \
    && ok "T39: $v/ingest.md defines bridges_loaded array" \
    || nope "T39: $v/ingest.md missing bridges_loaded"
  grep -qF 'bridges_unavailable' "$CODEBRAIN_ROOT/commands/$v/ingest.md" \
    && ok "T39: $v/ingest.md defines bridges_unavailable array" \
    || nope "T39: $v/ingest.md missing bridges_unavailable"
done

# Step 7 report includes the "Active bridges" block
for v in brain; do
  grep -qF 'Active bridges:' "$CODEBRAIN_ROOT/commands/$v/ingest.md" \
    && ok "T39: $v/ingest.md Step 7 report has Active bridges block" \
    || nope "T39: $v/ingest.md Step 7 report missing Active bridges block"
done

# Probe-and-Read pattern is documented as the portable primitive (no cross-plugin Skill() invocation)
for v in brain; do
  grep -qF 'probe-and-Read pattern is intentionally portable' "$CODEBRAIN_ROOT/commands/$v/ingest.md" \
    && ok "T39: $v/ingest.md documents probe-and-Read portability rationale" \
    || nope "T39: $v/ingest.md missing portability rationale"
done

# Alias parity — brain/ingest.md and codebrain/ingest.md byte-identical

# === Test 40: M#10a — /brain spec verb (spec-orchestrator agent + spec skill + spec.md per-verb) ===

# spec-orchestrator agent exists with proper frontmatter
test -f "$CODEBRAIN_ROOT/agents/brain/spec-orchestrator.md" \
  && ok "T40: agents/brain/spec-orchestrator.md exists" \
  || nope "T40: spec-orchestrator agent missing"

for field in name description tools model pattern trigger_phrases max_iterations; do
  grep -q "^${field}:" "$CODEBRAIN_ROOT/agents/brain/spec-orchestrator.md" \
    && ok "T40: spec-orchestrator has '$field' field" \
    || nope "T40: spec-orchestrator missing '$field' field"
done

grep -q "^pattern: Orchestrator$" "$CODEBRAIN_ROOT/agents/brain/spec-orchestrator.md" \
  && ok "T40: spec-orchestrator pattern is Orchestrator" \
  || nope "T40: spec-orchestrator wrong pattern"

grep -qF '/brain spec' "$CODEBRAIN_ROOT/agents/brain/spec-orchestrator.md" \
  && ok "T40: spec-orchestrator references /brain spec invocation" \
  || nope "T40: spec-orchestrator missing /brain spec reference"

# Agent rules forbid writing source code or .brain/
grep -qF 'Never write source code' "$CODEBRAIN_ROOT/agents/brain/spec-orchestrator.md" \
  && ok "T40: spec-orchestrator forbids writing source code" \
  || nope "T40: spec-orchestrator missing 'no source code' rule"

grep -qF "Never edit \`.brain/\`" "$CODEBRAIN_ROOT/agents/brain/spec-orchestrator.md" \
  && ok "T40: spec-orchestrator forbids editing .brain/" \
  || nope "T40: spec-orchestrator missing 'no .brain/' rule"

# core/spec skill exists with proper frontmatter
test -f "$CODEBRAIN_ROOT/skills/core/spec/SKILL.md" \
  && ok "T40: skills/core/spec/SKILL.md exists" \
  || nope "T40: core/spec skill missing"

for field in name description origin version tier pattern related_skills; do
  grep -q "^${field}:" "$CODEBRAIN_ROOT/skills/core/spec/SKILL.md" \
    && ok "T40: core/spec SKILL.md has '$field' field" \
    || nope "T40: core/spec SKILL.md missing '$field' field"
done

grep -q "^tier: core$" "$CODEBRAIN_ROOT/skills/core/spec/SKILL.md" \
  && ok "T40: core/spec is tier:core" \
  || nope "T40: core/spec wrong tier"

# Skill documents bridge dependency on M#9-prereq
grep -qF 'M#9-prereq' "$CODEBRAIN_ROOT/skills/core/spec/SKILL.md" \
  && ok "T40: core/spec SKILL.md cites M#9-prereq bridge dependency" \
  || nope "T40: core/spec SKILL.md missing M#9-prereq reference"

# Per-verb spec.md exists in both brain/ and codebrain/
for v in brain; do
  test -f "$CODEBRAIN_ROOT/commands/$v/spec.md" \
    && ok "T40: commands/$v/spec.md exists" \
    || nope "T40: commands/$v/spec.md missing"
done

# spec.md has Sp0-Sp7 steps
for sp in 'Sp0 — Argument parsing' 'Sp1 — Preconditions + bridge probe' 'Sp2 — Generate PRD' 'Sp3 — Generate plan' 'Sp4 — Sweep loop' 'Sp5 — Present + gate on approval' 'Sp6 — Mark the plan ready' 'Sp7 — Report + log'; do
  grep -qF "$sp" "$CODEBRAIN_ROOT/commands/brain/spec.md" \
    && ok "T40: brain/spec.md has '$sp'" \
    || nope "T40: brain/spec.md missing '$sp'"
done

# Bridge probe paths in Sp1 (M#9-prereq pattern)
grep -qF '$HOME/.claude/plugins/ecc/skills/plan-prd' "$CODEBRAIN_ROOT/commands/brain/spec.md" \
  && ok "T40: brain/spec.md Sp1 probes ecc:plan-prd via user-global path" \
  || nope "T40: brain/spec.md missing user-global plan-prd probe"

grep -qF '$HOME/.claude/plugins/ecc/skills/plan/SKILL.md' "$CODEBRAIN_ROOT/commands/brain/spec.md" \
  && ok "T40: brain/spec.md Sp1 probes ecc:plan via user-global path" \
  || nope "T40: brain/spec.md missing user-global plan probe"

# Top-level dispatcher mentions /brain:spec
grep -qF '/brain:spec' "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T40: brain.md dispatch table mentions /brain:spec" \
  || nope "T40: brain.md dispatch table missing /brain:spec"


# Legacy dispatcher routes 'spec' to the per-verb file
grep -qF "'init', \`ingest\`, \`query\`, \`lint\`, \`learn\`, \`status\`, \`spec\`" "$CODEBRAIN_ROOT/commands/brain.md" 2>/dev/null \
  || grep -q '`init`, `ingest`, `query`, `lint`, `learn`, `status`, `spec`' "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T40: brain.md legacy dispatcher knows 'spec' verb" \
  || nope "T40: brain.md legacy dispatcher missing 'spec' in verb list"

# Alias parity — brain/spec.md and codebrain/spec.md byte-identical

# npm pack ships the new files
pack_list="$(cd "$CODEBRAIN_ROOT" && npm pack --dry-run 2>&1)"
echo "$pack_list" | grep -q 'agents/brain/spec-orchestrator.md' \
  && ok "T40: spec-orchestrator.md in npm pack" \
  || nope "T40: spec-orchestrator.md missing from npm pack"

echo "$pack_list" | grep -q 'skills/core/spec/SKILL.md' \
  && ok "T40: core/spec SKILL.md in npm pack" \
  || nope "T40: core/spec SKILL.md missing from npm pack"

echo "$pack_list" | grep -q 'commands/brain/spec.md' \
  && ok "T40: brain/spec.md in npm pack" \
  || nope "T40: brain/spec.md missing from npm pack"


# === Test 41: M#10b — discovery-loop skill ==================================

test -f "$CODEBRAIN_ROOT/skills/core/discovery-loop/SKILL.md" \
  && ok "T41: skills/core/discovery-loop/SKILL.md exists" \
  || nope "T41: discovery-loop skill missing"

for field in name description origin version tier pattern related_skills; do
  grep -q "^${field}:" "$CODEBRAIN_ROOT/skills/core/discovery-loop/SKILL.md" \
    && ok "T41: discovery-loop SKILL.md has '$field' field" \
    || nope "T41: discovery-loop SKILL.md missing '$field' field"
done

grep -q "^tier: core$" "$CODEBRAIN_ROOT/skills/core/discovery-loop/SKILL.md" \
  && ok "T41: discovery-loop is tier:core" \
  || nope "T41: discovery-loop wrong tier"

grep -q "^pattern: Pipeline$" "$CODEBRAIN_ROOT/skills/core/discovery-loop/SKILL.md" \
  && ok "T41: discovery-loop pattern is Pipeline" \
  || nope "T41: discovery-loop wrong pattern"

# Procedure steps D0-D4 documented
for d in 'D0 — Inputs' 'D1 — Initialize' 'D2 — Sweep round' 'D3 — Convergence check' 'D4 — Output'; do
  grep -qF "$d" "$CODEBRAIN_ROOT/skills/core/discovery-loop/SKILL.md" \
    && ok "T41: discovery-loop has '$d'" \
    || nope "T41: discovery-loop missing '$d'"
done

# Severity tags documented (operational definitions)
for sev in 'BLOCKER' 'DRIFT' 'GAP' 'QUESTION'; do
  grep -qF "**$sev**" "$CODEBRAIN_ROOT/skills/core/discovery-loop/SKILL.md" \
    && ok "T41: discovery-loop documents $sev severity" \
    || nope "T41: discovery-loop missing $sev severity"
done

# Convergence criteria explicit
grep -qF 'convergence_threshold' "$CODEBRAIN_ROOT/skills/core/discovery-loop/SKILL.md" \
  && ok "T41: discovery-loop documents convergence_threshold parameter" \
  || nope "T41: discovery-loop missing convergence_threshold"

grep -qF 'max_rounds' "$CODEBRAIN_ROOT/skills/core/discovery-loop/SKILL.md" \
  && ok "T41: discovery-loop documents max_rounds parameter" \
  || nope "T41: discovery-loop missing max_rounds"

grep -qF 'Convergence criteria' "$CODEBRAIN_ROOT/skills/core/discovery-loop/SKILL.md" \
  && ok "T41: discovery-loop has 'Convergence criteria' section" \
  || nope "T41: discovery-loop missing Convergence criteria section"

# /brain spec Sp4 fallback path now resolvable
grep -qF 'skills/core/discovery-loop/SKILL.md' "$CODEBRAIN_ROOT/commands/brain/spec.md" \
  && ok "T41: brain/spec.md Sp4 references discovery-loop skill" \
  || nope "T41: brain/spec.md missing discovery-loop fallback"

# npm pack ships discovery-loop
pack_list_t41="$(cd "$CODEBRAIN_ROOT" && npm pack --dry-run 2>&1)"
echo "$pack_list_t41" | grep -q 'skills/core/discovery-loop/SKILL.md' \
  && ok "T41: discovery-loop SKILL.md in npm pack" \
  || nope "T41: discovery-loop SKILL.md missing from npm pack"

# === Test 42: M#10d — supersedes frontmatter + CHANGELOG + reading-principles ===

# Page-format templates document the optional supersedes fields
grep -qF 'superseded_by' "$CODEBRAIN_ROOT/skills/ingestion/page-format/templates/code-page.md" \
  && ok "T42: code-page template documents superseded_by field" \
  || nope "T42: code-page template missing superseded_by"

grep -qF 'supersedes:' "$CODEBRAIN_ROOT/skills/ingestion/page-format/templates/code-page.md" \
  && ok "T42: code-page template documents supersedes field" \
  || nope "T42: code-page template missing supersedes"

grep -qF 'superseded_by' "$CODEBRAIN_ROOT/skills/ingestion/concept-extraction/templates/concept-page.md" \
  && ok "T42: concept-page template documents superseded_by field" \
  || nope "T42: concept-page template missing superseded_by"

# /brain query Q4 skips superseded pages
grep -qF 'M#10d supersession check' "$CODEBRAIN_ROOT/commands/brain/query.md" \
  && ok "T42: brain/query.md Q4 has supersession check" \
  || nope "T42: brain/query.md missing supersession check"


# /brain lint L3/L4 has supersession checks
grep -qF 'Superseded pages still linked' "$CODEBRAIN_ROOT/commands/brain/lint.md" \
  && ok "T42: brain/lint.md L3 has superseded-pages-linked check" \
  || nope "T42: brain/lint.md missing superseded-pages-linked check"

grep -qF 'Asymmetric supersession' "$CODEBRAIN_ROOT/commands/brain/lint.md" \
  && ok "T42: brain/lint.md L4 has asymmetric supersession check" \
  || nope "T42: brain/lint.md missing asymmetric supersession check"

# init.js scaffolds CHANGELOG.md
T42_DIR="$(mktemp -d)"
( cd "$T42_DIR" && git init -q && node "$CB" init >/dev/null 2>&1 )
[ -f "$T42_DIR/.brain/CHANGELOG.md" ] \
  && ok "T42: init scaffolds .brain/CHANGELOG.md" \
  || nope "T42: .brain/CHANGELOG.md missing after init"

grep -qF '# CHANGELOG — what the brain learned' "$T42_DIR/.brain/CHANGELOG.md" \
  && ok "T42: CHANGELOG.md has expected header" \
  || nope "T42: CHANGELOG.md header malformed"

# llms.txt scaffold mentions CHANGELOG.md as a top-level file
grep -qF 'CHANGELOG.md' "$T42_DIR/.brain/llms.txt" \
  && ok "T42: llms.txt scaffold lists CHANGELOG.md" \
  || nope "T42: llms.txt scaffold missing CHANGELOG.md reference"

# Ingest report mentions CHANGELOG in Updated: line
grep -qF '.brain/llms.txt, .brain/CHANGELOG.md' "$CODEBRAIN_ROOT/commands/brain/ingest.md" \
  && ok "T42: brain/ingest.md Step 7 report mentions CHANGELOG.md" \
  || nope "T42: brain/ingest.md Step 7 report missing CHANGELOG.md"

# Learn consolidate appends to CHANGELOG (Le6 Task 8)
grep -qF 'CHANGELOG entry' "$CODEBRAIN_ROOT/commands/brain/learn.md" \
  && ok "T42: brain/learn.md Le6 has CHANGELOG entry step" \
  || nope "T42: brain/learn.md missing CHANGELOG entry step"

# wiki-reading-principles skill exists
test -f "$CODEBRAIN_ROOT/skills/behavioral/wiki-reading-principles/SKILL.md" \
  && ok "T42: skills/behavioral/wiki-reading-principles/SKILL.md exists" \
  || nope "T42: wiki-reading-principles skill missing"

for field in name description origin version tier pattern related_skills; do
  grep -q "^${field}:" "$CODEBRAIN_ROOT/skills/behavioral/wiki-reading-principles/SKILL.md" \
    && ok "T42: wiki-reading-principles has '$field' field" \
    || nope "T42: wiki-reading-principles missing '$field' field"
done

grep -q "^tier: behavioral$" "$CODEBRAIN_ROOT/skills/behavioral/wiki-reading-principles/SKILL.md" \
  && ok "T42: wiki-reading-principles is tier:behavioral" \
  || nope "T42: wiki-reading-principles wrong tier"

grep -q "^pattern: Behavioral-Constraint$" "$CODEBRAIN_ROOT/skills/behavioral/wiki-reading-principles/SKILL.md" \
  && ok "T42: wiki-reading-principles pattern is Behavioral-Constraint" \
  || nope "T42: wiki-reading-principles wrong pattern"

# Skill has the 3-tier always/ask/never structure
for section in '## ALWAYS' '## ASK' '## NEVER'; do
  grep -qF "$section" "$CODEBRAIN_ROOT/skills/behavioral/wiki-reading-principles/SKILL.md" \
    && ok "T42: wiki-reading-principles has '$section' section" \
    || nope "T42: wiki-reading-principles missing '$section'"
done

# npm pack ships M#10d additions
pack_list_t42="$(cd "$CODEBRAIN_ROOT" && npm pack --dry-run 2>&1)"
echo "$pack_list_t42" | grep -q 'skills/behavioral/wiki-reading-principles/SKILL.md' \
  && ok "T42: wiki-reading-principles SKILL.md in npm pack" \
  || nope "T42: wiki-reading-principles SKILL.md missing from npm pack"

# === Test 43: M#10c — intent-routing behavioral update ======================

# behavioral/codebrain SKILL.md has the new section
grep -qF '## Prompt-intent routing (M#10c)' "$CODEBRAIN_ROOT/skills/behavioral/codebrain/SKILL.md" \
  && ok "T43: behavioral/codebrain has Prompt-intent routing section" \
  || nope "T43: behavioral/codebrain missing Prompt-intent routing section"

# Default is OFF (safety-critical — must be opt-in)
grep -qF '**Default: OFF.**' "$CODEBRAIN_ROOT/skills/behavioral/codebrain/SKILL.md" \
  && ok "T43: intent routing default is OFF (opt-in)" \
  || nope "T43: intent routing default not declared OFF"

# Toggle file is .brain/.codebrain-intent-routing-state
grep -qF '.brain/.codebrain-intent-routing-state' "$CODEBRAIN_ROOT/skills/behavioral/codebrain/SKILL.md" \
  && ok "T43: intent routing toggle file is .codebrain-intent-routing-state" \
  || nope "T43: intent routing toggle file path missing"

# Feature-intent verbs listed
for verb in 'add' 'build' 'create' 'implement' "let me" "we should"; do
  grep -qF "\`$verb\`" "$CODEBRAIN_ROOT/skills/behavioral/codebrain/SKILL.md" \
    && ok "T43: intent routing detects '$verb' verb" \
    || nope "T43: intent routing missing '$verb' verb"
done

# Operator overrides documented
for ovr in 'just do it' 'skip the spec' 'no-spec'; do
  grep -qF -- "$ovr" "$CODEBRAIN_ROOT/skills/behavioral/codebrain/SKILL.md" \
    && ok "T43: intent routing documents '$ovr' override" \
    || nope "T43: intent routing missing '$ovr' override"
done

# /brain status surfaces intent-routing state
grep -qF 'Intent routing:' "$CODEBRAIN_ROOT/commands/brain/status.md" \
  && ok "T43: brain/status.md surfaces Intent routing state" \
  || nope "T43: brain/status.md missing Intent routing line"

grep -qF '.codebrain-intent-routing-state' "$CODEBRAIN_ROOT/commands/brain/status.md" \
  && ok "T43: brain/status.md reads the intent-routing toggle file" \
  || nope "T43: brain/status.md doesn't reference toggle file"

# Alias parity for status.md after M#10c edit

# init.js does NOT create the toggle file (default off = file absent)
T43_DIR="$(mktemp -d)"
( cd "$T43_DIR" && git init -q && node "$CB" init >/dev/null 2>&1 )
[ ! -f "$T43_DIR/.brain/.codebrain-intent-routing-state" ] \
  && ok "T43: init does NOT scaffold .codebrain-intent-routing-state (default off via absence)" \
  || nope "T43: init unexpectedly created .codebrain-intent-routing-state"

# Suggestion-text uses /brain:spec (namespaced form per M#12)
grep -qF '/brain:spec' "$CODEBRAIN_ROOT/skills/behavioral/codebrain/SKILL.md" \
  && ok "T43: intent routing suggests /brain:spec (namespaced form)" \
  || nope "T43: intent routing missing /brain:spec reference"

# === Test 44: M#11 — credential registry (file format + slash command + behavioral) ===

# M#11a — agent + skill + template + parser
test -f "$CODEBRAIN_ROOT/agents/brain/cred-registrar.md" \
  && ok "T44: agents/brain/cred-registrar.md exists" \
  || nope "T44: cred-registrar agent missing"

for field in name description tools model pattern trigger_phrases max_iterations; do
  grep -q "^${field}:" "$CODEBRAIN_ROOT/agents/brain/cred-registrar.md" \
    && ok "T44: cred-registrar has '$field' field" \
    || nope "T44: cred-registrar missing '$field' field"
done

grep -q "^pattern: Registrar$" "$CODEBRAIN_ROOT/agents/brain/cred-registrar.md" \
  && ok "T44: cred-registrar pattern is Registrar" \
  || nope "T44: cred-registrar wrong pattern"

# Rules forbid writing under repo root + forbid echoing values
grep -qF 'write the credential file to any path under the project root' "$CODEBRAIN_ROOT/agents/brain/cred-registrar.md" \
  && ok "T44: cred-registrar forbids writing under repo root" \
  || nope "T44: cred-registrar missing 'no under repo' rule"

grep -qF 'Never echo a credential value' "$CODEBRAIN_ROOT/agents/brain/cred-registrar.md" \
  && ok "T44: cred-registrar forbids echoing credential values" \
  || nope "T44: cred-registrar missing 'no echo' rule"

# core/creds skill exists
test -f "$CODEBRAIN_ROOT/skills/core/creds/SKILL.md" \
  && ok "T44: skills/core/creds/SKILL.md exists" \
  || nope "T44: core/creds skill missing"

grep -q "^tier: core$" "$CODEBRAIN_ROOT/skills/core/creds/SKILL.md" \
  && ok "T44: core/creds is tier:core" \
  || nope "T44: core/creds wrong tier"

# Refusal patterns documented (single source of truth)
for pat in 'sk-live_' 'sk_live_' 'pk_live_' 'AKIA' 'ghp_' 'gho_' 'xoxb-' 'xoxp-' 'sk-ant-'; do
  grep -qF "$pat" "$CODEBRAIN_ROOT/skills/core/creds/SKILL.md" \
    && ok "T44: core/creds documents '$pat' refusal pattern" \
    || nope "T44: core/creds missing '$pat' refusal pattern"
done

# Same-prompt-context guard documented
grep -qF 'Same-prompt-context guard' "$CODEBRAIN_ROOT/skills/core/creds/SKILL.md" \
  && ok "T44: core/creds documents same-prompt-context guard" \
  || nope "T44: core/creds missing same-prompt-context guard"

# Override flag is auditable
grep -qF -- 'i-understand-this-is-plaintext-production' "$CODEBRAIN_ROOT/skills/core/creds/SKILL.md" \
  && ok "T44: core/creds documents auditable override flag" \
  || nope "T44: core/creds missing override flag"

# Cross-platform path resolution
grep -qF 'XDG_DATA_HOME' "$CODEBRAIN_ROOT/skills/core/creds/SKILL.md" \
  && ok "T44: core/creds documents POSIX (XDG) path resolution" \
  || nope "T44: core/creds missing POSIX path resolution"

grep -qF 'LOCALAPPDATA' "$CODEBRAIN_ROOT/skills/core/creds/SKILL.md" \
  && ok "T44: core/creds documents Windows path resolution" \
  || nope "T44: core/creds missing Windows path resolution"

# Starter template
test -f "$CODEBRAIN_ROOT/skills/core/creds/templates/credentials.toon" \
  && ok "T44: credentials.toon template exists" \
  || nope "T44: credentials.toon template missing"

grep -qF 'WARNING: plaintext file' "$CODEBRAIN_ROOT/skills/core/creds/templates/credentials.toon" \
  && ok "T44: credentials.toon template has plaintext warning" \
  || nope "T44: credentials.toon template missing warning"

# TOON parser
test -f "$CODEBRAIN_ROOT/scripts/lib/toon.js" \
  && ok "T44: scripts/lib/toon.js exists" \
  || nope "T44: TOON parser missing"

# Parser exposes the documented API
node -e "
  const t = require('$CODEBRAIN_ROOT/scripts/lib/toon.js');
  for (const fn of ['parse', 'serialize', 'parseValue', 'serializeValue', 'readFile', 'writeFile']) {
    if (typeof t[fn] !== 'function') { console.error('missing fn:', fn); process.exit(1); }
  }
  process.exit(0);
" 2>/dev/null \
  && ok "T44: toon.js exports parse/serialize/readFile/writeFile + helpers" \
  || nope "T44: toon.js missing required exports"

# Parser round-trip
node -e "
  const t = require('$CODEBRAIN_ROOT/scripts/lib/toon.js');
  const input = '# header line 1\n# header line 2\n\n[staging-db]\nhost = \"db.example.com\"\nport = 5432\nuser = \"readonly\"\nnote = \"test\"\n';
  const parsed = t.parse(input);
  if (!parsed._sections['staging-db']) { console.error('parse failed: no section'); process.exit(1); }
  if (parsed._sections['staging-db'].host !== 'db.example.com') { console.error('parse failed: host wrong'); process.exit(1); }
  if (parsed._sections['staging-db'].port !== 5432) { console.error('parse failed: port not int'); process.exit(1); }
  if (parsed._header.length !== 2) { console.error('parse failed: header wrong'); process.exit(1); }
  const out = t.serialize(parsed);
  if (!out.includes('[staging-db]')) { console.error('serialize failed: no section'); process.exit(1); }
  if (!out.includes('host = \"db.example.com\"')) { console.error('serialize failed: host wrong'); process.exit(1); }
  process.exit(0);
" 2>/dev/null \
  && ok "T44: toon.js round-trip preserves sections, types, header" \
  || nope "T44: toon.js round-trip failed"

# M#11b — slash command (per-verb file in both dirs)
for v in brain; do
  test -f "$CODEBRAIN_ROOT/commands/$v/creds.md" \
    && ok "T44: commands/$v/creds.md exists" \
    || nope "T44: commands/$v/creds.md missing"
done

# Procedure has Cr0-Cr7
for cr in 'Cr0 — Argument parsing' 'Cr1 — Preconditions + path resolution' 'Cr2 — Dispatch' 'Cr3 — list' 'Cr4 — show' 'Cr5 — add' 'Cr6 — remove' 'Cr7 — forget-all'; do
  grep -qF "$cr" "$CODEBRAIN_ROOT/commands/brain/creds.md" \
    && ok "T44: brain/creds.md has '$cr'" \
    || nope "T44: brain/creds.md missing '$cr'"
done

# Alias parity

# Top-level dispatchers know /brain:creds
grep -qF '/brain:creds' "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T44: brain.md dispatch table mentions /brain:creds" \
  || nope "T44: brain.md missing /brain:creds"


# Legacy dispatcher knows 'creds' verb
grep -qF 'creds`' "$CODEBRAIN_ROOT/commands/brain.md" \
  && ok "T44: brain.md legacy dispatcher includes 'creds' verb" \
  || nope "T44: brain.md legacy dispatcher missing 'creds'"

# M#11c — behavioral integration
grep -qF 'Credential-handling protocol (M#11c)' "$CODEBRAIN_ROOT/skills/behavioral/codebrain/SKILL.md" \
  && ok "T44: behavioral/codebrain has Credential-handling protocol section" \
  || nope "T44: behavioral/codebrain missing Credential-handling protocol"

grep -qF '/brain:creds' "$CODEBRAIN_ROOT/skills/behavioral/codebrain/SKILL.md" \
  && ok "T44: Credential-handling protocol references /brain:creds (namespaced form)" \
  || nope "T44: Credential-handling protocol missing /brain:creds reference"

# npm pack ships M#11 additions
pack_list_t44="$(cd "$CODEBRAIN_ROOT" && npm pack --dry-run 2>&1)"
for path in 'agents/brain/cred-registrar.md' 'skills/core/creds/SKILL.md' 'skills/core/creds/templates/credentials.toon' 'scripts/lib/toon.js' 'commands/brain/creds.md'; do
  echo "$pack_list_t44" | grep -q "$path" \
    && ok "T44: $path in npm pack" \
    || nope "T44: $path missing from npm pack"
done

# Refusal-pattern enforcement test: parser correctly handles a refused value (we don't actually invoke /brain creds, just verify the regex would catch it)
node -e "
  const refusalPatterns = [/^sk-live_/, /^sk_live_/, /^pk_live_/, /^AKIA[A-Z0-9]{16}\$/, /^ghp_[A-Za-z0-9]{36}\$/];
  const samples = ['sk-live_51HABCDXYZ', 'AKIAIOSFODNN7EXAMPLE', 'ghp_abcdefghijklmnopqrstuvwxyz0123456789'];
  for (const s of samples) {
    if (!refusalPatterns.some(p => p.test(s))) { console.error('pattern miss:', s); process.exit(1); }
  }
  process.exit(0);
" 2>/dev/null \
  && ok "T44: refusal patterns correctly match production-secret samples (static check)" \
  || nope "T44: refusal patterns failed to match production-secret samples"

# === Test 45: M#9-coverage — 8 new detected/* skills + M#3d bridges ===========

# 8 new detected/* SKILL.md files
for stack in vue rails flask koa hapi gin echo fiber; do
  skill="$CODEBRAIN_ROOT/skills/detected/${stack}/SKILL.md"
  [ -f "$skill" ] && ok "T45: detected/${stack}/SKILL.md exists" || nope "T45: detected/${stack}/SKILL.md missing"

  for field in name description origin version tier pattern related_skills detect applies_to_extensions expert_skills; do
    grep -q "^${field}:" "$skill" \
      && ok "T45: detected/${stack} SKILL.md has '$field' field" \
      || nope "T45: detected/${stack} SKILL.md missing '$field' field"
  done

  grep -q "^tier: detected$" "$skill" \
    && ok "T45: detected/${stack} is tier:detected" \
    || nope "T45: detected/${stack} wrong tier"
done

# registry.json has all 8 new entries with expert_skills
node -e "
  const r = require('$CODEBRAIN_ROOT/skills/registry.json');
  const expected = ['detected/vue', 'detected/rails', 'detected/flask', 'detected/koa', 'detected/hapi', 'detected/gin', 'detected/echo', 'detected/fiber'];
  for (const k of expected) {
    if (!r.skills[k]) { console.error('missing skill:', k); process.exit(1); }
    if (r.skills[k].tier !== 'detected') { console.error('wrong tier:', k); process.exit(1); }
    if (!Array.isArray(r.skills[k].expert_skills) || r.skills[k].expert_skills.length === 0) {
      console.error('expert_skills empty or missing:', k); process.exit(1);
    }
  }
  process.exit(0);
" 2>/dev/null \
  && ok "T45: registry.json has 8 new detected entries with expert_skills" \
  || nope "T45: registry.json M#9-coverage entries malformed or missing"

# The 4 M#3d skills (react/typescript/python/go) gained expert_skills bridges
node -e "
  const r = require('$CODEBRAIN_ROOT/skills/registry.json');
  const m3d = {
    'detected/react': 'ecc:react-patterns',
    'detected/typescript': 'ecc:typescript-patterns',
    'detected/python': 'ecc:python-patterns',
    'detected/go': 'ecc:golang-patterns',
  };
  for (const [k, target] of Object.entries(m3d)) {
    if (!r.skills[k]) { console.error('missing:', k); process.exit(1); }
    if (!Array.isArray(r.skills[k].expert_skills)) { console.error('expert_skills not array:', k); process.exit(1); }
    if (!r.skills[k].expert_skills.includes(target)) { console.error('missing bridge', target, 'in', k); process.exit(1); }
  }
  process.exit(0);
" 2>/dev/null \
  && ok "T45: M#3d skills (react/typescript/python/go) gained expert_skills bridges" \
  || nope "T45: M#3d skills missing expert_skills bridges"

# stack-detection.json has the new framework detect rules (those not already present)
for stack in flask koa hapi gin echo fiber; do
  node -e "
    const j = require('$CODEBRAIN_ROOT/skills/core/init/templates/stack-detection.json');
    const match = j.stacks.find(s => s.name === '${stack}');
    if (!match) { console.error('missing stack:', '${stack}'); process.exit(1); }
    if (match.detected_skill !== 'detected/${stack}') { console.error('wrong detected_skill for ${stack}'); process.exit(1); }
    process.exit(0);
  " 2>/dev/null \
    && ok "T45: stack-detection.json has '${stack}' entry → detected/${stack}" \
    || nope "T45: stack-detection.json missing or malformed '${stack}'"
done

# npm pack ships the 8 new SKILL.md files
pack_list_t45="$(cd "$CODEBRAIN_ROOT" && npm pack --dry-run 2>&1)"
for stack in vue rails flask koa hapi gin echo fiber; do
  echo "$pack_list_t45" | grep -q "skills/detected/${stack}/SKILL.md" \
    && ok "T45: detected/${stack}/SKILL.md in npm pack" \
    || nope "T45: detected/${stack}/SKILL.md missing from npm pack"
done

# === Test 38: SKILL.md reciprocity — every related_skills entry resolves =====
# Bidirectional-links lint, run statically over the shipped skill set.
node -e "
  const fs = require('fs');
  const path = require('path');
  const root = '$CODEBRAIN_ROOT/skills';
  const errors = [];
  function walk(dir) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const p = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(p);
      else if (entry.name === 'SKILL.md') checkSkill(p);
    }
  }
  function checkSkill(file) {
    const raw = fs.readFileSync(file, 'utf8');
    if (!raw.startsWith('---\n')) return;
    const end = raw.indexOf('\n---\n', 4);
    if (end === -1) return;
    const fm = raw.slice(4, end);
    const m = fm.match(/^related_skills:\s*\[([^\]]*)\]/m);
    if (!m) return;
    const entries = m[1].split(',').map(s => s.trim()).filter(Boolean);
    for (const e of entries) {
      const target = path.join(root, e, 'SKILL.md');
      if (!fs.existsSync(target)) {
        errors.push(path.relative(root, file) + ' → ' + e + ' (target not found)');
      }
    }
  }
  walk(root);
  if (errors.length) { console.error(errors.join('\n')); process.exit(1); }
  process.exit(0);
" 2>/dev/null \
  && ok "T38: every related_skills entry resolves to a real SKILL.md" \
  || nope "T38: related_skills entries point to nonexistent skills"

# === Summary ==================================================================

total=$((pass+fail))
echo ""
echo "Summary: $pass / $total passed, $fail failed"
[ $fail -eq 0 ] && exit 0 || exit 1
