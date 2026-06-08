#!/bin/bash
#
# tests/create_worktree.test.sh - Integration tests for create_worktree()
#
# Verifies that create_worktree() delegates to provision_worktree (full mode):
#   - Canonical names are derived via cw_worktree_names
#   - Worktrees are placed under .claude/worktrees/
#   - Isolated task list (settings.local.json) is written with the correct ID
#
# Usage: bash tests/create_worktree.test.sh
#

set -euo pipefail

PASS=0
FAIL=0
ERRORS=()

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CW_COMMON="$REPO_ROOT/bin/lib/cw-common.sh"

if [ ! -f "$CW_COMMON" ]; then
    echo "[ERROR] Cannot find $CW_COMMON" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Helpers: log stubs + source cw-common.sh
# ---------------------------------------------------------------------------

log_error()   { echo "[error] $*" >&2; }
log_info()    { :; }
log_success() { :; }
log_warning() { :; }
export -f log_error log_info log_success log_warning

source "$CW_COMMON"

# Build a scratch git repo and return its path via stdout.
make_scratch_repo() {
    local name="${1:-claude-workflow}"
    local tmpdir
    tmpdir=$(mktemp -d)
    local repo="$tmpdir/$name"
    mkdir -p "$repo"
    git -C "$repo" init -q
    git -C "$repo" config user.email "test@test.com"
    git -C "$repo" config user.name "Test"
    # Need at least one commit so worktree add works
    touch "$repo/README"
    git -C "$repo" add README
    git -C "$repo" commit -q -m "init"
    echo "$repo"
}

cleanup() {
    local dir="$1"
    rm -rf "$dir"
}

# ---------------------------------------------------------------------------
# Scenario 1: Default feature slug produces repo-qualified names
#             under .claude/worktrees/ (delegation to provision_worktree)
# ---------------------------------------------------------------------------

echo ""
echo "=== Scenario 1: Default feature slug (login) — .claude/worktrees/ ==="

tmp=$(make_scratch_repo "claude-workflow")
(
    cd "$tmp"
    source "$CW_COMMON"
    create_worktree "login" >/dev/null 2>&1
    test -d ".claude/worktrees/feature-claude-workflow-login"     || { echo "worktree dir not found under .claude/worktrees/"; exit 1; }
    got_branch=$(git branch --list "feature/login")
    test -n "$got_branch"                                          || { echo "branch feature/login not found"; exit 1; }
    got_id=$(jq -r '.env.CLAUDE_CODE_TASK_LIST_ID' .claude/worktrees/feature-claude-workflow-login/.claude/settings.local.json 2>/dev/null)
    test "$got_id" = "feature-claude-workflow-login"               || { echo "task list id wrong: $got_id"; exit 1; }
)
r=$?
if [ "$r" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "[PASS] scenario1: feature-claude-workflow-login created under .claude/worktrees/"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL [scenario1: feature slug — .claude/worktrees/]")
    echo "[FAIL] scenario1: feature-claude-workflow-login"
fi
cleanup "$tmp"

# ---------------------------------------------------------------------------
# Scenario 2: Non-feature slug (fix-login) uses correct type prefix
# ---------------------------------------------------------------------------

echo ""
echo "=== Scenario 2: Non-feature slug (fix-login) ==="

tmp=$(make_scratch_repo "claude-workflow")
(
    cd "$tmp"
    source "$CW_COMMON"
    create_worktree "fix-login" >/dev/null 2>&1
    test -d ".claude/worktrees/fix-claude-workflow-login"     || { echo "worktree dir not found under .claude/worktrees/"; exit 1; }
    got_branch=$(git branch --list "fix/login")
    test -n "$got_branch"                                      || { echo "branch fix/login not found"; exit 1; }
)
r=$?
if [ "$r" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "[PASS] scenario2: fix-claude-workflow-login created under .claude/worktrees/"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL [scenario2: fix slug]")
    echo "[FAIL] scenario2: fix-claude-workflow-login"
fi
cleanup "$tmp"

# ---------------------------------------------------------------------------
# Scenario 3: Task list ID equals worktree directory basename
# ---------------------------------------------------------------------------

echo ""
echo "=== Scenario 3: Task list ID equals worktree directory basename ==="

tmp=$(make_scratch_repo "myrepo")
(
    cd "$tmp"
    source "$CW_COMMON"
    create_worktree "fix-login" >/dev/null 2>&1
    # Find the only worktree under .claude/worktrees/
    wt_dir=$(ls -d .claude/worktrees/*/ 2>/dev/null | head -1 | sed 's|/$||')
    wt_basename=$(basename "$wt_dir")
    got_id=$(jq -r '.env.CLAUDE_CODE_TASK_LIST_ID' "${wt_dir}/.claude/settings.local.json" 2>/dev/null)
    test "$got_id" = "$wt_basename" || { echo "task list id '$got_id' != dir basename '$wt_basename'"; exit 1; }
)
r=$?
if [ "$r" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "[PASS] scenario3: task list id equals worktree basename"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL [scenario3: task list id == basename]")
    echo "[FAIL] scenario3: task list id equals worktree basename"
fi
cleanup "$tmp"

# ---------------------------------------------------------------------------
# Scenario 4: Existing worktree directory is rejected (no CW_RESUME)
# ---------------------------------------------------------------------------

echo ""
echo "=== Scenario 4: Existing composed directory is rejected ==="

tmp=$(make_scratch_repo "claude-workflow")
(
    cd "$tmp"
    source "$CW_COMMON"
    mkdir -p ".claude/worktrees/feature-claude-workflow-login"
    if create_worktree "login" >/dev/null 2>&1; then
        echo "expected non-zero exit but got zero"; exit 1
    fi
)
r=$?
if [ "$r" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "[PASS] scenario4: existing worktree directory rejected"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL [scenario4: existing dir rejection]")
    echo "[FAIL] scenario4: existing worktree directory rejected"
fi
cleanup "$tmp"

# ---------------------------------------------------------------------------
# Scenario 5: Slug with invalid chars is rejected before worktree creation
# ---------------------------------------------------------------------------

echo ""
echo "=== Scenario 5: Invalid slug rejected ==="

tmp=$(make_scratch_repo "claude-workflow")
(
    cd "$tmp"
    source "$CW_COMMON"
    if create_worktree "Login Page" >/dev/null 2>&1; then
        echo "expected rejection but got success"; exit 1
    fi
    # No directory should have been created under .claude/worktrees/
    if ls -d .claude/worktrees/*/ >/dev/null 2>&1; then
        echo "unexpected directory created under .claude/worktrees/"; exit 1
    fi
)
r=$?
if [ "$r" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "[PASS] scenario5: invalid slug rejected, no dir created"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL [scenario5: invalid slug rejection]")
    echo "[FAIL] scenario5: invalid slug rejected, no dir created"
fi
cleanup "$tmp"

# ---------------------------------------------------------------------------
# Scenario 6: CW_WORKTREE_PATH is set to the absolute worktree path
# ---------------------------------------------------------------------------

echo ""
echo "=== Scenario 6: CW_WORKTREE_PATH is set to absolute path ==="

tmp=$(make_scratch_repo "myrepo")
(
    cd "$tmp"
    source "$CW_COMMON"
    create_worktree "my-feature" >/dev/null 2>&1
    test -n "$CW_WORKTREE_PATH" || { echo "CW_WORKTREE_PATH not set"; exit 1; }
    case "$CW_WORKTREE_PATH" in
        /*) ;;
        *) echo "CW_WORKTREE_PATH is not absolute: $CW_WORKTREE_PATH"; exit 1 ;;
    esac
    test "$(basename "$CW_WORKTREE_PATH")" = "feature-myrepo-my-feature" || { echo "CW_WORKTREE_PATH basename wrong: $CW_WORKTREE_PATH"; exit 1; }
)
r=$?
if [ "$r" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "[PASS] scenario6: CW_WORKTREE_PATH is absolute and correct"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL [scenario6: CW_WORKTREE_PATH absolute]")
    echo "[FAIL] scenario6: CW_WORKTREE_PATH is absolute and correct"
fi
cleanup "$tmp"

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
