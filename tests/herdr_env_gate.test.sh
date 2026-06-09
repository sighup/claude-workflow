#!/bin/bash
#
# tests/herdr_env_gate.test.sh
# Tests for the inside-herdr gate in bin/cw-herdr-open
#
# The helper must only operate when this process is running INSIDE a herdr
# pane (HERDR_ENV set). From a plain terminal it treats herdr as unavailable
# (exit 2) even when the daemon is reachable, because opening a tab in a
# detached herdr window the caller can't see is never the right default.
#
# Covers:
#   - HERDR_ENV unset  -> --probe exits 2 even with a reachable daemon
#   - HERDR_ENV empty  -> --probe exits 2 (empty treated as not-inside)
#   - HERDR_ENV=1      -> --probe exits 0 (gate passes, daemon reachable)
#   - HERDR_ENV unset  -> a diagnostic reason is written to stderr
#   - HERDR_ENV unset  -> normal flow (with a worktree path) also exits 2
#   - CW_DISABLE_HERDR=1 still wins even when HERDR_ENV=1
#
# Usage: bash tests/herdr_env_gate.test.sh
#

set -euo pipefail

PASS=0
FAIL=0
ERRORS=()

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$REPO_ROOT/bin/cw-herdr-open"

if [ ! -f "$HELPER" ]; then
    echo "[ERROR] Cannot find $HELPER" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Setup: a fake herdr daemon that answers `workspace list` (so the socket
# probe in _probe_herdr passes), plus a valid-named worktree directory.
# ---------------------------------------------------------------------------

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

FAKE_HERDR="$TMPROOT/herdr"
cat > "$FAKE_HERDR" <<'EOF'
#!/bin/bash
# Minimal fake herdr: only `workspace list` matters for --probe.
if [ "${1:-}" = "workspace" ] && [ "${2:-}" = "list" ]; then
    echo '{"result":{"workspaces":[]}}'
    exit 0
fi
exit 0
EOF
chmod +x "$FAKE_HERDR"

WT="$TMPROOT/fix-test-wt"
mkdir -p "$WT"

# ---------------------------------------------------------------------------
# Helpers — always run the helper with a reachable fake daemon so that the
# ONLY variable under test is HERDR_ENV. `env -u` guarantees a deterministic
# unset regardless of the environment this test runs in (e.g. inside herdr).
# ---------------------------------------------------------------------------

probe_without_env() {
    env -u HERDR_ENV HERDR_BIN="$FAKE_HERDR" bash "$HELPER" --probe "$@" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Scenario 1: HERDR_ENV unset -> --probe exits 2 (gate), daemon reachable
# ---------------------------------------------------------------------------

echo ""
echo "=== Scenario 1: HERDR_ENV unset -> --probe exits 2 ==="

(
    set +e
    env -u HERDR_ENV HERDR_BIN="$FAKE_HERDR" bash "$HELPER" --probe >/dev/null 2>&1
    rc=$?
    set -e
    test "$rc" -eq 2 || { echo "probe exited $rc, expected 2"; exit 1; }
)
r=$?
if [ "$r" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "[PASS] scenario1: probe exits 2 when not inside herdr"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL [scenario1: probe exits 2 when HERDR_ENV unset]")
    echo "[FAIL] scenario1: probe exits 2 when not inside herdr"
fi

# ---------------------------------------------------------------------------
# Scenario 2: HERDR_ENV empty string -> --probe exits 2 (empty == not-inside)
# ---------------------------------------------------------------------------

echo ""
echo "=== Scenario 2: HERDR_ENV='' -> --probe exits 2 ==="

(
    set +e
    HERDR_ENV="" HERDR_BIN="$FAKE_HERDR" bash "$HELPER" --probe >/dev/null 2>&1
    rc=$?
    set -e
    test "$rc" -eq 2 || { echo "probe exited $rc, expected 2"; exit 1; }
)
r=$?
if [ "$r" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "[PASS] scenario2: probe exits 2 when HERDR_ENV is empty"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL [scenario2: probe exits 2 when HERDR_ENV empty]")
    echo "[FAIL] scenario2: probe exits 2 when HERDR_ENV is empty"
fi

# ---------------------------------------------------------------------------
# Scenario 3: HERDR_ENV=1 + reachable daemon -> --probe exits 0 (gate passes)
# ---------------------------------------------------------------------------

echo ""
echo "=== Scenario 3: HERDR_ENV=1 -> --probe exits 0 ==="

(
    set +e
    HERDR_ENV=1 HERDR_BIN="$FAKE_HERDR" bash "$HELPER" --probe >/dev/null 2>&1
    rc=$?
    set -e
    test "$rc" -eq 0 || { echo "probe exited $rc, expected 0"; exit 1; }
)
r=$?
if [ "$r" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "[PASS] scenario3: probe exits 0 when inside herdr with reachable daemon"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL [scenario3: probe exits 0 when HERDR_ENV=1 and daemon up]")
    echo "[FAIL] scenario3: probe exits 0 when inside herdr with reachable daemon"
fi

# ---------------------------------------------------------------------------
# Scenario 4: HERDR_ENV unset -> a diagnostic reason is on stderr
# ---------------------------------------------------------------------------

echo ""
echo "=== Scenario 4: gate writes a discoverable reason to stderr ==="

(
    set +e
    err=$(env -u HERDR_ENV HERDR_BIN="$FAKE_HERDR" bash "$HELPER" --probe 2>&1 >/dev/null)
    set -e
    echo "$err" | grep -qi "not running inside a herdr session" \
        || { echo "stderr did not explain the reason: $err"; exit 1; }
)
r=$?
if [ "$r" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "[PASS] scenario4: gate explains itself on stderr"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL [scenario4: gate explains reason on stderr]")
    echo "[FAIL] scenario4: gate explains itself on stderr"
fi

# ---------------------------------------------------------------------------
# Scenario 5: HERDR_ENV unset -> normal flow (worktree path) also exits 2
# ---------------------------------------------------------------------------

echo ""
echo "=== Scenario 5: normal flow exits 2 when not inside herdr ==="

(
    set +e
    env -u HERDR_ENV HERDR_BIN="$FAKE_HERDR" bash "$HELPER" "$WT" >/dev/null 2>&1
    rc=$?
    set -e
    test "$rc" -eq 2 || { echo "normal flow exited $rc, expected 2"; exit 1; }
)
r=$?
if [ "$r" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "[PASS] scenario5: normal flow exits 2 when not inside herdr"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL [scenario5: normal flow exits 2 when HERDR_ENV unset]")
    echo "[FAIL] scenario5: normal flow exits 2 when not inside herdr"
fi

# ---------------------------------------------------------------------------
# Scenario 6: CW_DISABLE_HERDR=1 wins even when HERDR_ENV=1 (regression)
# ---------------------------------------------------------------------------

echo ""
echo "=== Scenario 6: CW_DISABLE_HERDR=1 still exits 2 ==="

(
    set +e
    HERDR_ENV=1 CW_DISABLE_HERDR=1 HERDR_BIN="$FAKE_HERDR" bash "$HELPER" --probe >/dev/null 2>&1
    rc=$?
    set -e
    test "$rc" -eq 2 || { echo "probe exited $rc, expected 2"; exit 1; }
)
r=$?
if [ "$r" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "[PASS] scenario6: CW_DISABLE_HERDR opt-out wins over HERDR_ENV"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL [scenario6: CW_DISABLE_HERDR wins over HERDR_ENV]")
    echo "[FAIL] scenario6: CW_DISABLE_HERDR opt-out wins over HERDR_ENV"
fi

# ---------------------------------------------------------------------------
# Summary
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
