#!/bin/bash
#
# bench/lib/task_list_id.sh - derive a unique CLAUDE_CODE_TASK_LIST_ID per
# (instance-id, arm, run-n) tuple.
#
# Sourced by bench/run_instance.sh. The id is deterministic per tuple, so two
# runs that differ only in --run-n get different ids and never share a
# ~/.claude/tasks list (which the concurrent-write-wipe risk documented in
# scripts/task-store-guard.sh makes unsafe).
#
set -euo pipefail

# derive_task_list_id <instance_id> <arm> <run_n> -> prints the isolated id.
derive_task_list_id() {
  local instance="$1" arm="$2" run="$3"
  local raw="${instance}-${arm}-${run}"
  local slug
  # collapse anything that is not env/filesystem-safe into a single dash
  slug="$(printf '%s' "$raw" | tr -c 'A-Za-z0-9._-' '-')"
  printf 'bench-tl-%s' "$slug"
}
