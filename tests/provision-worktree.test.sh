#!/bin/bash
#
# Integration tests for provision_worktree() in plugin/scripts/lib/cw-common.sh,
# run against throwaway git repos.
#
source "$(dirname "$0")/helpers.sh"
source "$PLUGIN_DIR/scripts/lib/cw-common.sh"

echo "provision_worktree: worktree creation in a fixture repo"

repo=$(make_repo myrepo)
cd "$repo" || exit 1

t "full-mode provisioning succeeds"
provision_worktree auth >/dev/null 2>&1
assert_success $?

wt="$repo/.claude/worktrees/feature-myrepo-auth"

t "worktree directory created at canonical path"
assert_dir "$wt"

t "branch feature/auth created"
git show-ref --verify --quiet refs/heads/feature/auth
assert_success $?

t "CW_WORKTREE_PATH points at the new worktree"
assert_eq "$wt" "$CW_WORKTREE_PATH"

t "settings.local.json carries the task-list id (dir==id invariant)"
grep -q '"CLAUDE_CODE_TASK_LIST_ID": "feature-myrepo-auth"' \
    "$wt/.claude/settings.local.json" 2>/dev/null
assert_success $?

t ".claude/worktrees/ appended to .gitignore"
grep -qxF ".claude/worktrees/" .gitignore
assert_success $?

t "gitignore append is idempotent across provisions"
echo "extra" > .env
provision_worktree billing >/dev/null 2>&1
assert_eq "1" "$(grep -cxF '.claude/worktrees/' .gitignore)"

t ".env copied into new worktree by default include list"
assert_file "$repo/.claude/worktrees/feature-myrepo-billing/.env"

t "existing branch is checked out instead of erroring"
git branch fix/login main
provision_worktree fix-login >/dev/null 2>&1
assert_success $?

t "existing-branch worktree is on that branch"
assert_eq "fix/login" \
    "$(git -C "$repo/.claude/worktrees/fix-myrepo-login" branch --show-current)"

t "minimal mode skips settings.local.json"
provision_worktree chore-docs "" minimal >/dev/null 2>&1
assert_no_file "$repo/.claude/worktrees/chore-myrepo-docs/.claude/settings.local.json"

t "invalid mode rejected"
provision_worktree whatever "" bogus >/dev/null 2>&1
assert_failure $?

t "base_ref respected"
git checkout -qb dev main
echo "dev change" >> README.md
git commit -qam "dev commit"
dev_sha=$(git rev-parse dev)
git checkout -q main
provision_worktree based dev >/dev/null 2>&1
assert_eq "$dev_sha" \
    "$(git -C "$repo/.claude/worktrees/feature-myrepo-based" rev-parse HEAD)"

t ".worktreeinclude overrides the default include list"
printf '# comment line\n\nconfig/secret.txt\n' > .worktreeinclude
mkdir -p config && echo "s3cret" > config/secret.txt
provision_worktree search >/dev/null 2>&1
assert_file "$repo/.claude/worktrees/feature-myrepo-search/config/secret.txt"

t ".env not copied when .worktreeinclude omits it"
assert_no_file "$repo/.claude/worktrees/feature-myrepo-search/.env"

finish
