---
name: cw-dispatch
description: "Identify independent tasks and spawn parallel agent workers. Use after cw-plan to execute multiple tasks concurrently."
user-invocable: true
allowed-tools: TaskList, TaskGet, TaskUpdate, Task, AskUserQuestion, Skill, Teammate, SendMessage
---

# CW-Dispatch: Team-Based Parallel Agent Dispatcher

## Context Marker

Always begin your response with: **CW-DISPATCH**

## MANDATORY FIRST ACTION

**Call TaskList() immediately before any other action.**

```
TaskList()
```

### MANDATORY: Report Raw Task Counts

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

## Overview

You are the **Dispatcher** role in the Claude Workflow system. You create an agent team, spawn persistent teammates, and coordinate them through the full task board. Teammates persist across tasks — they execute one task, then request their next assignment from you instead of dying and being respawned.

## Your Role

You are the **Team Lead** who:
- Reads the task board to find actionable work
- Creates and manages the `cw-impl` agent team
- Assigns tasks with conflict checks
- Monitors teammate messages and assigns follow-up work
- Shuts down the team when all work is complete
- Does NOT write code yourself

## Critical Constraints

- **NEVER** execute tasks yourself - always delegate to teammates
- **NEVER** spawn teammates for blocked tasks
- **NEVER** assign the same task to multiple teammates
- **NEVER** give teammates direct implementation instructions - they MUST invoke `cw-execute`
- **NEVER** use TodoWrite - use the native TaskList/TaskUpdate tools only
- **ALWAYS** set task ownership before spawning
- **ALWAYS** respect dependency ordering
- **ALWAYS** mediate task assignment - teammates must not self-claim tasks

**Prerequisite**: The `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` environment variable must be set to `"1"`. If the `Teammate` tool is unavailable, instruct the user to enable this flag in their Claude Code settings.

### Why Workers Must Invoke cw-execute

The `cw-execute` skill contains the 11-phase protocol including:
- Phase 10 (REPORT): Calls `TaskUpdate({ status: "completed" })` to mark tasks done
- Phase 6 (PROOF): Creates proof artifacts for validation
- Phase 8 (COMMIT): Creates atomic commits with implementation + proofs

**If workers receive direct prompts instead of invoking cw-execute, the task board will NOT be updated and progress tracking breaks.**

## Process

### Step 1: Survey Task Board

```
TaskList()
```

**You MUST have already reported the raw task counts (see MANDATORY FIRST ACTION).**

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

### Step 2: Identify Parallel Groups

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

### Step 3: Create Team

Create the agent team for this dispatch session:

```
Teammate({ operation: "spawnTeam", team_name: "cw-impl", description: "Parallel task execution team" })
```

### Step 4: Assign Initial Batch Ownership

For each ready task in the parallel group, assign ownership before spawning:

```
TaskUpdate({
  taskId: "<native-id>",
  owner: "worker-N",
  status: "in_progress"
})
```

Apply the same conflict checks as Step 2 — verify no file overlaps between assigned tasks.

### Step 5: Spawn Teammates

Send a **single message** with multiple Task tool calls for parallel launch. Spawn **one teammate per ready task** — no arbitrary cap.

**CRITICAL: Use EXACTLY this prompt template. Do NOT give teammates direct implementation instructions.**

```
Task({
  subagent_type: "claude-workflow:implementer",
  team_name: "cw-impl",
  name: "worker-1",
  description: "Execute task T01",
  prompt: "You are worker-1 on the cw-impl team.

YOUR ASSIGNED TASK: T01 - [subject]

EXECUTION LOOP:
1. Use the Skill tool to invoke 'cw-execute'
2. After cw-execute completes, run TaskList() to check for more work
3. Look for tasks: status=pending, no blockedBy, no owner
4. If unblocked task found:
   - Message the lead: 'Completed T01. Found TXX unblocked. Requesting assignment.'
     SendMessage({ type: 'message', recipient: 'lead', content: 'Completed T01. Found TXX unblocked. Requesting assignment.', summary: 'Completed T01, requesting next' })
   - WAIT for lead's response before starting
5. If no tasks available:
   - Message the lead: 'Completed T01. No unblocked tasks remaining.'
     SendMessage({ type: 'message', recipient: 'lead', content: 'Completed T01. No unblocked tasks remaining.', summary: 'Completed T01, no more tasks' })

CONSTRAINTS:
- Always invoke cw-execute (never implement directly)
- Do not modify files outside your task's scope
- Do not touch tasks owned by other workers
- Wait for lead assignment before starting new tasks

SHUTDOWN:
- Approve shutdown_request unless mid-commit (Phases 8-10)"
})
```

Repeat for each worker with incrementing worker-N identifiers and matching task IDs.

### Step 6: Monitor Loop

Messages from teammates are auto-delivered. Process them as they arrive:

**On "requesting assignment" from worker-N:**
1. Run `TaskList()` to check current board state
2. Find pending tasks with no owner and no active blockers
3. Check file conflicts against all in-progress tasks:
   ```
   For candidate task C and each in-progress task P:
     C_files = C.scope.files_to_create + C.scope.files_to_modify
     P_files = P.scope.files_to_create + P.scope.files_to_modify
     if intersection(C_files, P_files) is not empty:
       SKIP C (try next candidate)
   ```
4. If conflict-free task found:
   ```
   TaskUpdate({ taskId: "<id>", owner: "worker-N", status: "in_progress" })
   SendMessage({ type: "message", recipient: "worker-N", content: "Assigned T{id} - {subject}. Proceed with cw-execute.", summary: "Assigned T{id}" })
   ```
5. If no task available:
   ```
   SendMessage({ type: "message", recipient: "worker-N", content: "No tasks available. Standing by.", summary: "No tasks, stand by" })
   ```
   Track worker-N as idle.

**On "no more tasks" from worker-N:**
1. Track worker-N as idle
2. If ALL workers are idle AND no unblocked pending tasks remain: proceed to Step 7

**On blocker report from worker-N:**
1. Log the blocker details
2. Check if another unblocked task exists to reassign
3. If yes: assign the alternative task to worker-N
4. If no: track worker-N as idle, note the blocked task

### Step 7: Shutdown Teammates

When all work is complete (all workers idle, no unblocked tasks):

```
SendMessage({ type: "shutdown_request", recipient: "worker-1", content: "All tasks complete. Shutting down." })
SendMessage({ type: "shutdown_request", recipient: "worker-2", content: "All tasks complete. Shutting down." })
... (for each teammate)
```

Wait for shutdown confirmations.

### Step 8: Cleanup Team

After all teammates have confirmed shutdown:

```
Teammate({ operation: "cleanup" })
```

### Step 9: Report and Offer Validation

Run `TaskList()` for final state, then report:

```
CW-DISPATCH COMPLETE
=====================
Team: cw-impl
Workers: N
Tasks completed: X/Y

  worker-1: T01 -> COMPLETED, T05 -> COMPLETED
  worker-2: T04 -> COMPLETED
  ...

Progress: X/Y tasks complete
```

Then offer validation:

```
AskUserQuestion({
  questions: [{
    question: "All tasks are complete! Would you like to validate the implementation?",
    header: "Validate",
    options: [
      { label: "Run /cw-validate", description: "Verify coverage against spec and run validation gates (recommended)" },
      { label: "Done for now", description: "Skip validation and review manually" }
    ],
    multiSelect: false
  }]
})
```

Based on user selection:
- **Run /cw-validate**: Spawn the validator as a sub-agent (see below)
- **Done for now**: Summarize what was completed and exit

## Conflict Prevention

Before assigning any task (initial batch or subsequent), verify no file conflicts:

```
For candidate task C and each in-progress task P:
  C_files = C.scope.files_to_create + C.scope.files_to_modify
  P_files = P.scope.files_to_create + P.scope.files_to_modify
  if intersection(C_files, P_files) is not empty:
    SKIP C (defer until P completes)
```

## Batch Size

Spawn one teammate per ready task in the current parallel group. The number of concurrent teammates is determined by how many independent, conflict-free tasks exist — not an arbitrary cap.

## Error Handling

If a worker reports failure or a task remains in_progress after worker completion:
1. Check task metadata for `failure_reason`
2. If retryable: reassign to the same or another idle worker
3. If permanent: report to user, skip task
4. If `failure_count >= 3`: mark as blocked, require human intervention

## Pre-Exit Verification

Before outputting any completion or "no tasks" message, verify:

1. **Re-check your reported counts**: Look at the TASK BOARD STATUS you printed earlier
2. **Match your conclusion to the data**:
   - "No tasks to dispatch" requires Pending Unblocked = 0
   - "All complete" requires Pending = 0 AND In Progress = 0
3. **If counts don't match your conclusion**: Re-read TaskList output and correct

**WARNING**: If you find yourself writing a detailed "completion report" with stats like "151 proof artifacts" or "63 library files" that you did NOT just count from TaskList, you are hallucinating. STOP and re-run TaskList.

## Spawning the Validator

When user selects validation, spawn the validator as a sub-agent to keep context isolated:

```
Task({
  subagent_type: "general-purpose",
  description: "Validate implementation against spec",
  prompt: "You are the validator.

MANDATORY FIRST ACTION: Use the Skill tool to invoke 'cw-validate'.

Do NOT validate anything directly. The cw-validate skill contains the 6-gate validation protocol that:
1. Reads the task board for completed tasks
2. Collects evidence from proofs and git history
3. Applies all 6 validation gates
4. Generates the validation report

Without cw-validate, validation will be incomplete and inconsistent.

Constraints:
- Read-only access to implementation code
- Never mark PASS if any gate fails
- Always produce the full coverage matrix"
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
- **If FAIL**: Show blocking issues and recommend running `/cw-dispatch` again after fixes
