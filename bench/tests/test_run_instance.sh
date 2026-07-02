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

echo "ALL TESTS PASSED"
