---
name: cw-plan
description: "Transforms a specification into a task graph with dependencies. This skill should be used after cw-spec to break a spec into executable tasks with proper sequencing before dispatching with cw-dispatch."
user-invocable: true
allowed-tools: Glob, Grep, Read, Write, Bash, TaskCreate, TaskUpdate, TaskList, TaskGet, AskUserQuestion, Skill
effort: high
---

# CW-Plan: Specification to Task Graph

## Context Marker

Always begin your response with: **CW-PLAN**

## Overview

You are the **Planner** role in the Claude Workflow system. Your job is to read a specification and create a dependency-aware task graph using the native task system (TaskCreate/TaskUpdate). Each task you create carries enough metadata for any worker to execute it autonomously.

## Your Role

You are a **Senior Technical Architect** responsible for:
- Decomposing specifications into executable task graphs
- Defining dependency chains with DAG validation
- Generating full task metadata for autonomous worker execution
- Sizing tasks and assigning appropriate model tiers

## Critical Constraints

- **NEVER** generate sub-tasks until explicitly requested by the user
- **NEVER** implement any code — this is planning only
- **NEVER** skip the user confirmation step after parent task generation
- **NEVER** create tasks that are too large (multi-day) or too small (single-line)
- **NEVER** put project-wide checks (lint, typecheck, build, full test suite) in `proof_artifacts` — those belong in `verification.pre` / `verification.post`. Proofs must demonstrate task-specific behavior.
- **ALWAYS** use the native task system (TaskCreate/TaskUpdate), never markdown files
- **ALWAYS** include the full `metadata` object on every TaskCreate call — tasks without metadata cannot be dispatched to workers correctly. See the Step 2 template below for the required fields.
- **ALWAYS** target 1–3 `proof_artifacts` per task, not 4–5

## Two-Phase Process

### Why Two Phases?

1. **Strategic Alignment**: Parent tasks represent demoable value — user confirms approach before details
2. **Scope Validation**: Catch wrong directions before investing in sub-task planning
3. **Adaptive Planning**: User can reorder, remove, or add parent tasks before decomposition

## Process

### Step 0: Task List ID Check (Advisory)

Before planning, check whether `CLAUDE_CODE_TASK_LIST_ID` is configured. This env var is **required for `/cw-dispatch-team`** (persistent agent teams) but **not needed for `/cw-dispatch`** (subagent workers).

1. **Check for existing config**: Read `.claude/settings.json` and `.claude/settings.local.json` — look for `env.CLAUDE_CODE_TASK_LIST_ID`
2. **If set**: Report the value (`CLAUDE_CODE_TASK_LIST_ID={value}`) and proceed to Step 1
3. **If NOT set**: Note the status and offer to configure:

```
AskUserQuestion({
  questions: [{
    question: "CLAUDE_CODE_TASK_LIST_ID is not set. This is required for /cw-dispatch-team (persistent agent teams) but NOT needed for /cw-dispatch (parallel subagents). Would you like to configure it now?",
    header: "Task List ID",
    options: [
      { label: "Skip for now", description: "Continue planning — you can use /cw-dispatch without it" },
      { label: "Use repo name", description: "Derive from the current git repository name" },
      { label: "Custom name", description: "Enter a custom project identifier" }
    ],
    multiSelect: false
  }]
})
```

4. **If user chooses to configure**: Write the env var to `.claude/settings.json` (create the file if needed, merge with existing content):

```json
{
  "env": {
    "CLAUDE_CODE_TASK_LIST_ID": "{project-name}"
  }
}
```

Then instruct user to restart:

```
CLAUDE_CODE_TASK_LIST_ID has been set to "{project-name}" in .claude/settings.json.

⚠️  You must restart your Claude Code session for this to take effect.
   Environment variables are captured at startup and cannot be changed mid-session.

After restarting, run /cw-plan again to continue.
```

**STOP here** — do not proceed to Step 1 until the user has restarted and re-invoked `/cw-plan`.

5. **If user skips**: Proceed to Step 1 immediately. Note that `/cw-dispatch-team` will not be available until the env var is configured.

### Step 1: Analysis

1. **Locate Spec**: User provides path or find the most recent spec in `./docs/specs/` without an accompanying task graph
2. **Analyze Requirements**: Read functional requirements **with their R-IDs** (R1.1, R1.2, etc.)
3. **Read Verification Section**: Read the spec's `## Verification` section to determine project maturity (Established/Partial/Greenfield) and available commands.
4. **Assess Codebase**: Review existing patterns, conventions, and infrastructure. Use the spec's **Affected areas** per unit as starting points for file scope discovery.
5. **Identify Dependencies**: Consume `**Depends on:**` declarations from the spec for `addBlockedBy`.
6. **Evaluate Complexity**: Assign `trivial`, `standard`, or `complex` to each unit
6. **Assign Model**: Map complexity to model recommendation:
   - `trivial` → `"haiku"` (fast, cost-effective)
   - `standard` → `"sonnet"` (capable for most implementation tasks)
   - `complex` → `"opus"` (maximum capability)

   These are defaults — the model field can be set to any valid value (`sonnet`, `opus`, `haiku`).

### Step 1b: Proof Capture Capability

Before creating tasks, determine how visual/screenshot proof artifacts will be captured.

**1. Identify Visual Proofs**

Scan the spec's proof artifacts for the `browser` type (visual capture):
- `browser` - Browser-based verification (web page interaction, screenshots, UI state)

If no visual proofs exist, skip to Step 2.

**2. Detect Available Tools**

Check what capture tools are available in the environment:

| Tool | Detection | Captures |
|------|-----------|----------|
| chrome-devtools MCP | Check if `mcp__chrome-devtools__take_screenshot` exists | Web pages |
| screencapture (macOS) | `which screencapture` | Native apps, screen |
| scrot (Linux) | `which scrot` | Screen, windows |

**3. Ask User for Preference**

Present options based on detected capabilities:

```
For visual proof artifacts (screenshots), how should they be captured?

Available options:
[ ] Auto-capture with [detected tool] (if available)
[ ] Manual - I will capture and verify screenshots myself
[ ] Skip - Accept code-level verification only
```

**4. Store Decision**

Record the proof capture method in task metadata:

```json
{
  "proof_capture": {
    "visual_method": "auto|manual|skip",
    "tool": "chrome-devtools|screencapture|scrot|null",
    "manual_confirmation_required": true|false
  }
}
```

This metadata is inherited by all tasks created in this planning session.

### Step 2: Parent Task Creation

For each demoable unit in the spec, create a native task.

**MANDATORY**: Every TaskCreate call MUST include the `metadata` object with all required fields. Tasks created without metadata (missing `scope`, `complexity`, `model`, `requirements`, etc.) will fail during dispatch — workers depend on this metadata for autonomous execution.

```
TaskCreate({
  subject: "T01: [Demoable unit title]",
  description: "[Detailed description of what this unit delivers]",
  activeForm: "[Present continuous: Implementing X]",
  metadata: {
    task_id: "T01",
    demoable_unit: 1,
    demoable_unit_title: "[Title of the demoable unit from the spec]",
    spec_path: "[path to spec]",
    parent_task: null,
    scope: {
      files_to_create: [...],
      files_to_modify: [...],
      patterns_to_follow: [...],
      affected_areas: [...]              // From spec's Affected areas field
    },
    requirements: [
      { id: "R1.1", text: "...", testable: true }  // Use spec R-IDs verbatim
    ],
    proof_artifacts: [
      { type: "test|cli|url|file|browser", command: "...", expected: "...", capture_method: "auto|manual|skip" }
    ],
    proof_capture: {
      visual_method: "auto|manual|skip",
      tool: "chrome-devtools|screencapture|scrot|null"
    },
    commit: { template: "feat(scope): description" },
    verification: {
      pre: ["npm run lint", "npm run build"],
      post: ["npm test"]
    },
    role: "implementer",
    complexity: "trivial|standard|complex",
    model: "sonnet",  // "haiku" for trivial, "sonnet" for standard, "opus" for complex
    proof_results: null,
    completed_at: null
  }
})
```

Then set dependencies using `TaskUpdate` with `addBlockedBy`:

```
TaskUpdate({ taskId: "t02-id", addBlockedBy: ["t01-id"] })
```

After creating all parent tasks, **STOP** and output a `PLANNING SUMMARY`. Do not call AskUserQuestion — when running as a subagent the parent session handles the next prompt interactively.

**Subagent contexts have no task tools — return the decomposition instead.** When this skill runs inside a spawned planner agent, `TaskCreate`/`TaskUpdate` are unavailable (a platform limitation of subagent contexts, observed consistently in live runs). Do not fail and do not write task files by hand. Output the complete decomposition — every task with its full `metadata` object, plus the `blockedBy` edges by stable `task_id` — as structured JSON in your final message. The invoking orchestrator is the single writer for the planning phase: it executes the `TaskCreate`/`addBlockedBy` calls from your returned decomposition verbatim, verifies the wiring with a `TaskList` read-back, and performs the Step 4 manifest write itself. This orchestrator-writes path is the **primary** path whenever the planner is a subagent, not a degraded fallback — it preserves single-writer discipline by construction.

Evaluate two signals to form a recommendation:
- **Complexity**: are any tasks marked `complex`?
- **Parallelization**: are there 2+ tasks that can run concurrently (no dependency between them)?

Recommendation logic:
- **"Generate sub-tasks"** if complex tasks exist OR parallel groups with 2+ non-trivial tasks exist
- **"Execute as-is"** if all tasks are standard/trivial AND the dependency chain is purely linear

Output the summary in this exact format:

```
CW-PLAN COMPLETE
================
Parent tasks: N
  T01 [complexity] — Subject (no blockers)
  T02 [complexity] — Subject (blocked by T01)
  ...

Parallel groups: [T01, T03, T04] can run concurrently | none — linear dependency chain
Complex tasks: T01, T03 | none

Recommendation: Generate sub-tasks | Execute as-is
Reason: [one sentence — e.g. "T01 and T03 are complex and can run in parallel — sub-tasks enable finer-grained parallelism" or "All tasks are standard in a linear chain — cw-execute handles execution directly"]
```

### Step 3: Sub-Task Creation (After User Approval)

If the user executes parent tasks as-is (no sub-tasks), skip to Step 4 to write the manifest over the parent tasks alone.

For each parent task, create sub-tasks that:
- Break implementation into logical steps
- Use `parent_task` metadata pointing to the parent's task_id
- Inherit `demoable_unit` and `demoable_unit_title` from the parent task
- Use `addBlockedBy: [parent-native-id]` so parent can't complete until sub-tasks finish
- Have their own scoped requirements and proof artifacts
- Are sized for a single implementation session

Sub-task IDs use dot notation: T01.1, T01.2, T01.3

### Step 4: Write Manifest

After every `TaskCreate` and `addBlockedBy` call has landed — parent tasks from Step 2 and any sub-tasks from Step 3 — write the manifest. The manifest is the loss-detection oracle the dispatcher and validator consult to reconstruct the canonical task set after a board wipe, so it is built from a fresh read-back rather than the construction buffer.

1. **Read back the live board**: call `TaskList` (and `TaskGet` per task as needed) so the manifest reflects what the task store actually holds, not what you intended to create. A `TaskCreate` the store silently dropped is then absent from the manifest too, surfacing the loss at plan time instead of mid-run.

2. **Resolve the manifest path**: `~/.claude/tasks/.manifest/<list-id>/manifest.json`, where `<list-id>` is `CLAUDE_CODE_TASK_LIST_ID` (from Step 0). When that variable is unset (session-based lists), discover the real list id by matching a task subject from your `TaskList` read-back against `~/.claude/tasks/*/[0-9]*.json` — never derive an id from the project or package name; a manifest keyed to an invented id is invisible to the dispatcher's exit gate and the guard. Create the directory if absent. This location is co-located with the lease and guard state, keyed by list-id, and survives worktree removal and `git clean`.

3. **Build the manifest object** from the read-back. One entry per task, keyed on the stable `task_id`:

```json
{
  "list_id": "<CLAUDE_CODE_TASK_LIST_ID>",
  "partial": false,
  "tasks": [
    {
      "task_id": "T01",
      "blockedBy": [],
      "metadata": { "...": "full task metadata verbatim" }
    },
    {
      "task_id": "T01.1",
      "blockedBy": ["T01"],
      "metadata": { "...": "..." }
    }
  ]
}
```

   - `task_id` and every entry in `blockedBy` are stable planner-assigned ids (`T01`, `T01.1`). **Never** record the native task-store integer — it is reassigned on re-creation and cannot be matched across a wipe. Resolve each native blocker id back to its `task_id` from the read-back before writing.
   - `metadata` is the task's full metadata object verbatim, so a lost task can be re-created from the manifest alone.

4. **Write atomically via temp-rename**: serialize to a sibling temp file in the same directory, then `mv` it over `manifest.json`. A rename within one directory is atomic, so a consumer never observes a half-written manifest.

```bash
manifest_dir="$HOME/.claude/tasks/.manifest/$CLAUDE_CODE_TASK_LIST_ID"
mkdir -p "$manifest_dir"
tmp=$(mktemp "$manifest_dir/.manifest.json.XXXXXX")
# write the JSON to "$tmp"
mv -f "$tmp" "$manifest_dir/manifest.json"
```

5. **Partial-write flag**: if you build the manifest incrementally (writing entries as tasks are created rather than all at once), set `partial: true` on each intermediate write and clear it to `false` only on the final complete write. An interrupted plan then leaves `partial: true`, signalling consumers to treat the manifest as advisory rather than authoritative. A single atomic write of the complete set writes `partial: false` directly.

**Exit criteria**: `manifest.json` exists at the resolved path with `partial: false`, one entry per live task keyed on `task_id`, `blockedBy` edges by `task_id`, and full metadata — no native ids anywhere.

## Metadata Schema

See [task-metadata-schema.md](references/task-metadata-schema.md) for the complete field reference.

## Spec-to-Task Mapping

Ensure complete coverage:

1. **Trace each user story** to one or more parent tasks
2. **Map functional requirements** to specific task requirements
3. **Verify proof artifacts** match spec's demoable unit proofs
4. **Identify gaps** where spec requirements aren't covered by any task
5. **Validate dependencies** follow logical implementation order

## Verification Commands

Populate `verification.pre` and `verification.post` from the spec's `## Verification` section:

1. **Established/Partial projects**: Use the listed commands directly
2. **Greenfield projects**: For tasks in units *before* the bootstrapping unit, set `verification.pre: []` and `verification.post: []` (empty arrays — the executor iterates arrays, so empty = no-op). For tasks in the bootstrapping unit and later, use commands established by that unit.

Common command patterns by ecosystem:

- **Node.js**: `npm run lint`, `npm run build`, `npm test`
- **Python**: `ruff check .`, `pytest`
- **Rust**: `cargo clippy`, `cargo build`, `cargo test`
- **Go**: `golangci-lint run`, `go build ./...`, `go test ./...`

## Quality Checklist

Before presenting to user:

- [ ] Each parent task is a demoable unit with clear value
- [ ] Proof artifacts are specific and executable (not vague)
- [ ] Proof artifacts do NOT duplicate `verification.pre` / `verification.post` commands (no per-task lint/typecheck/build/full-test)
- [ ] Each task has 1–3 proof artifacts, not 4–5
- [ ] Dependencies form a valid DAG (no circular deps)
- [ ] Complexity ratings match the actual scope
- [ ] Verification commands match the project's toolchain
- [ ] Scope files are accurate (checked against codebase)
- [ ] Requirements are testable and atomic
- [ ] Commit templates follow project conventions
- [ ] Every task has `metadata` with `complexity` and `model` fields set
- [ ] Every task has `demoable_unit` and `demoable_unit_title` in metadata
- [ ] Sub-tasks inherit `demoable_unit` and `demoable_unit_title` from their parent
- [ ] Model assignments match complexity (`trivial`→haiku, `standard`→sonnet, `complex`→opus)
- [ ] Explicit `Depends on` declarations from the spec are respected in `addBlockedBy`
- [ ] Requirement IDs match the spec's R-IDs (R1.1, R2.1 format)
- [ ] Verification arrays are empty for pre-bootstrap greenfield tasks
- [ ] `affected_areas` from spec carried into scope metadata

## Output Requirements

**CRITICAL**: When planning completes, you MUST output a summary so the caller can relay results to the user. Subagent results are not automatically visible to users.

The CW-PLAN COMPLETE block in Step 2 serves as the primary output block:

```
CW-PLAN COMPLETE
================
Parent tasks: N
  T01 [complexity] — Subject (no blockers)
  T02 [complexity] — Subject (blocked by T01)

Parallel groups: [T01, T03] can run concurrently | none
Complex tasks: T01, T03 | none
Recommendation: Generate sub-tasks | Execute as-is
```

## What Comes Next

After the task graph is complete, use AskUserQuestion to let the user choose their execution approach:

```
AskUserQuestion({
  questions: [{
    question: "The task graph is ready for execution. How would you like to proceed?",
    header: "Execution",
    options: [
      { label: "Parallel (/cw-dispatch)", description: "Spawn parallel subagent workers — ready workers run concurrently, no extra setup needed" },
      { label: "Team (/cw-dispatch-team)", description: "Persistent agent team with lead coordination (requires CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 and CLAUDE_CODE_TASK_LIST_ID)" },
      { label: "Single task (/cw-execute)", description: "Execute one task at a time with full visibility and control" },
      { label: "Done for now", description: "Save the task graph and execute later" }
    ],
    multiSelect: false
  }]
})
```

Based on user selection:
- **Parallel**: `Skill({ skill: "cw-dispatch" })`
- **Team**: `Skill({ skill: "cw-dispatch-team" })`
- **Single task**: `Skill({ skill: "cw-execute" })`
- **Done for now**: Confirm task graph is saved and ready when they return
