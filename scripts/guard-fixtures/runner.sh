#!/bin/bash
#
# scripts/guard-fixtures/runner.sh - AutoResearch custom runner for the guard.
#
# AutoResearch (custom runner mode) invokes this once per test case with:
#   AUTORESEARCH_ARTIFACT   path to the guard variant under assessment
#   AUTORESEARCH_TEST_ID    test case id == scenario name (see test_cases.jsonl)
#   AUTORESEARCH_TEST_INPUT  human description (unused; the id selects the work)
#
# It runs exactly that one scenario against the variant in a hermetic temp tasks
# root and writes the scenario's structured result to stdout. assertions.py then
# grades stdout (it only needs to see "SCENARIO_RESULT: pass").
#
# Exit 0 always (per the runner contract — assertions decide pass/fail); a
# missing scenario or a crashed guard still produces a gradeable fail line.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SCENARIOS="${HERE}/scenarios.sh"
ARTIFACT="${AUTORESEARCH_ARTIFACT:-${HERE}/../task-store-guard.sh}"
TEST_ID="${AUTORESEARCH_TEST_ID:-}"

emit_fail() { echo "SCENARIO_RESULT: fail — $1"; exit 0; }

[ -n "$TEST_ID" ]      || emit_fail "no AUTORESEARCH_TEST_ID provided"
[ -f "$ARTIFACT" ]     || emit_fail "guard artifact not found: $ARTIFACT"
[ -f "$SCENARIOS" ]    || emit_fail "scenarios.sh not found: $SCENARIOS"

result="$(
  TMP="$(mktemp -d)"
  export CW_TASKS_DIR="$TMP"
  export CW_LEASE_SH="$TMP/no-lease-sh"     # non-existent => hermetic fallback lease path
  export CW_GUARD_MIN_TASKS=2
  # shellcheck disable=SC1090
  source "$ARTIFACT"
  # shellcheck disable=SC1090
  source "$SCENARIOS"
  if ! declare -F "scenario_${TEST_ID}" >/dev/null 2>&1; then
    echo "SCENARIO_RESULT: fail — unknown scenario: ${TEST_ID}"
  else
    "scenario_${TEST_ID}" 2>&1
  fi
  rm -rf "$TMP"
)"

line="$(printf '%s\n' "$result" | grep '^SCENARIO_RESULT:' | tail -n1)"
if [ -z "$line" ]; then
  # Guard crashed before self-grading (e.g. a variant that breaks under set -u).
  echo "SCENARIO_RESULT: fail — no result emitted (guard error)"
  printf '%s\n' "$result" | sed 's/^/# /'
else
  printf '%s\n' "$result"
fi
exit 0
