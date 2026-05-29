#!/bin/bash
# validate-task-metadata.sh
# TaskCreated hook for metadata validation
#
# Part of claude-workflow plugin - automatically active when plugin is installed
#
# Reads hook input JSON from stdin, extracts task metadata, and enforces the
# plan->execute typed contract: required fields (task_id, demoable_unit,
# spec_path, scope, requirements) and enum-valued fields (complexity, model,
# role) must be present and in-range.
#
# Blocking: on a plan->execute task with a missing required field or an
# out-of-enum value, outputs {"decision":"block"} naming the offending field
# to force the planner to re-emit. Tasks carrying none of the plan fields are
# not plan->execute tasks and pass through silently (exit 0, no output).

set -euo pipefail

# Read hook input from stdin
INPUT=$(cat)

# Required fields that /cw-plan should populate
REQUIRED_FIELDS=("task_id" "demoable_unit" "spec_path" "scope" "requirements")

# Helper: read a metadata field value ("" when absent)
get_field() {
  echo "$INPUT" | jq -r --arg f "$1" '.task.metadata[$f] // empty' 2>/dev/null || true
}

# Determine whether this is a plan->execute task. A task is plan-emitted when
# its metadata carries at least one of the required plan fields; tasks with
# none of them (e.g. manual or testing stubs) are out of scope and not blocked.
IS_PLAN_TASK=false
for field in "${REQUIRED_FIELDS[@]}"; do
  if [ -n "$(get_field "$field")" ]; then
    IS_PLAN_TASK=true
    break
  fi
done

# Not a plan->execute task - pass through silently
if [ "$IS_PLAN_TASK" = false ]; then
  exit 0
fi

# Build list of missing required fields
OFFENDERS=()
for field in "${REQUIRED_FIELDS[@]}"; do
  if [ -z "$(get_field "$field")" ]; then
    OFFENDERS+=("missing required field '${field}'")
  fi
done

# Enum-valued fields - validate when present (absence of a required enum field
# is already reported above; role is optional but must be in-range if set)
check_enum() {
  local field="$1" allowed="$2" value
  value=$(get_field "$field")
  if [ -n "$value" ] && ! grep -qx "$value" <<< "$allowed"; then
    OFFENDERS+=("field '${field}' has out-of-enum value '${value}' (allowed: $(echo "$allowed" | paste -sd '|' -))")
  fi
}

check_enum "complexity" $'trivial\nstandard\ncomplex'
check_enum "model" $'haiku\nsonnet\nopus'
check_enum "role" $'implementer\nvalidator\nspec-writer'

# If everything is valid, exit silently
if [ ${#OFFENDERS[@]} -eq 0 ]; then
  exit 0
fi

# Build comma-separated list of offending fields
OFFENDER_LIST=$(printf '%s; ' "${OFFENDERS[@]}")
OFFENDER_LIST="${OFFENDER_LIST%; }"

# Block task creation and instruct /cw-plan to re-emit with a valid contract
REASON="Task rejected - metadata contract violation: ${OFFENDER_LIST}. /cw-plan must re-emit this task with all required fields and in-enum values (complexity: trivial|standard|complex, model: haiku|sonnet|opus, role: implementer|validator|spec-writer) so workers can execute it autonomously."
jq -n --arg reason "$REASON" '{decision: "block", reason: $reason}'

exit 0
