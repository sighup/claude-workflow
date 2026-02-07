#!/usr/bin/env bash
# PreToolUse hook: Block cw-dispatch, cw-execute, and cw-validate
# when CLAUDE_CODE_TASK_LIST_ID is not set in the environment.
# cw-plan is allowed through so it can auto-configure the env var.

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

# Only gate specific cw-* skills (cw-plan is allowed through for auto-setup)
case "$SKILL_NAME" in
  cw-dispatch|cw-execute|cw-validate)
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
  echo "Agent teams require this env var to share the project task list." >&2
  echo "Without it, teammates use a separate team-scoped list and tasks diverge." >&2
  echo "" >&2
  echo "Run /cw-plan to auto-configure it, or add it manually to .claude/settings.json:" >&2
  echo '  { "env": { "CLAUDE_CODE_TASK_LIST_ID": "your-project-name" } }' >&2
  echo "" >&2
  echo "Then restart your Claude Code session (env vars are captured at startup)." >&2
  exit 2
fi

# Env var is set — allow
exit 0
