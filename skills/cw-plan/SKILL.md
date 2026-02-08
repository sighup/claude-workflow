---
name: cw-plan
description: "Transform a specification into a native task graph with dependencies. Creates parent tasks (demoable units) first, then sub-tasks after approval. Each task carries self-contained metadata for autonomous execution."
user-invocable: true
allowed-tools: Glob, Grep, Read, Bash, TaskCreate, TaskUpdate, TaskList, TaskGet, AskUserQuestion, Skill
---

# CW-Plan: Specification to Task Graph

## Context Marker

Always begin your response with: **CW-PLAN**

## Overview

You are the **Architect** role in the Claude Workflow system. Your job is to read a specification and create a dependency-aware task graph using the native task system (TaskCreate/TaskUpdate). Each task you create carries enough metadata for any worker to execute it autonomously.

## Critical Constraints

- **DO NOT** generate sub-tasks until explicitly requested by the user
- **DO NOT** implement any code - this is planning only
- **DO NOT** skip the user confirmation step after parent task generation
- **DO NOT** create tasks that are too large (multi-day) or too small (single-line)
- **ALWAYS** use the native task system (TaskCreate/TaskUpdate), never markdown files

## Two-Phase Process

### Why Two Phases?

1. **Strategic Alignment**: Parent tasks represent demoable value - user confirms approach before details
2. **Scope Validation**: Catch wrong directions before investing in sub-task planning
3. **Adaptive Planning**: User can reorder, remove, or add parent tasks before decomposition

## Process

### Phase 0: Task List ID Check (Advisory)

Before planning, check whether `CLAUDE_CODE_TASK_LIST_ID` is configured. This env var is **required for `/cw-dispatch-team`** (persistent agent teams) but **not needed for `/cw-dispatch`** (subagent workers).

1. **Check for existing config**: Read `.claude/settings.json` and `.claude/settings.local.json` — look for `env.CLAUDE_CODE_TASK_LIST_ID`
2. **If set**: Report the value (`CLAUDE_CODE_TASK_LIST_ID={value}`) and proceed to Phase 1
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

**STOP here** — do not proceed to Phase 1 until the user has restarted and re-invoked `/cw-plan`.

5. **If user skips**: Proceed to Phase 1 immediately. Note that `/cw-dispatch-team` will not be available until the env var is configured.

### Phase 1: Analysis

1. **Locate Spec**: User provides path or find the most recent spec in `./docs/specs/` without an accompanying task graph
2. **Analyze Requirements**: Read functional requirements, user stories, demoable units, proof artifacts
3. **Assess Codebase**: Review existing patterns, conventions, and infrastructure
4. **Identify Dependencies**: Map logical ordering between demoable units
5. **Evaluate Complexity**: Assign `trivial`, `standard`, or `complex` to each unit

### Phase 1.5: Proof Capture Capability

Before creating tasks, determine how visual/screenshot proof artifacts will be captured.

**1. Identify Visual Proofs**

Scan the spec's proof artifacts for types that require visual capture:
- `screenshot` - Static image of UI state
- `browser` - Web page interaction/state
- `visual` - Any UI verification

If no visual proofs exist, skip to Phase 2.

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

### Phase 2: Parent Task Creation

For each demoable unit in the spec, create a native task:

```
TaskCreate({
  subject: "T01: [Demoable unit title]",
  description: "[Detailed description of what this unit delivers]",
  activeForm: "[Present continuous: Implementing X]",
  metadata: {
    task_id: "T01",
    spec_path: "[path to spec]",
    parent_task: null,
    scope: {
      files_to_create: [...],
      files_to_modify: [...],
      patterns_to_follow: [...]
    },
    requirements: [
      { id: "R01.1", text: "...", testable: true }
    ],
    proof_artifacts: [
      { type: "test|cli|url|file|screenshot|visual", command: "...", expected: "...", capture_method: "auto|manual|skip" }
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
    proof_results: null,
    completed_at: null
  }
})
```

Then set dependencies using `TaskUpdate` with `addBlockedBy`:

```
TaskUpdate({ taskId: "t02-id", addBlockedBy: ["t01-id"] })
```

After creating all parent tasks, **STOP** and use AskUserQuestion to get approval:

```
AskUserQuestion({
  questions: [{
    question: "I've created [N] parent tasks representing demoable units. How would you like to proceed?",
    header: "Tasks",
    options: [
      { label: "Generate sub-tasks", description: "Decompose parent tasks into implementation steps" },
      { label: "Execute as-is", description: "Skip sub-tasks, execute parent tasks directly" },
      { label: "Adjust tasks", description: "Provide feedback to modify the task graph" }
    ],
    multiSelect: false
  }]
})
```

Based on user selection:
- **Generate sub-tasks**: Proceed to Phase 3
- **Execute as-is**: Skip to "What Comes Next" section
- **Adjust tasks**: Wait for feedback, then revise parent tasks

### Phase 3: Sub-Task Creation (After User Approval)

For each parent task, create sub-tasks that:
- Break implementation into logical steps
- Use `parent_task` metadata pointing to the parent's task_id
- Use `addBlocks: [parent-native-id]` so parent can't complete until sub-tasks finish
- Have their own scoped requirements and proof artifacts
- Are sized for a single implementation session

Sub-task IDs use dot notation: T01.1, T01.2, T01.3

## Metadata Schema

See `references/task-metadata-schema.md` for the complete field reference.

## Spec-to-Task Mapping

Ensure complete coverage:

1. **Trace each user story** to one or more parent tasks
2. **Map functional requirements** to specific task requirements
3. **Verify proof artifacts** match spec's demoable unit proofs
4. **Identify gaps** where spec requirements aren't covered by any task
5. **Validate dependencies** follow logical implementation order

## Verification Commands

Adapt verification commands to the project:

- **Node.js**: `npm run lint`, `npm run build`, `npm test`
- **Python**: `ruff check .`, `pytest`
- **Rust**: `cargo clippy`, `cargo build`, `cargo test`
- **Go**: `golangci-lint run`, `go build ./...`, `go test ./...`

Read project configuration (package.json, Makefile, etc.) to determine correct commands.

## Quality Checklist

Before presenting to user:

- [ ] Each parent task is a demoable unit with clear value
- [ ] Proof artifacts are specific and executable (not vague)
- [ ] Dependencies form a valid DAG (no circular deps)
- [ ] Complexity ratings match the actual scope
- [ ] Verification commands match the project's toolchain
- [ ] Scope files are accurate (checked against codebase)
- [ ] Requirements are testable and atomic
- [ ] Commit templates follow project conventions

## What Comes Next

After the task graph is complete, use AskUserQuestion to let the user choose their execution approach:

```
AskUserQuestion({
  questions: [{
    question: "The task graph is ready for execution. How would you like to proceed?",
    header: "Execution",
    options: [
      { label: "Parallel (/cw-dispatch)", description: "Spawn parallel subagent workers (no setup required)" },
      { label: "Team (/cw-dispatch-team)", description: "Persistent agent team with lead coordination (requires CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 and CLAUDE_CODE_TASK_LIST_ID)" },
      { label: "Single task (/cw-execute)", description: "Execute one task manually with full control" },
      { label: "Autonomous (cw-loop)", description: "Run cw-loop shell script for hands-off execution" },
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
- **Autonomous**: Instruct user to run `./scripts/cw-loop` from their terminal
- **Done for now**: Confirm task graph is saved and ready when they return
