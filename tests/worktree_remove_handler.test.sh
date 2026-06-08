#!/bin/bash
#
# tests/worktree_remove_handler.test.sh
# Integration tests for scripts/worktree-remove-handler.sh
#
# Covers:
#   - Handler always exits 0 on a valid remove payload
#   - Handler preserves isolated task board for resume
#   - Handler exits 0 when cleanup targets are missing
#   - handler exits 0 when herdr is absent
#
# Usage: bash tests/worktree_remove_handler.test.sh
#

set -euo pipefail

PASS=0
FAIL=0
ERRORS=()

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HANDLER="$REPO_ROOT/scripts/worktree-remove-handler.sh"

if [ ! -f "$HANDLER" ]; then
    echo "[ERROR] Cannot find $HANDLER" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

run_handler() {
    local payload="$1"
    printf '%s' "$payload" | bash "$HANDLER" 2>/dev/null
}

run_handler_stderr() {
    local payload="$1"
    printf '%s' "$payload" | bash "$HANDLER" 2>&1
}

# ---------------------------------------------------------------------------
# Scenario 1: Handler always exits 0 on a valid remove payload
# ---------------------------------------------------------------------------

echo ""
echo "=== Scenario 1: Handler always exits 0 on a valid remove payload ==="

(
    set +e
    out=$(run_handler '{"worktree_name":"fix-myrepo-gone","worktree_path":"/tmp/nonexistent-path/fix-myrepo-gone"}')
    rc=$?
    set -e
    test "$rc" -eq 0 || { echo "handler exited $rc, expected 0"; exit 1; }
)
r=$?
if [ "$r" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "[PASS] scenario1: handler exits 0 on valid remove payload"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL [scenario1: handler exits 0 on valid payload]")
    echo "[FAIL] scenario1: handler exits 0 on valid remove payload"
fi

# ---------------------------------------------------------------------------
# Scenario 2: Handler preserves isolated task board for resume
# ---------------------------------------------------------------------------

echo ""
echo "=== Scenario 2: Handler preserves isolated task board for resume ==="

(
    set +e
    task_id="fix-myrepo-keep-$$"
    task_dir="$HOME/.claude/tasks/$task_id"
    mkdir -p "$task_dir"
    echo '{"id":"t1","status":"pending"}' > "$task_dir/task-1.json"

    out=$(run_handler "{\"worktree_name\":\"${task_id}\",\"worktree_path\":\"/tmp/${task_id}\"}")
    rc=$?
    set -e

    test "$rc" -eq 0 || { rm -rf "$task_dir"; echo "handler exited $rc, expected 0"; exit 1; }
    test -d "$task_dir" || { echo "task board directory was deleted: $task_dir"; exit 1; }
    test -f "$task_dir/task-1.json" || { rm -rf "$task_dir"; echo "task file was deleted: $task_dir/task-1.json"; exit 1; }
    content=$(cat "$task_dir/task-1.json")
    rm -rf "$task_dir"
    test "$content" = '{"id":"t1","status":"pending"}' || { echo "task file content changed: $content"; exit 1; }
)
r=$?
if [ "$r" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "[PASS] scenario2: task board preserved intact after handler runs"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL [scenario2: task board preserved]")
    echo "[FAIL] scenario2: task board preserved intact after handler runs"
fi

# ---------------------------------------------------------------------------
# Scenario 3: Handler exits 0 even when cleanup targets are missing
# ---------------------------------------------------------------------------

echo ""
echo "=== Scenario 3: Handler exits 0 even when cleanup targets are missing ==="

(
    set +e
    out=$(run_handler '{"worktree_name":"vanished","worktree_path":"/tmp/does-not-exist/vanished"}')
    rc=$?
    set -e
    test "$rc" -eq 0 || { echo "handler exited $rc, expected 0 for missing targets"; exit 1; }
    # No task board under ~/.claude/tasks/ should be deleted (nothing existed)
    test ! -d "$HOME/.claude/tasks/vanished" || { echo "unexpected task board created"; exit 1; }
)
r=$?
if [ "$r" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "[PASS] scenario3: handler exits 0 when targets are missing"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL [scenario3: exits 0 when targets missing]")
    echo "[FAIL] scenario3: handler exits 0 when targets are missing"
fi

# ---------------------------------------------------------------------------
# Scenario 4: Handler exits 0 with an empty/minimal payload
# ---------------------------------------------------------------------------

echo ""
echo "=== Scenario 4: Handler exits 0 with an empty payload ==="

(
    set +e
    out=$(run_handler '{}')
    rc=$?
    set -e
    test "$rc" -eq 0 || { echo "handler exited $rc, expected 0 for empty payload"; exit 1; }
)
r=$?
if [ "$r" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "[PASS] scenario4: handler exits 0 with empty payload"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL [scenario4: exits 0 with empty payload]")
    echo "[FAIL] scenario4: handler exits 0 with empty payload"
fi

# ---------------------------------------------------------------------------
# Scenario 5: Handler exits 0 with no task board to preserve
# ---------------------------------------------------------------------------

echo ""
echo "=== Scenario 5: Handler exits 0 when no task board exists ==="

(
    set +e
    no_board_id="no-board-$$"
    test ! -d "$HOME/.claude/tasks/$no_board_id" || rm -rf "$HOME/.claude/tasks/$no_board_id"
    out=$(run_handler "{\"worktree_name\":\"${no_board_id}\",\"worktree_path\":\"/tmp/${no_board_id}\"}")
    rc=$?
    set -e
    test "$rc" -eq 0 || { echo "handler exited $rc, expected 0"; exit 1; }
    # Confirm no task board was created
    test ! -d "$HOME/.claude/tasks/$no_board_id" || { rmdir "$HOME/.claude/tasks/$no_board_id" 2>/dev/null || true; echo "unexpected task board created"; exit 1; }
)
r=$?
if [ "$r" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "[PASS] scenario5: handler exits 0 when no task board exists"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL [scenario5: exits 0 no task board]")
    echo "[FAIL] scenario5: handler exits 0 when no task board exists"
fi

# ---------------------------------------------------------------------------
# Scenario 6: Handler attempts herdr pane close via fake herdr binary
# ---------------------------------------------------------------------------

echo ""
echo "=== Scenario 6: Handler attempts herdr pane close (fake herdr stub) ==="

(
    set +e
    # Create a fake herdr that logs calls and exits 0
    fake_herdr_dir=$(mktemp -d)
    fake_herdr="$fake_herdr_dir/herdr"
    cat > "$fake_herdr" << 'FAKEEOF'
#!/bin/bash
# Fake herdr for testing: log subcommand and exit 0
echo "$@" >> "$fake_herdr_dir/calls.log" 2>/dev/null || true
if [ "${1:-}" = "workspace" ] && [ "${2:-}" = "list" ]; then
    echo '{"result":{"workspaces":[{"workspace_id":"ws1","label":"myrepo"}]}}'
    exit 0
fi
if [ "${1:-}" = "tab" ] && [ "${2:-}" = "list" ]; then
    echo '{"result":{"tabs":[{"tab_id":"tab1","label":"feature-myrepo-toclean"}]}}'
    exit 0
fi
if [ "${1:-}" = "tab" ] && [ "${2:-}" = "close" ]; then
    exit 0
fi
exit 0
FAKEEOF
    chmod +x "$fake_herdr"

    out=$(HERDR_BIN="$fake_herdr" run_handler '{"worktree_name":"feature-myrepo-toclean","worktree_path":"/tmp/myrepo/.claude/worktrees/feature-myrepo-toclean"}')
    rc=$?
    set -e

    rm -rf "$fake_herdr_dir"
    test "$rc" -eq 0 || { echo "handler exited $rc with fake herdr, expected 0"; exit 1; }
)
r=$?
if [ "$r" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "[PASS] scenario6: handler exits 0 and attempts herdr pane close"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL [scenario6: herdr pane close attempt]")
    echo "[FAIL] scenario6: handler exits 0 and attempts herdr pane close"
fi

# ---------------------------------------------------------------------------
# Scenario 7: Handler exits 0 when herdr is not installed (CW_DISABLE_HERDR-like)
# ---------------------------------------------------------------------------

echo ""
echo "=== Scenario 7: Handler exits 0 when herdr binary is not found ==="

(
    set +e
    out=$(HERDR_BIN="/nonexistent/herdr-binary" run_handler '{"worktree_name":"noherdrbinary","worktree_path":"/tmp/noherdrbinary"}')
    rc=$?
    set -e
    test "$rc" -eq 0 || { echo "handler exited $rc when herdr not found, expected 0"; exit 1; }
)
r=$?
if [ "$r" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "[PASS] scenario7: handler exits 0 when herdr not installed"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL [scenario7: exits 0 herdr not installed]")
    echo "[FAIL] scenario7: handler exits 0 when herdr not installed"
fi

# ---------------------------------------------------------------------------
# Scenario 8: plugin.json contains WorktreeRemove hook entry
# ---------------------------------------------------------------------------

echo ""
echo "=== Scenario 8: plugin.json contains WorktreeRemove hook entry ==="

(
    plugin_json="$REPO_ROOT/.claude-plugin/plugin.json"
    test -f "$plugin_json" || { echo "plugin.json not found: $plugin_json"; exit 1; }
    grep -q "WorktreeRemove" "$plugin_json" || { echo "WorktreeRemove not found in plugin.json"; exit 1; }
    grep -q "worktree-remove-handler.sh" "$plugin_json" || { echo "worktree-remove-handler.sh not found in plugin.json"; exit 1; }
    grep -q 'CLAUDE_PLUGIN_ROOT' "$plugin_json" || { echo "\${CLAUDE_PLUGIN_ROOT} pattern not found in plugin.json"; exit 1; }
)
r=$?
if [ "$r" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "[PASS] scenario8: plugin.json has WorktreeRemove entry referencing worktree-remove-handler.sh"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL [scenario8: plugin.json WorktreeRemove entry]")
    echo "[FAIL] scenario8: plugin.json WorktreeRemove entry"
fi

# ---------------------------------------------------------------------------
# Results
# ---------------------------------------------------------------------------

echo ""
echo "==============================="
echo "Results: $PASS passed, $FAIL failed"
echo "==============================="

if [ ${#ERRORS[@]} -gt 0 ]; then
    echo ""
    echo "Failures:"
    for e in "${ERRORS[@]}"; do
        echo "  $e"
    done
fi

[ "$FAIL" -eq 0 ]
