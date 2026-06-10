#!/bin/bash
#
# worktree-remove-handler.sh
# WorktreeRemove hook handler for claude-workflow plugin.
#
# Reads a JSON payload from stdin (worktree_name, worktree_path) and performs
# best-effort cleanup. Always exits 0 — this hook is observability-only and
# cannot block the removal.
#
# Behavior:
#   - PRESERVES ~/.claude/tasks/{id}/ (the isolated task board) for resume.
#   - Attempts a best-effort herdr pane/tab close for the removed worktree.
#   - Never removes any task board data, never exits non-zero.
#
# Stdin JSON fields:
#   worktree_name   — slug/basename of the removed worktree (e.g. "fix-myrepo-login")
#   worktree_path   — absolute path to the (now-removed) worktree directory
#
# Exit codes:
#   0 — always (observability-only, cannot block)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CW_COMMON="$SCRIPT_DIR/lib/cw-common.sh"

if [ -f "$CW_COMMON" ]; then
    source "$CW_COMMON"
fi

# Override log functions so all output goes to stderr.
log_error()   { echo "[ERROR] $*" >&2; }
log_info()    { echo "[INFO] $*" >&2; }
log_success() { echo "[OK] $*" >&2; }
log_warning() { echo "[WARN] $*" >&2; }

# ---------------------------------------------------------------------------
# Parse stdin JSON
# ---------------------------------------------------------------------------

INPUT=$(cat)

worktree_name=$(printf '%s' "$INPUT" | jq -r '.worktree_name // empty' 2>/dev/null || true)
worktree_path=$(printf '%s' "$INPUT" | jq -r '.worktree_path // empty' 2>/dev/null || true)

log_info "WorktreeRemove: name='${worktree_name:-<none>}' path='${worktree_path:-<none>}'"

# ---------------------------------------------------------------------------
# Determine task board id from worktree basename
#
# The isolated task board id is the worktree directory basename, which
# matches CLAUDE_CODE_TASK_LIST_ID written by provision_worktree (full mode).
# We derive it from worktree_path when available, falling back to worktree_name.
# ---------------------------------------------------------------------------

task_board_id=""
if [ -n "$worktree_path" ]; then
    task_board_id="$(basename "$worktree_path")"
elif [ -n "$worktree_name" ]; then
    task_board_id="$worktree_name"
fi

# ---------------------------------------------------------------------------
# Preserve task board — NO deletion
#
# The task board at ~/.claude/tasks/{id}/ is intentionally preserved so the
# user can resume work on the task list associated with this worktree even
# after the worktree directory has been removed (e.g. with `claude --worktree`
# or `cw-worktree create` on a new worktree with the same slug).
# ---------------------------------------------------------------------------

CLAUDE_TASKS_DIR="${CLAUDE_TASKS_DIR:-$HOME/.claude/tasks}"

if [ -n "$task_board_id" ]; then
    task_board_dir="$CLAUDE_TASKS_DIR/$task_board_id"
    if [ -d "$task_board_dir" ]; then
        log_info "Preserving task board at: $task_board_dir (not deleted)"
    else
        log_info "No task board found at: $task_board_dir (nothing to preserve)"
    fi
fi

# ---------------------------------------------------------------------------
# Best-effort herdr pane close for the removed worktree
#
# Strategy: look up the tab whose label matches the worktree basename, then
# close that tab (which closes all panes inside it). This mirrors the layout
# maintained by cw-herdr-open: one tab per worktree, labeled by basename.
#
# All herdr operations are wrapped in `|| true` so failures never propagate.
# The HERDR_BIN env var can be overridden in tests.
# ---------------------------------------------------------------------------

HERDR_BIN="${HERDR_BIN:-herdr}"
HERDR_TIMEOUT=5

_herdr() {
    local rc=0
    if command -v timeout >/dev/null 2>&1; then
        timeout "$HERDR_TIMEOUT" "$HERDR_BIN" "$@" 2>/dev/null || rc=$?
    else
        "$HERDR_BIN" "$@" 2>/dev/null &
        local bg_pid=$!
        (sleep "$HERDR_TIMEOUT" && kill "$bg_pid" 2>/dev/null) &
        local killer_pid=$!
        wait "$bg_pid" 2>/dev/null || rc=$?
        kill "$killer_pid" 2>/dev/null || true
    fi
    return $rc
}

_herdr_close_worktree_tab() {
    local tab_label="$1"

    # Confirm herdr binary is available
    if ! command -v "$HERDR_BIN" >/dev/null 2>&1; then
        log_info "herdr not installed — skipping pane close"
        return 0
    fi

    # Probe the daemon socket (workspace list requires daemon to be up)
    local probe_exit=0
    if command -v timeout >/dev/null 2>&1; then
        timeout 2 "$HERDR_BIN" workspace list >/dev/null 2>&1 || probe_exit=$?
    else
        "$HERDR_BIN" workspace list >/dev/null 2>&1 &
        local probe_pid=$!
        (sleep 2 && kill "$probe_pid" 2>/dev/null) &
        local kp=$!
        wait "$probe_pid" 2>/dev/null || probe_exit=$?
        kill "$kp" 2>/dev/null || true
    fi
    if [ "$probe_exit" -ne 0 ]; then
        log_info "herdr daemon not reachable — skipping pane close"
        return 0
    fi

    # List all workspaces and search their tabs for one matching our label
    local ws_json
    ws_json="$(_herdr workspace list 2>/dev/null)" || { log_info "herdr workspace list failed — skipping pane close"; return 0; }

    local workspace_ids
    if command -v jq >/dev/null 2>&1; then
        workspace_ids=$(printf '%s' "$ws_json" | jq -r '.result.workspaces[].workspace_id' 2>/dev/null || true)
    else
        workspace_ids=$(printf '%s' "$ws_json" | grep -o '"workspace_id":"[^"]*"' | sed 's/"workspace_id":"//;s/"//')
    fi

    if [ -z "$workspace_ids" ]; then
        log_info "No herdr workspaces found — skipping pane close"
        return 0
    fi

    local tab_id=""
    while IFS= read -r ws_id; do
        [ -z "$ws_id" ] && continue
        local tab_json
        tab_json="$(_herdr tab list --workspace "$ws_id" 2>/dev/null)" || continue
        if command -v jq >/dev/null 2>&1; then
            tab_id=$(printf '%s' "$tab_json" | jq -r --arg lbl "$tab_label" \
                '.result.tabs[] | select(.label == $lbl) | .tab_id' 2>/dev/null | head -1)
        else
            tab_id=$(printf '%s' "$tab_json" \
                | grep -o "\"label\":\"${tab_label}\"[^}]*\"tab_id\":\"[^\"]*\"" \
                | grep -o '"tab_id":"[^"]*"' | head -1 | sed 's/"tab_id":"//;s/"//')
        fi
        [ -n "$tab_id" ] && break
    done <<< "$workspace_ids"

    if [ -z "$tab_id" ]; then
        log_info "No herdr tab found for label '$tab_label' — nothing to close"
        return 0
    fi

    log_info "Closing herdr tab '$tab_label' (id: $tab_id)"
    _herdr tab close "$tab_id" >/dev/null 2>&1 || log_warning "herdr tab close failed for tab $tab_id (best-effort)"
    log_success "herdr tab close attempted for '$tab_label'"
    return 0
}

# Derive the tab label: basename of the worktree path (or worktree_name)
tab_label=""
if [ -n "$worktree_path" ]; then
    tab_label="$(basename "$worktree_path")"
elif [ -n "$worktree_name" ]; then
    tab_label="$worktree_name"
fi

if [ -n "$tab_label" ]; then
    _herdr_close_worktree_tab "$tab_label" || true
else
    log_warning "No worktree_name or worktree_path in payload — cannot attempt herdr pane close"
fi

# ---------------------------------------------------------------------------
# Always exit 0 — observability-only hook cannot block removal
# ---------------------------------------------------------------------------

exit 0
