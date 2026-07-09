#!/bin/bash
# verify-task-update.sh
# SubagentStop hook for cw-execute workers
#
# Ensures workers that commit code also record completion evidence.
# This prevents task board inconsistency when workers exhaust context after committing.
#
# Dual completion contract (this release): a committed worker may signal
# completion through EITHER handoff path —
#   - durable journal: the CW-RESULT-BLOCK sentinel in the final message, OR an
#     on-disk {task_id}.result.json under the run's results dir
#   - legacy board write: TaskUpdate(status='completed')
# The journal path is authoritative and the only one current worker protocols
# emit; the legacy branch is retained through this release for rollback safety
# so a session running an older worker protocol (e.g. the installed plugin
# cache, which still completes via TaskUpdate) is not wrongly blocked. It is
# removed only after the single-writer cut-over has proven out in production.
#
# Decision logic:
# - No commit happened → Allow stop (incomplete work; the dispatcher's dead-worker reset will re-queue this task)
# - Commit + (journal evidence OR TaskUpdate(completed)) → Allow stop
# - Commit with neither → Block stop (write the journal + emit the sentinel)
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

# Commit happened - look for completion evidence under EITHER contract.

# Durable-journal contract: the CW-RESULT-BLOCK sentinel emitted in the final
# message, or an on-disk {task_id}.result.json written under a results dir.
JOURNAL_PRESENT=false
if grep -q 'CW-RESULT-BLOCK-START' "$TRANSCRIPT" 2>/dev/null; then
  JOURNAL_PRESENT=true
fi
# An on-disk {task_id}.result.json is equally valid, but only THIS worker's own
# journal counts — a stale journal from a prior task in the shared results dir
# must not satisfy an unrelated worker's gate. Take the LAST task_id the worker
# names (its own completing TaskUpdate / result block sits at the end of the
# transcript); head -1 would pick an early-quoted sibling/dependency id and
# match a prior worker's journal.
if [ "$JOURNAL_PRESENT" = false ]; then
  TASK_ID=$(grep -o '"task_id":[ ]*"[^"]*"' "$TRANSCRIPT" 2>/dev/null \
    | tail -1 | sed 's/.*"\([^"]*\)"$/\1/')
  # The results dir is repo-relative, but SubagentStop's cwd is not guaranteed
  # to be the repo root (workers run under .claude/worktrees/<name>/). Resolve
  # the repo root from the payload cwd so a cwd-relative glob can't miss and
  # wrongly block a worker that did write its journal.
  HOOK_CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
  REPO_ROOT=$(git -C "${HOOK_CWD:-.}" rev-parse --show-toplevel 2>/dev/null) || true
  REPO_ROOT="${REPO_ROOT:-${HOOK_CWD:-.}}"
  if [ -n "$TASK_ID" ] && \
     ls "$REPO_ROOT"/docs/specs/*/results/"$TASK_ID".result.json >/dev/null 2>&1; then
    JOURNAL_PRESENT=true
  fi
fi

# Legacy board-write contract: TaskUpdate(status='completed'). Retained through
# this release for rollback safety (older worker protocols still complete this
# way); the journal path above is authoritative for current protocols.
TASK_UPDATED=false
if grep -q '"status":[ ]*"completed"' "$TRANSCRIPT" 2>/dev/null && \
   grep -q '"TaskUpdate"' "$TRANSCRIPT" 2>/dev/null; then
  TASK_UPDATED=true
fi

# Also check for the tool_name format
if grep -q '"tool_name":[ ]*"TaskUpdate"' "$TRANSCRIPT" 2>/dev/null && \
   grep -q '"status":[ ]*"completed"' "$TRANSCRIPT" 2>/dev/null; then
  TASK_UPDATED=true
fi

# Either contract satisfies the gate during this release.
if [ "$JOURNAL_PRESENT" = true ] || [ "$TASK_UPDATED" = true ]; then
  exit 0
fi

# FAILURE CASE: Commit happened but no completion evidence under either contract.
# Block the stop and instruct the worker to record the durable handoff.
cat << 'EOF'
{
  "decision": "block",
  "reason": "You committed code but recorded no completion evidence. Write the result journal and emit the sentinel:\n\n1. Write {task_id}.result.json into docs/specs/<run>/results/ (commit_sha, status, proof paths — see result-journal-schema.md).\n2. Emit the fenced CW-RESULT-BLOCK-START ... CW-RESULT-BLOCK-END sentinel as the final message, holding the same fields.\n\nThe dispatcher (sole board writer) harvests your journal directly; a completing TaskUpdate(status='completed') from an older worker protocol is also accepted this release."
}
EOF
exit 0
