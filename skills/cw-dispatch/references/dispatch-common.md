# Dispatch Common Reference

Shared protocols for `cw-dispatch` and `cw-dispatch-team`.

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

### Semantic Grouping (FIX-REVIEW tasks)

When the task board contains `FIX-REVIEW` tasks (from `cw-review` or `cw-review-team`), apply semantic grouping **before** conflict detection. FIX tasks from the same review are inherently coupled — they were found against a single code snapshot, and parallel fixes can produce inconsistent results even when they touch different files.

**Step 1: Group by shared file.** Tasks modifying the same file MUST be assigned to the same worker sequentially:

```
If T7.scope.files_to_modify ∩ T9.scope.files_to_modify ≠ ∅:
  → Same-file group: [T7, T9] — assign to one worker in sequence
```

**Step 2: Group by shared fix pattern.** Tasks fixing the same class of bug should use the same approach. Detect by comparing:
- `metadata.category` — same category (A, B, C)
- `subject` / `description` — similar root cause (e.g., multiple tasks about "wrong binary path", "missing validation")
- `suggested_fix` — similar fix strategy

```
If T8.subject contains "bin/cw-pipeline" AND T9.subject contains "bin/cw-* scripts":
  → Pattern group: [T8, T9] — same root cause, need consistent fix
```

**Step 3: Merge overlapping groups.** If T7 and T9 share a file, and T8 and T9 share a pattern, merge into one group: [T7, T8, T9].

**Step 4: Assign each group to one worker.** The worker executes them sequentially, carrying context from each fix into the next. Independent tasks (no file or pattern overlap) are dispatched in parallel as normal.

Example with FIX-REVIEW tasks:
```
Semantic Group A: T7 (pipeline.ts chdir), T9 (pipeline.ts bin paths), T8 (auto.ts bin paths)
  → Reason: T7+T9 share pipeline.ts, T8+T9 share "wrong binary path" pattern
  → Assign all to worker-1 sequentially

Semantic Group B: T4 (install.ts injection), T11 (install.ts bin path)
  → Reason: both modify install.ts
  → Assign all to worker-2 sequentially

Independent: T5 (lock.ts), T6 (history-store.ts), T10 (queue.ts + github.ts)
  → No overlaps — dispatch in parallel to worker-3, worker-4, worker-5
```

## Conflict Prevention

Before spawning or assigning, verify no file **or pattern** conflicts between parallel tasks.

### File Conflict Check

```
For each pair of tasks (A, B) in the group:
  A_files = A.scope.files_to_create + A.scope.files_to_modify
  B_files = B.scope.files_to_create + B.scope.files_to_modify
  if intersection(A_files, B_files) is not empty:
    Remove B from group (execute sequentially after A)
```

### Pattern Conflict Check

Even when files don't overlap, two tasks conflict if they fix the same class of bug and need a consistent approach. Check for:

1. **Same root cause**: Tasks whose descriptions reference the same underlying problem (e.g., "shells out to non-existent binary", "wrong binary path")
2. **Same fix strategy needed**: Tasks where the suggested fix involves choosing one of several approaches (e.g., "use process.argv" vs "call in-process") — these must agree
3. **Shared abstractions**: Tasks that both modify callers of the same function or both add imports from the same module

```
For each pair of tasks (A, B) in the group:
  if A.metadata.task_type == "review-fix" AND B.metadata.task_type == "review-fix":
    if similar_root_cause(A.description, B.description):
      Remove B from group (assign to same worker as A)
```

Pattern conflicts are judgment calls — when in doubt, serialize. The cost of unnecessary serialization is a slower dispatch. The cost of inconsistent parallel fixes is a broken codebase.

## Pre-Exit Verification

Before outputting any completion or "no tasks" message, verify:

1. **Re-check your reported counts**: Look at the TASK BOARD STATUS you printed earlier
2. **Match your conclusion to the data**:
   - "No tasks to dispatch" requires Pending Unblocked = 0
   - "All complete" requires Pending = 0 AND In Progress = 0
3. **If counts don't match your conclusion**: Re-read TaskList output and correct

**WARNING**: If you find yourself writing a detailed "completion report" with stats like "151 proof artifacts" or "63 library files" that you did NOT just count from TaskList, you are hallucinating. STOP and re-run TaskList.

## Error Handling

If a worker fails (task remains in_progress or goes back to pending):
1. Check task metadata for `failure_reason`
2. If retryable: include in next dispatch round (or reassign to an idle worker)
3. If permanent: report to user, skip task
4. If `failure_count >= 3`: mark as blocked, require human intervention

## Why Workers Must Invoke cw-execute

The `cw-execute` skill contains the 11-phase protocol including:
- Phase 10 (REPORT): Calls `TaskUpdate({ status: "completed" })` to mark tasks done
- Phase 6 (PROOF): Creates proof artifacts for validation
- Phase 8 (COMMIT): Creates atomic commits with implementation + proofs

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
