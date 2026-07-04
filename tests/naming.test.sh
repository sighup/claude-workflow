#!/bin/bash
#
# tests/naming.test.sh - Bash test runner for cw_worktree_names
#
# Tests R1.2-R1.5: type inference, keyword stripping, repo derivation,
# inside-a-worktree repo derivation, and rejection cases.
#
# Usage: bash tests/naming.test.sh
#

set -euo pipefail

PASS=0
FAIL=0
ERRORS=()

# Locate cw-common.sh relative to this script (repo root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CW_COMMON="$REPO_ROOT/plugin/scripts/lib/cw-common.sh"

if [ ! -f "$CW_COMMON" ]; then
    echo "[ERROR] Cannot find $CW_COMMON" >&2
    exit 1
fi

# Stub log_error so test output stays clean
log_error() { echo "[cw_worktree_names error] $*" >&2; }
log_info()  { :; }
log_success() { :; }
log_warning() { :; }
export -f log_error log_info log_success log_warning

# Source only the function under test (not the whole file which may rely on env)
# We do a targeted extraction: source with stubs already in place.
source "$CW_COMMON"

# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------

assert_names() {
    local label="$1"
    local slug="$2"
    local expected_dir="$3"
    local expected_branch="$4"

    local out
    if ! out=$(cw_worktree_names "$slug" 2>/dev/null); then
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL [$label]: cw_worktree_names '$slug' returned non-zero")
        echo "[FAIL] $label"
        return
    fi

    local got_dir got_id got_branch
    got_dir=$(echo "$out" | sed -n '1p')
    got_id=$(echo "$out"  | sed -n '2p')
    got_branch=$(echo "$out" | sed -n '3p')

    local ok=true

    # dir == id invariant
    if [ "$got_dir" != "$got_id" ]; then
        ok=false
        ERRORS+=("FAIL [$label]: dir ('$got_dir') != id ('$got_id') — invariant violated")
    fi

    # dir matches expected pattern (replace {repo} placeholder)
    if [ -n "$expected_dir" ]; then
        # expected_dir may contain literal {repo} which we allow to match any [a-z0-9-]+
        local dir_regex
        dir_regex=$(echo "$expected_dir" | sed 's/{repo}/[a-z0-9-]+/')
        if ! echo "$got_dir" | grep -qE "^${dir_regex}$"; then
            ok=false
            ERRORS+=("FAIL [$label]: dir '$got_dir' does not match expected pattern '$expected_dir'")
        fi
    fi

    # branch matches expected
    if [ -n "$expected_branch" ]; then
        if [ "$got_branch" != "$expected_branch" ]; then
            ok=false
            ERRORS+=("FAIL [$label]: branch '$got_branch' != expected '$expected_branch'")
        fi
    fi

    # dir/id must match ^[a-z0-9-]+$
    if ! echo "$got_dir" | grep -qE '^[a-z0-9-]+$'; then
        ok=false
        ERRORS+=("FAIL [$label]: dir '$got_dir' fails charset ^[a-z0-9-]+$")
    fi

    # branch must match ^[a-z0-9/-]+$
    if ! echo "$got_branch" | grep -qE '^[a-z0-9/-]+$'; then
        ok=false
        ERRORS+=("FAIL [$label]: branch '$got_branch' fails charset ^[a-z0-9/-]+$")
    fi

    if $ok; then
        PASS=$((PASS + 1))
        echo "[PASS] $label  (dir=$got_dir  branch=$got_branch)"
    else
        FAIL=$((FAIL + 1))
        echo "[FAIL] $label  (dir=$got_dir  branch=$got_branch)"
    fi
}

assert_reject() {
    local label="$1"
    local slug="$2"

    if cw_worktree_names "$slug" >/dev/null 2>&1; then
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL [$label]: expected non-zero for slug '$slug' but got zero")
        echo "[FAIL] $label  (expected rejection, got success)"
    else
        PASS=$((PASS + 1))
        echo "[PASS] $label  (correctly rejected '$slug')"
    fi
}

# ---------------------------------------------------------------------------
# Tests: R1.2 — type inference
# ---------------------------------------------------------------------------

echo ""
echo "=== R1.2: Type inference ==="

assert_names "feature default (no keyword)"    "my-new-thing"     "feature-{repo}-my-new-thing"    "feature/my-new-thing"
assert_names "feature-auth (not stripped)"     "feature-auth"     "feature-{repo}-feature-auth"    "feature/feature-auth"
assert_names "fix prefix"                      "fix-login"        "fix-{repo}-login"               "fix/login"
assert_names "bug prefix"                      "bug-crash"        "fix-{repo}-crash"               "fix/crash"
assert_names "hotfix prefix"                   "hotfix-memory"    "fix-{repo}-memory"              "fix/memory"
assert_names "research prefix"                 "research-caching" "research-{repo}-caching"        "research/caching"
assert_names "spike prefix"                    "spike-latency"    "research-{repo}-latency"        "research/latency"
assert_names "explore prefix"                  "explore-options"  "research-{repo}-options"        "research/options"
assert_names "chore prefix"                    "chore-cleanup"    "chore-{repo}-cleanup"           "chore/cleanup"
assert_names "refactor prefix"                 "refactor-db"      "chore-{repo}-db"                "chore/db"
assert_names "docs prefix"                     "docs-api"         "chore-{repo}-api"               "chore/api"
assert_names "build prefix"                    "build-pipeline"   "chore-{repo}-pipeline"          "chore/pipeline"
assert_names "ci prefix"                       "ci-fix"           "chore-{repo}-fix"               "chore/fix"

# ---------------------------------------------------------------------------
# Tests: R1.2 — keyword stripping
# ---------------------------------------------------------------------------

echo ""
echo "=== R1.2: Keyword stripping ==="

# Bare keyword (no trailing content) — keyword itself becomes empty slug → rejection
assert_reject "bare 'fix' keyword alone"       "fix"

# Keyword with hyphen-separated slug
assert_names  "fix-login strips 'fix-'"        "fix-login"        "fix-{repo}-login"               "fix/login"
assert_names  "research-caching strips prefix" "research-caching" "research-{repo}-caching"        "research/caching"

# Word that starts with keyword chars but isn't a keyword
assert_names  "fixed is not a keyword"         "fixed-bug"        "feature-{repo}-fixed-bug"       "feature/fixed-bug"
assert_names  "builds is not a keyword"        "builds-improve"   "feature-{repo}-builds-improve"  "feature/builds-improve"

# ---------------------------------------------------------------------------
# Tests: R1.3 — repo derivation (current directory is inside repo)
# ---------------------------------------------------------------------------

echo ""
echo "=== R1.3: Repo derivation ==="

# When run from the repo root the repo name must appear in dir/id
REPO_NAME=$(basename "$(git -C "$REPO_ROOT" worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')
assert_names "repo name embedded in dir" "fix-login" "fix-${REPO_NAME}-login" "fix/login"

# ---------------------------------------------------------------------------
# Tests: R1.3 — repo derivation from inside a worktree subdir
# ---------------------------------------------------------------------------

echo ""
echo "=== R1.3: Repo derivation inside a worktree ==="

# If a .worktrees/* directory exists, cd into it and verify repo still resolves
# to the main worktree basename (not the nested dir name).
WORKTREE_SUBDIR="$REPO_ROOT/.worktrees/feature-research-task-list-prefix"
if [ -d "$WORKTREE_SUBDIR" ]; then
    # Run in a subshell so we don't affect the rest of the test environment
    result=$(cd "$WORKTREE_SUBDIR" && source "$CW_COMMON" 2>/dev/null && cw_worktree_names "fix-login" 2>/dev/null | sed -n '1p')
    expected_pattern="fix-${REPO_NAME}-login"
    if [ "$result" = "$expected_pattern" ]; then
        PASS=$((PASS + 1))
        echo "[PASS] inside-worktree repo derivation  (dir=$result)"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL [inside-worktree repo derivation]: got '$result', expected '$expected_pattern'")
        echo "[FAIL] inside-worktree repo derivation  (dir=$result, expected=$expected_pattern)"
    fi
else
    echo "[SKIP] inside-worktree test: $WORKTREE_SUBDIR not found"
fi

# ---------------------------------------------------------------------------
# Tests: R1.5 — rejection cases
# ---------------------------------------------------------------------------

echo ""
echo "=== R1.5: Rejection cases ==="

assert_reject "empty slug"                     ""
assert_reject "bare keyword 'fix'"             "fix"
assert_reject "bare keyword 'research'"        "research"
assert_reject "uppercase letters"              "Fix-Login"
assert_reject "spaces in slug"                 "fix login"
assert_reject "special chars"                  "fix-login!"
assert_reject "slash in slug"                  "fix/login"

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
