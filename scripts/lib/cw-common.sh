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
CW_MANIFEST="${CW_MANIFEST:-cw-manifest.json}"

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
# Manifest Helpers
# =============================================================================

# Export manifest (calls Claude with haiku for speed)
export_manifest() {
    log_info "Exporting task state to $CW_MANIFEST..."
    invoke_claude "Use the Skill tool to invoke 'cw-manifest'. Export the current task board state." "haiku"
}

# Get count of pending unblocked tasks from manifest
get_pending_count() {
    jq '[.tasks[] | select(.status=="pending" and (.blocked_by|length)==0)] | length' "$CW_MANIFEST" 2>/dev/null || echo "0"
}

# Get next task ID from manifest
get_next_task_id() {
    jq -r '[.tasks[] | select(.status=="pending" and (.blocked_by|length)==0)] | sort_by(.task_id) | .[0].task_id // empty' "$CW_MANIFEST" 2>/dev/null
}

# Check if all tasks are complete
is_complete() {
    local RESULT
    RESULT=$(jq '.summary.pending == 0 and .summary.in_progress == 0' "$CW_MANIFEST" 2>/dev/null)
    [ "$RESULT" = "true" ]
}

# Get failed task count
get_failed_count() {
    jq '.summary.failed // 0' "$CW_MANIFEST" 2>/dev/null || echo "0"
}

# =============================================================================
# Status Display
# =============================================================================

print_manifest_status() {
    if [ ! -f "$CW_MANIFEST" ]; then
        log_warning "No manifest file found. Run export first."
        return 1
    fi

    local TOTAL COMPLETED PENDING IN_PROGRESS FAILED
    TOTAL=$(jq '.summary.total' "$CW_MANIFEST")
    COMPLETED=$(jq '.summary.completed' "$CW_MANIFEST")
    PENDING=$(jq '.summary.pending' "$CW_MANIFEST")
    IN_PROGRESS=$(jq '.summary.in_progress' "$CW_MANIFEST")
    FAILED=$(jq '.summary.failed' "$CW_MANIFEST")

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

# Show task list from manifest
show_task_list() {
    if [ ! -f "$CW_MANIFEST" ]; then
        log_warning "No manifest file found."
        return 1
    fi

    jq -r '.tasks[] |
        if .status == "completed" then "  \u001b[32m[✓]\u001b[0m \(.task_id): \(.subject)"
        elif .status == "failed" then "  \u001b[31m[✗]\u001b[0m \(.task_id): \(.subject)"
        elif .status == "in_progress" then "  \u001b[33m[~]\u001b[0m \(.task_id): \(.subject)"
        else "  [ ] \(.task_id): \(.subject)"
        end
    ' "$CW_MANIFEST"
}
