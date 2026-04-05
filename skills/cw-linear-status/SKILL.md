---
name: cw-linear-status
description: "Shows the current state of the Linear heartbeat lifecycle. Displays parent issues with their phases, sub-issues with execution status, queue depth, blocked issues, and recent heartbeat history."
user-invocable: true
allowed-tools: Bash, Read, Glob, Grep
effort: low
---

# CW-Linear-Status: Lifecycle Status Dashboard

## Context Marker

Always begin your response with: **CW-LINEAR-STATUS**

## Overview

You display the current state of the Linear heartbeat lifecycle — parent issues and their phases, sub-issues and their execution status, what's queued, what's blocked, and recent history.

## Your Role

You are a **status reporter** who:
- Reads the local config and heartbeat log
- Queries Linear for current issue state
- Presents a clear, phase-aware dashboard

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

Using Linear MCP tools, fetch issues assigned to the configured `user_name` in the configured `team`. Categorize:

**Parent Issues** (no `cw-managed` label):
- Detect phase from labels and status (see heartbeat-protocol.md)
- Count child sub-issues and their statuses

**Sub-issues** (has `cw-managed` label):
- Group by parent issue
- Show execution status

### Step 3: Check Lock State

```bash
if [ -f .claude-workflow/heartbeat.lock ]; then
  cat .claude-workflow/heartbeat.lock
else
  echo "UNLOCKED"
fi
```

### Step 4: Read Heartbeat History

```bash
tail -10 .claude-workflow/heartbeat-log.jsonl 2>/dev/null || echo "No history"
```

### Step 5: Display Dashboard

```
CW-LINEAR-STATUS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Config:     .claude-workflow/config.yaml
Team:       {team}
Agent:      {user_name}
Lock:       {UNLOCKED | LOCKED since HH:MM (phase: EXECUTE)}
Strategy:   {direct | integration}

PARENT ISSUES
─────────────
  ENG-100  JWT Authentication         phase: SPEC          [High]
    Sub-issues: 0 created (spec pending)

  ENG-200  Search redesign            phase: RESEARCH      [Medium]
    Sub-issues: 0 created (research pending)

  ENG-300  Billing module             phase: WAITING       [Low]
    Sub-issues: 2/3 done, 1 in progress
    ├── ENG-456  Add invoice endpoint      Done
    ├── ENG-457  Add payment webhook       In Progress (agent-working)
    └── ENG-458  Add billing dashboard     Backlog (not yet approved)

BLOCKED ({N})
─────────────
  ENG-457  Add payment webhook       agent-blocked  (Gate C failed: missing proof)
  ENG-200  Search redesign           agent-blocked  (Linear MCP unavailable)

PIPELINE CONFIG
───────────────
  auto_spec: yes    auto_plan: yes     auto_dispatch: yes
  auto_validate: yes  auto_review: no  auto_pr: no
  auto_research: no   auto_testing: yes
  parent_review: no   branch_strategy: direct

RECENT HEARTBEATS
─────────────────
  2026-04-05 10:30  ENG-456  EXECUTE    completed  5m 40s
  2026-04-05 10:15  ENG-100  SPEC       completed  2m 12s
  2026-04-05 10:00  ENG-200  RESEARCH   blocked    1m 05s
```
