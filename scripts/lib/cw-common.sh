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

CW_INVOKE_RETRIES="${CW_INVOKE_RETRIES:-3}"    # retries per invocation
CW_RETRY_DELAY="${CW_RETRY_DELAY:-10}"          # seconds between retries
CW_VERBOSE="${CW_VERBOSE:-false}"               # stream JSON output for visibility

invoke_claude() {
    local PROMPT="$1"
    local MODEL="${2:-$CW_MODEL}"
    local ATTEMPT=0

    local CMD=(claude --print --model "$MODEL" --dangerously-skip-permissions)

    # Add streaming JSON output for real-time visibility
    if [ "$CW_VERBOSE" = "true" ]; then
        CMD+=(--verbose --output-format stream-json)
    fi

    # Resume the discovered session to access its tasks
    if [ -n "$CW_SESSION_ID" ]; then
        CMD+=(--resume "$CW_SESSION_ID")
    fi

    CMD+=(-p "$PROMPT")

    local TIMEOUT_CMD=()
    if [ "$CW_TIMEOUT" -gt 0 ] 2>/dev/null; then
        TIMEOUT_CMD=(timeout "$CW_TIMEOUT")
    fi

    while [ "$ATTEMPT" -lt "$CW_INVOKE_RETRIES" ]; do
        ATTEMPT=$((ATTEMPT + 1))

        local EXIT_CODE=0
        local OUTPUT
        local TMPFILE
        TMPFILE=$(mktemp)

        # Run command, capturing stderr for error detection
        "${TIMEOUT_CMD[@]}" "${CMD[@]}" 2>"$TMPFILE" || EXIT_CODE=$?

        local STDERR
        STDERR=$(cat "$TMPFILE")
        rm -f "$TMPFILE"

        # Check for timeout
        if [ "$EXIT_CODE" -eq 124 ]; then
            log_error "Claude invocation timed out after ${CW_TIMEOUT}s (attempt $ATTEMPT/$CW_INVOKE_RETRIES)"
        # Check for known crash patterns in stderr
        elif echo "$STDERR" | grep -qE "No messages returned|unhandled|SIGTERM|SIGKILL"; then
            log_error "Claude CLI crashed: $(echo "$STDERR" | head -1) (attempt $ATTEMPT/$CW_INVOKE_RETRIES)"
            EXIT_CODE=1
        # Success
        elif [ "$EXIT_CODE" -eq 0 ]; then
            [ -n "$STDERR" ] && echo "$STDERR" >&2
            return 0
        else
            log_error "Claude invocation failed with exit code $EXIT_CODE (attempt $ATTEMPT/$CW_INVOKE_RETRIES)"
            [ -n "$STDERR" ] && echo "$STDERR" >&2
        fi

        # Retry with exponential backoff
        if [ "$ATTEMPT" -lt "$CW_INVOKE_RETRIES" ]; then
            local DELAY=$((CW_RETRY_DELAY * ATTEMPT))
            log_warning "Retrying in ${DELAY}s..."
            sleep "$DELAY"
        fi
    done

    log_error "All $CW_INVOKE_RETRIES attempts failed"
    return 1
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

# Get count of completed tasks
get_completed_count() {
    if [ -z "$CW_TASKS_DIR" ] || [ ! -d "$CW_TASKS_DIR" ]; then
        echo "0"
        return
    fi

    jq -s '[.[] | select(.status == "completed")] | length' "$CW_TASKS_DIR"/*.json 2>/dev/null || echo "0"
}

# Count pending FIX-* tasks
# Matches by subject/task_id prefix or metadata.fix_task_id (cw-testing convention)
get_pending_fix_count() {
    if [ -z "$CW_TASKS_DIR" ] || [ ! -d "$CW_TASKS_DIR" ]; then
        echo "0"
        return
    fi

    jq -s '[.[] | select(
        (.subject | test("^FIX"; "i")) or
        (.metadata.task_id // "" | test("^FIX"; "i")) or
        (.metadata.fix_task_id != null)
    ) | select(.status == "pending")] | length' "$CW_TASKS_DIR"/*.json 2>/dev/null || echo "0"
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
# Time Utilities
# =============================================================================

# Format seconds as "Xh Ym" or "Ym Zs"
format_elapsed() {
    local SECONDS_ELAPSED="$1"
    local HOURS=$((SECONDS_ELAPSED / 3600))
    local MINS=$(((SECONDS_ELAPSED % 3600) / 60))
    local SECS=$((SECONDS_ELAPSED % 60))

    if [ "$HOURS" -gt 0 ]; then
        printf "%dh %dm" "$HOURS" "$MINS"
    elif [ "$MINS" -gt 0 ]; then
        printf "%dm %ds" "$MINS" "$SECS"
    else
        printf "%ds" "$SECS"
    fi
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

# =============================================================================
# Worktree Management
# =============================================================================

# Create a git worktree for a feature
# Usage: create_worktree FEATURE_NAME
# Sets: CW_WORKTREE_PATH
create_worktree() {
    local feature_name="$1"

    if [ -z "$feature_name" ]; then
        log_error "Feature name is required"
        return 1
    fi

    # Validate feature name
    if [[ ! "$feature_name" =~ ^[a-z0-9-]+$ ]]; then
        log_error "Feature name must be lowercase alphanumeric with hyphens: $feature_name"
        return 1
    fi

    local worktree_dir=".worktrees/feature-${feature_name}"
    local branch_name="feature/${feature_name}"

    # Ensure .worktrees is gitignored
    if ! git check-ignore -q .worktrees 2>/dev/null; then
        echo ".worktrees/" >> .gitignore
        git add .gitignore
        git commit -m "chore: add .worktrees to gitignore"
    fi

    # Check for existing worktree
    if [ -d "$worktree_dir" ]; then
        log_error "Worktree already exists: $worktree_dir"
        return 1
    fi

    # Create worktree (use existing branch if it exists)
    if git show-ref --verify --quiet "refs/heads/$branch_name"; then
        log_warning "Branch $branch_name already exists, using it"
        git worktree add "$worktree_dir" "$branch_name"
    else
        git worktree add "$worktree_dir" -b "$branch_name"
    fi

    if [ $? -ne 0 ]; then
        log_error "Failed to create worktree"
        return 1
    fi

    # Configure isolated task list
    mkdir -p "${worktree_dir}/.claude"
    cat > "${worktree_dir}/.claude/settings.local.json" << EOF
{
  "env": {
    "CLAUDE_CODE_TASK_LIST_ID": "feature-${feature_name}"
  }
}
EOF

    CW_WORKTREE_PATH="$(cd "$worktree_dir" && pwd)"

    log_success "Worktree created: $worktree_dir (branch: $branch_name)"
    return 0
}

# =============================================================================
# Spec Input Resolution
# =============================================================================

# Resolve spec input from various sources
# Usage: resolve_spec_input MODE VALUE
#   MODE: "prompt" | "spec" | "auto"
#   VALUE: prompt text, spec path, or empty for auto
# Sets: CW_SPEC_MODE, CW_SPEC_VALUE
CW_SPEC_MODE=""
CW_SPEC_VALUE=""

resolve_spec_input() {
    local mode="${1:-auto}"
    local value="$2"

    case "$mode" in
        prompt)
            if [ -z "$value" ]; then
                log_error "Prompt text is required with --prompt"
                return 1
            fi
            CW_SPEC_MODE="prompt"
            CW_SPEC_VALUE="$value"
            ;;
        spec)
            if [ -z "$value" ]; then
                log_error "Spec path is required with --spec"
                return 1
            fi
            if [ ! -f "$value" ]; then
                log_error "Spec file not found: $value"
                return 1
            fi
            CW_SPEC_MODE="spec"
            CW_SPEC_VALUE="$value"
            ;;
        auto)
            # Auto-discover most recent spec in docs/specs/
            local specs_dir="docs/specs"
            if [ ! -d "$specs_dir" ]; then
                log_error "No specs directory found at $specs_dir"
                return 1
            fi

            # Find the most recently modified spec file
            local latest_spec=""
            latest_spec=$(find "$specs_dir" -name "*.md" -not -name "*questions*" -type f 2>/dev/null \
                | xargs ls -t 2>/dev/null \
                | head -1)

            if [ -z "$latest_spec" ]; then
                log_error "No spec files found in $specs_dir"
                return 1
            fi

            CW_SPEC_MODE="spec"
            CW_SPEC_VALUE="$latest_spec"
            log_info "Auto-discovered spec: $CW_SPEC_VALUE"
            ;;
        *)
            log_error "Unknown spec mode: $mode"
            return 1
            ;;
    esac

    return 0
}

# =============================================================================
# PID Management (Bash 3.2 compatible — indexed arrays)
# =============================================================================

# Indexed arrays for tracking background processes
PID_LIST=()
PID_LABELS=()
PID_STATUSES=()
PID_EXIT_CODES=()

# Register a background process for tracking
# Usage: register_pid PID LABEL
register_pid() {
    local pid="$1"
    local label="$2"

    PID_LIST+=("$pid")
    PID_LABELS+=("$label")
    PID_STATUSES+=("running")
    PID_EXIT_CODES+=("")

    log_info "Registered PID $pid for: $label"
}

# Monitor all registered PIDs until completion
# Usage: monitor_pids [INTERVAL]
# INTERVAL: polling interval in seconds (default: 30)
monitor_pids() {
    local interval="${1:-30}"
    local all_done=false

    while [ "$all_done" = false ]; do
        all_done=true

        for i in "${!PID_LIST[@]}"; do
            local pid="${PID_LIST[$i]}"
            local label="${PID_LABELS[$i]}"
            local status="${PID_STATUSES[$i]}"

            # Skip already completed
            if [ "$status" != "running" ]; then
                continue
            fi

            # Check if still running
            if kill -0 "$pid" 2>/dev/null; then
                all_done=false
            else
                # Process completed — capture exit code
                wait "$pid" 2>/dev/null
                local exit_code=$?
                PID_EXIT_CODES[$i]="$exit_code"

                if [ "$exit_code" -eq 0 ]; then
                    PID_STATUSES[$i]="completed"
                    log_success "$label: completed"
                else
                    PID_STATUSES[$i]="failed"
                    log_error "$label: failed (exit code $exit_code)"
                fi
            fi
        done

        if [ "$all_done" = false ]; then
            # Report running processes
            local running_count=0
            for status in "${PID_STATUSES[@]}"; do
                [ "$status" = "running" ] && running_count=$((running_count + 1))
            done
            log_info "$running_count process(es) still running. Checking again in ${interval}s..."
            sleep "$interval"
        fi
    done
}

# Get results summary after monitoring
# Returns: 0 if all succeeded, 1 if any failed
get_pipeline_results() {
    local total=${#PID_LIST[@]}
    local passed=0
    local failed=0

    echo ""
    log_header "Pipeline Results"

    for i in "${!PID_LIST[@]}"; do
        local label="${PID_LABELS[$i]}"
        local status="${PID_STATUSES[$i]}"
        local exit_code="${PID_EXIT_CODES[$i]}"

        if [ "$status" = "completed" ]; then
            echo -e "  ${GREEN}[PASS]${NC} $label"
            passed=$((passed + 1))
        else
            echo -e "  ${RED}[FAIL]${NC} $label (exit code: $exit_code)"
            failed=$((failed + 1))
        fi
    done

    echo ""
    echo -e "  Total: $total  |  ${GREEN}Passed: $passed${NC}  |  ${RED}Failed: $failed${NC}"
    echo ""

    [ "$failed" -eq 0 ]
}
