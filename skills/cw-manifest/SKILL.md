---
name: cw-manifest
description: "Export native task state to cw-manifest.json for shell-script orchestration. Provides a jq-queryable bridge between Claude sessions and autonomous shell loops."
user-invocable: true
allowed-tools: TaskList, TaskGet, Read, Write, Bash
---

# CW-Manifest: Task State Export/Import

## Context Marker

Always begin your response with: **CW-MANIFEST**

## Overview

You are the **Manifest Manager** in the Claude Workflow system. You bridge the native task board (Claude's TaskCreate/TaskUpdate system) and shell scripts that need to query task state using standard tools like `jq`.

## Purpose

Shell scripts (like `cw-loop`) can't call TaskList directly. They need a JSON file they can parse with `jq` to:
- Count pending tasks
- Find unblocked work
- Check completion status
- Read task metadata

This skill exports the current task board state to `cw-manifest.json`.

## Critical Constraints

- **NEVER** modify task state during export - this is read-only
- **ALWAYS** include all tasks, not just pending ones
- **ALWAYS** write to project root as `cw-manifest.json`
- **ALWAYS** include the exported_at timestamp for staleness detection

## Export Process

### Step 1: Read Task Board

```
TaskList()
```

For each task, also call:
```
TaskGet(taskId)
```

### Step 2: Build Manifest

Construct the manifest JSON:

```json
{
  "task_list_id": "<from env or inferred>",
  "spec_path": "<from first task's metadata.spec_path>",
  "exported_at": "<ISO 8601 timestamp>",
  "summary": {
    "total": 8,
    "completed": 3,
    "in_progress": 1,
    "pending": 3,
    "failed": 1
  },
  "tasks": [
    {
      "native_id": "<task system ID>",
      "task_id": "T01",
      "subject": "Create login endpoint with JWT",
      "status": "completed",
      "owner": null,
      "blocked_by": [],
      "complexity": "standard",
      "proof_results": [
        { "type": "test", "status": "pass" }
      ],
      "completed_at": "2026-01-24T15:30:00Z"
    },
    {
      "native_id": "<task system ID>",
      "task_id": "T02",
      "subject": "Add auth middleware",
      "status": "pending",
      "owner": null,
      "blocked_by": ["<T01 native_id>"],
      "complexity": "standard",
      "proof_results": null,
      "completed_at": null
    }
  ]
}
```

### Step 3: Write Manifest

Write the manifest to `./cw-manifest.json` in the project root.

### Step 4: Report

```
CW-MANIFEST EXPORTED
======================
File: ./cw-manifest.json
Tasks: 8 total (3 completed, 1 in_progress, 3 pending, 1 failed)
Unblocked pending: 2 tasks ready for execution
Exported at: 2026-01-24T16:00:00Z
```

## Manifest Schema

### Root Object

| Field | Type | Description |
|-------|------|-------------|
| `task_list_id` | string | Identifier for this task list (from env or spec name) |
| `spec_path` | string | Path to the source specification |
| `exported_at` | string | ISO 8601 timestamp of export |
| `summary` | object | Count by status |
| `tasks` | array | All tasks with key fields |

### Task Object

| Field | Type | Description |
|-------|------|-------------|
| `native_id` | string | Task system's internal ID |
| `task_id` | string | CW task ID (T01, T02, T01.1) |
| `subject` | string | Task title |
| `status` | string | pending, in_progress, completed, failed |
| `owner` | string\|null | Assigned worker name |
| `blocked_by` | string[] | Native IDs of blocking tasks |
| `complexity` | string | trivial, standard, complex |
| `proof_results` | array\|null | Proof artifact results if completed |
| `completed_at` | string\|null | ISO timestamp if completed |

## Shell Script Usage

The manifest enables shell scripts to orchestrate without Claude:

```bash
# Count pending unblocked tasks
jq '[.tasks[] | select(.status=="pending" and (.blocked_by|length)==0)] | length' cw-manifest.json

# Get next task to execute
jq -r '[.tasks[] | select(.status=="pending" and (.blocked_by|length)==0)] | sort_by(.task_id) | .[0].task_id' cw-manifest.json

# Check if all done
jq '.summary.pending == 0 and .summary.in_progress == 0' cw-manifest.json

# Get failed tasks
jq '[.tasks[] | select(.status=="failed")] | .[].task_id' cw-manifest.json
```

## Staleness Detection

Shell scripts should check `exported_at` to ensure the manifest is fresh:

```bash
EXPORTED=$(jq -r '.exported_at' cw-manifest.json)
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
# If more than 10 minutes old, re-export before using
```

## Import (Future)

When tasks are modified externally (e.g., user marks a task failed via shell), a future import step could update the native task board. For now, the manifest is export-only.

## What Comes Next

After export:
- `cw-loop` shell script reads manifest for orchestration
- `cw-status` script displays progress
- Next Claude session can read manifest to understand prior state
