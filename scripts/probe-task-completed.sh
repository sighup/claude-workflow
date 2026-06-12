#!/bin/bash
# probe-task-completed.sh
# TaskCompleted hook PROBE — temporary diagnostic, log-only, non-blocking.
#
# Purpose: empirically confirm whether TaskCompleted fires for native task-tool
# completions and what its payload carries (task_id, metadata, status), so we can
# decide whether to promote it to an evidence-gated completion veto. Same hook
# family as the already-working TaskCreated, but its firing/payload are unverified.
#
# Writes the raw stdin payload (pretty-printed when jq is available) plus an ISO
# timestamp to a probe log, then exits 0. Never blocks completion.
#
# Remove this script and its plugin.json wiring once the probe question is answered.

set -uo pipefail

INPUT=$(cat)
LOG="${HOME}/.claude/cw-hook-probe.log"
mkdir -p "$(dirname "$LOG")"

SUBJECT=""
if command -v jq >/dev/null 2>&1; then
  SUBJECT=$(echo "$INPUT" | jq -r '.task_subject // empty' 2>/dev/null || true)
fi

# Block-capability probe: if the completed task's subject contains BLOCKME,
# attempt to veto the completion via exit 2. Confirms whether TaskCompleted can
# actually prevent completion (docs claim it can) before we build a real gate.
DECISION="logged (exit 0)"
case "$SUBJECT" in
  *BLOCKME*) DECISION="VETO attempted (exit 2)" ;;
esac

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
{
  echo "==== TaskCompleted @ ${TS} — ${DECISION} ===="
  if command -v jq >/dev/null 2>&1; then
    echo "$INPUT" | jq . 2>/dev/null || echo "$INPUT"
  else
    echo "$INPUT"
  fi
  echo ""
} >> "$LOG"

case "$SUBJECT" in
  *BLOCKME*)
    echo "probe veto: task '${SUBJECT}' completion blocked (no journal evidence)." >&2
    exit 2
    ;;
esac

exit 0
