#!/bin/bash
#
# cw-common.sh - Shared functions and variables for Claude Workflow scripts
#
# Source this file at the beginning of CW scripts:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/cw-common.sh"
#
# Scope: this file backs the surviving bin/ tools (cw-status, cw-herdr-open).
# The autonomous runners that once relied on Claude invocation, pipeline state,
# and PID tracking have been removed, so only the cw-status task-reading cluster
# remains here. Worktree provisioning lives in scripts/lib/cw-common.sh.
#

# =============================================================================
# Colors
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

# Warnings and errors go to stderr so they never pollute $(...) command
# substitutions in callers.
log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
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

# Task file locations
CLAUDE_DIR="$HOME/.claude"
CLAUDE_TASKS_DIR="$CLAUDE_DIR/tasks"
CLAUDE_PROJECTS_DIR="$CLAUDE_DIR/projects"

# Session state (populated by discover_session)
CW_SESSION_ID=""
CW_TASK_LIST_ID=""
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

# =============================================================================
# Session Discovery
# =============================================================================

# Encode a path for Claude's project directory naming
# /Users/foo/bar -> -Users-foo-bar
encode_project_path() {
    local path="$1"
    echo "$path" | sed 's|^/|-|; s|/|-|g'
}

# Resolve CLAUDE_CODE_TASK_LIST_ID from env or project settings
# Usage: _resolve_task_list_id project_path
# Prints the task list ID if found, empty string otherwise
_resolve_task_list_id() {
    local project_path="$1"

    # 1. Environment variable (highest priority)
    if [ -n "${CLAUDE_CODE_TASK_LIST_ID:-}" ]; then
        echo "$CLAUDE_CODE_TASK_LIST_ID"
        return 0
    fi

    # 2. settings.local.json
    local local_settings="$project_path/.claude/settings.local.json"
    if [ -f "$local_settings" ]; then
        local val
        val=$(jq -r '.env.CLAUDE_CODE_TASK_LIST_ID // empty' "$local_settings" 2>/dev/null)
        if [ -n "$val" ]; then
            echo "$val"
            return 0
        fi
    fi

    # 3. settings.json
    local settings="$project_path/.claude/settings.json"
    if [ -f "$settings" ]; then
        local val
        val=$(jq -r '.env.CLAUDE_CODE_TASK_LIST_ID // empty' "$settings" 2>/dev/null)
        if [ -n "$val" ]; then
            echo "$val"
            return 0
        fi
    fi

    return 1
}

# Warn once about any corrupt JSON task files in CW_TASKS_DIR
_warn_corrupt_tasks() {
    [ -n "$CW_TASKS_DIR" ] && [ -d "$CW_TASKS_DIR" ] || return 0
    local bad_files=()
    for f in "$CW_TASKS_DIR"/*.json; do
        [ -f "$f" ] || continue
        jq empty "$f" 2>/dev/null || bad_files+=("$(basename "$f")")
    done
    if [ ${#bad_files[@]} -gt 0 ]; then
        log_warning "${#bad_files[@]} corrupt task file(s) will be skipped: ${bad_files[*]}"
    fi
}

# Find the session ID for a project that has tasks
# Usage: discover_session [project_path]
# Sets: CW_SESSION_ID, CW_TASK_LIST_ID, CW_TASKS_DIR
discover_session() {
    local project_path="${1:-$(pwd)}"

    # Fast path: check for CLAUDE_CODE_TASK_LIST_ID
    local task_list_id
    task_list_id=$(_resolve_task_list_id "$project_path") || true
    if [ -n "$task_list_id" ]; then
        local tl_dir="$CLAUDE_TASKS_DIR/$task_list_id"
        # Check for actual .json task files, not just any files (e.g. .DS_Store)
        local tl_json=("$tl_dir"/*.json)
        if [ -d "$tl_dir" ] && [ -f "${tl_json[0]}" ]; then
            CW_TASK_LIST_ID="$task_list_id"
            CW_TASKS_DIR="$tl_dir"
            log_info "Task list: $CW_TASK_LIST_ID"
            log_info "Tasks dir: $CW_TASKS_DIR"
            _warn_corrupt_tasks
            return 0
        fi
        # No .json task files — fall through to session-based lookup
    fi

    # Session-based lookup (original path)
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
    _warn_corrupt_tasks
    return 0
}

# =============================================================================
# Task Helpers (Direct File Access)
# =============================================================================

# Check if task dir has JSON files (call after directory guard)
_has_task_files() {
    local files=("$CW_TASKS_DIR"/*.json)
    [ -f "${files[0]}" ]
}

# Slurp valid task JSON files into an array, skipping corrupt files.
# One malformed file must not break all task operations.
# Usage: _slurp_tasks '.[] | .status'  (pass jq filter directly)
_slurp_tasks() {
    local filter="${1:-.}"
    for f in "$CW_TASKS_DIR"/*.json; do
        jq -c '.' "$f" 2>/dev/null
    done | jq -s "$filter" 2>/dev/null
}

# Get task counts by status
get_task_counts() {
    if [ -z "$CW_TASKS_DIR" ] || [ ! -d "$CW_TASKS_DIR" ]; then
        echo '{"total":0,"completed":0,"pending":0,"in_progress":0,"failed":0}'
        return
    fi
    _has_task_files || { echo '{"total":0,"completed":0,"pending":0,"in_progress":0,"failed":0}'; return; }

    _slurp_tasks '{
        total: length,
        completed: [.[] | select(.status=="completed")] | length,
        pending: [.[] | select(.status=="pending")] | length,
        in_progress: [.[] | select(.status=="in_progress")] | length,
        failed: [.[] | select(.metadata.failure_count > 0)] | length
    }' || echo '{"total":0,"completed":0,"pending":0,"in_progress":0,"failed":0}'
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
    _has_task_files || { log_warning "No tasks found."; return 1; }

    _slurp_tasks '.[] |
        if .status == "completed" then "  \u001b[32m[✓]\u001b[0m \(.metadata.task_id // .id): \(.subject)"
        elif .metadata.failure_count > 0 then "  \u001b[31m[✗]\u001b[0m \(.metadata.task_id // .id): \(.subject)"
        elif .status == "in_progress" then "  \u001b[33m[~]\u001b[0m \(.metadata.task_id // .id): \(.subject)"
        else "  [ ] \(.metadata.task_id // .id): \(.subject)"
        end
    ' 2>/dev/null | sort
}
