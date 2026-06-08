#!/bin/bash
#
# tests/path_compat.test.sh - Path compatibility tests for dual-location worktree support
#
# Verifies that worktree-session-init.sh, cwd-changed-worktree.sh, and related tooling
# accept both .claude/worktrees/ (new) and .worktrees/ (legacy) paths.
#
# Usage: bash tests/path_compat.test.sh
#

set -euo pipefail

PASS=0
FAIL=0
ERRORS=()

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SESSION_INIT="$REPO_ROOT/scripts/worktree-session-init.sh"
CWD_CHANGED="$REPO_ROOT/scripts/cwd-changed-worktree.sh"
GITIGNORE="$REPO_ROOT/.gitignore"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

assert_pass() {
    local label="$1"
    PASS=$((PASS + 1))
    echo "[PASS] $label"
}

assert_fail() {
    local label="$1"
    local reason="$2"
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL [$label]: $reason")
    echo "[FAIL] $label  ($reason)"
}

# Run session-init with a fake cwd injected via CW_OVERRIDE_CWD env variable.
# Returns the stdout output of the script.
run_session_init_with_cwd() {
    local fake_cwd="$1"
    CW_OVERRIDE_CWD="$fake_cwd" bash "${SESSION_INIT}" 2>/dev/null || true
}

# Run cwd-changed with a fake cwd in the JSON input.
run_cwd_changed_with_cwd() {
    local fake_cwd="$1"
    echo "{\"cwd\": \"${fake_cwd}\"}" | bash "${CWD_CHANGED}" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Tests: .gitignore contains both worktree locations
# ---------------------------------------------------------------------------

echo ""
echo "=== .gitignore dual-location entries ==="

if [ ! -f "$GITIGNORE" ]; then
    assert_fail "gitignore exists" "file not found at $GITIGNORE"
else
    if grep -qxF '.worktrees/' "$GITIGNORE"; then
        assert_pass "gitignore contains .worktrees/"
    else
        assert_fail "gitignore contains .worktrees/" "line '.worktrees/' missing from $GITIGNORE"
    fi

    if grep -qxF '.claude/worktrees/' "$GITIGNORE"; then
        assert_pass "gitignore contains .claude/worktrees/"
    else
        assert_fail "gitignore contains .claude/worktrees/" "line '.claude/worktrees/' missing from $GITIGNORE"
    fi
fi

# ---------------------------------------------------------------------------
# Tests: worktree-session-init.sh — new .claude/worktrees/ location
# ---------------------------------------------------------------------------

echo ""
echo "=== session-init: new .claude/worktrees/ location ==="

NEW_CWD="/home/user/myproject/.claude/worktrees/fix-myrepo-login/src"
OUT=$(run_session_init_with_cwd "$NEW_CWD")

if echo "$OUT" | grep -q "fix-myrepo-login"; then
    assert_pass "session-init extracts worktree name from .claude/worktrees/"
else
    assert_fail "session-init extracts worktree name from .claude/worktrees/" "expected 'fix-myrepo-login' in output, got: $OUT"
fi

if echo "$OUT" | grep -q ".claude/worktrees/fix-myrepo-login"; then
    assert_pass "session-init reports .claude/worktrees/ containing dir"
else
    assert_fail "session-init reports .claude/worktrees/ containing dir" "expected .claude/worktrees/fix-myrepo-login in output"
fi

# Verify it does NOT report the legacy path for a new-location worktree
if echo "$OUT" | grep -q "/.worktrees/fix-myrepo-login"; then
    assert_fail "session-init does not conflate new location with legacy path" "output contains /.worktrees/ but expected .claude/worktrees/"
else
    assert_pass "session-init does not conflate new location with legacy path"
fi

# ---------------------------------------------------------------------------
# Tests: worktree-session-init.sh — legacy .worktrees/ location
# ---------------------------------------------------------------------------

echo ""
echo "=== session-init: legacy .worktrees/ location ==="

LEGACY_CWD="/home/user/myproject/.worktrees/feature-login/src"
OUT=$(run_session_init_with_cwd "$LEGACY_CWD")

if echo "$OUT" | grep -q "feature-login"; then
    assert_pass "session-init extracts worktree name from .worktrees/"
else
    assert_fail "session-init extracts worktree name from .worktrees/" "expected 'feature-login' in output, got: $OUT"
fi

if echo "$OUT" | grep -q "/.worktrees/feature-login"; then
    assert_pass "session-init reports .worktrees/ containing dir"
else
    assert_fail "session-init reports .worktrees/ containing dir" "expected /.worktrees/feature-login in output"
fi

# ---------------------------------------------------------------------------
# Tests: worktree-session-init.sh — no output for non-worktree cwd
# ---------------------------------------------------------------------------

echo ""
echo "=== session-init: non-worktree directory produces no output ==="

PLAIN_CWD="/home/user/myproject/src"
OUT=$(run_session_init_with_cwd "$PLAIN_CWD")

if [ -z "$OUT" ]; then
    assert_pass "session-init is silent for non-worktree cwd"
else
    assert_fail "session-init is silent for non-worktree cwd" "unexpected output for plain cwd: $OUT"
fi

# ---------------------------------------------------------------------------
# Tests: cwd-changed-worktree.sh — new .claude/worktrees/ location
# ---------------------------------------------------------------------------

echo ""
echo "=== cwd-changed: new .claude/worktrees/ location ==="

NEW_CWD2="/home/user/myproject/.claude/worktrees/fix-myrepo-api/src"
OUT=$(run_cwd_changed_with_cwd "$NEW_CWD2")

if echo "$OUT" | grep -q "fix-myrepo-api"; then
    assert_pass "cwd-changed identifies worktree from .claude/worktrees/"
else
    assert_fail "cwd-changed identifies worktree from .claude/worktrees/" "expected 'fix-myrepo-api' in output, got: $OUT"
fi

if echo "$OUT" | grep -q ".claude/worktrees/fix-myrepo-api"; then
    assert_pass "cwd-changed reports .claude/worktrees/ containing dir"
else
    assert_fail "cwd-changed reports .claude/worktrees/ containing dir" "expected .claude/worktrees/fix-myrepo-api in output"
fi

# ---------------------------------------------------------------------------
# Tests: cwd-changed-worktree.sh — legacy .worktrees/ location
# ---------------------------------------------------------------------------

echo ""
echo "=== cwd-changed: legacy .worktrees/ location ==="

LEGACY_CWD2="/home/user/myproject/.worktrees/feature-api/src"
OUT=$(run_cwd_changed_with_cwd "$LEGACY_CWD2")

if echo "$OUT" | grep -q "feature-api"; then
    assert_pass "cwd-changed identifies worktree from .worktrees/"
else
    assert_fail "cwd-changed identifies worktree from .worktrees/" "expected 'feature-api' in output, got: $OUT"
fi

# ---------------------------------------------------------------------------
# Tests: cwd-changed-worktree.sh — no output for non-worktree or empty cwd
# ---------------------------------------------------------------------------

echo ""
echo "=== cwd-changed: non-worktree or empty input ==="

OUT=$(run_cwd_changed_with_cwd "/home/user/myproject/src")
if [ -z "$OUT" ]; then
    assert_pass "cwd-changed silent for non-worktree cwd"
else
    assert_fail "cwd-changed silent for non-worktree cwd" "unexpected output: $OUT"
fi

OUT=$(echo '{}' | bash "${CWD_CHANGED}" 2>/dev/null || true)
if [ -z "$OUT" ]; then
    assert_pass "cwd-changed silent when cwd field missing"
else
    assert_fail "cwd-changed silent when cwd field missing" "unexpected output: $OUT"
fi

# ---------------------------------------------------------------------------
# Tests: cw-spec SKILL.md in-worktree probe pattern
# ---------------------------------------------------------------------------

echo ""
echo "=== cw-spec SKILL.md in-worktree probe ==="

SPEC_SKILL="$REPO_ROOT/skills/cw-spec/SKILL.md"

if [ ! -f "$SPEC_SKILL" ]; then
    assert_fail "cw-spec SKILL.md exists" "file not found: $SPEC_SKILL"
else
    # The probe regex should match both locations
    PROBE_LINE=$(grep -E 'grep.*worktrees' "$SPEC_SKILL" | head -1)

    if echo "$PROBE_LINE" | grep -q '\.claude/worktrees'; then
        assert_pass "cw-spec probe matches .claude/worktrees/"
    else
        assert_fail "cw-spec probe matches .claude/worktrees/" "probe line does not mention .claude/worktrees: $PROBE_LINE"
    fi

    if echo "$PROBE_LINE" | grep -q '\.worktrees'; then
        assert_pass "cw-spec probe still matches legacy .worktrees/"
    else
        assert_fail "cw-spec probe still matches legacy .worktrees/" "probe line does not mention .worktrees: $PROBE_LINE"
    fi

    # Verify the probe logic works correctly for both paths
    PROBE_CMD=$(grep -A1 'in-worktree probe' "$SPEC_SKILL" 2>/dev/null | grep 'grep' | head -1 || \
                grep 'grep.*worktrees.*echo' "$SPEC_SKILL" | head -1 || \
                grep 'grep -qE.*worktrees' "$SPEC_SKILL" | head -1)

    # Test the actual pattern by extracting and running it
    GREP_PATTERN=$(grep -oE "grep -qE '[^']+'" "$SPEC_SKILL" | grep worktrees | head -1)
    if [ -n "$GREP_PATTERN" ]; then
        # Test new location
        if echo "/project/.claude/worktrees/fix-myrepo-spec" | eval "$GREP_PATTERN" 2>/dev/null; then
            assert_pass "probe pattern matches .claude/worktrees/ path"
        else
            assert_fail "probe pattern matches .claude/worktrees/ path" "pattern '$GREP_PATTERN' did not match .claude/worktrees/ path"
        fi

        # Test legacy location
        if echo "/project/.worktrees/feature-spec" | eval "$GREP_PATTERN" 2>/dev/null; then
            assert_pass "probe pattern matches legacy .worktrees/ path"
        else
            assert_fail "probe pattern matches legacy .worktrees/ path" "pattern '$GREP_PATTERN' did not match .worktrees/ path"
        fi

        # Test non-worktree path does NOT match
        if echo "/project/src/main" | eval "$GREP_PATTERN" 2>/dev/null; then
            assert_fail "probe pattern rejects non-worktree path" "pattern matched a plain path — false positive"
        else
            assert_pass "probe pattern rejects non-worktree path"
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Tests: worktree-commands.md resolver patterns
# ---------------------------------------------------------------------------

echo ""
echo "=== worktree-commands.md resolver grep patterns ==="

WT_CMDS="$REPO_ROOT/skills/cw-worktree/references/worktree-commands.md"

if [ ! -f "$WT_CMDS" ]; then
    assert_fail "worktree-commands.md exists" "file not found: $WT_CMDS"
else
    # Check that no resolver still uses the old single-location grep
    if grep -q 'grep "/\\\.worktrees/"' "$WT_CMDS" 2>/dev/null; then
        OLD_COUNT=$(grep -c 'grep "/\\\.worktrees/"' "$WT_CMDS" 2>/dev/null || true)
        assert_fail "worktree-commands.md has no single-location grep patterns" "${OLD_COUNT:-some} old patterns remain"
    else
        assert_pass "worktree-commands.md has no single-location grep patterns"
    fi

    # Check that dual-location grep -E patterns are present
    NEW_PATTERN_COUNT=$(grep -c 'grep -E.*claude/worktrees.*worktrees' "$WT_CMDS" 2>/dev/null || echo 0)
    if [ "$NEW_PATTERN_COUNT" -gt 0 ]; then
        assert_pass "worktree-commands.md uses dual-location grep -E patterns"
    else
        assert_fail "worktree-commands.md uses dual-location grep -E patterns" "no grep -E dual-location patterns found"
    fi

    # Verify the resolver pattern emits the full absolute path (not a hardcoded prefix)
    ECHO_PATTERN=$(grep 'echo.*_wt' "$WT_CMDS" | head -1)
    if echo "$ECHO_PATTERN" | grep -q 'echo "\$_wt"'; then
        assert_pass "worktree-commands.md resolver emits full path from git worktree list"
    else
        assert_fail "worktree-commands.md resolver emits full path from git worktree list" "resolver may still use hardcoded .worktrees/ prefix: $ECHO_PATTERN"
    fi
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
