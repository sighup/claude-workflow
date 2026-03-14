# Team Coordination Protocol

Reference document for the `cw-dispatch` team-based parallel execution flow.

## Team Lifecycle

```
CREATE  →  SPAWN  →  MONITOR  →  SHUTDOWN  →  CLEANUP
```

1. **CREATE**: `Teammate({ operation: "spawnTeam", team_name: "{task-list-id}-team" })`
2. **SPAWN**: One `Task()` call per ready task, all in a single message for parallel launch
3. **MONITOR**: Lead receives auto-delivered messages, assigns new tasks, tracks idle workers
4. **SHUTDOWN**: `SendMessage({ to: "worker-N", message: { type: "shutdown_request" }, summary: "..." })` to each teammate
5. **CLEANUP**: `Teammate({ operation: "cleanup" })`

## Task List Access

When Claude Code creates an agent team, it auto-sets `CLAUDE_CODE_TEAM_NAME` on teammates. By default, this routes their `TaskList`/`TaskUpdate` calls to `~/.claude/tasks/{CLAUDE_CODE_TEAM_NAME}/` — the team's built-in task list.

However, when `CLAUDE_CODE_TASK_LIST_ID` is also set (in `.claude/settings.json` or `.claude/settings.local.json`), it **overrides** `CLAUDE_CODE_TEAM_NAME` for task routing. All agents (lead + teammates) then use the same project task list.

**Both must coexist:**
- **`CLAUDE_CODE_TEAM_NAME`** (`{task-list-id}-team`): Used for messaging and coordination between agents
- **`CLAUDE_CODE_TASK_LIST_ID`**: Overrides task routing so all agents share the project's task list

The team name is always `{CLAUDE_CODE_TASK_LIST_ID}-team` to ensure it never collides with the task list ID. This way, `TeamDelete` only cleans the unused team task directory (`~/.claude/tasks/{task-list-id}-team/`), not the project's tasks.

## Message Protocol

### Worker → Lead Messages

**Task completed, requesting next assignment:**
```
"Completed T{id} ({subject}). Found T{next_id} unblocked. Requesting assignment."
```

**Task completed, no more work:**
```
"Completed T{id} ({subject}). No unblocked tasks remaining."
```

**Blocker encountered:**
```
"BLOCKED on T{id}: {description of blocker}. Cannot proceed."
```

### Lead → Worker Messages

**Assignment (unrelated to prior task):**
```
"Assigned T{id} - {subject}. Proceed with cw-execute."
```

**Assignment with context (related to prior task):**
```
"Assigned T{id} - {subject}. Proceed with cw-execute.

CONTEXT FROM PRIOR TASK: You just completed T{prev_id} which [brief description of what was done and the approach used]. Use the same pattern for consistency."
```

Use the context form when the new task shares a file, fix pattern, or root cause with the worker's prior task. This prevents inconsistent approaches across related fixes.

**Stand by (no work available):**
```
"No tasks available. Standing by for shutdown."
```

## Task Assignment Protocol

All task assignment is **lead-mediated**. Workers never self-claim tasks.

### Initial Assignment (Step 4)

Before spawning teammates, the lead:
1. Identifies all ready (pending, unblocked) tasks
2. Checks file conflicts between them (see Conflict Check below)
3. Assigns ownership via `TaskUpdate({ taskId, owner: "worker-N", status: "in_progress" })`
4. Spawns one teammate per assigned task

### Subsequent Assignment (Monitor Loop)

When a worker requests a new task:
1. Lead runs `TaskList()` to get current state
2. Finds pending tasks with no owner and no active blockers
3. **Prefers tasks unblocked by the worker's completed task** — keeps related work (especially chained FIX-REVIEW tasks) on the same worker for consistency
4. Checks file conflicts against all in-progress tasks
5. If conflict-free task found: assigns via `TaskUpdate` and messages worker, **with context from prior work** if the tasks are related (see message templates above)
6. If no task found: messages worker to stand by, tracks as idle

### Conflict Check

```
For candidate task C and each in-progress task P:
  C_files = C.scope.files_to_create + C.scope.files_to_modify
  P_files = P.scope.files_to_create + P.scope.files_to_modify
  if intersection(C_files, P_files) is not empty:
    SKIP C (try next candidate)
```

**Note:** FIX-REVIEW tasks from `cw-review-team` should already have `blockedBy` dependencies that prevent file and pattern conflicts. The file conflict check above is a safety net.

## Teammate Spawn Prompt Template

```
You are worker-{N} on the {task-list-id}-team team.

YOUR ASSIGNED TASK: T{id} - {subject}

EXECUTION LOOP:
1. Use the Skill tool to invoke 'cw-execute'
2. After cw-execute completes, run TaskList() to check for more work
3. Look for tasks: status=pending, no blockedBy, no owner
4. If unblocked task found:
   - Message the lead: "Completed T{id}. Found T{next} unblocked. Requesting assignment."
   - Wait for lead's response before starting
5. If no tasks available:
   - Message the lead: "Completed T{id}. No unblocked tasks remaining."

CONSTRAINTS:
- Always invoke cw-execute (never implement directly)
- Do not modify files outside task scope
- Do not touch tasks owned by other workers
- Wait for lead assignment before starting new tasks

SHUTDOWN:
- Approve shutdown_request unless mid-commit
```

## Multi-Task Loop (Worker Perspective)

```
while true:
  1. Invoke cw-execute (handles the assigned task end-to-end)
  2. TaskList() to scan for unblocked pending tasks
  3. If unblocked task exists:
       SendMessage({ to: "lead", message: "Completed T{done}. Found T{next} unblocked. Requesting assignment.", summary: "Completed T{done}, requesting next" })
       WAIT for lead response
       If lead assigns T{next}:
         continue loop (cw-execute will pick up the new owned task)
       If lead says "stand by":
         WAIT for further instructions or shutdown
  4. If no unblocked task:
       SendMessage({ to: "lead", message: "Completed T{done}. No unblocked tasks remaining.", summary: "Completed T{done}, no more tasks" })
       WAIT for shutdown
```

## Dispatcher Monitor Loop (Lead Perspective)

```
Messages from teammates are auto-delivered.

On "requesting assignment" from worker-N:
  1. TaskList() to check current state
  2. Find unblocked pending tasks without owners
  3. Prefer tasks unblocked by worker's completed task (keeps chains on same worker)
  4. Check file conflicts against in-progress tasks
  5. If conflict-free task found:
     - TaskUpdate({ taskId, owner: "worker-N", status: "in_progress" })
     - If related to worker's prior task:
       SendMessage({ to: "worker-N", message: "Assigned T{id}. Proceed.\n\nCONTEXT: T{prev} used [approach]. Use same pattern.", summary: "Assigned T{id} with context" })
     - If unrelated:
       SendMessage({ to: "worker-N", message: "Assigned T{id}. Proceed.", summary: "Assigned T{id}" })
  6. If none available:
     - SendMessage({ to: "worker-N", message: "No tasks available. Standing by.", summary: "No tasks, stand by" })
     - Track worker as idle

On "no more tasks" from worker-N:
  1. Track worker as idle
  2. If all workers idle AND no unblocked tasks: proceed to Shutdown

On blocker report from worker-N:
  1. Log the blocker
  2. Check if another unblocked task exists to reassign
  3. If yes: assign the alternative task
  4. If no: track worker as idle, note the blocked task
```

## Shutdown Flow

```
1. All workers idle AND no unblocked tasks remaining
2. For each worker:
   SendMessage({ to: "worker-N", message: { type: "shutdown_request" }, summary: "All tasks complete. Shutting down." })
3. Workers approve shutdown (unless mid-commit)
4. After all workers confirmed:
   Teammate({ operation: "cleanup" })
5. Proceed to validation offer
```

## Error Escalation

| Situation | Worker Action | Lead Action |
|-----------|--------------|-------------|
| cw-execute fails | Message lead with error details | Check task metadata, reassign or mark blocked |
| Task remains in_progress after worker reports done | N/A | Re-check TaskList, may need manual intervention |
| Worker unresponsive | N/A | After timeout, reclaim task ownership, reassign |
| File conflict detected at assignment | N/A | Skip conflicting task, try next candidate |
| `failure_count >= 3` on a task | Report to lead | Mark task as blocked, inform user |
