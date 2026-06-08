#!/bin/bash
#
# worktree-create-handler.sh
# WorktreeCreate hook handler for claude-workflow plugin.
#
# Reads a JSON payload from stdin, provisions a canonical worktree via
# provision_worktree, and prints the absolute worktree path on stdout.
# Exits non-zero on any failure, which aborts native creation.
#
# Stdin JSON fields (all optional except worktree_name):
#   worktree_name   — slug for the new worktree (required, must match [a-z0-9-])
#   base_ref        — git ref to base the new branch on (optional, default: HEAD)
#   isolation_type  — "user" | "subagent" | "background" (optional, default: "user")
#   cwd             — working directory (optional, uses pwd if omitted)
#   session_id      — session identifier (optional, informational)
#
# Stdout contract:
#   On success: a single absolute path to the newly created worktree.
#   On failure: nothing on stdout; error message written to stderr.
#
# Exit codes:
#   0 — success, worktree created, absolute path on stdout
#   1 — validation or provisioning failure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CW_COMMON="$REPO_ROOT/bin/lib/cw-common.sh"

if [ ! -f "$CW_COMMON" ]; then
    echo "[ERROR] Cannot find $CW_COMMON" >&2
    exit 1
fi

source "$CW_COMMON"

# Override log functions after sourcing so all output goes to stderr.
# The stdout contract is: only the absolute worktree path on success.
log_error()   { echo "[ERROR] $*" >&2; }
log_info()    { echo "[INFO] $*" >&2; }
log_success() { echo "[OK] $*" >&2; }
log_warning() { echo "[WARN] $*" >&2; }
export -f log_error log_info log_success log_warning

# ---------------------------------------------------------------------------
# Parse stdin JSON
# ---------------------------------------------------------------------------

INPUT=$(cat)

worktree_name=$(printf '%s' "$INPUT" | jq -r '.worktree_name // empty' 2>/dev/null || true)
base_ref=$(printf '%s' "$INPUT" | jq -r '.base_ref // empty' 2>/dev/null || true)
isolation_type=$(printf '%s' "$INPUT" | jq -r '.isolation_type // "user"' 2>/dev/null || echo "user")
cwd=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
session_id=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)

# ---------------------------------------------------------------------------
# Validate worktree_name
# ---------------------------------------------------------------------------

if [ -z "$worktree_name" ]; then
    log_error "worktree_name is required in the hook payload"
    exit 1
fi

if [[ ! "$worktree_name" =~ ^[a-z0-9-]+$ ]]; then
    log_error "worktree_name must match [a-z0-9-], got: $worktree_name"
    exit 1
fi

# ---------------------------------------------------------------------------
# Determine working directory
# ---------------------------------------------------------------------------

if [ -n "$cwd" ]; then
    cd "$cwd" || { log_error "Cannot cd to cwd: $cwd"; exit 1; }
fi

# ---------------------------------------------------------------------------
# Subagent-isolation guard: determine provisioning mode from isolation_type
#
# Empirical signal: `isolation_type` in the stdin JSON payload.
#
# Claude Code sends this field in all WorktreeCreate payloads. Values observed:
#   "user"       — interactive `claude --worktree <name>` or EnterWorktree.
#                  Full provisioning is desired: write settings.local.json with
#                  CLAUDE_CODE_TASK_LIST_ID so the worktree gets an isolated task
#                  board, and copy gitignored include files (.env, etc.).
#   "subagent"   — a skill/agent invoked with `isolation: worktree`.
#                  Ephemeral; the subagent will run and be cleaned up. Heavy
#                  setup (task-list config, include-file copying) is wasteful and
#                  pollutes the task board. Minimal mode is appropriate.
#   "background" — a background session with isolation: worktree. Same
#                  reasoning as subagent: ephemeral, no task-list overhead.
#
# Alternative signals considered and rejected:
#   - `session_id` alone: present in all creates, not a reliable discriminator.
#   - `transcript_path`: present in all creates, does not vary by isolation type.
#   - Environment variables: no env var distinguishes subagent from user at
#     hook invocation time; the hook inherits the parent environment which is
#     identical for both paths.
#   - `cwd`: same for user and subagent creates initiated from the same directory.
#
# Fallback: an unrecognised isolation_type defaults to full mode (conservative —
# we'd rather over-provision an unknown type than silently skip setup for a user).
#
# "user" -> full mode (settings.local.json written, includes copied)
# "subagent" | "background" -> minimal mode (no settings, no includes)
# ---------------------------------------------------------------------------

case "$isolation_type" in
    user)
        mode="full"
        ;;
    subagent|background)
        mode="minimal"
        ;;
    *)
        log_warning "Unknown isolation_type '$isolation_type', defaulting to full mode"
        mode="full"
        ;;
esac

# ---------------------------------------------------------------------------
# Provision the worktree
# Redirect stdout to stderr during provisioning so that git messages
# (e.g. "HEAD is now at ...") do not pollute the stdout path contract.
# ---------------------------------------------------------------------------

{
    provision_worktree "$worktree_name" "$base_ref" "$mode"
} >&2 || { log_error "provision_worktree failed for slug '$worktree_name'"; exit 1; }

# ---------------------------------------------------------------------------
# Output the absolute path on stdout (the only stdout output)
# ---------------------------------------------------------------------------

printf '%s\n' "$CW_WORKTREE_PATH"
exit 0
