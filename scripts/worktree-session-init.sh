#!/bin/bash
# worktree-session-init.sh
# Validates task list configuration for worktree sessions and provides context to Claude
#
# Part of claude-workflow plugin - automatically active when plugin is installed

CURRENT_DIR=$(pwd)

# Check if we're in a worktree under .worktrees/*
if [[ "$CURRENT_DIR" == */.worktrees/* ]]; then
  # Extract worktree name from path (handles nested directories within the worktree)
  # Example: /project/.worktrees/feature-auth/src/lib -> feature-auth
  WORKTREE_NAME=$(echo "$CURRENT_DIR" | sed 's|^.*/\.worktrees/||' | cut -d'/' -f1)

  if [ -n "$WORKTREE_NAME" ]; then
    # Find the worktree root (where .claude/settings.local.json should be)
    WORKTREE_ROOT=$(echo "$CURRENT_DIR" | sed "s|\(.*/.worktrees/${WORKTREE_NAME}\).*|\1|")
    SETTINGS_FILE="${WORKTREE_ROOT}/.claude/settings.local.json"

    # Check if settings.local.json exists with task list ID
    if [ -f "$SETTINGS_FILE" ]; then
      # Verify it contains the correct task list ID
      if grep -q "CLAUDE_CODE_TASK_LIST_ID" "$SETTINGS_FILE"; then
        CONFIGURED_ID=$(grep "CLAUDE_CODE_TASK_LIST_ID" "$SETTINGS_FILE" | sed 's/.*: *"\([^"]*\)".*/\1/')
        STATUS="Task list configured: ${CONFIGURED_ID}"
      else
        STATUS="WARNING: .claude/settings.local.json exists but missing CLAUDE_CODE_TASK_LIST_ID"
      fi
    else
      STATUS="WARNING: Missing .claude/settings.local.json - tasks may go to wrong list. Run: mkdir -p .claude && echo '{\"env\":{\"CLAUDE_CODE_TASK_LIST_ID\":\"${WORKTREE_NAME}\"}}' > .claude/settings.local.json"
    fi

    # Extract branch name from worktree (if it follows feature/* pattern)
    BRANCH_NAME=$(cd "$WORKTREE_ROOT" && git branch --show-current 2>/dev/null || echo "unknown")

    # Provide context to Claude about the worktree environment
    cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "WORKTREE SESSION: You are working in git worktree '.worktrees/${WORKTREE_NAME}/' on branch '${BRANCH_NAME}'. ${STATUS}. Tasks persist across sessions in ~/.claude/tasks/${WORKTREE_NAME}/. Use /cw-spec, /cw-plan, /cw-dispatch, /cw-validate to manage the workflow. When complete, create a PR with 'gh pr create'."
  }
}
EOF
  fi
fi

exit 0
