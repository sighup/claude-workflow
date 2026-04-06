---
name: cw-dispatch
description: "Identifies independent tasks and spawns parallel agent workers. This skill should be used after cw-plan to execute multiple tasks concurrently."
user-invocable: true
allowed-tools: TaskList, TaskGet, TaskUpdate, Task, AskUserQuestion, Skill
effort: medium
---

# CW-Dispatch: Parallel Agent Dispatcher

## Context Marker

Always begin your response with: **CW-DISPATCH**

## MANDATORY FIRST ACTION

See [dispatch-common.md](references/dispatch-common.md#mandatory-first-action) for the TaskList() call, TASK BOARD STATUS template, and CRITICAL VERIFICATION bullets.

## Overview

You are the **Dispatcher** role in the Claude Workflow system. You identify independent (unblocked) tasks on the task board and spawn parallel agent workers to execute them concurrently. This is the parallelism layer that maximizes throughput.

## Your Role

You are a **Team Lead** who:
- Reads the task board to find actionable work
- Groups independent tasks for parallel execution
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

### Why Workers Must Invoke cw-execute

See [dispatch-common.md](references/dispatch-common.md#why-workers-must-invoke-cw-execute) for details.

## Process

### Step 1: Survey Task Board

See [dispatch-common.md](references/dispatch-common.md#survey-task-board) for task categorization, exit conditions, and anti-hallucination check.

### Step 2: Identify Parallel Groups

See [dispatch-common.md](references/dispatch-common.md#identify-parallel-groups) for grouping logic and example.

### Step 3: Assign Ownership

For each task being dispatched:

```
TaskUpdate({
  taskId: "<native-id>",
  owner: "worker-N",
  status: "in_progress"
})
```

### Step 3b: Record Shared Baseline (once per dispatch round)

Before fanning out workers, run the project's verification commands **once** so every worker can skip its own redundant baseline run. Without this, N parallel workers each pay the full baseline cost on the same tree.

1. Pick any task in the dispatched group and read `metadata.verification.post`
2. Run each command. If any fails:
   - Stop and surface the failure to the user — the tree is not green and dispatch should not proceed
3. If all pass, record the result on every task being dispatched in this round:

```
HEAD_SHA=$(git rev-parse HEAD)
```

```
TaskUpdate({
  taskId: "<native-id>",
  metadata: {
    shared_baseline: {
      sha: "<HEAD_SHA>",
      status: "pass",
      verified_at: "<ISO timestamp>",
      verified_by: "dispatcher"
    }
  }
})
```

Workers will check `metadata.shared_baseline.sha` against the current HEAD in their Phase 2 (Baseline) and skip the redundant run if they match.

**Skip this step if** the dispatched group has only one task, or if `verification.post` is empty (greenfield/pre-bootstrap tasks).

### Step 4: Spawn Workers

Send a **single message** with multiple Task tool calls for parallel execution.

**Model Selection**: Read `metadata.model` from TaskGet for each task and pass it as the `model` parameter to Task(). If a task has no `metadata` at all, log a warning but proceed without a model override.

**CRITICAL: Use EXACTLY this prompt template. Do NOT give workers direct implementation instructions.**

```
Task({
  subagent_type: "claude-workflow:implementer",
  model: "sonnet",  // from task metadata: "haiku" | "sonnet" | "opus"
  description: "Execute task T01",
  prompt: "You are worker-1. Your assigned task is T01. Run cw-execute to implement it.

Constraints:
- Do not modify files outside your task's scope
- Do not touch tasks owned by other workers"
})
```

Repeat for each worker with incrementing worker-N identifiers.

### Step 5: Monitor and Report

After workers complete:

1. Run `TaskList` to check final state
2. Report results:

```
CW-DISPATCH COMPLETE
=====================
Workers spawned: 2
  worker-1: T01 - [subject] -> COMPLETED
  worker-2: T04 - [subject] -> COMPLETED

Newly unblocked:
  T02 (was blocked by T01) -> now READY
  T05 (was blocked by T04) -> now READY

Progress: X/Y tasks complete

Run /cw-dispatch again to execute the next parallel group.
```

## Conflict Prevention

See [dispatch-common.md](references/dispatch-common.md#conflict-prevention) for the file conflict check algorithm.

## Batch Size

- **Default**: Spawn up to 3 workers simultaneously
- **Reason**: More than 3 parallel agents risk git conflicts and resource contention
- If more than 3 tasks are ready, dispatch in batches of 3

## When to Prefer cw-dispatch-team

`cw-dispatch` is a barrier-style fan-out: each batch waits for **all** workers to finish before the next batch starts. This wastes parallelism whenever a batch contains tasks of uneven duration — fast workers sit idle until the slowest peer is done.

Prefer `cw-dispatch-team` (which uses a continuous monitor loop) when:
- The current batch mixes `complex` tasks with `standard`/`trivial` tasks (high duration variance)
- More than ~2 follow-on batches are queued behind the current one (the long pole compounds)
- The user has `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` enabled

`cw-dispatch` remains the right choice for: small task graphs, single-batch dispatches, or environments without team support.

## Error Handling

See [dispatch-common.md](references/dispatch-common.md#error-handling) for failure handling rules.

## Pre-Exit Verification

See [dispatch-common.md](references/dispatch-common.md#pre-exit-verification) for the 3-step verification and hallucination warning.

## What Comes Next

After workers complete, check if more tasks became unblocked:

1. **If newly unblocked tasks exist**: Automatically dispatch them (loop back to Step 1)
2. **If ALL tasks are complete**: Use AskUserQuestion to offer validation

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

### Spawning the Validator

See [dispatch-common.md](references/dispatch-common.md#spawning-the-validator) for the validator spawn template and result relay protocol.

When relaying FAIL results, recommend running `/cw-dispatch` again after fixes.
