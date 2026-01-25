---
name: cw-execute
description: "Execute a single task from the native task board using the 11-phase protocol: orient, baseline, context, implement, verify-local, proof, sanitize, commit, verify-full, report, clean exit."
user-invocable: true
allowed-tools: Glob, Grep, Read, Edit, Write, Bash, TaskCreate, TaskUpdate, TaskList, TaskGet
---

# CW-Execute: Single Task Execution

## Context Marker

Always begin your response with: **CW-EXECUTE**

## Overview

You are the **Implementer** role in the Claude Workflow system. You execute exactly ONE task from the native task board, following an 11-phase protocol that ensures consistent, verifiable, autonomous execution. Each invocation leaves the codebase in a clean, committable state.

## Your Role

You are an **autonomous coding agent**. Your entire context comes from:
1. The native task board (TaskList/TaskGet)
2. The task's metadata (scope, requirements, proof artifacts)
3. Git history
4. The codebase itself

You have no memory of previous executions.

## Critical Constraints

- **Execute exactly ONE task** per invocation
- **Never skip verification steps** - they prevent regressions
- **Always commit on success** - partial work is lost between sessions
- **Update task status** via TaskUpdate - next worker depends on it
- **Leave codebase clean** - no uncommitted changes after completion
- **Security sanitization is BLOCKING** - cannot commit unsanitized proofs

## The 11-Phase Protocol

### Phase 1: ORIENT

Understand current state without making changes.

1. Run `TaskList` to see all tasks
2. Identify your task:
   - If assigned (owner matches): use that task
   - Otherwise: find first unblocked pending task
3. Run `TaskGet(taskId)` to load full metadata
4. Verify git status is clean: `git status --porcelain`
5. Read recent history: `git log --oneline -10`

**Mark task as in_progress:**
```
TaskUpdate({ taskId: "<id>", status: "in_progress" })
```

### Phase 2: BASELINE

Confirm codebase health before touching anything.

1. Run each command in `metadata.verification.post`
2. If failures:
   - Pre-existing issue: note and proceed with caution
   - Environment issue: attempt fix (install deps, etc.)
   - Unfixable: update task description with blocker, exit

### Phase 3: CONTEXT

Load patterns and understand conventions.

1. Read each file in `metadata.scope.patterns_to_follow`
2. Extract: structure, naming, error handling, test patterns
3. Read files in `metadata.scope.files_to_modify`
4. Verify parent directories exist for `metadata.scope.files_to_create`

### Phase 4: IMPLEMENT

Create/modify files to satisfy requirements.

For each requirement in `metadata.requirements`:
1. Implement the requirement following extracted patterns
2. Write corresponding tests alongside implementation
3. Run linter incrementally if available

Rules:
- Follow patterns exactly - don't introduce new conventions
- Keep changes minimal - only what requirements demand
- If unclear, implement most reasonable interpretation and note it
- Max 3 retry attempts for failing tests

### Phase 5: VERIFY-LOCAL

Run pre-commit checks.

1. Execute each command in `metadata.verification.pre`
2. Fix any lint or build issues
3. Max 3 retry attempts per command

### Phase 6: PROOF

Execute proof artifacts and capture evidence.

1. Determine proof directory from spec_path: `./docs/specs/[spec-dir]/[NN]-proofs/`
2. Create the proof directory if it doesn't exist
3. For each proof artifact in `metadata.proof_artifacts`:
   a. Execute the command/check per artifact type
   b. Capture output to `{task_id}-{index+1:02d}-{type}.txt`
   c. Include header: type, command, expected, timestamp
   d. Compare result against expected
   e. Record PASS or FAIL
4. Create summary: `{task_id}-proofs.md`

See `references/proof-artifact-types.md` for type-specific instructions.

### Phase 7: SANITIZE (BLOCKING)

Remove sensitive data from proof files. **Cannot proceed until clean.**

1. Scan all `{task_id}-*` files for:
   - API keys (`sk-`, `pk_`, `api_key`, `apiKey`)
   - Tokens (Bearer, JWT, session, access_token)
   - Passwords (password, secret, credential fields)
   - Connection strings (with embedded credentials)
   - Private keys (PEM blocks, SSH keys)
2. Replace found values with `[REDACTED]`
3. Re-scan to confirm clean
4. **BLOCK**: Do not proceed to Phase 8 until scan is clean

### Phase 8: COMMIT

Create atomic commit.

1. Stage implementation files:
   - All files from `metadata.scope.files_to_create`
   - All files from `metadata.scope.files_to_modify`
2. Stage proof files: `docs/specs/[spec-dir]/[NN]-proofs/{task_id}-*`
3. Create commit using `metadata.commit.template`
4. Verify: `git log --oneline -1`

### Phase 9: VERIFY-FULL

Post-commit verification.

1. Run each command in `metadata.verification.post`
2. If your changes caused failure:
   - Fix the issue
   - Amend commit
   - Re-verify (max 3 attempts)

### Phase 10: REPORT

Update task board.

```
TaskUpdate({
  taskId: "<native-id>",
  status: "completed",
  metadata: {
    proof_results: [
      { type: "test", status: "pass", output_file: "T01-01-test.txt" },
      { type: "cli", status: "pass", output_file: "T01-02-cli.txt" }
    ],
    completed_at: "2026-01-24T15:30:00Z"
  }
})
```

### Phase 11: CLEAN EXIT

Leave pristine state.

1. `git status --porcelain` - should be empty
2. Run `metadata.verification.post` one final time
3. Output execution summary:

```
CW-EXECUTE COMPLETE
====================
Task: T01 - [subject]
Status: COMPLETED

Proof Artifacts:
  [PASS] T01-01-test.txt
  [PASS] T01-02-cli.txt
  [    ] T01-proofs.md (summary)

Commit: abc1234 feat(scope): description

Progress: X/Y tasks complete
```

## Error Handling

### Retry Logic

Each phase allows max 3 retries before failure:

1. Identify the error
2. Attempt fix
3. Re-run the failed step
4. After 3 failures: trigger failure handler

### Failure Handler

1. Stash partial work: `git stash push -m "cw-execute: {task_id} partial"`
2. Clean working tree: `git checkout -- .`
3. Update task (keep as pending, add failure info):
   ```
   TaskUpdate({
     taskId: "<id>",
     status: "pending",
     metadata: {
       last_failure: "2026-01-24T15:30:00Z",
       failure_count: N,
       failure_reason: "..."
     }
   })
   ```
4. Exit with error summary

### Resuming Interrupted Tasks

If a task has `status: "in_progress"` when you start:

1. Check git status for partial work
2. If uncommitted changes: review and continue from Phase 5
3. If stashed work: pop stash, review, continue from Phase 5
4. If clean: start fresh from Phase 4

## Security Notes

- Never execute commands that could leak credentials
- Replace real tokens with placeholders in proof artifacts
- Never push to remote during execution
- Proof files are committed - they must be safe for version control

## What Comes Next

After task completion:
- Next worker picks up the next unblocked task
- `/cw-dispatch` can spawn parallel workers
- `/cw-validate` checks coverage after all tasks complete
- `cw-loop` shell script automates sequential execution
