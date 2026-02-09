# Shell Script Examples

Usage examples for all shell scripts (run from the terminal, unattended).

## cw-pipeline

Full end-to-end orchestrator. Goes from a prompt or spec to a pull request.

```bash
# Single feature from a prompt
./scripts/cw-pipeline --prompt "Build JWT authentication" --name auth

# Single feature from an existing spec
./scripts/cw-pipeline --spec docs/specs/01-spec-auth.md --name auth

# Skip optional stages
./scripts/cw-pipeline --prompt "Add health check" --name health --no-test --no-review

# Auto-create PR without pausing for confirmation
./scripts/cw-pipeline --prompt "Add billing API" --name billing --auto-pr

# Use a specific model
./scripts/cw-pipeline --prompt "Build search" --name search -m opus

# Multiple features in parallel
./scripts/cw-pipeline \
  --feature "auth:prompt:Build JWT authentication" \
  --feature "billing:spec:docs/specs/02-spec-billing.md"

# Run in current directory (no worktree)
./scripts/cw-pipeline --prompt "Fix login bug" --name login-fix --no-worktree
```

Stages: worktree → spec → plan → execute → validate → review → test-init → test-loop → re-validate → PR.

## cw-init

Generate a spec and plan without executing. Useful for reviewing the plan before running `cw-loop`.

```bash
# From a prompt
./scripts/cw-init --prompt "Build JWT authentication"

# From an existing spec (skips spec generation)
./scripts/cw-init --spec docs/specs/01-spec-auth.md

# Auto-discover the most recent spec
./scripts/cw-init

# With a specific model and verbose output
./scripts/cw-init --prompt "Add user profiles" -m opus -v
```

## cw-loop

Autonomous execution loop. Picks up tasks and executes them until the board is complete.

```bash
# Default — quiet mode, sequential execution
./scripts/cw-loop

# Stream output for visibility
./scripts/cw-loop --verbose

# Parallel execution via cw-dispatch
./scripts/cw-loop --dispatch

# Custom model and iteration limit
./scripts/cw-loop -m opus -n 100

# Shorter sleep between iterations
./scripts/cw-loop -s 2

# Point at a specific project directory
./scripts/cw-loop /path/to/project

# Combine options
./scripts/cw-loop -d -m opus -n 100 -v
```

## cw-loop-interactive

Human-in-the-loop execution. Pauses after each task for review.

```bash
./scripts/cw-loop-interactive

# With a specific model
./scripts/cw-loop-interactive -m opus
```

Interactive commands after each task:
- **Enter** — continue to next task
- **r** — retry the current task
- **s** — skip the current task
- **q** — quit the loop
- **v** — run validation
- **d** — show git diff

## cw-test-init

Generate E2E test scenarios and add them to the task board as `TEST-*` tasks.

```bash
# From a spec file
./scripts/cw-test-init --spec docs/specs/01-spec-auth/01-spec-auth.md

# From a description
./scripts/cw-test-init --prompt "Test JWT authentication flows"

# Auto-discover the most recent spec
./scripts/cw-test-init

# With verbose output
./scripts/cw-test-init --spec docs/specs/01-spec-auth.md -v
```

## cw-test-loop

Execute test tasks with auto-fix cycles. Runs tests, creates fix tasks for failures, executes fixes, then retests.

```bash
# Default — 3 fix cycles, 50 iterations per cycle
./scripts/cw-test-loop

# More fix cycles for complex projects
./scripts/cw-test-loop --max-cycles 5

# Custom iteration limit per cycle
./scripts/cw-test-loop -n 100

# Point at a specific project
./scripts/cw-test-loop /path/to/project

# Combine options
./scripts/cw-test-loop -c 5 -n 100 -m opus -v
```

## cw-status

Check task progress. Reads task files directly — no Claude invocation needed.

```bash
# Summary view
./scripts/cw-status

# Full task list with IDs and status
./scripts/cw-status --list

# Only pending unblocked tasks
./scripts/cw-status --pending

# Only failed tasks
./scripts/cw-status --failed

# Raw JSON output (for scripting)
./scripts/cw-status --json

# Check a specific project
./scripts/cw-status /path/to/project
```

## cw-reset

Reset failed or stuck tasks. Operates directly on task files — no Claude invocation needed.

```bash
# Reset specific tasks by ID
./scripts/cw-reset T01 T03

# Reset all failed tasks
./scripts/cw-reset --all-failed

# Reset stuck in_progress tasks (likely abandoned)
./scripts/cw-reset --stuck
```
