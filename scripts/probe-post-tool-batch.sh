#!/bin/bash
# probe-post-tool-batch.sh
# PostToolBatch hook PROBE — temporary diagnostic, log-only, non-blocking.
#
# Purpose: empirically determine whether PostToolBatch fires after a batch of
# parallel tool calls AND, critically, whether it fires for batches that contain
# native task-tool calls (TaskUpdate/TaskCreate) — the exact trigger of the
# task-store wipe. If it does, it is a synchronous detection point strictly
# better than the guard's 1s poll: it runs right after the dangerous batch and
# can block the agentic loop before the next model call.
#
# Logs a compact summary of each batch (timestamp + the tool names in the batch,
# extracted however they appear in the payload) plus the raw payload, then exits
# 0. Never blocks.
#
# Remove this script and its plugin.json wiring once the probe question is answered.

set -uo pipefail

INPUT=$(cat)
LOG="${HOME}/.claude/cw-hook-probe.log"
mkdir -p "$(dirname "$LOG")"

TOOLS="(jq unavailable)"
if command -v jq >/dev/null 2>&1; then
  # Try several plausible shapes for where tool names live in the batch payload.
  TOOLS=$(echo "$INPUT" | jq -rc '
    [ .. | objects | (.tool_name? // .toolName? // .name?) | select(type=="string") ]
    | unique | join(",")
  ' 2>/dev/null || echo "(parse-failed)")
fi

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
{
  echo "==== PostToolBatch @ ${TS} — tools: [${TOOLS}] ===="
  if command -v jq >/dev/null 2>&1; then
    echo "$INPUT" | jq . 2>/dev/null || echo "$INPUT"
  else
    echo "$INPUT"
  fi
  echo ""
} >> "$LOG"

exit 0
