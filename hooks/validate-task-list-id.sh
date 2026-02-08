#!/usr/bin/env bash
# PreToolUse hook: Block cw-dispatch-team when CLAUDE_CODE_TASK_LIST_ID
# is not set in the environment. Other skills (cw-dispatch, cw-execute,
# cw-validate, cw-plan) are allowed through without the env var.

set -euo pipefail

# Read the tool input from stdin
INPUT=$(cat)

# Extract the skill name from the tool input JSON.
# The Skill tool receives { "skill": "skill-name", ... }
SKILL_NAME=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    # tool_input is the nested input passed to the Skill tool
    tool_input = data.get('tool_input', data)
    print(tool_input.get('skill', ''))
except Exception:
    print('')
" 2>/dev/null || echo "")

# Strip any prefix (e.g., "claude-workflow:cw-dispatch" -> "cw-dispatch")
SKILL_NAME="${SKILL_NAME##*:}"

# Only gate cw-dispatch-team (persistent teams require CLAUDE_CODE_TASK_LIST_ID).
# All other skills (cw-dispatch, cw-execute, cw-validate, cw-plan) are allowed.
case "$SKILL_NAME" in
  cw-dispatch-team)
    ;;
  *)
    # Not a gated skill — allow
    exit 0
    ;;
esac

# Check if CLAUDE_CODE_TASK_LIST_ID is set
if [ -z "${CLAUDE_CODE_TASK_LIST_ID:-}" ]; then
  echo "CLAUDE_CODE_TASK_LIST_ID is not set." >&2
  echo "" >&2
  echo "/cw-dispatch-team requires this env var so all teammates share the project task list." >&2
  echo "Without it, teammates use a separate team-scoped list and tasks diverge." >&2
  echo "" >&2
  echo "Tip: Use /cw-dispatch instead for zero-config parallel subagent workers." >&2
  echo "" >&2
  echo "To configure for team mode, run /cw-plan or add manually to .claude/settings.json:" >&2
  echo '  { "env": { "CLAUDE_CODE_TASK_LIST_ID": "your-project-name" } }' >&2
  echo "" >&2
  echo "Then restart your Claude Code session (env vars are captured at startup)." >&2
  exit 2
fi

# Env var is set — allow
exit 0
