#!/usr/bin/env bash
# PreToolUse hook: Block team-based skills (cw-dispatch-team, cw-review-team)
# when CLAUDE_CODE_TASK_LIST_ID is not set in the environment.
#
# Filtering happens in this script (not via the "if" field in hooks.json)
# because the "if" field accepts only a single permission rule — boolean
# operators like || are silently rejected, which would cause this hook to
# fire on every Skill invocation.

set -euo pipefail

# Read the tool input from stdin
INPUT=$(cat)

# Extract the skill name from the tool input JSON using jq.
# Strip any namespace prefix (e.g., "claude-workflow:cw-dispatch-team" -> "cw-dispatch-team")
SKILL_NAME=$(echo "$INPUT" | jq -r '(.tool_input.skill // "") | split(":") | last' 2>/dev/null || echo "")

# Only gate team-based skills; allow everything else through.
case "$SKILL_NAME" in
  cw-dispatch-team) ALT_SKILL="/cw-dispatch" ;;
  cw-review-team)   ALT_SKILL="/cw-review" ;;
  *)                exit 0 ;;
esac

# Check if CLAUDE_CODE_TASK_LIST_ID is set
if [ -z "${CLAUDE_CODE_TASK_LIST_ID:-}" ]; then
  echo "CLAUDE_CODE_TASK_LIST_ID is not set." >&2
  echo "" >&2
  echo "/$SKILL_NAME requires this env var so all teammates share the project task list." >&2
  echo "Without it, teammates use a separate team-scoped list and tasks diverge." >&2
  echo "" >&2
  echo "Tip: Use $ALT_SKILL instead for zero-config parallel subagent workers." >&2
  echo "" >&2
  echo "To configure for team mode, run /cw-plan or add manually to .claude/settings.json:" >&2
  echo '  { "env": { "CLAUDE_CODE_TASK_LIST_ID": "your-project-name" } }' >&2
  echo "" >&2
  echo "Then restart your Claude Code session (env vars are captured at startup)." >&2
  exit 2
fi

# Env var is set — allow
exit 0
