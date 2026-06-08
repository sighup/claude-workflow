#!/bin/bash
#
# tests/provision_worktree.test.sh - Integration tests for provision_worktree()
#
# Covers: placement under .claude/worktrees/, base-ref honoring,
# existing-branch checkout, and the no-commit guarantee.
#
# Usage: bash tests/provision_worktree.test.sh
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
# Log stubs — keep test output clean
# ---------------------------------------------------------------------------

log_error()   { echo "[error] $*" >&2; }
log_info()    { :; }
log_success() { :; }
log_warning() { :; }
export -f log_error log_info log_success log_warning

source "$CW_COMMON"

# ---------------------------------------------------------------------------
# Helper: build a scratch git repo and return its path
# ---------------------------------------------------------------------------

make_scratch_repo() {
    local name="${1:-test-repo}"
    local tmpdir
    tmpdir=$(mktemp -d)
    local repo="$tmpdir/$name"
    mkdir -p "$repo"
    git -C "$repo" init -q
    git -C "$repo" config user.email "test@test.com"
    git -C "$repo" config user.name "Test"
    touch "$repo/README"
    git -C "$repo" add README
    git -C "$repo" commit -q -m "init"
    echo "$repo"
}

cleanup() {
    local dir="${1%/*}"
    rm -rf "$dir"
}

# ---------------------------------------------------------------------------
# Scenario 1: Worktree is placed under .claude/worktrees/ with canonical name
# ---------------------------------------------------------------------------

echo ""
echo "=== Scenario 1: Placement under .claude/worktrees/ ==="

tmp=$(make_scratch_repo "claude-workflow")
(
    cd "$tmp"
    source "$CW_COMMON"
    provision_worktree "fix-login" >/dev/null 2>&1
    test -d ".claude/worktrees/fix-claude-workflow-login" || { echo "worktree dir not found"; exit 1; }
    got_branch=$(git branch --list "fix/login")
    test -n "$got_branch" || { echo "branch fix/login not found"; exit 1; }
    test -n "$CW_WORKTREE_PATH" || { echo "CW_WORKTREE_PATH not set"; exit 1; }
    case "$CW_WORKTREE_PATH" in
        /*) ;;
        *) echo "CW_WORKTREE_PATH is not absolute: $CW_WORKTREE_PATH"; exit 1 ;;
    esac
    test "$(basename "$CW_WORKTREE_PATH")" = "fix-claude-workflow-login" || { echo "CW_WORKTREE_PATH basename wrong: $CW_WORKTREE_PATH"; exit 1; }
)
r=$?
if [ "$r" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "[PASS] scenario1: worktree placed under .claude/worktrees/"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL [scenario1: placement under .claude/worktrees/]")
    echo "[FAIL] scenario1: worktree placed under .claude/worktrees/"
fi
cleanup "$tmp"

# ---------------------------------------------------------------------------
# Scenario 2: Base-ref honoring — new branch based on supplied ref
# ---------------------------------------------------------------------------

echo ""
echo "=== Scenario 2: Base-ref honoring ==="

tmp=$(make_scratch_repo "myrepo")
(
    cd "$tmp"
    source "$CW_COMMON"
    # Create a second commit so we have something to base off
    echo "v0" > version.txt
    git add version.txt
    git commit -q -m "v0 commit"
    # Tag the current HEAD as v0
    git tag v0
    # Add a third commit so HEAD != v0
    echo "v1" > version.txt
    git add version.txt
    git commit -q -m "v1 commit"

    provision_worktree "from-base" "v0" >/dev/null 2>&1

    # The new worktree's HEAD should equal the v0-tagged commit
    v0_sha=$(git rev-parse v0)
    wt_head=$(git -C ".claude/worktrees/feature-myrepo-from-base" rev-parse HEAD)
    test "$wt_head" = "$v0_sha" || { echo "worktree HEAD $wt_head != v0 $v0_sha"; exit 1; }
)
r=$?
if [ "$r" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "[PASS] scenario2: branch based on supplied base ref"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL [scenario2: base-ref honoring]")
    echo "[FAIL] scenario2: branch based on supplied base ref"
fi
cleanup "$tmp"

# ---------------------------------------------------------------------------
# Scenario 3: No base ref — branch based off current HEAD
# ---------------------------------------------------------------------------

echo ""
echo "=== Scenario 3: No base ref — based off HEAD ==="

tmp=$(make_scratch_repo "myrepo")
(
    cd "$tmp"
    source "$CW_COMMON"
    head_sha=$(git rev-parse HEAD)
    provision_worktree "from-head" >/dev/null 2>&1

    wt_head=$(git -C ".claude/worktrees/feature-myrepo-from-head" rev-parse HEAD)
    test "$wt_head" = "$head_sha" || { echo "worktree HEAD $wt_head != HEAD $head_sha"; exit 1; }
)
r=$?
if [ "$r" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "[PASS] scenario3: worktree HEAD matches repo HEAD when no base ref"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL [scenario3: no-base-ref HEAD]")
    echo "[FAIL] scenario3: worktree HEAD matches repo HEAD when no base ref"
fi
cleanup "$tmp"

# ---------------------------------------------------------------------------
# Scenario 4: Existing branch is checked out instead of creating a new one
# ---------------------------------------------------------------------------

echo ""
echo "=== Scenario 4: Existing branch checkout ==="

tmp=$(make_scratch_repo "myrepo")
(
    cd "$tmp"
    source "$CW_COMMON"
    # Pre-create the branch
    git checkout -q -b "fix/reuse"
    echo "extra" > extra.txt
    git add extra.txt
    git commit -q -m "branch commit"
    branch_sha=$(git rev-parse HEAD)
    git checkout -q main 2>/dev/null || git checkout -q master

    # Now provision — should reuse the existing branch, not error
    out=$(provision_worktree "fix-reuse" 2>&1)
    r=$?
    test "$r" -eq 0 || { echo "provision_worktree failed: $out"; exit 1; }

    test -d ".claude/worktrees/fix-myrepo-reuse" || { echo "worktree dir not found"; exit 1; }
    wt_head=$(git -C ".claude/worktrees/fix-myrepo-reuse" rev-parse HEAD)
    test "$wt_head" = "$branch_sha" || { echo "wt HEAD $wt_head != branch HEAD $branch_sha"; exit 1; }
)
r=$?
if [ "$r" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "[PASS] scenario4: existing branch checked out without error"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL [scenario4: existing branch checkout]")
    echo "[FAIL] scenario4: existing branch checked out without error"
fi
cleanup "$tmp"

# ---------------------------------------------------------------------------
# Scenario 5: No commit ever occurs — HEAD and staging area unchanged
# ---------------------------------------------------------------------------

echo ""
echo "=== Scenario 5: No commit guarantee ==="

tmp=$(make_scratch_repo "myrepo")
(
    cd "$tmp"
    source "$CW_COMMON"
    head_before=$(git rev-parse HEAD)
    provision_worktree "no-commit" >/dev/null 2>&1

    head_after=$(git rev-parse HEAD)
    test "$head_after" = "$head_before" || { echo "HEAD changed from $head_before to $head_after"; exit 1; }

    # Staging area must have no files added by provisioning
    staged=$(git diff --cached --name-only)
    test -z "$staged" || { echo "unexpected staged files: $staged"; exit 1; }
)
r=$?
if [ "$r" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "[PASS] scenario5: HEAD unchanged and staging area clean after provisioning"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL [scenario5: no-commit guarantee]")
    echo "[FAIL] scenario5: HEAD unchanged and staging area clean after provisioning"
fi
cleanup "$tmp"

# ---------------------------------------------------------------------------
# Scenario 6: .gitignore ensure-only — entry appended when missing
# ---------------------------------------------------------------------------

echo ""
echo "=== Scenario 6: gitignore ensure-only — entry appended ==="

tmp=$(make_scratch_repo "myrepo")
(
    cd "$tmp"
    source "$CW_COMMON"
    # No .gitignore exists yet
    rm -f .gitignore
    provision_worktree "ignore-add" >/dev/null 2>&1

    grep -qxF ".claude/worktrees/" .gitignore || { echo ".gitignore entry not added"; exit 1; }

    # Must be unstaged
    staged=$(git diff --cached --name-only)
    test -z "$staged" || { echo ".gitignore was staged: $staged"; exit 1; }

    # HEAD must not have a new commit
    head_after=$(git rev-parse HEAD)
    head_before=$(git -C "$(pwd)" log --oneline -1 | cut -d' ' -f1)
    commit_msg=$(git log -1 --pretty=%s)
    test "$commit_msg" = "init" || { echo "unexpected commit after provisioning: $commit_msg"; exit 1; }
)
r=$?
if [ "$r" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "[PASS] scenario6: .gitignore entry appended, unstaged, no commit"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL [scenario6: gitignore ensure-only]")
    echo "[FAIL] scenario6: .gitignore entry appended, unstaged, no commit"
fi
cleanup "$tmp"

# ---------------------------------------------------------------------------
# Scenario 7: .gitignore not duplicated when entry already present
# ---------------------------------------------------------------------------

echo ""
echo "=== Scenario 7: gitignore not duplicated ==="

tmp=$(make_scratch_repo "myrepo")
(
    cd "$tmp"
    source "$CW_COMMON"
    echo ".claude/worktrees/" > .gitignore

    provision_worktree "ignore-dup" >/dev/null 2>&1

    count=$(grep -cxF ".claude/worktrees/" .gitignore)
    test "$count" -eq 1 || { echo "duplicate entries: $count"; exit 1; }
)
r=$?
if [ "$r" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "[PASS] scenario7: .gitignore entry not duplicated"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL [scenario7: gitignore no duplicate]")
    echo "[FAIL] scenario7: .gitignore entry not duplicated"
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
