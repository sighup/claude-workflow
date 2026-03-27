#!/bin/bash
# validate-task-metadata.sh
# TaskCreated hook for metadata validation
#
# Part of claude-workflow plugin - automatically active when plugin is installed
#
# Reads hook input JSON from stdin, extracts task metadata, and checks for
# required fields: task_id, demoable_unit, spec_path, scope, requirements.
# Outputs additionalContext listing missing fields when any are absent.
# Exits silently (exit 0, no output) when all required fields are present.
# Non-blocking: never prevents task creation.

set -euo pipefail

# Read hook input from stdin
INPUT=$(cat)

# Extract metadata from task - TaskCreated hook provides task data
# The spec assumes task data is nested under .task.metadata
METADATA=$(echo "$INPUT" | jq -r '.task.metadata // {} | to_entries | map(.key) | @json' 2>/dev/null || echo '[]')

# Required fields that /cw-plan should populate
REQUIRED_FIELDS=("task_id" "demoable_unit" "spec_path" "scope" "requirements")

# Build list of missing fields
MISSING_FIELDS=()
for field in "${REQUIRED_FIELDS[@]}"; do
  # Check if field exists and is non-empty in metadata
  VALUE=$(echo "$INPUT" | jq -r --arg f "$field" '.task.metadata[$f] // empty' 2>/dev/null || true)
  if [ -z "$VALUE" ]; then
    MISSING_FIELDS+=("$field")
  fi
done

# If all required fields are present, exit silently
if [ ${#MISSING_FIELDS[@]} -eq 0 ]; then
  exit 0
fi

# Build comma-separated list of missing fields
MISSING_LIST=$(printf '%s, ' "${MISSING_FIELDS[@]}")
MISSING_LIST="${MISSING_LIST%, }"

# Output warning as additionalContext (non-blocking - no "decision": "block")
cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "TaskCreated",
    "additionalContext": "Task created with missing metadata: ${MISSING_LIST}. Tasks from /cw-plan should include these fields for proper /cw-execute tracking. Run /cw-plan to generate tasks with complete metadata."
  }
}
EOF

exit 0
