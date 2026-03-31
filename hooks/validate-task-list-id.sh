#!/usr/bin/env bash
# PreToolUse hook: Block team-based skills (cw-dispatch-team, cw-review-team)
# when CLAUDE_CODE_TASK_LIST_ID is not set in the environment. Filtering to
# only fire for team-based skills is handled declaratively via the "if" field
# in hooks/hooks.json.

set -euo pipefail

# Read the tool input from stdin
INPUT=$(cat)

# Extract the skill name from the tool input JSON using jq.
# Strip any namespace prefix (e.g., "claude-workflow:cw-dispatch-team" -> "cw-dispatch-team")
SKILL_NAME=$(echo "$INPUT" | jq -r '(.tool_input.skill // "") | split(":") | last' 2>/dev/null || echo "")

# Check if CLAUDE_CODE_TASK_LIST_ID is set
if [ -z "${CLAUDE_CODE_TASK_LIST_ID:-}" ]; then
  # Suggest the non-team alternative based on which skill was invoked
  case "$SKILL_NAME" in
    cw-dispatch-team) ALT_SKILL="/cw-dispatch" ;;
    cw-review-team)   ALT_SKILL="/cw-review" ;;
    *)                ALT_SKILL="the non-team variant" ;;
  esac

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
