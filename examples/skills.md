# Skill Examples

Usage examples for all interactive skills (run inside Claude).

## /cw-spec

Generate a structured specification from a feature idea.

```
/cw-spec
> Describe your feature: "JWT authentication with refresh tokens"

/cw-spec auth                          # Short description, Claude fills in details
```

Output: `docs/specs/01-spec-auth/01-spec-auth.md` with demoable units, requirements, and proof artifacts.

**Tip: Use a meta-prompt to build a better spec prompt.** Vague prompts produce vague specs. Before running `/cw-spec`, ask Claude to help you research and refine your idea into a detailed prompt:

```
Help me create a prompt for /cw-spec to add Google authentication to my app.
Research the Google OAuth2 flow and look at my existing codebase to understand
what auth patterns are already in place.
```

Claude will explore your codebase, research the topic, and produce a detailed prompt that captures specific requirements, edge cases, and integration points. This research step turns a one-line idea into a rich input that gives `/cw-spec` much more to work with.

## /cw-plan

Transform a spec into a dependency-aware task graph.

```
/cw-plan                               # Auto-discovers most recent spec
/cw-plan docs/specs/01-spec-auth/01-spec-auth.md
```

Creates parent tasks (one per demoable unit), then generates sub-tasks with metadata after approval.

## /cw-execute

Execute a single task from the task board.

```
/cw-execute                            # Picks next available unblocked task
/cw-execute T03                        # Execute a specific task
```

Runs the 11-phase protocol: orient, baseline, context, implement, verify-local, proof, sanitize, commit, verify-full, report, clean exit.

## /cw-dispatch

Spawn parallel subagent workers for independent tasks.

```
/cw-dispatch                           # Finds and dispatches all unblocked tasks
```

Identifies independent tasks, spawns workers, monitors completion, then loops for newly unblocked tasks. No setup required.

## /cw-dispatch-team

Persistent agent team with lead coordination. Requires setup (see Prerequisites in README).

```
/cw-dispatch-team                      # Spawns a managed team for task execution
```

## /cw-validate

Validate the implementation against the spec.

```
/cw-validate                           # Runs all 6 validation gates
```

Checks proof artifacts, requirement coverage, file scope, credential safety, and produces a coverage matrix report with PASS/FAIL determination.

## /cw-review

Review implementation code for bugs, security, and quality issues.

```
/cw-review                             # Reviews all changes on the current branch
```

Creates `FIX-REVIEW` tasks for blocking issues found. Use after `/cw-validate` as a last quality gate before PR creation. Run `/cw-dispatch` after to execute fix tasks.

## /cw-testing

E2E testing with auto-fix. Generate tests, execute them, and auto-fix application bugs. You can use explicit subcommands or natural language — Claude parses the intent.

```
# Generate test scenarios
/cw-testing init                       # Auto-discovers spec
/cw-testing create test scenarios for the user registration journey
/cw-testing generate tests from the auth spec

# Execute tests
/cw-testing run                        # Run all pending tests with auto-fix
/cw-testing run the tests

# Check progress
/cw-testing status                     # Show test progress and results
/cw-testing show me which tests passed

# Reset for re-run
/cw-testing reset                      # Reset all tests
/cw-testing reset the failed tests     # Only reset failures
/cw-testing reset --step T04           # Reset a specific test
```

## /cw-worktree

Manage git worktrees for parallel feature development.

```
/cw-worktree create fix-login          # Create a fix worktree
/cw-worktree create auth billing       # Create multiple at once
/cw-worktree list                      # Show all worktrees and their status
/cw-worktree sync                      # Rebase current worktree on main
/cw-worktree cleanup                   # Remove merged/orphaned worktrees
```

The worktree directory name and task list ID are derived automatically from the slug you provide. The leading keyword determines the type (`fix`, `research`, `chore`, or `feature`), and the repo name is inserted automatically. For example, `/cw-worktree create fix-login` in a repo named `myrepo` creates `.claude/worktrees/fix-myrepo-login` on branch `fix/login`.

You can also describe what you want and let Claude figure out how many worktrees to create:

```
I want to make two different variants of a frontend change — one using a modal
dialog and one using an inline expandable panel. Set up worktrees so I can
develop both approaches side by side.
```

Claude will create the worktrees (e.g., `feature-myrepo-modal-dialog` and `feature-myrepo-inline-panel`), each with an isolated task list and feature branch. You can then open separate terminals to develop each variant independently and compare the results.

For a single fix, just name what you're fixing:

```
/cw-worktree create fix-checkout-redesign
```

Then open a new terminal in the worktree to start working:

```bash
cd .claude/worktrees/fix-myrepo-checkout-redesign && claude
/cw-spec → /cw-plan → /cw-dispatch → /cw-validate
gh pr create
```

> **Legacy worktrees:** Worktrees created before this naming scheme (e.g. `feature-checkout-redesign`) are fully supported — all commands are prefix-agnostic.

## /cw-loop

Design a bounded loop with an explicit exit condition, or audit an existing one. `cw-loop` does not run loops — it designs them and emits a runnable harness.

```
# Design a loop from a task description
/cw-loop design keep fixing lint until the linter is clean
/cw-loop design iterate on the summary until a separate judge scores it >= 4/5

# Audit an existing loop, prompt, or script against the exit-condition rubric
/cw-loop check ./scripts/retry-deploy.sh
/cw-loop check "keep refining the code until it looks correct"

# Fast path: wrap a single command in a bounded loop
/cw-loop wrap npm run build
```

The skill enforces the rules your loop needs to be safe: an **external, re-runnable check** (never "until it looks good"), a **hard cap**, a **no-progress stop**, and a **named terminal state** on exit (`success`, `clean-noop`, `blocked`, `needs-approval`, `exhausted`, `no-progress`). Output goes to `docs/loops/<slug>.md` plus an optional `<slug>.sh` harness.

`/cw-loop check` is useful as a lint pass on any "keep going until…" prompt before you trust it:

```
I have a prompt that tells an agent to "rewrite the function until the output
is good." Audit it.
> /cw-loop check "rewrite the function until the output is good"
```

Claude reports that the success condition is self-graded (RULE 1 FAIL — no external check), and proposes replacing it with an external signal such as "until `npm test -- fn.test.ts` exits 0," plus the missing cap and no-progress stop.

For running the harness afterward: drive per-iteration coding tasks with `/cw-execute`, use the built-in `/loop` for interval/self-paced cadence, or — if the loop *is* the whole spec pipeline — use `/cw-dispatch`, which already implements continuous execution with a hardened exit gate.
