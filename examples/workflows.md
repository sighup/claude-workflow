# Common Workflows

End-to-end examples combining skills and shell scripts.

## Quick feature (interactive)

```
# Inside Claude
/cw-spec auth
/cw-plan
/cw-dispatch
/cw-validate
```

## Quick feature (unattended)

```bash
# From terminal — single command does everything
./bin/cw-pipeline --prompt "Build JWT authentication" --name auth
```

## Plan first, execute later

```bash
# Generate spec + plan, review before executing
./bin/cw-init --prompt "Build JWT authentication"
./bin/cw-status --list              # Review the task plan

# Execute when ready
./bin/cw-loop --dispatch --verbose

# Validate
./bin/cw-loop-interactive           # Or use cw-loop for unattended
```

## Recover from failures

```bash
# Check what failed
./bin/cw-status --failed

# Re-run — Claude will pick up failed tasks and retry
./bin/cw-loop --verbose
```

## Parallel features (unattended)

```bash
./bin/cw-pipeline \
  --feature "auth:prompt:Build JWT authentication" \
  --feature "billing:prompt:Add Stripe billing integration" \
  --feature "search:prompt:Full-text search with Elasticsearch"
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
