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
- **YOU are the single writer.** Workers hold no Task tools — every board mutation in the run (ownership + completion) is yours. Hold the writer lease while writing and apply each write serially. See [dispatch-common.md](references/dispatch-common.md#single-writer-discipline).

### Why Workers Must Invoke cw-execute

See [dispatch-common.md](references/dispatch-common.md#why-workers-must-invoke-cw-execute) for details.

## MANDATORY FIRST ACTION

See [dispatch-common.md](references/dispatch-common.md#mandatory-first-action) for the TaskList() call, TASK BOARD STATUS template, and CRITICAL VERIFICATION bullets.

## Process

### Step 1: Survey Task Board

See [dispatch-common.md](references/dispatch-common.md#survey-task-board) for task categorization, exit conditions, and anti-hallucination check. Every candidate exit routes through the [Manifest-Authoritative Exit Gate](references/dispatch-common.md#manifest-authoritative-exit-gate): the dispatcher never exits on board counts alone — an empty/thin board while the manifest holds uncompleted `task_id`s is a wipe signal that triggers reconcile, never exit.

### Step 2: Identify Parallel Groups

See [dispatch-common.md](references/dispatch-common.md#identify-parallel-groups) for grouping logic and example.

### Step 3: Acquire the Writer Lease

You are the run's single writer. **Before your first board write** (the ownership writes in Step 3b), acquire the cross-process writer lease so no second dispatcher, resumed session, or guard write fights you. Acquire-or-wait — never proceed without it. Full lifecycle (stable `CW_LEASE_PID`, per-loop refresh, release at exit): [dispatch-common.md](references/dispatch-common.md#writer-lease-lifecycle).

```bash
export CW_LEASE_PID=$$   # stable owner id reused by refresh/release across invocations
"$CLAUDE_PLUGIN_ROOT/scripts/cw-lease.sh" acquire "$CLAUDE_CODE_TASK_LIST_ID" --phase dispatch
```

`acquire` blocks until the lease is free or reclaimable. Do not issue any `TaskUpdate`/`TaskCreate` until it returns success.

### Step 3b: Assign Ownership

Lease held. For each task being dispatched, apply the ownership write **serially** (one `TaskUpdate` per message, never batched with a read):

```
TaskUpdate({
  taskId: "<native-id>",
  owner: "worker-N",
  status: "in_progress",
  metadata: { dispatched_at: "<ISO timestamp>" }
})
```

The `dispatched_at` timestamp is the reference point for the dead-worker liveness timeout (Step 5, dead-worker check).

### Step 4: Spawn Workers

**Before spawning, check for existing evidence.** For each ready task, run the skip-if-evidence check: if a sha-verified `{task_id}.result.json` or proof dir already exists, apply completed-by-evidence (serial write→checkpoint→read-back) and do not spawn a worker for it. Full protocol: [dispatch-common.md](references/dispatch-common.md#skip-if-evidence-idempotent-re-dispatch).

Send a **single message** with multiple Task tool calls for parallel execution.

**Model Selection**: Read `metadata.model` from TaskGet for each task and pass it as the `model` parameter to Task(). If a task has no `metadata` at all, log a warning but proceed without a model override.

**Workers hold no Task tools** — they cannot read the board. `TaskGet` the task once here and inline its **complete** assignment into the spawn prompt: `task_id`, `requirements`, `scope` (`files_to_create`, `files_to_modify`, `patterns_to_follow`), `proof_artifacts`, `proof_capture`, `spec_path`, `commit.template`, and `verification.pre`/`verification.post`. A worker with stripped tools has no board fallback, so an incomplete prompt cannot be recovered — verify the serialized assignment is complete before spawning.

**CRITICAL: Use EXACTLY this prompt shape. Do NOT give workers direct implementation instructions — inline the task metadata only.**

```
Task({
  subagent_type: "claude-workflow:implementer",
  model: "sonnet",  // from task metadata: "haiku" | "sonnet" | "opus"
  description: "Execute task T01",
  prompt: "You are worker-1. Your assigned task is T01. Run cw-execute to implement it.

ASSIGNMENT (your sole source of task metadata — you hold no Task tools):
task_id: T01
requirements:
  - <requirement 1>
  - <requirement 2>
scope:
  files_to_create: [<path>, ...]
  files_to_modify: [<path>, ...]
  patterns_to_follow: [<path>, ...]
spec_path: docs/specs/<run>/
proof_artifacts: [<type/command/expected per artifact>, ...]
proof_capture: { visual_method: <auto|manual|skip>, tool: <tool> }
verification:
  pre:  [<command>, ...]
  post: [<command>, ...]
commit_template: \"<type(scope): subject>\"

Constraints:
- Do not modify files outside your task's scope
- Do not touch tasks owned by other workers
- You hold no Task tools — orient from this assignment, hand off via journal + RESULT BLOCK"
})
```

Repeat for each worker with incrementing worker-N identifiers, inlining that task's own metadata.

### Step 4.5: Harvest and Apply

Workers hold no Task tools — they never mark themselves done. **After each batch joins, you harvest their durable evidence and apply every completion yourself.** For each joined worker's `task_id`, resolve its outcome by evidence order (RESULT BLOCK → `{task_id}.result.json` → proof-dir scan by `task_id`), verify the journal's `commit_sha` is reachable in git, then apply **one** `TaskUpdate(completed)` at a time — writing a harvest-checkpoint line **before** each and doing a `TaskGet` read-back **after** each. Never a burst. Full protocol: [dispatch-common.md](references/dispatch-common.md#harvest-and-apply).

### Step 5: Refresh, Monitor, and Report

1. **Refresh the lease**: `"$CLAUDE_PLUGIN_ROOT/scripts/cw-lease.sh" refresh "$CLAUDE_CODE_TASK_LIST_ID"` so the heartbeat advances each loop (a stale lease becomes reclaimable by another writer)
2. Run `TaskList` to check final state — the completions you applied in Step 4.5 are the board's source of truth, not any worker self-report
3. **Progress heartbeat**: for each in-progress task whose worker produced a new journal/proof artifact since the last poll, apply a metadata-only progress heartbeat (`progress: <stage>`, **no status change**) — sole-writer, serial, idempotent. Status transitions stay exclusively in Step 4.5 harvest. Full protocol: [dispatch-common.md](references/dispatch-common.md#progress-heartbeat).
4. **Dead-worker check**: for each in-progress task, evaluate the four liveness conditions. Reset and re-queue any confirmed dead worker. Full protocol: [dispatch-common.md](references/dispatch-common.md#dead-worker-reset).
5. Run post-completion synthesis — see [dispatch-common.md](references/dispatch-common.md#post-completion-synthesis) for integration checks
6. Report results:

```
CW-DISPATCH COMPLETE
=====================
Workers spawned: 2
  worker-1: T01 - [subject] -> COMPLETED
  worker-2: T04 - [subject] -> COMPLETED

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

Loop Step 1 → Step 5 → Step 1 until termination conditions fire (`Ready=0+Pending=0` or `Ready=0+Blocked>0`). These conditions are **candidate** stops only — each must clear the [Manifest-Authoritative Exit Gate](references/dispatch-common.md#manifest-authoritative-exit-gate) before the loop actually terminates. With a manifest present, exit requires journal/proof evidence for **every** manifest `task_id`; an empty/thin board with uncompleted manifest `task_id`s is a wipe → reconcile and keep looping, never exit. Absent-manifest (legacy) runs fall back to the count-based conditions after the one-time synth-manifest-from-board step, reported as reduced coverage. Findings, build failures, worker errors, and scope discoveries go in the report — the loop continues with whatever remains dispatchable. Never call AskUserQuestion mid-loop.

**Lease across the loop**: acquire once (Step 3, before the first ownership write), refresh every loop (Step 5.1), and **release at loop exit** so the next phase or dispatcher can take it:

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/cw-lease.sh" release "$CLAUDE_CODE_TASK_LIST_ID"
```

Release is idempotent and owner-checked (it uses the same `CW_LEASE_PID` you exported in Step 3). Release whenever the loop terminates — including the early-exit conditions in [dispatch-common.md](references/dispatch-common.md#survey-task-board). Never leave a held lease behind; a leaked live lease blocks the next writer until its TTL expires.

## Conflict Prevention

See [dispatch-common.md](references/dispatch-common.md#conflict-prevention) for the file conflict check algorithm.

## Batch Size

- **Default**: Spawn up to 3 workers simultaneously
- **Reason**: More than 3 parallel agents risk git conflicts and resource contention
- If more than 3 tasks are ready, dispatch in batches of 3

## Error Handling

See [dispatch-common.md](references/dispatch-common.md#error-handling) for failure handling rules.

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
