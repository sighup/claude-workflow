# Execution Protocol Reference

Detailed phase-by-phase instructions for the implementer worker.

## Phase 1: ORIENT

**Goal**: Understand current state without making changes.

1. Verify working directory matches project root
2. Run `TaskList` to see all tasks and their statuses
3. Identify your assigned task (by owner or next unblocked pending task)
4. Run `TaskGet(taskId)` to load full task metadata
5. Check git status - ensure clean working tree
6. Read recent git history (`git log --oneline -10`)

**Exit criteria**: You know which task to execute and the codebase is clean.

## Phase 2: BASELINE

**Goal**: Confirm the codebase is healthy before you touch it.

1. Run each command in `metadata.verification.post` (the full test suite)
2. If any fail:
   - Check if failure is pre-existing (not your fault)
   - If pre-existing: note in task description, proceed with caution
   - If environment issue: attempt fix (install deps, etc.)
   - If unfixable: mark task blocked, exit

**Exit criteria**: All verification.post commands pass (or failures are documented pre-existing).

## Phase 3: CONTEXT

**Goal**: Understand conventions before writing code.

1. Read each file in `metadata.scope.patterns_to_follow`
2. Extract:
   - File structure and organization
   - Naming conventions (variables, functions, files)
   - Error handling patterns
   - Test structure and assertion style
   - Import/export patterns
3. Read files in `metadata.scope.files_to_modify` to understand current state
4. Check if `metadata.scope.files_to_create` parent directories exist

**Exit criteria**: You understand the patterns and can write consistent code.

## Phase 4: IMPLEMENT

**Goal**: Create/modify files to satisfy all requirements.

For each requirement in `metadata.requirements`:

1. Identify which files need changes
2. Implement the requirement following extracted patterns
3. Write corresponding tests
4. Run linter incrementally if available

Rules:
- Follow patterns exactly - don't introduce new conventions
- Keep changes minimal - only what requirements demand
- Write tests alongside implementation, not after
- If a requirement is unclear, implement the most reasonable interpretation and note it

**Exit criteria**: All requirements have corresponding implementation and tests.

## Phase 5: VERIFY-LOCAL

**Goal**: Confirm your changes don't break anything locally.

1. Run each command in `metadata.verification.pre` (typically lint + build)
2. If lint fails: fix issues and re-run
3. If build fails: fix compilation errors and re-run
4. Max 3 retry attempts per command

**Exit criteria**: All verification.pre commands pass.

## Phase 6: PROOF

**Goal**: Execute proof artifacts and capture evidence.

1. Create proof directory: `./docs/specs/[spec-dir]/[NN]-proofs/`
2. For each item in `metadata.proof_artifacts`:
   a. Execute the command/check
   b. Capture output to `{task_id}-{index+1:02d}-{type}.txt`
   c. Compare result against `expected`
   d. Record PASS or FAIL
3. Create summary file `{task_id}-proofs.md`

See `references/proof-artifact-types.md` for type-specific guidance.

**Exit criteria**: All proof artifacts collected, all PASS.

## Phase 7: SANITIZE

**Goal**: Remove sensitive data from proof artifacts. THIS IS BLOCKING.

1. Scan all proof files for patterns:
   - API keys (strings matching `sk-`, `pk_`, `api_key`, etc.)
   - Tokens (Bearer tokens, JWT tokens, session tokens)
   - Passwords (any field named password, secret, credential)
   - Connection strings (database URLs with credentials)
   - Private keys (PEM blocks, SSH keys)
2. Replace found values with `[REDACTED]`
3. Re-scan to confirm sanitization complete

**Exit criteria**: No sensitive data in any proof file. CANNOT proceed until clean.

## Phase 8: COMMIT

**Goal**: Create atomic commit with implementation + proofs.

1. Stage implementation files (from `metadata.scope.files_to_create` + `files_to_modify`)
2. Stage proof artifact files
3. Create commit using `metadata.commit.template`
4. Verify commit exists: `git log --oneline -1`

**Exit criteria**: Commit created with all implementation and proof files.

## Phase 9: VERIFY-FULL

**Goal**: Confirm nothing broke after commit.

1. Run each command in `metadata.verification.post` (full test suite)
2. If failures:
   - If your changes caused it: fix, amend commit, re-verify
   - If pre-existing: document in proof_results
   - Max 3 fix attempts

**Exit criteria**: All verification.post commands pass.

## Phase 10: REPORT

**Goal**: Update task board with results.

1. Construct proof_results:
   ```json
   [
     { "type": "test", "status": "pass", "output_file": "T01-01-test.txt" },
     { "type": "cli", "status": "pass", "output_file": "T01-02-cli.txt" }
   ]
   ```
2. Update task:
   ```
   TaskUpdate({
     taskId: "<native-id>",
     status: "completed",
     metadata: {
       proof_results: [...],
       completed_at: "<ISO timestamp>"
     }
   })
   ```

**Exit criteria**: Task marked completed with proof results in metadata.

## Phase 11: CLEAN EXIT

**Goal**: Leave codebase in pristine state for next worker.

1. Run `git status --porcelain` - should be empty
2. If uncommitted changes exist: stash or commit as appropriate
3. Run final test: `metadata.verification.post`
4. Output execution summary

**Exit criteria**: Clean git status, all tests pass, summary output.

## Error Recovery

### Retry Logic (Max 3 per phase)

```
attempt = 0
while attempt < 3:
  result = execute_phase()
  if result.success:
    break
  attempt += 1
  fix_issue(result.error)

if attempt >= 3:
  handle_failure()
```

### Failure Handling

1. `git stash push -m "cw-execute: {task_id} partial work"`
2. `git checkout -- .` (clean working tree)
3. Update task:
   ```
   TaskUpdate({
     taskId: "<native-id>",
     status: "pending",
     metadata: {
       proof_results: [{ status: "failed", error: "..." }],
       last_failure: "<ISO timestamp>",
       failure_count: N
     }
   })
   ```
4. Exit with error summary
