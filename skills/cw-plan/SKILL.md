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

### Phase 1: Analysis

1. **Locate Spec**: User provides path or find the most recent spec in `./docs/specs/` without an accompanying task graph
2. **Analyze Requirements**: Read functional requirements, user stories, demoable units, proof artifacts
3. **Assess Codebase**: Review existing patterns, conventions, and infrastructure
4. **Identify Dependencies**: Map logical ordering between demoable units
5. **Evaluate Complexity**: Assign `trivial`, `standard`, or `complex` to each unit

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
      { type: "test|cli|url|file|screenshot|visual", command: "...", expected: "..." }
    ],
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
      { label: "Parallel (/cw-dispatch)", description: "Spawn parallel workers for independent tasks (recommended)" },
      { label: "Single task (/cw-execute)", description: "Execute one task manually with full control" },
      { label: "Setup proof capture (/cw-proof-setup)", description: "Configure visual proof capture tools before execution" },
      { label: "Autonomous (cw-loop)", description: "Run cw-loop shell script for hands-off execution" },
      { label: "Done for now", description: "Save the task graph and execute later" }
    ],
    multiSelect: false
  }]
})
```

Based on user selection:
- **Parallel**: `Skill({ skill: "cw-dispatch" })`
- **Single task**: `Skill({ skill: "cw-execute" })`
- **Setup proof capture**: `Skill({ skill: "cw-proof-setup" })` - recommended if spec has visual proof artifacts
- **Autonomous**: Instruct user to run `./scripts/cw-loop` from their terminal
- **Done for now**: Confirm task graph is saved and ready when they return
