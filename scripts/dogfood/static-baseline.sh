#!/usr/bin/env bash
# graphbrain dogfood — static-baseline.sh
#
# Gather measurements that don't require a Claude Code session: line counts,
# file inventory, frontmatter validity, agent/skill counts per pattern/tier,
# npm pack summary, test coverage. Outputs .claude/validation/v0.1-static-
# baseline.md for the validation report.
#
# Run anytime; updates the report file in place.

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEBRAIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REPORT="$CODEBRAIN_ROOT/.claude/validation/v0.1-static-baseline.md"

mkdir -p "$(dirname "$REPORT")"

# --- Gather metrics ---------------------------------------------------------

today="$(date -u +%Y-%m-%d)"
git_sha="$(cd "$CODEBRAIN_ROOT" && git rev-parse --short HEAD 2>/dev/null || echo 'untracked')"
pkg_version="$(node -e "console.log(require('$CODEBRAIN_ROOT/package.json').version)")"

# Line counts of shipped source files
loc() { wc -l < "$CODEBRAIN_ROOT/$1" 2>/dev/null | awk '{print $1}'; }
bin_loc=$(loc bin/graphbrain.js)
init_loc=$(loc scripts/init.js)
stale_loc=$(loc scripts/hooks/stale-detect.js)
guard_loc=$(loc scripts/hooks/verified-guard.js)
pageio_loc=$(loc scripts/hooks/lib/page-io.js)
brain_md_loc=$(loc commands/brain.md)
codebrain_md_loc=$(loc commands/graphbrain.md)
total_loc=$((bin_loc + init_loc + stale_loc + guard_loc + pageio_loc + brain_md_loc + codebrain_md_loc))

# Agent count + per-pattern breakdown
agent_files=$(find "$CODEBRAIN_ROOT/agents" -name '*.md' -not -name 'README.md' -type f 2>/dev/null)
agent_count=$(echo "$agent_files" | grep -c . || echo 0)

count_pattern() {
  local pattern="$1"
  local n=0
  local names=()
  for f in $agent_files; do
    if grep -q "^pattern: ${pattern}$" "$f" 2>/dev/null; then
      n=$((n+1))
      names+=("$(basename "$f" .md)")
    fi
  done
  echo "$n|${names[*]:-}"
}

meta=$(count_pattern Meta)
generator=$(count_pattern Generator)
reviewer=$(count_pattern Reviewer)
planner=$(count_pattern Planner)
researcher=$(count_pattern Researcher)
verifier=$(count_pattern Verifier)
observer=$(count_pattern Observer)

split_pat() { echo "$1" | cut -d'|' -f1; }
split_names() { echo "$1" | cut -d'|' -f2; }

# Skill count + per-tier breakdown
skill_files=$(find "$CODEBRAIN_ROOT/skills" -name 'SKILL.md' -type f 2>/dev/null)
skill_count=$(echo "$skill_files" | grep -c . || echo 0)

count_tier() {
  local tier="$1"
  local n=0
  local names=()
  for f in $skill_files; do
    if grep -q "^tier: ${tier}$" "$f" 2>/dev/null; then
      n=$((n+1))
      names+=("$(echo "$f" | sed "s|$CODEBRAIN_ROOT/skills/||; s|/SKILL.md||")")
    fi
  done
  echo "$n|${names[*]:-}"
}

t_behavioral=$(count_tier behavioral)
t_ingestion=$(count_tier ingestion)
t_core=$(count_tier core)
t_detected=$(count_tier detected)
t_available=$(count_tier available)

# Templates count
template_count=$(find "$CODEBRAIN_ROOT/skills" -path '*/templates/*' -name '*.md' -type f 2>/dev/null | wc -l | awk '{print $1}')

# npm pack summary
pack_summary="$(cd "$CODEBRAIN_ROOT" && npm pack --dry-run 2>&1)"
pack_files=$(echo "$pack_summary" | grep -c '^npm notice [0-9].*kB\|^npm notice 0B' || echo 0)
pack_size=$(echo "$pack_summary" | grep -E 'package size:' | awk -F'[: ]+' '{print $5, $6}' | head -1)

# Slash command surface
implemented_verbs=$(grep -oE '\*\*implemented \(M#[0-9a-z]+\)\*\*' "$CODEBRAIN_ROOT/commands/brain.md" | sort -u | wc -l | awk '{print $1}')
stubbed_milestones=$(grep -oE 'Milestone #[0-9a-z]+' "$CODEBRAIN_ROOT/commands/brain.md" | sort -u | tr '\n' ', ' | sed 's/,$//')

# Hook count
pre_hooks=$(grep -c "id: graphbrain:pre:" "$CODEBRAIN_ROOT/scripts/init.js" 2>/dev/null || echo 0)
post_hooks=$(grep -c "id: graphbrain:post:" "$CODEBRAIN_ROOT/scripts/init.js" 2>/dev/null || echo 0)

# Test coverage — parse from the actual test summary.
# Recursion guard: when invoked from inside e2e-test.sh (which has T32
# that runs us), skip the test run to avoid infinite loop. e2e-test.sh
# sets CODEBRAIN_BASELINE_NESTED=1 before invoking us.
if [ "${CODEBRAIN_BASELINE_NESTED:-0}" = "1" ]; then
  test_assertions="(skipped — nested invocation from e2e-test.sh)"
  test_passed="(skipped)"
  test_runtime="(skipped)"
else
  test_runtime_start=$(date +%s)
  test_output="$(bash "$CODEBRAIN_ROOT/tests/e2e-test.sh" 2>&1)"
  test_runtime_end=$(date +%s)
  test_runtime="$((test_runtime_end - test_runtime_start))s"
  # Summary line is like: "Summary: 432 / 432 passed, 0 failed"
  test_assertions=$(echo "$test_output" | grep -E '^Summary:' | sed -E 's/Summary: ([0-9]+) \/ ([0-9]+) passed.*/\2/' | head -1)
  test_passed=$(echo "$test_output" | grep -E '^Summary:' | sed -E 's/Summary: ([0-9]+) \/ ([0-9]+) passed.*/\1/' | head -1)
  test_assertions=${test_assertions:-0}
  test_passed=${test_passed:-0}
fi

# --- Write report -----------------------------------------------------------

cat > "$REPORT" <<EOF
# graphbrain v${pkg_version} — static baseline

**Generated**: ${today}
**Repo SHA**: ${git_sha}
**Generator**: \`scripts/dogfood/static-baseline.sh\`

This file is auto-generated. Do not edit manually. Re-run \`bash scripts/dogfood/static-baseline.sh\` to refresh.

## Shipped source files

| File | Lines |
|---|---|
| \`bin/graphbrain.js\` | ${bin_loc} |
| \`scripts/init.js\` | ${init_loc} |
| \`scripts/hooks/stale-detect.js\` | ${stale_loc} |
| \`scripts/hooks/verified-guard.js\` | ${guard_loc} |
| \`scripts/hooks/lib/page-io.js\` | ${pageio_loc} |
| \`commands/brain.md\` | ${brain_md_loc} |
| \`commands/graphbrain.md\` | ${codebrain_md_loc} |
| **Total core source LOC** | **${total_loc}** |

## Agents (${agent_count} total)

| Pattern | Count | Agents |
|---|---|---|
| Meta | $(split_pat "$meta") | $(split_names "$meta") |
| Generator | $(split_pat "$generator") | $(split_names "$generator") |
| Reviewer | $(split_pat "$reviewer") | $(split_names "$reviewer") |
| Planner | $(split_pat "$planner") | $(split_names "$planner") |
| Researcher | $(split_pat "$researcher") | $(split_names "$researcher") |
| Verifier | $(split_pat "$verifier") | $(split_names "$verifier") |
| Observer | $(split_pat "$observer") | $(split_names "$observer") |

## Skills (${skill_count} total)

| Tier | Count | Skills |
|---|---|---|
| behavioral | $(split_pat "$t_behavioral") | $(split_names "$t_behavioral") |
| ingestion | $(split_pat "$t_ingestion") | $(split_names "$t_ingestion") |
| core | $(split_pat "$t_core") | $(split_names "$t_core") |
| detected | $(split_pat "$t_detected") | $(split_names "$t_detected") |
| available | $(split_pat "$t_available") | $(split_names "$t_available") |

## Templates

| Total | ${template_count} |
|---|---|

## npm package

| | |
|---|---|
| package.json version | ${pkg_version} |
| npm pack files | ${pack_files} |
| npm pack total size | ${pack_size} |

## Hooks (in scripts/init.js codebrainOwnedHooks)

| Phase | Count |
|---|---|
| PreToolUse graphbrain entries | ${pre_hooks} |
| PostToolUse graphbrain entries | ${post_hooks} |

## Slash-command surface

| | |
|---|---|
| Implemented verbs | ${implemented_verbs} |
| Stubbed milestones | ${stubbed_milestones} |

## Test coverage

| | |
|---|---|
| e2e-test.sh assertions | ${test_assertions} |
| Passed | ${test_passed} / ${test_assertions} |
| Test runtime | ${test_runtime} |
EOF

echo "Static baseline written: $REPORT"
echo "Summary:"
echo "  Total source LOC: ${total_loc}"
echo "  Agents:           ${agent_count}"
echo "  Skills:           ${skill_count}"
echo "  Templates:        ${template_count}"
echo "  npm files/size:   ${pack_files} / ${pack_size}"
echo "  Test assertions:  ${test_assertions} (runtime ${test_runtime}s)"
