#!/bin/bash
# verify-task-update.sh
# SubagentStop hook for cw-execute workers
#
# Ensures workers that commit code also record completion evidence.
# This prevents task board inconsistency when workers exhaust context after committing.
#
# Single-writer contract: a committed worker signals completion through the
# durable journal handoff path only —
#   - CW-RESULT-BLOCK sentinel in the final message, OR
#   - an on-disk {task_id}.result.json under the run's results dir
# The legacy TaskUpdate(status='completed') branch has been removed; the
# dispatcher is the sole board writer and harvests journals/proofs directly.
#
# Decision logic:
# - No commit happened → Allow stop (incomplete work, cw-loop will retry)
# - Commit + journal evidence → Allow stop
# - Commit with no journal evidence → Block stop (write the journal + emit the sentinel)
#
# Best-effort, in-session only: this hook does not fire for headless `claude -p`
# workers or on SIGKILL. The dispatcher's git + proof harvest is the authority.

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

# Commit happened - look for durable journal evidence.

# Durable-journal contract: the CW-RESULT-BLOCK sentinel emitted in the final
# message, or an on-disk {task_id}.result.json written under a results dir.
JOURNAL_PRESENT=false
if grep -q 'CW-RESULT-BLOCK-START' "$TRANSCRIPT" 2>/dev/null; then
  JOURNAL_PRESENT=true
fi
# An on-disk {task_id}.result.json is equally valid, but only THIS worker's own
# journal counts — a stale journal from a prior task in the shared results dir
# must not satisfy an unrelated worker's gate. Scope the check to the task_id the
# worker names in its transcript.
if [ "$JOURNAL_PRESENT" = false ]; then
  TASK_ID=$(grep -o '"task_id":[ ]*"[^"]*"' "$TRANSCRIPT" 2>/dev/null \
    | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
  if [ -n "$TASK_ID" ] && \
     ls docs/specs/*/results/"$TASK_ID".result.json >/dev/null 2>&1; then
    JOURNAL_PRESENT=true
  fi
fi

# Journal evidence is the only accepted contract.
if [ "$JOURNAL_PRESENT" = true ]; then
  exit 0
fi

# FAILURE CASE: Commit happened but no journal evidence.
# Block the stop and instruct the worker to record the durable handoff.
cat << 'EOF'
{
  "decision": "block",
  "reason": "You committed code but recorded no completion evidence. Write the result journal and emit the sentinel:\n\n1. Write {task_id}.result.json into docs/specs/<run>/results/ (commit_sha, status, proof paths — see result-journal-schema.md).\n2. Emit the fenced CW-RESULT-BLOCK-START ... CW-RESULT-BLOCK-END sentinel as the final message, holding the same fields.\n\nThe dispatcher (sole board writer) harvests your journal directly — do not call TaskUpdate."
}
EOF
exit 0
