# Common Workflows

End-to-end examples combining skills.

## Quick feature (interactive)

```
# Inside Claude
/cw-spec auth
/cw-plan
/cw-dispatch
/cw-validate
```

## Plan first, execute later

```
# Generate spec + plan, review before executing
/cw-spec "Build JWT authentication"
/cw-plan

# Review the task list, then execute when ready
/cw-dispatch
/cw-validate
```

## Recover from failures

```
# Check what failed
/cw-validate

# Re-run dispatch — Claude picks up failed tasks and retries
/cw-dispatch
```

## Parallel features (interactive)

```
# Main session — create worktrees (repo name inserted automatically, e.g. myrepo)
/cw-worktree create auth
/cw-worktree create fix-login

# Terminal 1 — feature-myrepo-auth on branch feature/auth
cd .claude/worktrees/feature-myrepo-auth && claude
/cw-spec → /cw-plan → /cw-dispatch → /cw-validate
gh pr create

# Terminal 2 — fix-myrepo-login on branch fix/login
cd .claude/worktrees/fix-myrepo-login && claude
/cw-spec → /cw-plan → /cw-dispatch → /cw-validate
gh pr create

# Main session — cleanup after PRs merged
/cw-worktree cleanup
```
