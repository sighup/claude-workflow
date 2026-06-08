#!/bin/bash
#
# tests/create_worktree.test.sh - Integration tests for create_worktree()
#
# Verifies that create_worktree() delegates name derivation to cw_worktree_names
# and that all three hardcoded "feature-" compositions are gone.
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

run_test() {
    local label="$1"
    shift
    local result
    if result=$("$@" 2>&1); then
        PASS=$((PASS + 1))
        echo "[PASS] $label"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL [$label]: $result")
        echo "[FAIL] $label"
        echo "       $result"
    fi
}

# ---------------------------------------------------------------------------
# Scenario 1: Default feature slug produces repo-qualified names
# ---------------------------------------------------------------------------

echo ""
echo "=== Scenario 1: Default feature slug (login) ==="

tmp=$(make_scratch_repo "claude-workflow")
(
    cd "$tmp"
    source "$CW_COMMON"
    create_worktree "login" >/dev/null 2>&1
    test -d ".worktrees/feature-claude-workflow-login"     || { echo "worktree dir not found"; exit 1; }
    got_branch=$(git branch --list "feature/login")
    test -n "$got_branch"                                  || { echo "branch feature/login not found"; exit 1; }
    got_id=$(grep -o '"CLAUDE_CODE_TASK_LIST_ID": "[^"]*"' .worktrees/feature-claude-workflow-login/.claude/settings.local.json | grep -o '"[^"]*"$' | tr -d '"')
    test "$got_id" = "feature-claude-workflow-login"       || { echo "task list id wrong: $got_id"; exit 1; }
)
r=$?
if [ "$r" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "[PASS] scenario1: feature-claude-workflow-login created"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL [scenario1: feature slug]")
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
    test -d ".worktrees/fix-claude-workflow-login"     || { echo "worktree dir not found"; exit 1; }
    got_branch=$(git branch --list "fix/login")
    test -n "$got_branch"                              || { echo "branch fix/login not found"; exit 1; }
)
r=$?
if [ "$r" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "[PASS] scenario2: fix-claude-workflow-login created"
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
    # Find the only worktree under .worktrees/
    wt_dir=$(ls -d .worktrees/*/ 2>/dev/null | head -1 | sed 's|/$||')
    wt_basename=$(basename "$wt_dir")
    got_id=$(grep -o '"CLAUDE_CODE_TASK_LIST_ID": "[^"]*"' "${wt_dir}/.claude/settings.local.json" | grep -o '"[^"]*"$' | tr -d '"')
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
    mkdir -p ".worktrees/feature-claude-workflow-login"
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
    # No directory should have been created under .worktrees/
    if ls -d .worktrees/*/ >/dev/null 2>&1; then
        echo "unexpected directory created under .worktrees/"; exit 1
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
