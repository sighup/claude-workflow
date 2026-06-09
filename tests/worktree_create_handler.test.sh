#!/bin/bash
#
# tests/worktree_create_handler.test.sh
# Integration tests for scripts/worktree-create-handler.sh
#
# Covers:
#   - Stdin JSON parse → provision call → stdout absolute path contract
#   - base_ref honoring
#   - User isolation type → full mode (settings.local.json written)
#   - Provisioning failure → non-zero exit
#   - Invalid worktree_name rejected before any path is created
#
# Usage: bash tests/worktree_create_handler.test.sh
#

set -euo pipefail

PASS=0
FAIL=0
ERRORS=()

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HANDLER="$REPO_ROOT/scripts/worktree-create-handler.sh"

if [ ! -f "$HANDLER" ]; then
    echo "[ERROR] Cannot find $HANDLER" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

make_scratch_repo() {
    local name="${1:-claude-workflow}"
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

run_handler() {
    local payload="$1"
    printf '%s' "$payload" | bash "$HANDLER" 2>/dev/null
}

run_handler_raw() {
    local payload="$1"
    printf '%s' "$payload" | bash "$HANDLER"
}

# ---------------------------------------------------------------------------
# Scenario 1: Basic provisioning — stdout is an absolute .claude/worktrees path
# ---------------------------------------------------------------------------

echo ""
echo "=== Scenario 1: stdout is absolute .claude/worktrees/{type}-{repo}-{slug} path ==="

tmp=$(make_scratch_repo "claude-workflow")
(
    cd "$tmp"
    payload='{"worktree_name":"settings","isolation_type":"user"}'
    out=$(run_handler "$payload")
    r=$?
    test "$r" -eq 0 || { echo "handler exited $r"; exit 1; }

    # stdout must be non-empty and absolute
    test -n "$out" || { echo "stdout was empty"; exit 1; }
    case "$out" in
        /*) ;;
        *) echo "stdout not absolute: $out"; exit 1 ;;
    esac

    # Must contain .claude/worktrees/
    echo "$out" | grep -q "\.claude/worktrees/" || { echo "path missing .claude/worktrees/: $out"; exit 1; }

    # Directory and branch must exist
    test -d "$out" || { echo "worktree dir does not exist: $out"; exit 1; }
    repo_name=$(basename "$tmp")
    expected_basename="feature-${repo_name}-settings"
    actual_basename=$(basename "$out")
    test "$actual_basename" = "$expected_basename" || { echo "expected basename $expected_basename, got $actual_basename"; exit 1; }

    branch=$(git -C "$out" branch --show-current)
    test "$branch" = "feature/settings" || { echo "expected branch feature/settings, got $branch"; exit 1; }
)
r=$?
if [ "$r" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "[PASS] scenario1: stdout is absolute .claude/worktrees path with dir+branch"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL [scenario1: stdout absolute path contract]")
    echo "[FAIL] scenario1: stdout is absolute .claude/worktrees path with dir+branch"
fi
cleanup "$tmp"

# ---------------------------------------------------------------------------
# Scenario 2: base_ref honored — new branch based on supplied ref
# ---------------------------------------------------------------------------

echo ""
echo "=== Scenario 2: base_ref honored ==="

tmp=$(make_scratch_repo "myrepo")
(
    cd "$tmp"
    # Add a tagged commit and then advance HEAD
    echo "v1" > version.txt
    git add version.txt
    git commit -q -m "v1"
    git tag release
    echo "v2" > version.txt
    git add version.txt
    git commit -q -m "v2"

    payload='{"worktree_name":"branchoff","base_ref":"release","isolation_type":"user"}'
    out=$(run_handler "$payload")

    release_sha=$(git rev-parse release)
    wt_head=$(git -C "$out" rev-parse HEAD)
    test "$wt_head" = "$release_sha" || { echo "wt HEAD $wt_head != release $release_sha"; exit 1; }
)
r=$?
if [ "$r" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "[PASS] scenario2: base_ref honored, branch created from tagged commit"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL [scenario2: base_ref honored]")
    echo "[FAIL] scenario2: base_ref honored, branch created from tagged commit"
fi
cleanup "$tmp"

# ---------------------------------------------------------------------------
# Scenario 3: User isolation → full mode → settings.local.json written
# ---------------------------------------------------------------------------

echo ""
echo "=== Scenario 3: user isolation_type → full mode → settings.local.json ==="

tmp=$(make_scratch_repo "myrepo")
(
    cd "$tmp"
    payload='{"worktree_name":"userflow","isolation_type":"user"}'
    out=$(run_handler "$payload")

    settings="${out}/.claude/settings.local.json"
    test -f "$settings" || { echo "settings.local.json not found: $settings"; exit 1; }

    got_id=$(jq -r '.env.CLAUDE_CODE_TASK_LIST_ID' "$settings" 2>/dev/null)
    expected_id="feature-myrepo-userflow"
    test "$got_id" = "$expected_id" || { echo "expected CLAUDE_CODE_TASK_LIST_ID=$expected_id, got $got_id"; exit 1; }
)
r=$?
if [ "$r" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "[PASS] scenario3: user isolation → full mode → settings.local.json with correct ID"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL [scenario3: user isolation full mode]")
    echo "[FAIL] scenario3: user isolation → full mode → settings.local.json"
fi
cleanup "$tmp"

# ---------------------------------------------------------------------------
# Scenario 4: Provisioning failure → non-zero exit, no leftover directory
# ---------------------------------------------------------------------------

echo ""
echo "=== Scenario 4: provisioning failure → non-zero exit ==="

tmp=$(mktemp -d)
(
    cd "$tmp"
    # Not a git repo — provision_worktree will fail
    payload='{"worktree_name":"willfail","isolation_type":"user"}'
    set +e
    out=$(run_handler_raw "$payload" 2>/dev/null)
    rc=$?
    set -e
    test "$rc" -ne 0 || { echo "handler should have exited non-zero, got 0"; exit 1; }
    test -z "$out" || { echo "stdout should be empty on failure, got: $out"; exit 1; }
    test ! -d ".claude/worktrees/feature-tmp-willfail" || { echo "leftover worktree dir found"; exit 1; }
)
r=$?
if [ "$r" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "[PASS] scenario4: provisioning failure → non-zero exit, no leftover"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL [scenario4: provisioning failure non-zero]")
    echo "[FAIL] scenario4: provisioning failure → non-zero exit"
fi
rm -rf "$tmp"

# ---------------------------------------------------------------------------
# Scenario 5: Invalid worktree_name rejected before any path is created
# ---------------------------------------------------------------------------

echo ""
echo "=== Scenario 5: invalid worktree_name rejected ==="

tmp=$(make_scratch_repo "myrepo")
(
    cd "$tmp"
    payload='{"worktree_name":"../escape","isolation_type":"user"}'
    set +e
    out=$(run_handler_raw "$payload" 2>/dev/null)
    rc=$?
    set -e
    test "$rc" -ne 0 || { echo "handler should have exited non-zero for invalid slug"; exit 1; }
    test -z "$out" || { echo "stdout should be empty on rejection, got: $out"; exit 1; }
)
r=$?
if [ "$r" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "[PASS] scenario5: invalid slug rejected with non-zero exit"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL [scenario5: invalid slug rejected]")
    echo "[FAIL] scenario5: invalid slug rejected"
fi
cleanup "$tmp"

# ---------------------------------------------------------------------------
# Scenario 6: Missing worktree_name → non-zero exit
# ---------------------------------------------------------------------------

echo ""
echo "=== Scenario 6: missing worktree_name → non-zero exit ==="

tmp=$(make_scratch_repo "myrepo")
(
    cd "$tmp"
    payload='{"isolation_type":"user"}'
    set +e
    out=$(run_handler_raw "$payload" 2>/dev/null)
    rc=$?
    set -e
    test "$rc" -ne 0 || { echo "handler should have exited non-zero with no worktree_name"; exit 1; }
)
r=$?
if [ "$r" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "[PASS] scenario6: missing worktree_name → non-zero exit"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL [scenario6: missing worktree_name]")
    echo "[FAIL] scenario6: missing worktree_name → non-zero exit"
fi
cleanup "$tmp"

# ---------------------------------------------------------------------------
# Scenario 7: Subagent isolation → minimal mode → NO settings.local.json
#             and NO include copying
# ---------------------------------------------------------------------------

echo ""
echo "=== Scenario 7: subagent isolation_type → minimal mode → no settings.local.json ==="

tmp=$(make_scratch_repo "myrepo")
(
    cd "$tmp"
    payload='{"worktree_name":"agentisolated","isolation_type":"subagent"}'
    out=$(run_handler "$payload")
    r=$?
    test "$r" -eq 0 || { echo "handler exited $r for subagent isolation"; exit 1; }

    # stdout must still be an absolute .claude/worktrees path
    test -n "$out" || { echo "stdout was empty"; exit 1; }
    echo "$out" | grep -q "\.claude/worktrees/" || { echo "path missing .claude/worktrees/: $out"; exit 1; }

    # Directory must exist
    test -d "$out" || { echo "worktree dir does not exist: $out"; exit 1; }

    # settings.local.json must NOT exist (minimal mode skips it)
    settings="${out}/.claude/settings.local.json"
    test ! -f "$settings" || { echo "settings.local.json must NOT be present in minimal mode, found: $settings"; exit 1; }
)
r=$?
if [ "$r" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "[PASS] scenario7: subagent isolation → minimal mode → no settings.local.json"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL [scenario7: subagent isolation minimal mode]")
    echo "[FAIL] scenario7: subagent isolation → minimal mode → no settings.local.json"
fi
cleanup "$tmp"

# ---------------------------------------------------------------------------
# Scenario 8: Background isolation → minimal mode → NO settings.local.json
# ---------------------------------------------------------------------------

echo ""
echo "=== Scenario 8: background isolation_type → minimal mode → no settings.local.json ==="

tmp=$(make_scratch_repo "myrepo")
(
    cd "$tmp"
    payload='{"worktree_name":"bgisolated","isolation_type":"background"}'
    out=$(run_handler "$payload")
    r=$?
    test "$r" -eq 0 || { echo "handler exited $r for background isolation"; exit 1; }

    # Worktree directory must exist
    test -d "$out" || { echo "worktree dir does not exist: $out"; exit 1; }

    # settings.local.json must NOT exist (minimal mode skips it)
    settings="${out}/.claude/settings.local.json"
    test ! -f "$settings" || { echo "settings.local.json must NOT be present in minimal mode, found: $settings"; exit 1; }
)
r=$?
if [ "$r" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "[PASS] scenario8: background isolation → minimal mode → no settings.local.json"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL [scenario8: background isolation minimal mode]")
    echo "[FAIL] scenario8: background isolation → minimal mode → no settings.local.json"
fi
cleanup "$tmp"

# ---------------------------------------------------------------------------
# Scenario 9: Full-mode create copies .worktreeinclude-listed gitignored file
# ---------------------------------------------------------------------------

echo ""
echo "=== Scenario 9: full-mode create copies .worktreeinclude-listed .env ==="

tmp=$(make_scratch_repo "myrepo")
(
    cd "$tmp"
    # Create a gitignored .env file
    echo "SECRET=1" > .env
    printf '\n.env\n' >> .gitignore
    # Create .worktreeinclude listing .env
    echo ".env" > .worktreeinclude

    payload='{"worktree_name":"fullcopy","isolation_type":"user"}'
    out=$(run_handler "$payload")
    r=$?
    test "$r" -eq 0 || { echo "handler exited $r"; exit 1; }

    # .env must exist in the new worktree with the correct content
    copied="${out}/.env"
    test -f "$copied" || { echo ".env not copied into worktree: $copied"; exit 1; }
    content=$(cat "$copied")
    test "$content" = "SECRET=1" || { echo ".env content wrong: $content"; exit 1; }

    # Copied .env must NOT be staged or committed in the new worktree
    staged=$(git -C "$out" diff --cached --name-only)
    test -z "$staged" || { echo "copied .env was staged in worktree: $staged"; exit 1; }

    # HEAD of new worktree must not contain .env
    files_in_head=$(git -C "$out" show --name-only HEAD 2>/dev/null | tail -n +5)
    echo "$files_in_head" | grep -qF ".env" && { echo ".env was committed in new worktree"; exit 1; } || true
)
r=$?
if [ "$r" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "[PASS] scenario9: full-mode create copies .worktreeinclude .env, not staged/committed"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL [scenario9: full-mode include file copy]")
    echo "[FAIL] scenario9: full-mode create copies .worktreeinclude .env, not staged/committed"
fi
cleanup "$tmp"

# ---------------------------------------------------------------------------
# Scenario 10: Subagent/minimal create does NOT copy .env even when .worktreeinclude exists
# ---------------------------------------------------------------------------

echo ""
echo "=== Scenario 10: subagent/minimal create does NOT copy .env ==="

tmp=$(make_scratch_repo "myrepo")
(
    cd "$tmp"
    # Create a gitignored .env and .worktreeinclude listing it
    echo "SECRET=1" > .env
    printf '\n.env\n' >> .gitignore
    echo ".env" > .worktreeinclude

    payload='{"worktree_name":"nocopy","isolation_type":"subagent"}'
    out=$(run_handler "$payload")
    r=$?
    test "$r" -eq 0 || { echo "handler exited $r for subagent isolation"; exit 1; }

    # .env must NOT be present in the new worktree
    test ! -f "${out}/.env" || { echo ".env was incorrectly copied into minimal-mode worktree"; exit 1; }
)
r=$?
if [ "$r" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "[PASS] scenario10: subagent/minimal create does NOT copy .env"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL [scenario10: subagent minimal no include copy]")
    echo "[FAIL] scenario10: subagent/minimal create does NOT copy .env"
fi
cleanup "$tmp"

# ---------------------------------------------------------------------------
# Scenario 11: Comment-only .worktreeinclude → empty array, hook succeeds (bash 3.2 guard)
# ---------------------------------------------------------------------------

echo ""
echo "=== Scenario 11: comment-only .worktreeinclude → no crash, hook succeeds ==="

tmp=$(make_scratch_repo "myrepo")
(
    cd "$tmp"
    # .worktreeinclude exists but contains only comments and blank lines
    printf '# this file is intentionally blank\n\n# another comment\n' > .worktreeinclude

    payload='{"worktree_name":"emptyinclude","isolation_type":"user"}'
    out=$(run_handler "$payload")
    r=$?
    test "$r" -eq 0 || { echo "handler exited $r with comment-only .worktreeinclude"; exit 1; }

    # Worktree directory must exist
    test -d "$out" || { echo "worktree dir does not exist: $out"; exit 1; }

    # No unexpected files copied (no .env or similar)
    test ! -f "${out}/.env" || { echo ".env was unexpectedly copied"; exit 1; }
)
r=$?
if [ "$r" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "[PASS] scenario11: comment-only .worktreeinclude → empty array guard, hook succeeds"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL [scenario11: comment-only .worktreeinclude empty array guard]")
    echo "[FAIL] scenario11: comment-only .worktreeinclude → empty array guard"
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
