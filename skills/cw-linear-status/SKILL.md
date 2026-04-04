---
name: cw-linear-status
description: "Shows the current state of the Linear-integrated heartbeat system. Displays issue queue depth, blocked issues, recent heartbeat history, and pipeline configuration."
user-invocable: true
allowed-tools: Bash, Read, Glob, Grep
effort: low
---

# CW-Linear-Status: Heartbeat Status Dashboard

## Context Marker

Always begin your response with: **CW-LINEAR-STATUS**

## Overview

You display the current state of the Linear heartbeat integration — what's queued, what's blocked, and what happened recently.

## Your Role

You are a **status reporter** who:
- Reads the local config and heartbeat log
- Queries Linear for current issue state
- Presents a clear dashboard of system status

## Critical Constraints

- **NEVER** modify any files or issue state — this is read-only
- **ALWAYS** check that `.claude-workflow/config.yaml` exists before proceeding

## Process

### Step 1: Load Configuration

Read `.claude-workflow/config.yaml`. If missing, report:
```
Linear integration not configured. Run /cw-linear-init first.
```

### Step 2: Query Linear

Using Linear MCP tools, fetch issues assigned to the configured `user_name` in the configured `team`:

1. **Queued** — Issues in "Todo" status (ready for pickup)
2. **In Progress** — Issues with `agent-working` label
3. **Blocked** — Issues with `agent-blocked` label

### Step 3: Check Lock State

```bash
if [ -f .claude-workflow/heartbeat.lock ]; then
  echo "LOCKED (heartbeat in progress)"
  cat .claude-workflow/heartbeat.lock
else
  echo "UNLOCKED"
fi
```

### Step 4: Read Heartbeat History

If `--history` is in the args (or always show last 5):

```bash
tail -5 .claude-workflow/heartbeat-log.jsonl 2>/dev/null || echo "No heartbeat history"
```

Each log entry contains:
```json
{
  "timestamp": "2026-04-04T10:30:00Z",
  "heartbeat_number": 42,
  "issue_id": "ENG-123",
  "issue_title": "Add search endpoint",
  "duration_seconds": 340,
  "result": "completed",
  "commits": ["abc1234"],
  "spec_path": "docs/specs/01-spec-search/01-spec-search.md"
}
```

### Step 5: Display Dashboard

Format the output as a clear dashboard:

```
CW-LINEAR-STATUS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Config:     .claude-workflow/config.yaml
Team:       {team}
Agent:      {user_name}
Lock:       {UNLOCKED | LOCKED since HH:MM}

Queue ({N} issues):
  ENG-123  Add search endpoint          Todo
  ENG-124  Fix pagination bug           Todo

In Progress ({N} issues):
  ENG-120  Refactor auth middleware      agent-working

Blocked ({N} issues):
  ENG-118  Database migration strategy   agent-blocked

Pipeline Config:
  auto_spec: {yes/no}  auto_plan: {yes/no}
  auto_dispatch: {yes/no}  auto_validate: {yes/no}
  auto_review: {yes/no}  auto_pr: {yes/no}

Recent Heartbeats:
  #42  ENG-123  completed  5m 40s  2026-04-04 10:30
  #41  ENG-120  completed  3m 12s  2026-04-04 10:15
  #40  ENG-118  blocked    1m 05s  2026-04-04 10:00
```
