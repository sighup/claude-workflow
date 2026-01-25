#!/bin/bash
# verify-task-update.sh
# SubagentStop hook for cw-execute workers
#
# Ensures workers that commit code also call TaskUpdate(status='completed').
# This prevents task board inconsistency when workers exhaust context after committing.
#
# Decision logic:
# - No commit happened → Allow stop (incomplete work, cw-loop will retry)
# - Commit + TaskUpdate(completed) → Allow stop (protocol complete)
# - Commit without TaskUpdate(completed) → Block stop (must complete Phase 10)

set -e

# Read hook input from stdin
INPUT=$(cat)

# Extract agent transcript path
TRANSCRIPT=$(echo "$INPUT" | jq -r '.agent_transcript_path // empty')

# If no transcript or file doesn't exist, allow stop (not a cw-execute worker)
if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
  exit 0
fi

# Check if this looks like a cw-execute worker by looking for CW-EXECUTE marker
if ! grep -q "CW-EXECUTE" "$TRANSCRIPT" 2>/dev/null; then
  # Not a cw-execute worker, allow stop
  exit 0
fi

# Check if a git commit succeeded
# Look for Bash tool calls containing 'git commit' that completed successfully
COMMIT_HAPPENED=false
if grep -q '"git commit"' "$TRANSCRIPT" 2>/dev/null; then
  # Look for commit success indicators
  if grep -E '(committed|create mode|files changed|insertions|deletions|\[.*\]\s+\w+:)' "$TRANSCRIPT" 2>/dev/null | grep -qv 'error\|failed\|fatal'; then
    COMMIT_HAPPENED=true
  fi
fi

# Alternative: check for commit_sha in TaskUpdate metadata (more reliable)
if grep -q '"commit_sha"' "$TRANSCRIPT" 2>/dev/null; then
  COMMIT_HAPPENED=true
fi

# If no commit happened, allow stop (incomplete work, will retry)
if [ "$COMMIT_HAPPENED" = false ]; then
  exit 0
fi

# Commit happened - check if TaskUpdate was called with status='completed'
TASK_UPDATED=false
if grep -q '"status":\s*"completed"' "$TRANSCRIPT" 2>/dev/null && \
   grep -q '"TaskUpdate"' "$TRANSCRIPT" 2>/dev/null; then
  TASK_UPDATED=true
fi

# Also check for the tool_name format
if grep -q '"tool_name":\s*"TaskUpdate"' "$TRANSCRIPT" 2>/dev/null && \
   grep -q '"status":\s*"completed"' "$TRANSCRIPT" 2>/dev/null; then
  TASK_UPDATED=true
fi

# If TaskUpdate was called, allow stop
if [ "$TASK_UPDATED" = true ]; then
  exit 0
fi

# FAILURE CASE: Commit happened but TaskUpdate wasn't called
# Block the stop and instruct the worker to complete Phase 10
cat << 'EOF'
{
  "decision": "block",
  "reason": "You committed code but did not call TaskUpdate. Complete Phase 10 of the cw-execute protocol:\n\nTaskUpdate({\n  taskId: '<your-task-id>',\n  status: 'completed',\n  metadata: {\n    proof_dir: 'docs/specs/.../NN-proofs',\n    commit_sha: '<sha from git log --oneline -1>',\n    completed_at: '<ISO timestamp>'\n  }\n})\n\nThis ensures the task board reflects your completed work."
}
EOF
exit 0
