#!/bin/bash
# worktree-session-init.sh
# Validates task list configuration for worktree sessions and provides context to Claude
#
# Part of claude-workflow plugin - automatically active when plugin is installed

# CW_OVERRIDE_CWD is accepted for testing; in normal operation pwd is used.
CURRENT_DIR="${CW_OVERRIDE_CWD:-$(pwd)}"

# Read the SessionStart hook JSON input from stdin once. Malformed or empty
# stdin must not crash the hook: jq failures leave these empty via command
# substitution rather than aborting the script.
HOOK_INPUT=$(cat)
SOURCE=$(printf '%s' "$HOOK_INPUT" | jq -r '.source // empty' 2>/dev/null)
SESSION_TITLE_INPUT=$(printf '%s' "$HOOK_INPUT" | jq -r '.session_title // empty' 2>/dev/null)

# Detect worktree location: supports both .claude/worktrees/ (new) and .worktrees/ (legacy)
WORKTREE_NAME=""
WORKTREE_ROOT=""
if [[ "$CURRENT_DIR" == */.claude/worktrees/* ]]; then
  # New location: .claude/worktrees/{name}/...
  # Example: /project/.claude/worktrees/fix-myrepo-auth/src/lib -> fix-myrepo-auth
  WORKTREE_NAME=$(echo "$CURRENT_DIR" | sed 's|^.*/\.claude/worktrees/||' | cut -d'/' -f1)
  # shellcheck disable=SC2001
  WORKTREE_ROOT=$(echo "$CURRENT_DIR" | sed "s|\(.*/.claude/worktrees/${WORKTREE_NAME}\).*|\1|")
elif [[ "$CURRENT_DIR" == */.worktrees/* ]]; then
  # Legacy location: .worktrees/{name}/...
  # Example: /project/.worktrees/feature-myrepo-auth/src/lib -> feature-myrepo-auth
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
  # (keeps this hook consistent with cwd-changed-worktree.sh)
  TASK_ID="${CONFIGURED_ID:-$WORKTREE_NAME}"

  # Only set sessionTitle on startup/resume, and only if the caller hasn't
  # already set a title (via --name or a prior /rename) — never clobber it.
  SET_TITLE=false
  if [[ "$SOURCE" == "startup" || "$SOURCE" == "resume" ]] && [ -z "$SESSION_TITLE_INPUT" ]; then
    SET_TITLE=true
  fi

  # Build the JSON with jq so quotes/backslashes in path-derived values
  # cannot break the hook output
  jq -n \
    --arg ctx "WORKTREE SESSION: You are working in git worktree '${CONTAINING_DIR}/' on branch '${BRANCH_NAME}'. ${STATUS}. Tasks persist across sessions in ~/.claude/tasks/${TASK_ID}/. Use /cw-spec, /cw-plan, /cw-dispatch, /cw-validate to manage the workflow. When complete, create a PR with 'gh pr create'." \
    --arg title "$TASK_ID" \
    --argjson setTitle "$SET_TITLE" \
    '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":$ctx}}
     | if $setTitle then .hookSpecificOutput.sessionTitle = $title else . end'
fi

exit 0
