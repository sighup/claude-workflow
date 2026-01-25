#!/bin/bash
#
# cw-common.sh - Shared functions and variables for Claude Workflow scripts
#
# Source this file at the beginning of CW scripts:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/cw-common.sh"
#

# =============================================================================
# Colors
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# =============================================================================
# Logging Functions
# =============================================================================

log_header() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_banner() {
    local TITLE="$1"
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    printf "${CYAN}║${NC}  %-56s ${CYAN}║${NC}\n" "$TITLE"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# =============================================================================
# Environment Configuration
# =============================================================================

CW_MODEL="${CW_MODEL:-sonnet}"
CW_TIMEOUT="${CW_TIMEOUT:-0}"            # seconds, 0 = no timeout
CW_SLEEP="${CW_SLEEP:-5}"                 # seconds between iterations
CW_MAX_ITERATIONS="${CW_MAX_ITERATIONS:-50}"
CW_MAX_FAILURES="${CW_MAX_FAILURES:-3}"

# Task file locations
CLAUDE_DIR="$HOME/.claude"
CLAUDE_TASKS_DIR="$CLAUDE_DIR/tasks"
CLAUDE_PROJECTS_DIR="$CLAUDE_DIR/projects"

# Session state (populated by discover_session)
CW_SESSION_ID=""
CW_TASKS_DIR=""

# =============================================================================
# Dependency Checks
# =============================================================================

check_jq() {
    if ! command -v jq &> /dev/null; then
        log_error "jq is required but not installed. Install with: brew install jq"
        return 1
    fi
    return 0
}

check_claude() {
    if ! command -v claude &> /dev/null; then
        log_error "claude CLI is required but not installed."
        return 1
    fi
    return 0
}

# =============================================================================
# Claude Invocation
# =============================================================================

invoke_claude() {
    local PROMPT="$1"
    local MODEL="${2:-$CW_MODEL}"

    local CMD=(claude --print --model "$MODEL" --dangerously-skip-permissions)
    CMD+=(-p "$PROMPT")

    local TIMEOUT_CMD=()
    if [ "$CW_TIMEOUT" -gt 0 ] 2>/dev/null; then
        TIMEOUT_CMD=(timeout "$CW_TIMEOUT")
    fi

    local EXIT_CODE=0
    "${TIMEOUT_CMD[@]}" "${CMD[@]}" || EXIT_CODE=$?

    if [ "$EXIT_CODE" -eq 124 ]; then
        log_error "Claude invocation timed out after ${CW_TIMEOUT}s"
        return 1
    fi
    return $EXIT_CODE
}

# =============================================================================
# Session Discovery
# =============================================================================

# Encode a path for Claude's project directory naming
# /Users/foo/bar -> -Users-foo-bar
encode_project_path() {
    local path="$1"
    echo "$path" | sed 's|^/|-|; s|/|-|g'
}

# Find the session ID for a project that has tasks
# Usage: discover_session [project_path]
# Sets: CW_SESSION_ID, CW_TASKS_DIR
discover_session() {
    local project_path="${1:-$(pwd)}"
    local encoded_path
    encoded_path=$(encode_project_path "$project_path")

    local sessions_index="$CLAUDE_PROJECTS_DIR/$encoded_path/sessions-index.json"

    if [ ! -f "$sessions_index" ]; then
        log_error "No sessions found for project: $project_path"
        log_info "Sessions index not found: $sessions_index"
        return 1
    fi

    # Find session with tasks, preferring most recently modified
    local session_id=""
    while IFS= read -r sid; do
        local tasks_dir="$CLAUDE_TASKS_DIR/$sid"
        if [ -d "$tasks_dir" ] && [ -n "$(ls -A "$tasks_dir" 2>/dev/null)" ]; then
            session_id="$sid"
            break
        fi
    done < <(jq -r '.entries | sort_by(.modified) | reverse | .[].sessionId' "$sessions_index" 2>/dev/null)

    if [ -z "$session_id" ]; then
        log_error "No session with tasks found for project: $project_path"
        return 1
    fi

    CW_SESSION_ID="$session_id"
    CW_TASKS_DIR="$CLAUDE_TASKS_DIR/$session_id"

    log_info "Session: $CW_SESSION_ID"
    log_info "Tasks dir: $CW_TASKS_DIR"
    return 0
}

# =============================================================================
# Task Helpers (Direct File Access)
# =============================================================================

# Read all tasks and output as JSON array
get_all_tasks() {
    if [ -z "$CW_TASKS_DIR" ] || [ ! -d "$CW_TASKS_DIR" ]; then
        echo "[]"
        return 1
    fi

    # Use jq to properly merge all task files into a single array
    jq -s '.' "$CW_TASKS_DIR"/*.json 2>/dev/null || echo "[]"
}

# Get count of pending unblocked tasks
# A task is unblocked if blockedBy is empty or all blockedBy tasks are completed
get_pending_count() {
    if [ -z "$CW_TASKS_DIR" ] || [ ! -d "$CW_TASKS_DIR" ]; then
        echo "0"
        return
    fi

    # Single jq call: compute completed IDs, then count pending unblocked
    jq -s '
        . as $all |
        [$all[] | select(.status == "completed") | .id] as $completed |
        [$all[] | select(
            .status == "pending" and
            ((.blockedBy // []) - $completed | length == 0)
        )] | length
    ' "$CW_TASKS_DIR"/*.json 2>/dev/null || echo "0"
}

# Get next task ID (first pending unblocked task)
get_next_task_id() {
    if [ -z "$CW_TASKS_DIR" ] || [ ! -d "$CW_TASKS_DIR" ]; then
        echo ""
        return
    fi

    # Single jq call: compute completed IDs, then find first pending unblocked
    jq -rs '
        . as $all |
        [$all[] | select(.status == "completed") | .id] as $completed |
        [$all[] | select(
            .status == "pending" and
            ((.blockedBy // []) - $completed | length == 0)
        )] | sort_by(.id | tonumber? // .id) | .[0].id // empty
    ' "$CW_TASKS_DIR"/*.json 2>/dev/null || echo ""
}

# Check if all tasks are complete
is_complete() {
    if [ -z "$CW_TASKS_DIR" ] || [ ! -d "$CW_TASKS_DIR" ]; then
        return 1
    fi

    local result
    result=$(jq -s '
        ([.[] | select(.status == "pending")] | length == 0) and
        ([.[] | select(.status == "in_progress")] | length == 0)
    ' "$CW_TASKS_DIR"/*.json 2>/dev/null)

    [ "$result" = "true" ]
}

# Get task counts by status
get_task_counts() {
    if [ -z "$CW_TASKS_DIR" ] || [ ! -d "$CW_TASKS_DIR" ]; then
        echo '{"total":0,"completed":0,"pending":0,"in_progress":0,"failed":0}'
        return
    fi

    jq -s '{
        total: length,
        completed: [.[] | select(.status=="completed")] | length,
        pending: [.[] | select(.status=="pending")] | length,
        in_progress: [.[] | select(.status=="in_progress")] | length,
        failed: [.[] | select(.metadata.failure_count > 0)] | length
    }' "$CW_TASKS_DIR"/*.json 2>/dev/null || echo '{"total":0,"completed":0,"pending":0,"in_progress":0,"failed":0}'
}

# =============================================================================
# Status Display
# =============================================================================

print_task_status() {
    local counts
    counts=$(get_task_counts)

    local TOTAL COMPLETED PENDING IN_PROGRESS FAILED
    TOTAL=$(echo "$counts" | jq '.total')
    COMPLETED=$(echo "$counts" | jq '.completed')
    PENDING=$(echo "$counts" | jq '.pending')
    IN_PROGRESS=$(echo "$counts" | jq '.in_progress')
    FAILED=$(echo "$counts" | jq '.failed')

    echo ""
    echo -e "  ${GREEN}Completed:${NC}   $COMPLETED/$TOTAL"
    echo -e "  ${YELLOW}Pending:${NC}     $PENDING"
    echo -e "  ${BLUE}In Progress:${NC} $IN_PROGRESS"
    echo -e "  ${RED}Failed:${NC}      $FAILED"
    echo ""

    if [ "$TOTAL" -gt 0 ]; then
        local PCT=$((COMPLETED * 100 / TOTAL))
        echo -e "  Progress: ${GREEN}${PCT}%${NC}"
        echo ""
    fi
}

# Show task list
show_task_list() {
    if [ -z "$CW_TASKS_DIR" ] || [ ! -d "$CW_TASKS_DIR" ]; then
        log_warning "No tasks directory found."
        return 1
    fi

    local count
    count=$(ls "$CW_TASKS_DIR"/*.json 2>/dev/null | wc -l | tr -d ' ')

    if [ "$count" -eq 0 ]; then
        log_warning "No tasks found."
        return 1
    fi

    jq -rs '.[] |
        if .status == "completed" then "  \u001b[32m[✓]\u001b[0m \(.metadata.task_id // .id): \(.subject)"
        elif .metadata.failure_count > 0 then "  \u001b[31m[✗]\u001b[0m \(.metadata.task_id // .id): \(.subject)"
        elif .status == "in_progress" then "  \u001b[33m[~]\u001b[0m \(.metadata.task_id // .id): \(.subject)"
        else "  [ ] \(.metadata.task_id // .id): \(.subject)"
        end
    ' "$CW_TASKS_DIR"/*.json 2>/dev/null | sort
}

# Get task subject by ID
get_task_subject() {
    local task_id="$1"
    if [ -z "$CW_TASKS_DIR" ] || [ ! -d "$CW_TASKS_DIR" ]; then
        echo ""
        return
    fi

    jq -rs --arg id "$task_id" '.[] | select(.id == $id) | .subject' "$CW_TASKS_DIR"/*.json 2>/dev/null || echo ""
}
