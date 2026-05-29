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

## Overview

You are the **Dispatcher** role in the Claude Workflow system. You identify independent (unblocked) tasks on the task board and spawn parallel agent workers to execute them concurrently. This is the parallelism layer that maximizes throughput.

## Your Role

You are a **Team Lead** who:
- Reads the task board to find actionable work
- Groups independent tasks for parallel execution
- Spawns workers and monitors completion
- Does NOT write code yourself

## Critical Constraints

- **NEVER** execute tasks yourself — always delegate to workers
- **NEVER** spawn workers for blocked tasks
- **NEVER** assign the same task to multiple workers
- **NEVER** give workers direct implementation instructions — they **MUST** invoke `cw-execute`
- **NEVER** use TodoWrite — use the native TaskList/TaskUpdate tools only
- **ALWAYS** set task ownership before spawning
- **ALWAYS** respect dependency ordering

### Why Workers Must Invoke cw-execute

See [dispatch-common.md](references/dispatch-common.md#why-workers-must-invoke-cw-execute) for details.

## MANDATORY FIRST ACTION

See [dispatch-common.md](references/dispatch-common.md#mandatory-first-action) for the TaskList() call, TASK BOARD STATUS template, and CRITICAL VERIFICATION bullets.

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

### Step 4: Spawn and Continuously Refill Workers

Fill the in-flight set up to the concurrency cap, then refill on demand — do **not** dispatch a fixed batch and wait for the slowest member.

- **Initial fill**: Send a **single message** with one Task tool call per ready task, up to the cap (N=3). Owning each task per Step 3 first.
- **Refill on every return**: The instant a worker returns (verified completion, error, or timeout), re-run `TaskList` and re-survey (Steps 1–2). If a conflict-free unblocked task exists, assign ownership (Step 3) and spawn it immediately to refill the freed slot. A fast worker never idles waiting for a slow one — only the file-scope conflict guard (see [Conflict Prevention](#conflict-prevention)) and the cap gate a spawn.
- **Drain trigger**: When the in-flight set drains to zero with no conflict-free unblocked task left to spawn, run the periodic synthesis sweep (Step 5) before looping or terminating.

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

Repeat for each worker with incrementing worker-N identifiers, both at initial fill and on each refill.

Spawned workers bypass the `invoke_claude` retry/timeout wrapper — bound, retry, and salvage each one per [Resilient Worker Invocation](#resilient-worker-invocation).

### Step 5: Synthesis Sweep and Report

The integration check is a **periodic synthesis sweep**, not a per-worker step. Trigger it when the in-flight set drains to zero (no worker running and no conflict-free unblocked task left to refill) — every freed slot otherwise feeds straight back into Step 4.

On a drain:

1. Run `TaskList` to check current state
2. Run post-completion synthesis — see [dispatch-common.md](references/dispatch-common.md#post-completion-synthesis) for integration checks across the workers that have completed since the last sweep
3. Report results, naming any degraded worker per [Resilient Worker Invocation](#resilient-worker-invocation):

```
CW-DISPATCH COMPLETE
=====================
Workers spawned: 3 (returned: 2)
  worker-1: T01 - [subject] -> COMPLETED
  worker-2: T04 - [subject] -> COMPLETED
  worker-3: T07 - [subject] -> TIMED-OUT (salvaged: task left pending for next round)

Integration Check:
  Build: PASS | FAIL
  Cross-worker issues: [none | list]
  Pattern consistency: [consistent | list]

Newly unblocked:
  T02 (was blocked by T01) -> now READY
  T05 (was blocked by T04) -> now READY

Progress: X/Y tasks complete
```

## Continuous Execution

This is dataflow scheduling, not barrier scheduling: a freed slot refills the instant its worker returns (Step 4), so no fast task waits on a slow one. The synthesis sweep (Step 5) fires only when the in-flight set drains. Re-survey (Steps 1–2) on every return and on every drain; continue until termination conditions fire (`Ready=0+Pending=0` or `Ready=0+Blocked>0`). These are the only stop conditions. Findings, build failures, worker errors, and scope discoveries go in the report — refill continues with whatever remains dispatchable. Never call AskUserQuestion mid-loop.

## Conflict Prevention

See [dispatch-common.md](references/dispatch-common.md#conflict-prevention) for the file conflict check algorithm.

## Concurrency Cap

- **Default**: Keep up to **N=3** workers in flight at once
- **Reason**: More than 3 parallel agents risk git conflicts and resource contention
- This is a *cap*, not a batch — you refill continuously (Step 4), never wait for a slowest batch-mate. The instant a worker returns, re-survey the board and spawn the next conflict-free unblocked task to refill the freed slot.

## Error Handling

See [dispatch-common.md](references/dispatch-common.md#error-handling) for failure handling rules.

## Resilient Worker Invocation

The `invoke_claude` retry/timeout/crash wrapper only guards top-level `claude -p`. In-session `Task(implementer)` workers bypass it — a worker that errors, hangs, or returns empty leaves its task `in_progress` with no salvage. Apply equivalent discipline to every worker you spawn:

- **Bound each worker.** If a worker does not return within its wait budget, treat it as timed-out — do not wait indefinitely. The orchestrator owns the clock; a stalled worker frees its slot for refill, it never stalls the in-flight set.
- **Retry transient failures once.** A worker that errors or times out (not one that ran and reported a task failure) may be re-spawned a single time for its task. Re-verify ownership first so you never double-assign.
- **Log every failure.** For each worker that errors, hangs, or returns empty, record `worker-N: T<id> <errored|timed-out|empty>` — never silently drop it.
- **Mark the unit unreliable.** A worker that did not return verified completion has NOT completed its task, regardless of any partial self-report. Trust the task board (its `cw-execute` TaskUpdate), not the worker's narration — the orchestrator is a control plane, the worker an untrusted data plane. Leave the task `pending`/`in_progress`; do not mark it `completed` on the worker's word.
- **Salvage and proceed.** After the retry, abstain on any task whose worker still did not return verified completion and refill the slot with the next conflict-free task — a single dead worker never blocks refill. Carry the loss into the completion report.

Account these losses with the funnel-accounting sub-protocol (see [funnel-accounting.md](../cw-research/references/funnel-accounting.md)): `spawned` = workers dispatched across the run, `returned` = workers that returned verified completion. Name every degraded worker (`worker-N: T<id> <errored|timed-out|empty>`) in the completion report's `Workers spawned` block — a thin run must never read as a full one.

## Pre-Exit Verification

See [dispatch-common.md](references/dispatch-common.md#pre-exit-verification) for the 3-step verification and hallucination warning.

## What Comes Next (after natural termination)

When the loop terminates, offer the next step via AskUserQuestion:

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
