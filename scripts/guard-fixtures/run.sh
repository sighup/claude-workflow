#!/bin/bash
#
# scripts/guard-fixtures/run.sh - Standalone guard regression suite.
#
# Runs every guard decision fixture against task-store-guard.sh and reports
# pass/fail. Independent of autoresearch — usable as a plain CI gate:
#
#   scripts/guard-fixtures/run.sh                 # test the in-repo guard
#   scripts/guard-fixtures/run.sh path/to/guard   # test a specific variant
#
# Exit 0 iff every scenario passes.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ARTIFACT="${1:-${HERE}/../task-store-guard.sh}"
SCENARIOS="${HERE}/scenarios.sh"

if [ ! -f "$ARTIFACT" ]; then
  echo "guard artifact not found: $ARTIFACT" >&2
  exit 2
fi

# Pull the scenario list without sourcing the artifact into this shell.
# shellcheck disable=SC1090
source "$SCENARIOS"

PASS=0
FAIL=0
for name in $GF_SCENARIOS; do
  result="$(
    TMP="$(mktemp -d)"
    export CW_TASKS_DIR="$TMP"
    export CW_LEASE_SH="$TMP/no-lease-sh"   # non-existent => hermetic fallback lease path
    export CW_GUARD_MIN_TASKS=2
    # shellcheck disable=SC1090
    source "$ARTIFACT"
    # shellcheck disable=SC1090
    source "$SCENARIOS"
    "scenario_${name}" 2>&1
    rm -rf "$TMP"
  )"
  line="$(printf '%s\n' "$result" | grep '^SCENARIO_RESULT:' | tail -n1)"
  case "$line" in
    "SCENARIO_RESULT: pass")
      PASS=$((PASS + 1))
      printf '  PASS  %s\n' "$name"
      ;;
    *)
      FAIL=$((FAIL + 1))
      printf '  FAIL  %s — %s\n' "$name" "${line#SCENARIO_RESULT: fail — }"
      ;;
  esac
done

echo "----------------------------------------"
echo "guard fixtures: ${PASS} passed, ${FAIL} failed ($(printf '%s' "$GF_SCENARIOS" | grep -c .) total)"
[ "$FAIL" -eq 0 ]
