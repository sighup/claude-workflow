# Dispatch Common Reference

Shared protocols for `cw-dispatch` and `cw-dispatch-team`.

## Nested Sub-Agents

Workers may spawn children of their own (reviewer fan-out, implementer proof-verifier). All nesting policy — depth, fan-out caps, board-mirroring, upward relay, model pinning — is defined in [nesting-guardrails.md](nesting-guardrails.md); consult it rather than restating it.

## Serialize Task-Tool Calls

Never combine a task write (`TaskUpdate`, `TaskCreate`) with a task read (`TaskList`, `TaskGet`) for the same task list in one parallel tool batch — issue them in separate messages, write first. A concurrent write+read can race the task store and wipe every task file on the board. If a TaskList result contradicts a TaskUpdate you just made (stale status), STOP issuing task calls and re-read with TaskGet before continuing — that staleness is the precursor to the wipe.

## Single-Writer Discipline

The native task store wipes or drops task state when two or more processes sharing one `CLAUDE_CODE_TASK_LIST_ID` issue task-tool calls at overlapping times. The execute phase removes that trigger: **only the dispatcher (this orchestrator) ever issues task-tool writes.** Workers carry their assignment inline, hold no Task tools, and hand off through a committed implementation plus a per-task journal — `{task_id}.result.json` in the run's gitignored `docs/specs/<run>/results/` — and a `CW-RESULT-BLOCK` sentinel in their final message. You harvest that evidence and apply every `TaskUpdate` yourself, serially, under a cross-process writer lease.

Two rules make this safe:

- **Lease before any board write.** Hold the writer lease across the whole run so no second dispatcher, resumed session, or backstop guard writes concurrently.
- **Serial, never burst.** Apply one `TaskUpdate` per message, write a harvest-checkpoint line before each and read it back with `TaskGet` after each. A burst of reconcile writes is the proven wipe trigger.

### Writer Lease Lifecycle

The lease is `scripts/cw-lease.sh` — an atomic `mkdir`-based lease at `~/.claude/tasks/<list-id>.writer` holding `pid+host+heartbeat+phase`, reclaimable only once its heartbeat exceeds the TTL. `<list-id>` is `CLAUDE_CODE_TASK_LIST_ID`. Invoke it via `"$CLAUDE_PLUGIN_ROOT/scripts/cw-lease.sh"`.

1. **Export a stable owner id once, before acquiring**:
   ```bash
   export CW_LEASE_PID=$$
   ```
   The lease records ownership as `CW_LEASE_PID` + host. Exporting a stable value (your shell pid) lets a later `refresh`/`release` — even from a separate CLI invocation the orchestrator drives — still match the holder. Without it, each invocation defaults to its own `$$` and cannot refresh or release a lease an earlier invocation took.

2. **Acquire before the first board write** (Step 3 ownership writes), acquire-or-wait:
   ```bash
   "$CLAUDE_PLUGIN_ROOT/scripts/cw-lease.sh" acquire "$CLAUDE_CODE_TASK_LIST_ID" --phase dispatch
   ```
   `acquire` blocks until the lease is free or reclaimable, then takes it — it **never proceeds-with-warning**. Issue no `TaskUpdate`/`TaskCreate` until it returns success. A second dispatcher or resumed session waits here rather than racing you.

3. **Refresh each loop** (Step 5), so the heartbeat advances and the lease is never mistaken for stale while you still hold it:
   ```bash
   "$CLAUDE_PLUGIN_ROOT/scripts/cw-lease.sh" refresh "$CLAUDE_CODE_TASK_LIST_ID"
   ```
   `refresh` fails if you are not the holder — if it does, stop writing and re-check `status`; another writer holds the lease and your single-writer assumption is broken.

4. **Release at loop exit** — every termination path, including the early exits in [Survey Task Board](#survey-task-board):
   ```bash
   "$CLAUDE_PLUGIN_ROOT/scripts/cw-lease.sh" release "$CLAUDE_CODE_TASK_LIST_ID"
   ```
   Release is idempotent and owner-checked. A leaked live lease blocks the next writer until its TTL expires, so always release.

The slimmed backstop guard runs mirror/log-only while any writer lease is held, so guard and orchestrator are coordinated writers, never independent ones.

### Harvest-and-Apply

Workers never mark themselves done. After each batch joins, resolve each joined `task_id`'s outcome from durable evidence and apply the completion yourself. Run this for every task in the batch.

**1. Resolve the outcome by evidence order** (first hit wins):

1. **RESULT BLOCK** — scan the worker's final message from the first `CW-RESULT-BLOCK-START` line to the matching `CW-RESULT-BLOCK-END` and parse the enclosed JSON. Highest precedence. If it fails to parse, lacks required fields, or has `status != "completed"`, fall through.
2. **`{task_id}.result.json`** — read the journal from `docs/specs/<run>/results/{task_id}.result.json`. The block and journal carry identical fields; the journal is the fallback when the worker died before emitting a final message.
3. **Proof-dir scan by `task_id`** — when neither journal nor block exists, scan the proof dir for `{task_id}-*` artifacts and reconstruct `proof_results` (type + pass/fail + filename) from them plus the `{task_id}-proofs.md` summary. The `commit_sha` is then the worker's implementation commit found in `git log`.

A `task_id` with no RESULT BLOCK, no journal, and no proofs has **no completion evidence** — do not mark it completed. It is re-dispatched on a later loop (re-dispatch and dead-worker handling are covered separately under [Error Handling](#error-handling)).

**2. Verify the commit sha is reachable in git** (mandatory — the sha is the only commit-to-task link, since commits carry no metadata trailers):

```bash
git cat-file -e "${commit_sha}^{commit}" 2>/dev/null && \
  git merge-base --is-ancestor "$commit_sha" HEAD
```

The sha must both exist as a commit **and** be reachable from `HEAD` (not reverted, not from a stale prior run). If verification fails, **do not mark the task completed** — log the sha verification failure for that `task_id` and leave it for re-dispatch. A `result.json` carried over from a previous run referencing a vanished or unreachable sha is rejected here.

**3. Apply ONE `TaskUpdate` at a time** — never a batch. For each task whose evidence verified:

a. **Write a harvest-checkpoint line first.** Append the `task_id` to the run's harvest-checkpoint file under the results dir, before the board write:
   ```bash
   echo "$task_id" >> "docs/specs/<run>/results/harvest-checkpoint.log"
   ```
   A session interrupted mid-harvest reads this file on resume and skips already-applied `task_id`s, so a completion is never applied twice and the harvest is restartable. (The checkpoint records intent before the write; a read-back that shows the task already completed confirms the prior write landed.)

b. **Apply the single completion**, resolving the live native id for the `task_id` at write time (never cross-reference a cached native id — re-creation reassigns them):
   ```
   TaskUpdate({
     taskId: "<live native id for this task_id>",
     status: "completed",
     metadata: {
       proof_dir, proof_results, proof_summary,
       commit_sha, completed_at,
       verifier_verdict, verifier_tokens, verification_mode,
       model_used
     }
   })
   ```
   Populate `metadata` from the resolved evidence record (the RESULT BLOCK / journal fields).

c. **Read back with `TaskGet` after** — in a separate message, never batched with the write:
   ```
   TaskGet({ taskId: "<live native id>" })
   ```
   Confirm `status: "completed"`. If the read-back contradicts the write you just applied, the store dropped it (or you read a stale snapshot) — stop bursting, re-read, and re-apply that single write before moving to the next task. This per-task write→checkpoint→read-back cadence is what keeps the reconcile off the burst path that wipes the board.

Apply tasks one at a time through (a)–(c) before starting the next. A batch of completions issued together is exactly the multi-write burst this discipline exists to prevent.

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

### Skip-if-Evidence (Idempotent Re-Dispatch)

Before dispatching any task — at every loop top, before assigning ownership — check whether durable completion evidence already exists for it. A task with verified evidence is completed-by-evidence and must not be re-dispatched.

**Check order** (first hit wins):
1. `{task_id}.result.json` exists at `docs/specs/<run>/results/{task_id}.result.json` and its `commit_sha` passes the git reachability check (`git cat-file -e` + `git merge-base --is-ancestor … HEAD`).
2. The proof dir contains `{task_id}-proofs.md` and at least one `{task_id}-*.txt` artifact — reconstruct the sha from `git log` (the worker's implementation commit) and verify it as above.

If evidence is found:
- Apply the completing `TaskUpdate` (same serial write→checkpoint→read-back cadence as Harvest-and-Apply) using the evidence record to populate metadata.
- Log `task_id: completed-by-evidence` to the harvest-checkpoint file.
- Do not spawn a worker. Do not re-assign ownership.

This makes re-dispatch safe: a task that was completed in a prior run, or whose completion write was dropped by the board, is recovered from on-disk evidence rather than repeated.

### Dead-Worker Reset

A worker that has been in-progress past the liveness timeout with no commit or journal evidence is treated as dead and its task is reset for re-dispatch.

**Liveness timeout**: 30 minutes from the recorded dispatch timestamp (stored in the task's metadata as `dispatched_at` when ownership is assigned in Step 3b).

**Detection** — during each monitor poll (Step 5), for every in-progress task evaluate:
1. Time elapsed since `dispatched_at` exceeds the liveness timeout.
2. No `{task_id}.result.json` exists under the results dir.
3. No proof artifacts (`{task_id}-proofs.md`) exist in the proof dir.
4. No implementation commit for the task is reachable in git (checked via `git log --oneline -- <scope files>`).

All four conditions together confirm a dead worker. A task missing only some evidence is in-flight, not dead — never reset until all four apply.

**Reset** (sole writer, serial):
```bash
# Record intent before the board write
echo "${task_id}:dead-worker-reset:$(date -u +%s)" >> "docs/specs/<run>/results/harvest-checkpoint.log"
```
```
TaskUpdate({
  taskId: "<live native id>",
  status: "pending",
  metadata: { dead_worker_reset: true, reset_at: "<ISO timestamp>", prior_owner: "<worker-N>" }
})
```
Follow with a `TaskGet` read-back to confirm the reset landed. The task re-enters the pending pool and is dispatched on the next loop. The skip-if-evidence check at that loop's top makes the re-dispatch safe — if the worker actually did finish and only the evidence was not yet visible, the check will find it and apply completed-by-evidence instead of spawning a new worker.

**Worker failure (non-timeout)**:
If a worker fails with a `failure_reason` in its metadata (or a FAIL in its RESULT BLOCK) but is not yet past the timeout:
1. Check task metadata for `failure_reason`.
2. If retryable: include in next dispatch round.
3. If permanent: report to user, skip task.
4. If `failure_count >= 3`: mark as blocked, require human intervention.

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
