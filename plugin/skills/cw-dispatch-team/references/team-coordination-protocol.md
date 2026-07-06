# Team Coordination Protocol

Reference document for the `cw-dispatch` team-based parallel execution flow.

## Team Lifecycle

```
CREATE  →  SPAWN  →  MONITOR  →  SHUTDOWN  →  CLEANUP
```

1. **CREATE**: `Teammate({ operation: "spawnTeam", team_name: "{task-list-id}-team" })`
2. **SPAWN**: One `Task()` call per ready task, all in a single message for parallel launch
3. **MONITOR**: Lead receives auto-delivered messages, assigns new tasks, tracks idle workers
4. **SHUTDOWN**: `SendMessage({ type: "shutdown_request" })` to each teammate
5. **CLEANUP**: `Teammate({ operation: "cleanup" })`

## Task List Access

The **lead is the sole board writer.** Teammates run cw-execute with all Task tools stripped — they never read or write the task list. The lead holds the writer lease, dispatches each assignment fully inline in the spawn prompt, and harvests every teammate's `{task_id}.result.json` journal + RESULT BLOCK to apply completions itself, serially.

When Claude Code creates an agent team, it auto-sets `CLAUDE_CODE_TEAM_NAME` on teammates. When `CLAUDE_CODE_TASK_LIST_ID` is also set (in `.claude/settings.json` or `.claude/settings.local.json`), it **overrides** `CLAUDE_CODE_TEAM_NAME` for task routing, so the lead's board writes target the project's task list.

**Both coexist:**
- **`CLAUDE_CODE_TEAM_NAME`** (`{task-list-id}-team`): Used for messaging and coordination between agents
- **`CLAUDE_CODE_TASK_LIST_ID`**: Routes the lead's board writes to the project's task list

The team name is always `{CLAUDE_CODE_TASK_LIST_ID}-team` to ensure it never collides with the task list ID. This way, `TeamDelete` only cleans the unused team task directory (`~/.claude/tasks/{task-list-id}-team/`), not the project's tasks.

## Message Protocol

### Worker → Lead Messages

Workers hold no Task tools and never scan the board; they report completion by evidence and stand by for the next inline assignment.

**Task completed, standing by:**
```
"Completed T{id} ({subject}). RESULT BLOCK emitted + journal written. Standing by for next assignment."
```

**Blocker encountered:**
```
"BLOCKED on T{id}: {description of blocker}. Cannot proceed."
```

### Lead → Worker Messages

**Assignment** (carries the full inline metadata block — the worker cannot read the board):
```
"Assigned T{id} - {subject}. Proceed with cw-execute.

ASSIGNMENT (your sole source of task metadata — you hold no Task tools):
{full inline metadata — see the cw-dispatch Step 4 ASSIGNMENT block}"
```

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

When a worker reports "standing by":
1. Lead harvests the just-finished task's journal + RESULT BLOCK and applies its completion `TaskUpdate` (sole writer)
2. Lead runs `TaskList()` to get current state
3. Finds pending tasks with no owner and no active blockers
4. Checks file conflicts against all in-progress tasks
5. If conflict-free task found: `TaskUpdate({ taskId, owner: "worker-N", status: "in_progress" })`, then SendMessage the worker its **full inline assignment** (the metadata block, since the worker cannot read the board)
6. If no task found: messages worker to stand by, tracks as idle

### Conflict Check

```
For candidate task C and each in-progress task P:
  C_files = C.scope.files_to_create + C.scope.files_to_modify
  P_files = P.scope.files_to_create + P.scope.files_to_modify
  if intersection(C_files, P_files) is not empty:
    SKIP C (try next candidate)
```

## Teammate Spawn Prompt Template

The lead inlines the **complete** assignment (same metadata fields as the cw-dispatch spawn template: `task_id`, `requirements`, `scope`, `spec_path`, `proof_artifacts`, `proof_capture`, `verification.pre`/`post`, `commit_template`). The teammate holds no Task tools and has no board fallback, so the lead verifies the serialized assignment is complete before spawning.

```
You are worker-{N} on the {task-list-id}-team team.

YOUR ASSIGNED TASK: T{id} - {subject}

ASSIGNMENT (your sole source of task metadata — you hold no Task tools):
{full inline metadata — see the cw-dispatch Step 4 ASSIGNMENT block}

EXECUTION LOOP:
1. Use the Skill tool to invoke 'cw-execute'
2. After cw-execute completes, you have emitted your RESULT BLOCK + journal
3. Message the lead: "Completed T{id}. Standing by for next assignment."
4. Wait for the lead's next inline assignment or a shutdown_request — never scan the board

CONSTRAINTS:
- Always invoke cw-execute (never implement directly)
- Do not modify files outside task scope
- You hold no Task tools — orient from the inline assignment, hand off via journal + RESULT BLOCK
- Wait for the lead to assign each task inline before starting

SHUTDOWN:
- Approve shutdown_request unless mid-commit
```

## Multi-Task Loop (Worker Perspective)

```
while true:
  1. Invoke cw-execute (handles the assigned task end-to-end, emits journal + RESULT BLOCK)
  2. SendMessage to lead: "Completed T{done}. Standing by for next assignment."
  3. WAIT for the lead's response (never scan the board — you hold no Task tools):
       If lead sends a new inline assignment:
         continue loop (cw-execute orients from the inline assignment)
       If lead says "stand by":
         WAIT for further instructions or shutdown
       If shutdown_request:
         approve (unless mid-commit)
```

## Dispatcher Monitor Loop (Lead Perspective)

```
Messages from teammates are auto-delivered.

On "standing by" from worker-N:
  1. Harvest the finished task's journal + RESULT BLOCK; apply its completion TaskUpdate (sole writer)
  2. TaskList() to check current state
  3. Find unblocked pending tasks without owners
  4. Check file conflicts against in-progress tasks
  5. If conflict-free task found:
     - TaskUpdate({ taskId, owner: "worker-N", status: "in_progress" })
     - SendMessage to worker-N: "Assigned T{id}. Proceed." + the full inline ASSIGNMENT block
  6. If none available:
     - SendMessage to worker-N: "No tasks available. Standing by."
     - Track worker as idle; if all workers idle AND no unblocked tasks: proceed to Shutdown

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
   SendMessage({ type: "shutdown_request", recipient: "worker-N" })
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
