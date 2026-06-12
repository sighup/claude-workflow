#!/bin/bash
#
# scripts/detect-board-wipe.sh - PostToolBatch hook: synchronous board-wipe
# detection that closes the polling guard's ~1s race.
#
# Background. task-store-guard.sh restores a wiped task board, but it polls on a
# timer (~1s). A wipe can land and the model can read the empty board before the
# next poll restores it. PostToolBatch is the only interception point causally
# ordered with the model: it fires once per parallel tool batch, AFTER the batch
# resolves and BEFORE the next model call, and it sees the exact parallel
# TaskUpdate batch that triggers a wipe. This hook restores on that signature
# synchronously — before the model's next turn.
#
# Scope and cost. PostToolBatch fires for EVERY tool batch in EVERY plugin-loaded
# session (most of which touch no task tool and run outside any cw worktree).
# So this is built around a two-stage early exit:
#   Stage 1 - a pure-bash substring test for a Task* tool name. Absent -> exit 0
#             with no subprocess and no file I/O. This is the >99% path.
#   Stage 2 - resolve the cw worktree + task list id from the batch's cwd. Not a
#             cw worktree, or no list id -> exit 0. Off-cw sessions are inert.
# Only a task-tool batch inside a cw worktree reaches the wipe check.
#
# Behaviour. DETECT-AND-RESTORE only; it never blocks the agentic loop (no
# exit 2). The SessionStart guard daemon remains the system of record and the
# only component that can restore across sessions (it can recover a board wiped
# by a session that never loaded this hook); this hook reuses that daemon's
# shadow journal and its guard_restore (lease-deferral, evidence-newer skip,
# symlink safety, incident logging) and adds no new source of truth. If a future
# Claude Code release changes or drops PostToolBatch, this hook simply stops
# firing and posture falls back to the fixture-tested daemon — never below today.

set -u

INPUT=$(cat 2>/dev/null || true)

# --- Stage 1: cheapest possible reject (no task tool in this batch) ----------
# The batch payload names each call as "tool_name":"TaskUpdate" etc. If the
# substring "Task does not appear at all, no task tool ran — bail with zero I/O.
# A spurious match (the literal appearing elsewhere) only falls through to the
# equally-cheap Stage 2; correctness does not depend on this being exact.
case "$INPUT" in
  *'"Task'*) : ;;
  *) exit 0 ;;
esac

# --- Stage 2: cw-worktree scoping -------------------------------------------
# Resolve the session cwd from the hook payload (authoritative; the hook process
# cwd may differ), then derive the task list id exactly as the guard daemon does
# at SessionStart. Outside a cw worktree LIST_ID stays empty and the hook is inert.
CWD=""
if command -v jq >/dev/null 2>&1; then
  CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
fi
[ -n "$CWD" ] || CWD="$(pwd)"

LIST_ID=""
for marker in "/.claude/worktrees/" "/.worktrees/"; do
  if [[ "$CWD" == *"${marker}"* ]]; then
    WT_NAME="${CWD#*"${marker}"}"; WT_NAME="${WT_NAME%%/*}"
    SETTINGS="${CWD%%"${marker}"*}${marker}${WT_NAME}/.claude/settings.local.json"
    if [ -f "$SETTINGS" ] && command -v jq >/dev/null 2>&1; then
      LIST_ID=$(jq -r '.env.CLAUDE_CODE_TASK_LIST_ID // empty' "$SETTINGS" 2>/dev/null)
    fi
    [ -n "$LIST_ID" ] || LIST_ID="$WT_NAME"
    break
  fi
done
[ -n "$LIST_ID" ] || exit 0

# --- Source the guard for shadow state + restore logic ----------------------
# Only reached for a task-tool batch inside a cw worktree (rare), so the cost of
# sourcing the guard is off the hot path. Sourcing defines count_tasks,
# guard_restore, lease_holder, and the TASKS_ROOT/GUARD_ROOT/MIN_TASKS globals;
# its CLI dispatch is skipped (BASH_SOURCE guard) so no daemon is spawned.
GUARD_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/task-store-guard.sh"
[ -f "$GUARD_SH" ] || exit 0
# shellcheck source=/dev/null
. "$GUARD_SH" || exit 0

# --- Wipe check + synchronous restore ---------------------------------------
LIST_DIR="${TASKS_ROOT}/${LIST_ID}"
SHADOW="${GUARD_ROOT}/${LIST_ID}"

# List dir must exist and not be a symlink (never follow one out of the root).
{ [ -d "$LIST_DIR" ] && [ ! -L "$LIST_DIR" ]; } || exit 0

LIVE=$(count_tasks "$LIST_DIR")
[ "$LIVE" -eq 0 ] || exit 0                       # board not empty -> no wipe

# The shadow (maintained by the daemon's mirror) stands in for the pre-wipe
# count. Empty board while the shadow holds >= MIN_TASKS is the wipe signature.
SHADOW_COUNT=$(count_tasks "$SHADOW")
[ "$SHADOW_COUNT" -ge "$MIN_TASKS" ] || exit 0    # below signature -> not a wipe

log_incident "$LIST_ID" "PostToolBatch wipe signature: live board emptied while shadow holds ${SHADOW_COUNT}; synchronous restore (pre-empting poll)"
# guard_restore handles lease-deferral, evidence-newer skip, symlink safety and
# its own incident logging. Idempotent with the daemon (cp -p of the same files).
guard_restore "$LIST_ID" "$LIST_DIR" "$SHADOW" "$SHADOW_COUNT" >/dev/null 2>&1 || true

exit 0
