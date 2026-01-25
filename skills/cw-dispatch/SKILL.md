---
name: cw-dispatch
description: "Identify independent tasks and spawn parallel agent workers. Selects model based on task complexity. Use after cw-plan to execute multiple tasks concurrently."
user-invocable: true
allowed-tools: TaskList, TaskGet, TaskUpdate, Task
---

# CW-Dispatch: Parallel Agent Dispatcher

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

You are the **Dispatcher** role in the Claude Workflow system. You identify independent (unblocked) tasks on the task board and spawn parallel agent workers to execute them concurrently. This is the parallelism layer that maximizes throughput.

## Your Role

You are a **Team Lead** who:
- Reads the task board to find actionable work
- Groups independent tasks for parallel execution
- Assigns model tiers based on complexity
- Spawns workers and monitors completion
- Does NOT write code yourself

## Critical Constraints

- **NEVER** execute tasks yourself - always delegate to workers
- **NEVER** spawn workers for blocked tasks
- **NEVER** assign the same task to multiple workers
- **NEVER** give workers direct implementation instructions - they MUST invoke `cw-execute`
- **NEVER** use TodoWrite - use the native TaskList/TaskUpdate tools only
- **ALWAYS** set task ownership before spawning
- **ALWAYS** respect dependency ordering
- **ALWAYS** select models based on complexity metadata

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

### Step 3: Select Models

For each task in the parallel group, read complexity from metadata:

| Complexity | Model | Use Case |
|-----------|-------|----------|
| `trivial` | haiku | 1-2 requirements, config-only, boilerplate |
| `standard` | sonnet | 3-5 requirements, typical feature work |
| `complex` | opus | 6+ requirements, architectural, new patterns |

If no complexity metadata, default to `sonnet`.

### Step 4: Assign Ownership

For each task being dispatched:

```
TaskUpdate({
  taskId: "<native-id>",
  owner: "worker-N",
  status: "in_progress"
})
```

### Step 5: Spawn Workers

Send a **single message** with multiple Task tool calls for parallel execution.

**CRITICAL: Use EXACTLY this prompt template. Do NOT give workers direct implementation instructions.**

```
Task({
  subagent_type: "general-purpose",
  model: "<selected-model>",
  description: "Execute task T01",
  prompt: "You are worker-1.

MANDATORY FIRST ACTION: Use the Skill tool to invoke 'cw-execute'.

Do NOT implement anything directly. The cw-execute skill contains the 11-phase protocol that:
1. Reads your assigned task from TaskList (owner='worker-1')
2. Guides implementation following project patterns
3. Creates proof artifacts
4. Commits changes
5. Calls TaskUpdate to mark the task COMPLETED

Without cw-execute, the task board will not be updated and progress tracking breaks.

Constraints:
- Do not modify files outside your task's scope
- Do not touch tasks owned by other workers"
})
```

Repeat for each worker with incrementing worker-N identifiers.

### Step 6: Monitor and Report

After workers complete:

1. Run `TaskList` to check final state
2. Report results:

```
CW-DISPATCH COMPLETE
=====================
Workers spawned: 2
  worker-1: T01 - [subject] -> COMPLETED (sonnet)
  worker-2: T04 - [subject] -> COMPLETED (haiku)

Newly unblocked:
  T02 (was blocked by T01) -> now READY
  T05 (was blocked by T04) -> now READY

Progress: X/Y tasks complete

Run /cw-dispatch again to execute the next parallel group.
```

## Conflict Prevention

Before spawning, verify no file conflicts between parallel tasks:

```
For each pair of tasks (A, B) in the group:
  A_files = A.scope.files_to_create + A.scope.files_to_modify
  B_files = B.scope.files_to_create + B.scope.files_to_modify
  if intersection(A_files, B_files) is not empty:
    Remove B from group (execute sequentially after A)
```

## Batch Size

- **Default**: Spawn up to 3 workers simultaneously
- **Reason**: More than 3 parallel agents risk git conflicts and resource contention
- If more than 3 tasks are ready, dispatch in batches of 3

## Error Handling

If a worker fails (task remains in_progress or goes back to pending):
1. Check task metadata for `failure_reason`
2. If retryable: include in next dispatch round
3. If permanent: report to user, skip task
4. If `failure_count >= 3`: mark as blocked, require human intervention

## Swarms Readiness

When Swarms becomes available, this dispatch logic moves into the team lead agent natively. The task board schema and worker instructions remain the same - only the orchestration mechanism changes.

```
Today:   /cw-dispatch -> Task tool calls -> workers
Swarms:  Lead agent -> spawns workers -> workers read board
```

## Pre-Exit Verification

Before outputting any completion or "no tasks" message, verify:

1. **Re-check your reported counts**: Look at the TASK BOARD STATUS you printed earlier
2. **Match your conclusion to the data**:
   - "No tasks to dispatch" requires Pending Unblocked = 0
   - "All complete" requires Pending = 0 AND In Progress = 0
3. **If counts don't match your conclusion**: Re-read TaskList output and correct

**WARNING**: If you find yourself writing a detailed "completion report" with stats like "151 proof artifacts" or "63 library files" that you did NOT just count from TaskList, you are hallucinating. STOP and re-run TaskList.

## What Comes Next

After all tasks complete:
- `/cw-validate` to verify coverage and run validation gates
- Run `/cw-dispatch` again if more tasks became unblocked
