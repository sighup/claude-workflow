#!/bin/bash
#
# tests/run.sh - run every tests/*.test.sh and report a summary.
#
# Test files run under /bin/bash by default: on macOS that is bash 3.2, the
# oldest interpreter the plugin's shell code and documented snippets must
# parse under. Override with CW_TEST_BASH=/path/to/bash.
#
set -u

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
BASH_BIN="${CW_TEST_BASH:-/bin/bash}"

total=0
failed=0
for f in "$TESTS_DIR"/*.test.sh; do
    total=$((total + 1))
    echo "== $(basename "$f")"
    if ! "$BASH_BIN" "$f"; then
        failed=$((failed + 1))
    fi
    echo
done

if [ "$failed" -eq 0 ]; then
    echo "ALL PASS ($total test files)"
else
    echo "FAILURES in $failed of $total test files" >&2
    exit 1
fi
