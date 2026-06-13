#!/bin/bash
# cwd-changed-worktree.sh
# CwdChanged hook for worktree context injection
#
# Fires when Claude Code changes directory. Detects if the new directory is within
# a .claude/worktrees/* (new) or .worktrees/* (legacy) path and injects worktree
# context (branch, task list status, available commands) so developers don't need
# to restart their session.
#
# Part of claude-workflow plugin - automatically active when plugin is installed

# Read hook input from stdin
INPUT=$(cat)

# Extract the new working directory from hook input
CURRENT_DIR=$(echo "$INPUT" | jq -r '.cwd // empty')

# Exit silently if no cwd provided
if [ -z "$CURRENT_DIR" ]; then
  exit 0
fi

# Detect worktree location: supports both .claude/worktrees/ (new) and .worktrees/ (legacy)
WORKTREE_NAME=""
WORKTREE_ROOT=""
if [[ "$CURRENT_DIR" == */.claude/worktrees/* ]]; then
  # New location: .claude/worktrees/{name}/...
  # Example: /project/.claude/worktrees/fix-myrepo-api/src -> fix-myrepo-api
  WORKTREE_NAME=$(echo "$CURRENT_DIR" | sed 's|^.*/\.claude/worktrees/||' | cut -d'/' -f1)
  # shellcheck disable=SC2001
  WORKTREE_ROOT=$(echo "$CURRENT_DIR" | sed "s|\(.*/.claude/worktrees/${WORKTREE_NAME}\).*|\1|")
elif [[ "$CURRENT_DIR" == */.worktrees/* ]]; then
  # Legacy location: .worktrees/{name}/...
  # Example: /project/.worktrees/feature-login/src -> feature-login
  WORKTREE_NAME=$(echo "$CURRENT_DIR" | sed 's|^.*/\.worktrees/||' | cut -d'/' -f1)
  # shellcheck disable=SC2001
  WORKTREE_ROOT=$(echo "$CURRENT_DIR" | sed "s|\(.*/.worktrees/${WORKTREE_NAME}\).*|\1|")
fi

if [ -n "$WORKTREE_NAME" ]; then
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

  # Extract branch name from worktree
  BRANCH_NAME=$(cd "$WORKTREE_ROOT" && git branch --show-current 2>/dev/null || echo "unknown")

  # Provide context to Claude about the worktree environment
  # Report the actual containing directory (new or legacy)
  CONTAINING_DIR="$WORKTREE_ROOT"
  # Prefer the configured task-list id from settings; fall back to the dir name
  TASK_ID="${CONFIGURED_ID:-$WORKTREE_NAME}"
  # Build the JSON with jq so quotes/backslashes in path-derived values
  # cannot break the hook output
  jq -n \
    --arg ctx "WORKTREE SESSION: You are working in git worktree '${CONTAINING_DIR}/' on branch '${BRANCH_NAME}'. ${STATUS}. Tasks persist across sessions in ~/.claude/tasks/${TASK_ID}/. Use /cw-spec, /cw-plan, /cw-dispatch, /cw-validate to manage the workflow. When complete, create a PR with 'gh pr create'." \
    '{"hookSpecificOutput":{"hookEventName":"CwdChanged","additionalContext":$ctx}}'
fi

exit 0
