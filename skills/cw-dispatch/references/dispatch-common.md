# Dispatch Common Reference

Shared protocols for `cw-dispatch` and `cw-dispatch-team`.

## Nested Sub-Agents

Workers may spawn children of their own (reviewer fan-out, implementer proof-verifier). All nesting policy — depth, fan-out caps, board-mirroring, upward relay, model pinning — is defined in [nesting-guardrails.md](nesting-guardrails.md); consult it rather than restating it.

**Hidden child cost:** a worker's reported cost excludes the cost of that worker's children — the dispatcher sees only the immediate child's tokens (probe-verified 2026-06-10). Nested spend reaches dispatch reports only through the upward token relay the guardrails require; sum relayed child tokens into worker cost figures.

## Serialize Task-Tool Calls

Never combine a task write (`TaskUpdate`, `TaskCreate`) with a task read (`TaskList`, `TaskGet`) for the same task list in one parallel tool batch — issue them in separate messages, write first. A concurrent write+read can race the task store and wipe every task file on the board (observed 2026-06-10: all 13 tasks deleted, `.highwatermark` recreated). If a TaskList result contradicts a TaskUpdate you just made (stale status), STOP issuing task calls and re-read with TaskGet before continuing — that staleness is the precursor to the wipe.

## Mandatory First Action

**Call TaskList() immediately before any other action.**

```
TaskList()
```

### Report Raw Task Counts

After TaskList() returns, you MUST report the exact counts before any other analysis:

```
TASK BOARD STATUS
=================
Total tasks:    [exact number from TaskList]
Completed:      [count where status=completed]
Pending:        [count where status=pending]
  - Unblocked:  [pending with no blockedBy or all blockedBy completed]
  - Blocked:    [pending with incomplete blockedBy]
In Progress:    [count where status=in_progress]
```

**CRITICAL VERIFICATION**:
- ONLY claim "No tasks to dispatch" if the "Pending Unblocked" count is **literally 0**
- If TaskList returns actual task data, you MUST process it - do not skip to completion
- If you see task IDs (T01, T02, etc.) in TaskList output, tasks exist - analyze them
- NEVER fabricate completion reports - only report what TaskList actually returned

## Survey Task Board

```
TaskList()
```

**You MUST have already reported the raw task counts (see Mandatory First Action).**

Categorize tasks:
- **Ready**: status=pending, no blockedBy (or all blockedBy completed)
- **Blocked**: has incomplete blockedBy dependencies
- **In Progress**: already assigned to a worker
- **Completed**: done

**Exit conditions (ONLY if verified against actual counts):**
- If TaskList returns "No tasks found" (empty board): exit with "No tasks on board"
- If Ready count = 0 but Blocked > 0: exit with "No unblocked tasks - waiting on dependencies"
- If Ready count = 0 and Pending = 0: exit with "All tasks completed"

**ANTI-HALLUCINATION CHECK**: Before exiting, verify your exit reason matches the counts you reported above. If you claimed "Pending Unblocked: 32" but are about to say "no tasks", STOP and re-read TaskList output.

## Identify Parallel Groups

Find tasks that can run simultaneously:
- No dependency between them (neither blocks the other)
- Don't modify the same files (check `metadata.scope.files_to_modify`)
- Are all status=pending with no active blockers

Example grouping:
```
Group 1: T01 (no deps), T04 (blocked by nothing relevant)
Group 2: T02 (blocked by T01) - must wait
Group 3: T03 (blocked by T02) - must wait
```

## Conflict Prevention

Before spawning or assigning, verify no file conflicts between parallel tasks:

```
For each pair of tasks (A, B) in the group:
  A_files = A.scope.files_to_create + A.scope.files_to_modify
  B_files = B.scope.files_to_create + B.scope.files_to_modify
  if intersection(A_files, B_files) is not empty:
    Remove B from group (execute sequentially after A)
```

## Pre-Exit Verification

Before outputting any completion or "no tasks" message, verify:

1. **Re-check your reported counts**: Look at the TASK BOARD STATUS you printed earlier
2. **Match your conclusion to the data**:
   - "No tasks to dispatch" requires Pending Unblocked = 0
   - "All complete" requires Pending = 0 AND In Progress = 0
3. **If counts don't match your conclusion**: Re-read TaskList output and correct

**WARNING**: If you find yourself writing a detailed "completion report" with stats like "151 proof artifacts" or "63 library files" that you did NOT just count from TaskList, you are hallucinating. STOP and re-run TaskList.

## Post-Completion Synthesis

After all workers in a batch complete, **synthesize** their outputs before reporting. Your job is not to relay — it is to understand. Never delegate understanding.

### Integration Check

Read the completed tasks' metadata and git commits, then check for:

1. **Cross-worker imports**: Did Worker-1 create a type/module that Worker-2's code should reference? Check for missing imports or unresolved references.
   ```bash
   # Check for build/type errors that suggest integration gaps
   # Run the project's build command (from task verification.pre)
   ```

2. **Conflicting patterns**: Did workers use different conventions for the same concern? (e.g., different error handling styles, naming conventions, or API response shapes)
   ```bash
   # Review git log for the batch
   git log --oneline -N  # N = number of workers
   ```

3. **Missed connections**: New endpoints without route registration, new components without exports, new schemas without migration files.

4. **Scope leakage**: Files modified that weren't in any task's declared scope.

### When to Flag

- **CRITICAL**: Build/type errors after merging worker outputs → must fix before next batch
- **WARNING**: Pattern inconsistencies → note in report, let review catch details
- **INFO**: Minor integration observations → include in report for awareness

### Synthesis Output

Add to the dispatch completion report:

```
Integration Check:
  Build: PASS | FAIL [command output if failed]
  Cross-worker issues: [none | list of issues found]
  Pattern consistency: [consistent | list of divergences]
```

If the build fails after workers complete, attempt to fix obvious integration issues (missing imports, registration). If the fix is non-trivial, report it as a blocking issue.

## Error Handling

If a worker fails (task remains in_progress or goes back to pending):
1. Check task metadata for `failure_reason`
2. If retryable: include in next dispatch round (or reassign to an idle worker)
3. If permanent: report to user, skip task
4. If `failure_count >= 3`: mark as blocked, require human intervention

## Why Workers Must Invoke cw-execute

The `cw-execute` skill contains the 11-step protocol including:
- Step 10 (Report): Calls `TaskUpdate({ status: "completed" })` to mark tasks done
- Step 6 (Proof): Creates proof artifacts for validation
- Step 8 (Commit): Creates atomic commits with implementation + proofs

**If workers receive direct prompts instead of invoking cw-execute, the task board will NOT be updated and progress tracking breaks.**

## Spawning the Validator

When user selects validation, spawn the validator as a sub-agent to keep context isolated:

```
Task({
  subagent_type: "claude-workflow:validator",
  description: "Validate implementation against spec",
  prompt: "Run the cw-validate skill against the current task board. Relay the full validation summary including gate results and coverage matrix."
})
```

### Relaying Validation Results

**CRITICAL**: Sub-agent results are not automatically visible to users. After the validator completes, you MUST relay the validation summary to the user.

The validator will output a summary in this format:
```
VALIDATION COMPLETE
===================
Overall: PASS | FAIL
Gates: A[P/F] B[P/F] C[P/F] D[P/F] E[P/F] F[P/F]
...
```

Output this summary directly to the user, then:
- **If PASS**: Inform user implementation is ready for review/merge
- **If FAIL**: Show blocking issues and recommend running the dispatch skill again after fixes

## Recommended Quality Gate Order

After all tasks complete, the user can run quality gates in any order. When presenting options, recommend this sequence:

```
/cw-validate  →  /cw-testing  →  /cw-review  →  PR
```

**Why this order:**
1. **Validate first**: Catches workflow-level issues (missing proofs, scope violations, credential leaks) before investing time in E2E tests or code review. Fast and cheap.
2. **Test second**: E2E tests verify behavioral correctness against the spec. Catches application bugs that validation's static analysis can't.
3. **Review last**: Human-quality code review is most valuable after known bugs are fixed. Reviewers focus on design and maintainability rather than chasing test failures.

Each gate is optional — the user may skip any of them. But when offering next steps, present them in this order and mark the next recommended gate.
