# Shell Script Examples

Usage examples for all shell scripts (run from the terminal, unattended).

## cw-pipeline

Full end-to-end orchestrator. Goes from a prompt or spec to a pull request.

```bash
# Single feature from a prompt
./bin/cw-pipeline --prompt "Build JWT authentication" --name auth

# Single feature from an existing spec
./bin/cw-pipeline --spec docs/specs/01-spec-auth.md --name auth

# Skip optional stages
./bin/cw-pipeline --prompt "Add health check" --name health --no-test --no-review

# Auto-create PR without pausing for confirmation
./bin/cw-pipeline --prompt "Add billing API" --name billing --auto-pr

# Use a specific model
./bin/cw-pipeline --prompt "Build search" --name search -m opus

# Multiple features in parallel
./bin/cw-pipeline \
  --feature "auth:prompt:Build JWT authentication" \
  --feature "billing:spec:docs/specs/02-spec-billing.md"

# Run in current directory (no worktree)
./bin/cw-pipeline --prompt "Fix login bug" --name login-fix --no-worktree
```

Stages: worktree → spec → plan → execute → validate → review → test-init → test-loop → re-validate → PR.

## cw-init

Generate a spec and plan without executing. Useful for reviewing the plan before running `cw-loop`.

```bash
# From a prompt
./bin/cw-init --prompt "Build JWT authentication"

# From an existing spec (skips spec generation)
./bin/cw-init --spec docs/specs/01-spec-auth.md

# Auto-discover the most recent spec
./bin/cw-init

# With a specific model and verbose output
./bin/cw-init --prompt "Add user profiles" -m opus -v
```

## cw-loop

Autonomous execution loop. Picks up tasks and executes them until the board is complete.

```bash
# Default — quiet mode, sequential execution
./bin/cw-loop

# Stream output for visibility
./bin/cw-loop --verbose

# Parallel execution via cw-dispatch
./bin/cw-loop --dispatch

# Custom model and iteration limit
./bin/cw-loop -m opus -n 100

# Shorter sleep between iterations
./bin/cw-loop -s 2

# Point at a specific project directory
./bin/cw-loop /path/to/project

# Combine options
./bin/cw-loop -d -m opus -n 100 -v
```

## cw-loop-interactive

Human-in-the-loop execution. Pauses after each task for review.

```bash
./bin/cw-loop-interactive

# With a specific model
./bin/cw-loop-interactive -m opus
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
./bin/cw-test-init --spec docs/specs/01-spec-auth/01-spec-auth.md

# From a description
./bin/cw-test-init --prompt "Test JWT authentication flows"

# Auto-discover the most recent spec
./bin/cw-test-init

# With verbose output
./bin/cw-test-init --spec docs/specs/01-spec-auth.md -v
```

## cw-test-loop

Execute test tasks with auto-fix cycles. Runs tests, creates fix tasks for failures, executes fixes, then retests.

```bash
# Default — 3 fix cycles, 50 iterations per cycle
./bin/cw-test-loop

# More fix cycles for complex projects
./bin/cw-test-loop --max-cycles 5

# Custom iteration limit per cycle
./bin/cw-test-loop -n 100

# Point at a specific project
./bin/cw-test-loop /path/to/project

# Combine options
./bin/cw-test-loop -c 5 -n 100 -m opus -v
```

## cw-status

Check task progress. Reads task files directly — no Claude invocation needed.

```bash
# Summary view
./bin/cw-status

# Full task list with IDs and status
./bin/cw-status --list

# Only pending unblocked tasks
./bin/cw-status --pending

# Only failed tasks
./bin/cw-status --failed

# Raw JSON output (for scripting)
./bin/cw-status --json

# Check a specific project
./bin/cw-status /path/to/project
```

