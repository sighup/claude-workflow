#!/bin/bash
# worktree-session-init.sh
# Automatically configure CLAUDE_CODE_TASK_LIST_ID for worktree sessions
# This enables persistent task lists that survive session restarts
#
# Part of claude-workflow plugin - automatically active when plugin is installed

CURRENT_DIR=$(pwd)

# Check if we're in a worktree under .worktrees/feature-*
if [[ "$CURRENT_DIR" == */.worktrees/feature-* ]]; then
  # Extract feature name from path (handles nested directories within the worktree)
  # Example: /project/.worktrees/feature-auth/src/lib -> auth
  FEATURE_NAME=$(echo "$CURRENT_DIR" | sed 's|^.*/\.worktrees/feature-||' | cut -d'/' -f1)

  if [ -n "$CLAUDE_ENV_FILE" ] && [ -n "$FEATURE_NAME" ]; then
    # Set task list ID for this feature - persists for the entire session
    echo "export CLAUDE_CODE_TASK_LIST_ID=\"feature-${FEATURE_NAME}\"" >> "$CLAUDE_ENV_FILE"

    # Provide context to Claude about the worktree environment
    cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "WORKTREE SESSION: You are working in git worktree '.worktrees/feature-${FEATURE_NAME}/' on branch 'feature/${FEATURE_NAME}'. Task list is isolated to this feature (CLAUDE_CODE_TASK_LIST_ID=feature-${FEATURE_NAME}). Tasks persist across sessions in ~/.claude/tasks/feature-${FEATURE_NAME}/. Use /cw-plan, /cw-dispatch, /cw-validate to manage the workflow. When complete, return to project root and run /cw-worktree merge ${FEATURE_NAME}."
  }
}
EOF
  fi
fi

exit 0
