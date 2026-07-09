#!/bin/bash
#
# Unit tests for cw_worktree_names() in plugin/scripts/lib/cw-common.sh:
# type inference, keyword stripping, slug validation, repo-name sanitization.
#
source "$(dirname "$0")/helpers.sh"
source "$PLUGIN_DIR/scripts/lib/cw-common.sh"

echo "cw_worktree_names: naming derivation"

repo=$(make_repo myrepo)
cd "$repo" || exit 1

t "plain slug defaults to feature type"
assert_eq "feature-myrepo-auth
feature-myrepo-auth
feature/auth" "$(cw_worktree_names auth)"

t "fix keyword stripped into fix type"
assert_eq "fix-myrepo-login
fix-myrepo-login
fix/login" "$(cw_worktree_names fix-login)"

t "bug maps to fix"
assert_eq "fix/crash" "$(cw_worktree_names bug-crash | sed -n 3p)"

t "spike maps to research"
assert_eq "research-myrepo-cache" "$(cw_worktree_names spike-cache | sed -n 1p)"

t "refactor maps to chore"
assert_eq "chore/db-layer" "$(cw_worktree_names refactor-db-layer | sed -n 3p)"

t "keyword only matches with hyphen boundary (fixer stays feature)"
assert_eq "feature/fixer" "$(cw_worktree_names fixer | sed -n 3p)"

t "bare keyword rejected (empty slug after strip)"
cw_worktree_names fix >/dev/null 2>&1
assert_failure $?

t "empty slug rejected"
cw_worktree_names "" >/dev/null 2>&1
assert_failure $?

t "invalid characters rejected"
cw_worktree_names "Bad_Slug" >/dev/null 2>&1
assert_failure $?

t "error path emits nothing on stdout (stderr-only logging)"
out=$(cw_worktree_names "" 2>/dev/null)
assert_empty "$out"

repo2=$(make_repo "My_Repo.X")
cd "$repo2" || exit 1

t "repo name sanitized to [a-z0-9-]"
assert_eq "feature-my-repo-x-auth" "$(cw_worktree_names auth | sed -n 1p)"

t "bin/lib/cw-common.sh sources cleanly (standalone cw-status library)"
bash -c "source '$PLUGIN_DIR/bin/lib/cw-common.sh' && type discover_session >/dev/null" >/dev/null 2>&1
assert_success $?

finish
