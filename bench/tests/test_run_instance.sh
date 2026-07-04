#!/bin/bash
#
# bench/tests/test_run_instance.sh - integration test for bench/run_instance.sh.
#
# Runs entirely against local fixtures (stub agent + toy repo): no real claude
# call, no docker, no network. Asserts:
#   1. happy-path capture writes non-empty patch.diff / stream.jsonl / metrics.json
#      with a non-tampering status and the LOCAL fixture image (not swebench/*);
#   2. the checksum guard marks the run "FAILED: test-tampering" AND exits nonzero
#      when the stub agent edits the designated test file;
#   3. the CLAUDE_CODE_TASK_LIST_ID is isolated per (instance, arm, run) tuple.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
RUNNER="$ROOT/bench/run_instance.sh"
STUB="$ROOT/bench/fixtures/stub-agent.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-run-instance.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
RESULTS="$TMP/results"

fail() { echo "ASSERT FAIL: $1" >&2; exit 1; }
pass() { echo "ok: $1"; }

# --- 1. happy path (relative --agent-cmd, run from repo root, as the CLI proof
#        invokes it — guards against the cd-into-workdir path-resolution bug) ---
( cd "$ROOT" && bench/run_instance.sh --instance-id toy-1 --arm vanilla --run-n 1 \
  --agent-cmd bench/fixtures/stub-agent.sh --results-dir "$RESULTS" )
OUT="$RESULTS/toy-1/vanilla/1"
for f in patch.diff stream.jsonl metrics.json; do
  [ -s "$OUT/$f" ] || fail "expected non-empty $f"
done
grep -q '"status": "completed"' "$OUT/metrics.json" || fail "expected completed status"
grep -q '"test_tampering": false' "$OUT/metrics.json" || fail "expected no tampering"
grep -q '"image": "bench-fixture:local"' "$OUT/metrics.json" \
  || fail "expected local fixture image tag"
if grep -qi 'swebench/' "$OUT/metrics.json"; then
  fail "metrics.json must not reference an external swebench/* image"
fi
grep -q 'README.md' "$OUT/patch.diff" || fail "patch should reflect stub edit to README.md"
if grep -qi 'claude' "$OUT/stream.jsonl"; then
  fail "stub must not invoke the claude binary"
fi
pass "happy-path capture + metrics correct"

# --- 2. test-tampering guard ----------------------------------------------
set +e
BENCH_STUB_TAMPER=1 "$RUNNER" --instance-id toy-1 --arm vanilla --run-n 2 \
  --agent-cmd "$STUB" --results-dir "$RESULTS"
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "runner must exit nonzero when a test file is tampered"
TOUT="$RESULTS/toy-1/vanilla/2"
grep -q '"status": "FAILED: test-tampering"' "$TOUT/metrics.json" \
  || fail "expected status FAILED: test-tampering"
grep -q '"resolved": false' "$TOUT/metrics.json" \
  || fail "a tampered run must not be reported as resolved"
pass "test-tampering guard fires and marks the run FAILED"

# --- 3. task-list isolation ------------------------------------------------
id1="$(grep '"task_list_id"' "$OUT/metrics.json")"
id2="$(grep '"task_list_id"' "$TOUT/metrics.json")"
[ "$id1" != "$id2" ] || fail "task_list_id must differ across run-n values"
pass "task-list ids isolated per (instance, arm, run) tuple"

# --- 4. empty --test-files must not crash (bash 3.2 empty-array bug) -------
# Regression for: macOS's default /bin/bash (3.2.57) trips `set -u` on
# "${TEST_FILE_ARR[@]}" when the array has zero elements, which a legitimate
# empty --test-files (no designated ground-truth test for this instance)
# produces. Fixed only in bash 4.4+; run_instance.sh must guard both
# expansion sites so this exits 0 with no "unbound variable" error.
set +e
EOUT="$(bash "$RUNNER" --instance-id empty-tf --arm vanilla --run-n 1 \
  --agent-cmd "$STUB" --test-files "" --results-dir "$RESULTS" 2>&1)"
erc=$?
set -e
[ "$erc" -eq 0 ] || fail "empty --test-files must exit 0, got $erc: $EOUT"
if echo "$EOUT" | grep -qi 'unbound variable'; then
  fail "empty --test-files must not raise an unbound-variable error: $EOUT"
fi
EMPTY_OUT="$RESULTS/empty-tf/vanilla/1"
[ -s "$EMPTY_OUT/metrics.json" ] || fail "expected non-empty metrics.json for empty --test-files"
grep -q '"designated_test_files": \[\]' "$EMPTY_OUT/metrics.json" \
  || fail "expected an empty designated_test_files JSON array"
pass "empty --test-files exits 0 without an unbound-variable crash"

echo "ALL TESTS PASSED"
