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
CW_PROOF_TIMEOUT="${CW_PROOF_TIMEOUT:-120}"  # seconds per re-executed proof
CW_MAX_TURNS="${CW_MAX_TURNS:-0}"        # per-invocation agentic turn cap, 0 = unlimited

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

    # Proactive per-invocation budget: cap agentic turns so a runaway worker
    # cannot burn the whole run before the reactive 429-detector trips.
    if [ "$CW_MAX_TURNS" -gt 0 ] 2>/dev/null; then
        CMD+=(--max-turns "$CW_MAX_TURNS")
    fi

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

# Validate that a flag requiring a value actually received one
require_arg() {
    if [ -z "${2:-}" ]; then
        log_error "$1 requires a value"
        exit 4
    fi
}

# Read all tasks and output as JSON array
get_all_tasks() {
    if [ -z "$CW_TASKS_DIR" ] || [ ! -d "$CW_TASKS_DIR" ]; then
        echo "[]"
        return 1
    fi
    _has_task_files || { echo "[]"; return 1; }

    _slurp_tasks '.' || echo "[]"
}

# Get count of pending unblocked tasks
# A task is unblocked if blockedBy is empty or all blockedBy tasks are completed
get_pending_count() {
    if [ -z "$CW_TASKS_DIR" ] || [ ! -d "$CW_TASKS_DIR" ]; then
        echo "0"
        return
    fi
    _has_task_files || { echo "0"; return; }

    _slurp_tasks '
        . as $all |
        [$all[] | select(.status == "completed") | .id] as $completed |
        [$all[] | select(
            .status == "pending" and
            ((.blockedBy // []) - $completed | length == 0)
        )] | length
    ' || echo "0"
}

# Get next task ID (first pending unblocked task)
get_next_task_id() {
    if [ -z "$CW_TASKS_DIR" ] || [ ! -d "$CW_TASKS_DIR" ]; then
        echo ""
        return
    fi
    _has_task_files || { echo ""; return; }

    _slurp_tasks '
        . as $all |
        [$all[] | select(.status == "completed") | .id] as $completed |
        [$all[] | select(
            .status == "pending" and
            ((.blockedBy // []) - $completed | length == 0)
        )] | sort_by(.id | tonumber? // .id) | .[0].id // empty
    ' || echo ""
}

# Check if all tasks are complete
is_complete() {
    if [ -z "$CW_TASKS_DIR" ] || [ ! -d "$CW_TASKS_DIR" ]; then
        return 1
    fi
    _has_task_files || return 1

    local result
    result=$(_slurp_tasks '
        ([.[] | select(.status == "pending")] | length == 0) and
        ([.[] | select(.status == "in_progress")] | length == 0)
    ')

    [ "$result" = "true" ]
}

# Get count of completed tasks
get_completed_count() {
    if [ -z "$CW_TASKS_DIR" ] || [ ! -d "$CW_TASKS_DIR" ]; then
        echo "0"
        return
    fi
    _has_task_files || { echo "0"; return; }

    _slurp_tasks '[.[] | select(.status == "completed")] | length' || echo "0"
}

# Count pending FIX-* tasks
# Matches by subject/task_id prefix or metadata.fix_task_id (cw-testing convention)
get_pending_fix_count() {
    if [ -z "$CW_TASKS_DIR" ] || [ ! -d "$CW_TASKS_DIR" ]; then
        echo "0"
        return
    fi
    _has_task_files || { echo "0"; return; }

    _slurp_tasks '[.[] | select(
        (.subject | test("^FIX"; "i")) or
        (.metadata.task_id // "" | test("^FIX"; "i")) or
        (.metadata.fix_task_id != null)
    ) | select(.status == "pending")] | length' || echo "0"
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
    _has_task_files || { log_warning "No tasks found."; return 1; }

    _slurp_tasks '.[] |
        if .status == "completed" then "  \u001b[32m[✓]\u001b[0m \(.metadata.task_id // .id): \(.subject)"
        elif .metadata.failure_count > 0 then "  \u001b[31m[✗]\u001b[0m \(.metadata.task_id // .id): \(.subject)"
        elif .status == "in_progress" then "  \u001b[33m[~]\u001b[0m \(.metadata.task_id // .id): \(.subject)"
        else "  [ ] \(.metadata.task_id // .id): \(.subject)"
        end
    ' 2>/dev/null | sort
}

# Get task subject by ID
get_task_subject() {
    local task_id="$1"
    if [ -z "$CW_TASKS_DIR" ] || [ ! -d "$CW_TASKS_DIR" ]; then
        echo ""
        return
    fi
    _has_task_files || { echo ""; return; }

    jq -r '.subject' "$CW_TASKS_DIR/$task_id.json" 2>/dev/null || echo ""
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

    # Ensure .worktrees is gitignored (with lock to prevent races)
    local lockfile=".git/cw-gitignore.lock"
    if ! git check-ignore -q .worktrees/ 2>/dev/null && ! grep -qx '.worktrees/' .gitignore 2>/dev/null; then
        # Simple lock: try to create atomically
        if (set -o noclobber; echo $$ > "$lockfile") 2>/dev/null; then
            echo ".worktrees/" >> .gitignore
            git add .gitignore
            git commit -m "chore: add .worktrees to gitignore" -- .gitignore 2>/dev/null || true
            rm -f "$lockfile"
        else
            # Another process is handling it — wait briefly
            sleep 2
        fi
    fi

    # Check for existing worktree
    if [ -d "$worktree_dir" ]; then
        if [ "${CW_RESUME:-false}" = "true" ]; then
            log_info "Reusing existing worktree: $worktree_dir"
            CW_WORKTREE_PATH="$(cd "$worktree_dir" && pwd)"
            return 0
        else
            log_error "Worktree already exists: $worktree_dir"
            log_info "Use --resume to continue from where you left off"
            return 1
        fi
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

# =============================================================================
# Input-Hash Idempotency (shared by proof gate + pipeline checkpoints)
# =============================================================================
#
# A re-entered stage/proof is only safe to skip when its *inputs* are unchanged.
# The input hash is computed over the committed tree (git blob SHAs of scope
# files) plus the command string, so it is reproducible on re-entry and a
# working-copy edit cannot mask staleness. See
# skills/cw-execute/references/proof-gate.md.

# Content hash of a proof/stage's true input set: the command string plus the
# git blob SHA of every scope file (deterministic order). A scope file with no
# committed blob hashes as MISSING:<path> — a distinct value that forces re-run.
# Usage: proof_input_hash COMMAND [SCOPE_FILE...]
proof_input_hash() {
    local cmd="$1"; shift
    {
        local f
        for f in $(printf '%s\n' "$@" | LC_ALL=C sort); do
            git rev-parse "HEAD:$f" 2>/dev/null || echo "MISSING:$f"
        done
        printf '%s\n' "$cmd"
    } | git hash-object --stdin
}

# Re-entry verdict for a single proof artifact: should it be re-executed?
# Skip applies only to a recorded PASS whose stamped hash matches the recomputed
# hash; a FAIL/BLOCKED, a missing hash, or a hash mismatch always re-runs.
# Usage: proof_should_rerun STORED_STATUS STAMPED_HASH CURRENT_HASH
# Returns: 0 (re-run) when stale/unverified, 1 (skip) when prior PASS still valid
proof_should_rerun() {
    local stored_status="$1"
    local stamped_hash="$2"
    local current_hash="$3"

    [ "$stored_status" = "PASS" ] || return 0
    [ -n "$stamped_hash" ] || return 0
    [ "$stamped_hash" = "$current_hash" ] || return 0
    return 1
}

# Re-execute a task's proof artifacts in a fresh shell and decide PASS/FAIL
# independently of the worker's self-reported proof_results. The producer is an
# untrusted data plane: its stored status is narration, not evidence. See
# skills/cw-execute/references/proof-gate.md.
#
# For each artifact: recompute the input hash over the committed scope, skip only
# a recorded PASS at a matching hash (proof_should_rerun), otherwise re-run the
# command under timeout and judge by exit status. Non-automatable proofs
# (browser, or capture method "manual") accept a recorded PASS attestation only
# while its hash matches; an unverifiable proof with no valid attestation fails.
#
# Usage: proof_gate_passes TASK_ID
# Returns: 0 if every artifact gates PASS (or there are none), 1 otherwise.
proof_gate_passes() {
    local task_id="$1"
    local task_file="$CW_TASKS_DIR/$task_id.json"
    [ -f "$task_file" ] || { log_warning "Proof gate: task $task_id not found"; return 1; }

    local artifacts
    artifacts=$(jq -c '.metadata.proof_artifacts // []' "$task_file" 2>/dev/null)
    local count
    count=$(printf '%s' "$artifacts" | jq 'length' 2>/dev/null || echo 0)
    [ "${count:-0}" -gt 0 ] || return 0

    local repo_root
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
        log_warning "Proof gate: not in a git repo, cannot re-verify $task_id"
        return 1
    }

    local scope_files
    scope_files=$(jq -r '
        [(.metadata.scope.files_to_create // [])[],
         (.metadata.scope.files_to_modify // [])[]] | .[]
    ' "$task_file" 2>/dev/null)
    local sf_arr=()
    while IFS= read -r f; do [ -n "$f" ] && sf_arr+=("$f"); done <<< "$scope_files"

    local i all_pass=0
    for ((i = 0; i < count; i++)); do
        local art type cmd cap_method
        art=$(printf '%s' "$artifacts" | jq -c ".[$i]")
        type=$(printf '%s' "$art" | jq -r '.type // "cli"')
        cap_method=$(printf '%s' "$art" | jq -r '.capture_method // "auto"')
        # The proof command string is the part hashed and re-executed.
        case "$type" in
            file) cmd=$(printf '%s' "$art" | jq -r '(.path // "") + " :: " + (.contains // "")') ;;
            url)  cmd=$(printf '%s' "$art" | jq -r '(.method // "GET") + " " + (.url // "")') ;;
            *)    cmd=$(printf '%s' "$art" | jq -r '.command // ""') ;;
        esac

        local cur_hash
        cur_hash=$(proof_input_hash "$cmd" "${sf_arr[@]}")

        # Stored verdict + stamped hash for this artifact (by index).
        local stored_status stamped_hash
        stored_status=$(jq -r ".metadata.proof_results[$i].status // \"\" | ascii_upcase" "$task_file" 2>/dev/null)
        stamped_hash=$(jq -r ".metadata.proof_results[$i].input_hash // \"\"" "$task_file" 2>/dev/null)

        if ! proof_should_rerun "$stored_status" "$stamped_hash" "$cur_hash"; then
            log_info "Proof gate [$task_id #$((i + 1)) $type]: PASS (hash match, skip re-run)"
            continue
        fi

        # Non-automatable proofs cannot be re-executed by the gate. Accept a
        # recorded PASS attestation only while its hash still matches.
        if [ "$type" = "browser" ] || [ "$cap_method" = "manual" ]; then
            if [ "$stored_status" = "PASS" ] && [ -n "$stamped_hash" ] && [ "$stamped_hash" = "$cur_hash" ]; then
                log_info "Proof gate [$task_id #$((i + 1)) $type]: PASS (attested, hash match)"
            else
                log_warning "Proof gate [$task_id #$((i + 1)) $type]: FAIL (no valid attestation)"
                all_pass=1
            fi
            continue
        fi

        if [ -z "$cmd" ] || [ "$cmd" = " :: " ]; then
            log_warning "Proof gate [$task_id #$((i + 1)) $type]: FAIL (no command to re-execute)"
            all_pass=1
            continue
        fi

        # Re-execute from the committed tree under a timeout (fresh shell).
        local rc=0
        if [ "$type" = "file" ]; then
            local p c
            p=$(printf '%s' "$art" | jq -r '.path // ""')
            c=$(printf '%s' "$art" | jq -r '.contains // ""')
            if [ ! -f "$repo_root/$p" ]; then
                rc=1
            elif [ -n "$c" ] && ! grep -qF -- "$c" "$repo_root/$p"; then
                rc=1
            fi
        else
            ( cd "$repo_root" && timeout "$CW_PROOF_TIMEOUT" bash -c "$cmd" ) >/dev/null 2>&1 || rc=$?
        fi

        if [ "$rc" -eq 0 ]; then
            log_info "Proof gate [$task_id #$((i + 1)) $type]: PASS (re-executed)"
        else
            log_warning "Proof gate [$task_id #$((i + 1)) $type]: FAIL (re-executed, exit $rc)"
            all_pass=1
        fi
    done

    return "$all_pass"
}

# Reset a task that failed its proof gate back to pending so the loop re-attempts
# it, recording why. A worker's TaskUpdate is not the source of truth — the gate
# is — so a completed-but-unproven task must not be counted done.
# Usage: reset_task_pending TASK_ID REASON
reset_task_pending() {
    local task_id="$1"
    local reason="${2:-proof gate failed}"
    local task_file="$CW_TASKS_DIR/$task_id.json"
    [ -f "$task_file" ] || return 1

    local tmp_file
    tmp_file=$(mktemp)
    if jq --arg r "$reason" \
        '.status = "pending" | .metadata.proof_gate = {"verdict": "FAIL", "reason": $r, "at": (now | todate)}' \
        "$task_file" > "$tmp_file" 2>/dev/null; then
        mv "$tmp_file" "$task_file"
    else
        rm -f "$tmp_file"
        return 1
    fi
}

# =============================================================================
# Pipeline State Management (Resumable Pipeline)
# =============================================================================

PIPELINE_STATE_FILE=".claude/pipeline-state.json"

# Stage name lookup
_pipeline_stage_name() {
    case "$1" in
        1) echo "worktree" ;;
        2) echo "init" ;;
        3) echo "execute" ;;
        4) echo "validate" ;;
        5) echo "review" ;;
        6) echo "test-init" ;;
        7) echo "test-loop" ;;
        8) echo "revalidate" ;;
        9) echo "pr" ;;
        *) echo "unknown" ;;
    esac
}

# Initialize pipeline state file
# Usage: pipeline_state_init WORK_DIR FEATURE_NAME MODE VALUE
pipeline_state_init() {
    local work_dir="$1"
    local feature_name="$2"
    local mode="$3"
    local value="$4"
    local state_file="$work_dir/$PIPELINE_STATE_FILE"

    mkdir -p "$(dirname "$state_file")"

    local stages='{}'
    for i in $(seq 1 9); do
        stages=$(echo "$stages" | jq --arg n "$i" --arg name "$(_pipeline_stage_name "$i")" \
            '.[$n] = {"name": $name, "status": "pending", "started_at": null, "completed_at": null}')
    done

    jq -n \
        --arg fn "$feature_name" \
        --arg m "$mode" \
        --arg v "$value" \
        --argjson stages "$stages" \
        --argjson no_test "${NO_TEST:-false}" \
        --argjson no_review "${NO_REVIEW:-false}" \
        --argjson no_pr "${NO_PR:-false}" \
        --argjson no_worktree "${NO_WORKTREE:-false}" \
        --argjson auto_pr "${AUTO_PR:-false}" \
        --arg model "${CW_MODEL:-sonnet}" \
        --argjson verbose "${CW_VERBOSE:-false}" \
        '{
            version: 1,
            feature_name: $fn,
            mode: $m,
            value: $v,
            current_stage: 0,
            stages: $stages,
            flags: {
                no_test: $no_test,
                no_review: $no_review,
                no_pr: $no_pr,
                no_worktree: $no_worktree,
                auto_pr: $auto_pr,
                model: $model,
                verbose: $verbose
            },
            created_at: (now | todate),
            updated_at: (now | todate)
        }' > "$state_file"

    log_info "Pipeline state initialized: $state_file"
}

# Update a stage's status with timestamp. An optional INPUT_HASH stamps the
# committed-tree hash of the stage's inputs so re-entry can detect staleness;
# omit it for stages with no scope (the stage then always re-runs on change).
# Usage: pipeline_checkpoint WORK_DIR STAGE_NUM STATUS [INPUT_HASH]
pipeline_checkpoint() {
    local work_dir="$1"
    local stage_num="$2"
    local new_status="$3"
    local input_hash="${4:-}"
    local state_file="$work_dir/$PIPELINE_STATE_FILE"

    if [ ! -f "$state_file" ]; then
        log_warning "No pipeline state file found at $state_file"
        return 1
    fi

    local ts_field
    case "$new_status" in
        in_progress) ts_field="started_at" ;;
        completed|skipped) ts_field="completed_at" ;;
        *) ts_field="" ;;
    esac

    local tmp_file
    tmp_file=$(mktemp)

    if [ -n "$ts_field" ]; then
        jq --arg n "$stage_num" --arg s "$new_status" --arg tf "$ts_field" --arg ih "$input_hash" \
            '.stages[$n].status = $s | .stages[$n][$tf] = (now | todate) | (if $ih != "" then .stages[$n].input_hash = $ih else . end) | .current_stage = ($n | tonumber) | .updated_at = (now | todate)' \
            "$state_file" > "$tmp_file" && mv "$tmp_file" "$state_file"
    else
        jq --arg n "$stage_num" --arg s "$new_status" --arg ih "$input_hash" \
            '.stages[$n].status = $s | (if $ih != "" then .stages[$n].input_hash = $ih else . end) | .current_stage = ($n | tonumber) | .updated_at = (now | todate)' \
            "$state_file" > "$tmp_file" && mv "$tmp_file" "$state_file"
    fi
}

# Get the first stage that needs to run (not completed/skipped)
# Usage: pipeline_get_resume_stage WORK_DIR
# Prints stage number or "done"
pipeline_get_resume_stage() {
    local work_dir="$1"
    local state_file="$work_dir/$PIPELINE_STATE_FILE"

    if [ ! -f "$state_file" ]; then
        echo "1"
        return
    fi

    local result
    result=$(jq -r '
        [.stages | to_entries[] | select(.value.status != "completed" and .value.status != "skipped") | .key | tonumber] |
        sort | first // "done"
    ' "$state_file")

    echo "$result"
}

# Re-entry verdict for a completed/skipped stage: must it re-run because its
# inputs changed? Recomputes the committed-tree input hash from CURRENT_HASH and
# compares it to the stamped hash. A stage with no stamped hash is treated as
# unverified and re-runs; a matching hash lets the coarse status flag stand.
# Usage: pipeline_stage_is_stale WORK_DIR STAGE_NUM CURRENT_HASH
# Returns: 0 (stale, re-run) or 1 (fresh, prior result still valid)
pipeline_stage_is_stale() {
    local work_dir="$1"
    local stage_num="$2"
    local current_hash="$3"
    local state_file="$work_dir/$PIPELINE_STATE_FILE"

    [ -f "$state_file" ] || return 0

    local stored_status stamped_hash
    stored_status=$(jq -r --arg n "$stage_num" '.stages[$n].status // ""' "$state_file")
    stamped_hash=$(jq -r --arg n "$stage_num" '.stages[$n].input_hash // ""' "$state_file")

    case "$stored_status" in
        completed|skipped) ;;
        *) return 0 ;;
    esac
    [ -n "$stamped_hash" ] || return 0
    [ "$stamped_hash" = "$current_hash" ] && return 1
    return 0
}

# Check if pipeline state file exists
# Usage: pipeline_state_exists WORK_DIR
pipeline_state_exists() {
    local work_dir="$1"
    [ -f "$work_dir/$PIPELINE_STATE_FILE" ]
}

# Read stored flags from state file and export as shell variables
# Usage: pipeline_read_flags WORK_DIR
pipeline_read_flags() {
    local work_dir="$1"
    local state_file="$work_dir/$PIPELINE_STATE_FILE"

    if [ ! -f "$state_file" ]; then
        log_error "No pipeline state file: $state_file"
        return 1
    fi

    # Read flags — CLI overrides take precedence (only set if not already set by CLI)
    local flags
    flags=$(jq '.flags' "$state_file")

    if [ "${NO_TEST_SET:-false}" != "true" ]; then
        NO_TEST=$(echo "$flags" | jq -r '.no_test')
    fi
    if [ "${NO_REVIEW_SET:-false}" != "true" ]; then
        NO_REVIEW=$(echo "$flags" | jq -r '.no_review')
    fi
    if [ "${NO_PR_SET:-false}" != "true" ]; then
        NO_PR=$(echo "$flags" | jq -r '.no_pr')
    fi
    if [ "${NO_WORKTREE_SET:-false}" != "true" ]; then
        NO_WORKTREE=$(echo "$flags" | jq -r '.no_worktree')
    fi
    if [ "${AUTO_PR_SET:-false}" != "true" ]; then
        AUTO_PR=$(echo "$flags" | jq -r '.auto_pr')
    fi
    if [ "${MODEL_SET:-false}" != "true" ]; then
        CW_MODEL=$(echo "$flags" | jq -r '.model')
    fi
    if [ "${VERBOSE_SET:-false}" != "true" ]; then
        CW_VERBOSE=$(echo "$flags" | jq -r '.verbose')
    fi

    # Read feature metadata
    local mode value
    mode=$(jq -r '.mode' "$state_file")
    value=$(jq -r '.value' "$state_file")

    RESUME_MODE="$mode"
    RESUME_VALUE="$value"

    log_info "Restored flags from pipeline state"
}
