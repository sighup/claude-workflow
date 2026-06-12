#!/bin/bash
#
# scripts/guard-fixtures/detect-wipe-test.sh - Hermetic tests for
# detect-board-wipe.sh, the PostToolBatch synchronous wipe-detection hook.
#
# Each case runs the real hook as a subprocess with a synthetic PostToolBatch
# payload on stdin and an isolated CW_TASKS_DIR, then asserts the board state.
# No real sleeps, no wall-clock dependence, no live wipe needed. Exit 0 iff all
# cases pass.
#
# Covers the judge's pre-merge validations:
#   (a) a no-task batch is rejected at Stage 1 (no restore, inert)
#   (b) the proven 3x TaskUpdate wipe batch restores from the shadow
#   (c) off-cw / below-signature / non-empty boards never trigger a false restore

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${HERE}/../detect-board-wipe.sh"

PASS=0
FAIL=0
note() { printf '  %s\n' "$1"; }
ok()   { PASS=$((PASS + 1)); printf 'PASS: %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf 'FAIL: %s — %s\n' "$1" "$2"; }

# Run the hook in a fresh hermetic tasks root. Args: <case-name> <cwd> <payload>
# Sets globals: T (temp root), LIVE_DIR, SHADOW_DIR for the caller to inspect.
setup() {
  T="$(mktemp -d)"
  LIST="wtlist"
  LIVE_DIR="${T}/${LIST}"
  SHADOW_DIR="${T}/.guard/${LIST}"
  mkdir -p "$LIVE_DIR" "$SHADOW_DIR"
}
run_hook() { # cwd(unused; cwd travels in payload .cwd) payload
  printf '%s' "$2" | \
    CW_TASKS_DIR="$T" CW_GUARD_MIN_TASKS=2 CW_LEASE_SH="${T}/no-lease-sh" \
    bash "$HOOK"
}
live_count()   { find "$LIVE_DIR"   -maxdepth 1 -name '[0-9]*.json' 2>/dev/null | wc -l | tr -d ' '; }
shadow_seed()  { local n; for n in "$@"; do printf '{"task_id":"T%s"}\n' "$n" > "${SHADOW_DIR}/${n}.json"; done; }
live_seed()    { local n; for n in "$@"; do printf '{"task_id":"T%s"}\n' "$n" > "${LIVE_DIR}/${n}.json"; done; }

WT_CWD_BASE="/tmp/repo/.claude/worktrees/wtlist"   # marker + WT_NAME=wtlist (fallback list id)

# --- Case 1: no-task batch (Stage 1 reject) ---------------------------------
# A REPL-only batch must not restore even when a wiped board + full shadow exist.
setup
shadow_seed 1 2 3                 # shadow holds 3; live empty (looks wiped)
run_hook "$WT_CWD_BASE" '{"cwd":"'"$WT_CWD_BASE"'","tool_calls":[{"tool_name":"REPL","tool_input":{}}]}' >/dev/null 2>&1
if [ "$(live_count)" = "0" ]; then ok "no-task batch is inert (Stage 1)"; else bad "no-task batch is inert (Stage 1)" "restored $(live_count) files"; fi
rm -rf "$T"

# --- Case 2: task batch but OFF a cw worktree (Stage 2 reject) ---------------
setup
shadow_seed 1 2 3
run_hook "/tmp/plain-repo" '{"cwd":"/tmp/plain-repo","tool_calls":[{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"completed"}}]}' >/dev/null 2>&1
if [ "$(live_count)" = "0" ]; then ok "off-cw task batch is inert (Stage 2)"; else bad "off-cw task batch is inert (Stage 2)" "restored $(live_count) files"; fi
rm -rf "$T"

# --- Case 3: the proven wipe batch restores (3x parallel TaskUpdate) ---------
setup
shadow_seed 1 2 3                 # pre-wipe board mirrored to shadow
# live is empty => wipe signature; payload is the proven 3x TaskUpdate batch
P3='{"cwd":"'"$WT_CWD_BASE"'","tool_calls":[{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"completed"}},{"tool_name":"TaskUpdate","tool_input":{"taskId":"2","status":"completed"}},{"tool_name":"TaskUpdate","tool_input":{"taskId":"3","status":"completed"}}]}'
run_hook "$WT_CWD_BASE" "$P3" >/dev/null 2>&1
if [ "$(live_count)" = "3" ]; then ok "wipe batch restores 3 files synchronously"; else bad "wipe batch restores 3 files synchronously" "live count is $(live_count), want 3"; fi
rm -rf "$T"

# --- Case 4: below signature (shadow < MIN_TASKS) never restores -------------
setup
shadow_seed 1                     # only 1 in shadow; MIN_TASKS=2
run_hook "$WT_CWD_BASE" "$P3" >/dev/null 2>&1
if [ "$(live_count)" = "0" ]; then ok "below-signature board is not restored"; else bad "below-signature board is not restored" "restored $(live_count) files"; fi
rm -rf "$T"

# --- Case 5: non-empty live board is left alone -----------------------------
setup
shadow_seed 1 2 3
live_seed 1 2                     # board not empty => not a wipe
run_hook "$WT_CWD_BASE" "$P3" >/dev/null 2>&1
if [ "$(live_count)" = "2" ]; then ok "non-empty board left untouched"; else bad "non-empty board left untouched" "live count is $(live_count), want 2"; fi
rm -rf "$T"

echo "----"
echo "detect-wipe: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
