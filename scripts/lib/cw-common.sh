#!/bin/bash
#
# scripts/lib/cw-common.sh - Worktree provisioning functions for hook handlers
#
# Contains: provision_worktree, cw_worktree_names, create_worktree, plus the
# logging functions, color constants, and path constants those functions require.
#
# Source this file from hook handlers:
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib/cw-common.sh"
#
# This is the single source of truth for the relocated provisioning functions.
# bin/lib/cw-common.sh sources this file to avoid duplicated definitions.
#

# =============================================================================
# Colors
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# =============================================================================
# Logging Functions
# =============================================================================

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

# =============================================================================
# Path Constants (used by discover_session / task helpers in bin/lib)
# =============================================================================

CLAUDE_DIR="$HOME/.claude"
CLAUDE_TASKS_DIR="$CLAUDE_DIR/tasks"
CLAUDE_PROJECTS_DIR="$CLAUDE_DIR/projects"

# =============================================================================
# Worktree Management
# =============================================================================

# Derive deterministic worktree names from a raw slug.
#
# Usage: cw_worktree_names SLUG
#   Prints three lines:
#     1. directory basename (= task list ID): {type}-{repo}-{slug}
#     2. task list ID (same as line 1)
#     3. branch name: {type}/{slug}
#
# Type inference (first matching rule wins):
#   fix|bug|hotfix        -> fix
#   research|spike|explore -> research
#   chore|refactor|docs|build|ci -> chore
#   (anything else)       -> feature
#
# The matching leading keyword and its separating hyphen are stripped from slug.
# Repo is derived from the main worktree (not a nested worktree directory).
# Returns non-zero if the post-strip slug is empty or contains chars outside [a-z0-9-].
cw_worktree_names() {
    local raw_slug="$1"

    if [ -z "$raw_slug" ]; then
        log_error "cw_worktree_names: slug is required"
        return 1
    fi

    # Infer type and strip leading keyword
    local type slug
    if [[ "$raw_slug" =~ ^(fix|bug|hotfix)(-|$) ]]; then
        type="fix"
        slug="${raw_slug#"${BASH_REMATCH[1]}"}"
        slug="${slug#-}"
    elif [[ "$raw_slug" =~ ^(research|spike|explore)(-|$) ]]; then
        type="research"
        slug="${raw_slug#"${BASH_REMATCH[1]}"}"
        slug="${slug#-}"
    elif [[ "$raw_slug" =~ ^(chore|refactor|docs|build|ci)(-|$) ]]; then
        type="chore"
        slug="${raw_slug#"${BASH_REMATCH[1]}"}"
        slug="${slug#-}"
    else
        type="feature"
        slug="$raw_slug"
    fi

    # Reject empty or invalid slug after stripping
    if [ -z "$slug" ]; then
        log_error "cw_worktree_names: slug is empty after keyword stripping (input: $raw_slug)"
        return 1
    fi
    if [[ ! "$slug" =~ ^[a-z0-9-]+$ ]]; then
        log_error "cw_worktree_names: slug contains invalid characters (must match ^[a-z0-9-]+$): $slug"
        return 1
    fi

    # Derive repo name from the main worktree (not a nested worktree path)
    local main_worktree
    main_worktree=$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')
    if [ -z "$main_worktree" ]; then
        # Fallback: parent of git-common-dir
        local common_dir
        common_dir=$(git rev-parse --git-common-dir 2>/dev/null)
        if [ -n "$common_dir" ]; then
            main_worktree=$(cd "$common_dir/.." 2>/dev/null && pwd)
        fi
    fi
    if [ -z "$main_worktree" ]; then
        log_error "cw_worktree_names: could not determine main worktree"
        return 1
    fi

    # Sanitize repo name to [a-z0-9-]
    local repo
    repo=$(basename "$main_worktree" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//; s/-$//')

    local dir_id="${type}-${repo}-${slug}"
    local branch="${type}/${slug}"

    printf '%s\n%s\n%s\n' "$dir_id" "$dir_id" "$branch"
    return 0
}

# Provision a canonical worktree — naming, directory, base-ref, no-commit.
#
# Usage: provision_worktree SLUG [BASE_REF] [MODE]
#   SLUG     — raw slug (may carry type prefix; passed to cw_worktree_names)
#   BASE_REF — optional git ref to base the new branch on (default: HEAD)
#   MODE     — "full" (default) or "minimal"
#              full:    writes .claude/settings.local.json with CLAUDE_CODE_TASK_LIST_ID
#                       and copies gitignored include files into the new worktree
#              minimal: skips the settings write and include copying entirely
#
# Include file copying (full mode only):
#   Reads the list of files to copy from ".worktreeinclude" in the source tree root.
#   If ".worktreeinclude" is absent, falls back to a default list containing ".env".
#   Each listed file is copied from the source tree into the new worktree only if it
#   exists at the source path. Files are NOT staged or committed — they are expected
#   to be gitignored in the new worktree (same gitignore rules apply).
#
# Side effects:
#   - Creates the worktree directory under .claude/worktrees/{type}-{repo}-{slug}
#   - Appends ".claude/worktrees/" to .gitignore if not already present (unstaged)
#   - Sets CW_WORKTREE_PATH to the absolute path of the new worktree
#   - In full mode: writes {worktree}/.claude/settings.local.json (CLAUDE_CODE_TASK_LIST_ID = dir_id)
#   - In full mode: copies gitignored include files from source tree into new worktree
#
# Guarantees:
#   - Never runs git add or git commit
#   - Checks out an existing branch instead of erroring when the branch exists
#
# Returns non-zero on any provisioning failure.
provision_worktree() {
    local raw_slug="$1"
    local base_ref="${2:-}"
    local mode="${3:-full}"

    if [ -z "$raw_slug" ]; then
        log_error "provision_worktree: slug is required"
        return 1
    fi

    case "$mode" in
        full|minimal) ;;
        *)
            log_error "provision_worktree: mode must be 'full' or 'minimal', got: $mode"
            return 1
            ;;
    esac

    # Derive canonical names
    local names
    names=$(cw_worktree_names "$raw_slug") || return 1

    local dir_id branch_name
    dir_id=$(printf '%s' "$names" | sed -n '1p')
    branch_name=$(printf '%s' "$names" | sed -n '3p')

    local worktree_dir=".claude/worktrees/${dir_id}"

    # Ensure .claude/worktrees/ is gitignored — ensure-only, no staging/commit.
    # Respect any pre-existing broader ignore rule (via git check-ignore) before
    # appending, so we don't add a redundant exact-match line.
    local gitignore_entry=".claude/worktrees/"
    if ! git check-ignore -q "$gitignore_entry" 2>/dev/null \
        && ! grep -qxF "$gitignore_entry" .gitignore 2>/dev/null; then
        printf '\n%s\n' "$gitignore_entry" >> .gitignore
    fi

    # Create parent directory
    mkdir -p "$(dirname "$worktree_dir")"

    # Create worktree — checkout existing branch or create new one
    if git show-ref --verify --quiet "refs/heads/$branch_name"; then
        log_warning "provision_worktree: branch $branch_name already exists, checking it out"
        git worktree add "$worktree_dir" "$branch_name" || return 1
    elif [ -n "$base_ref" ]; then
        git worktree add -b "$branch_name" "$worktree_dir" "$base_ref" || return 1
    else
        git worktree add -b "$branch_name" "$worktree_dir" || return 1
    fi

    # Full mode: write isolated task-list settings (dir==id invariant)
    if [ "$mode" = "full" ]; then
        mkdir -p "${worktree_dir}/.claude"
        cat > "${worktree_dir}/.claude/settings.local.json" << EOF
{
  "env": {
    "CLAUDE_CODE_TASK_LIST_ID": "${dir_id}"
  }
}
EOF

        # Copy gitignored include files into the new worktree.
        # Source list: .worktreeinclude in the repo root (one path per line, blank lines
        # and lines starting with '#' are ignored). Fallback when absent: ".env" only.
        local source_root
        source_root="$(pwd)"
        local include_files=()
        if [ -f "${source_root}/.worktreeinclude" ]; then
            while IFS= read -r inc_line; do
                # Strip leading/trailing whitespace
                inc_line="${inc_line#"${inc_line%%[![:space:]]*}"}"
                inc_line="${inc_line%"${inc_line##*[![:space:]]}"}"
                # Skip blank lines and comments
                [ -z "$inc_line" ] && continue
                [[ "$inc_line" == \#* ]] && continue
                include_files+=("$inc_line")
            done < "${source_root}/.worktreeinclude"
        else
            include_files=(".env")
        fi

        local src_file dst_file
        if [ "${#include_files[@]}" -gt 0 ]; then
            for inc_entry in "${include_files[@]}"; do
                src_file="${source_root}/${inc_entry}"
                dst_file="${worktree_dir}/${inc_entry}"
                if [ -f "$src_file" ]; then
                    mkdir -p "$(dirname "$dst_file")"
                    cp "$src_file" "$dst_file"
                    log_info "provision_worktree: copied include file $inc_entry into worktree"
                fi
            done
        fi
    fi

    CW_WORKTREE_PATH="$(cd "$worktree_dir" && pwd)"

    log_success "provision_worktree: created $worktree_dir (branch: $branch_name, mode: $mode)"
    return 0
}

# Create a git worktree for a feature
# Usage: create_worktree SLUG
#   SLUG may carry a type prefix (fix-, research-, chore-, etc.) — cw_worktree_names
#   derives the type, repo, and canonical directory/branch names.
# Sets: CW_WORKTREE_PATH
#
# Delegates to provision_worktree (full mode) for the actual provisioning.
# Worktrees are created under .claude/worktrees/{type}-{repo}-{slug}.
create_worktree() {
    local feature_name="$1"

    if [ -z "$feature_name" ]; then
        log_error "Feature name is required"
        return 1
    fi

    # Validate slug characters before calling the helper
    if [[ ! "$feature_name" =~ ^[a-z0-9-]+$ ]]; then
        log_error "Feature name must be lowercase alphanumeric with hyphens: $feature_name"
        return 1
    fi

    # Derive canonical names to support CW_RESUME check and logging
    local names
    names=$(cw_worktree_names "$feature_name") || return 1

    local dir_id
    dir_id=$(printf '%s' "$names" | sed -n '1p')

    local worktree_dir=".claude/worktrees/${dir_id}"

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

    # Delegate to provision_worktree (full mode) — handles naming, dir creation,
    # gitignore ensure, branch creation, and settings.local.json write.
    provision_worktree "$feature_name" "" "full" || return 1

    return 0
}
