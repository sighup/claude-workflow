#!/bin/bash
#
# bench/fixtures/stub-agent.sh - synthetic stand-in for a real `claude` agent,
# used only by the local fixture proofs so bench/run_instance.sh can be
# exercised end-to-end with no real billing and no network.
#
# run_instance.sh cd's into a throwaway working copy of the repo and runs this
# script there, capturing its stdout as stream.jsonl. This stub:
#   - default             appends a harmless line to README.md (a NON-test file)
#   - BENCH_STUB_TAMPER=1  additionally edits the designated test file
#                          (failing_test.sh) to prove the checksum guard fires
# It never invokes the real `claude` binary.
#
set -euo pipefail

emit() { printf '%s\n' "$1"; }

emit "{\"type\":\"system\",\"subtype\":\"init\",\"agent\":\"stub-agent\",\"task_list_id\":\"${CLAUDE_CODE_TASK_LIST_ID:-}\",\"ts\":\"$(date -u +%FT%TZ)\"}"

if [ -f README.md ]; then
  printf '\nstub-agent edited this non-test file for instance %s run %s\n' \
    "${BENCH_INSTANCE_ID:-?}" "${BENCH_RUN_N:-?}" >> README.md
  emit "{\"type\":\"tool_use\",\"name\":\"edit\",\"file\":\"README.md\",\"tokens\":12}"
fi

if [ "${BENCH_STUB_TAMPER:-0}" = "1" ]; then
  printf '\n# illicitly modified by stub-agent (should trip the guard)\n' \
    >> failing_test.sh
  emit "{\"type\":\"tool_use\",\"name\":\"edit\",\"file\":\"failing_test.sh\",\"tokens\":8}"
fi

emit "{\"type\":\"result\",\"subtype\":\"success\",\"total_tokens\":20,\"ts\":\"$(date -u +%FT%TZ)\"}"
