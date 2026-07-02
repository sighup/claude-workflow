#!/bin/bash
#
# Designated ground-truth test for the toy-repo fixture.
#
# It intentionally FAILS (exit 1) to represent an unresolved SWE-bench instance:
# a real agent is expected to fix the code under test so this passes, NOT to edit
# the test. bench/run_instance.sh checksum-guards this file and marks the run
# "FAILED: test-tampering" if its contents change during the agent run.
#
set -euo pipefail

expected="4"
actual="$((2 + 3))" # deliberately wrong (5 != 4): the unfixed-bug stand-in

if [ "$actual" = "$expected" ]; then
  echo "PASS"
  exit 0
fi

echo "FAIL: expected $expected, got $actual"
exit 1
