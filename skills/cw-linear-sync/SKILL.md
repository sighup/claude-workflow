---
name: cw-linear-sync
description: "Internal skill that abstracts Linear MCP interactions for the heartbeat lifecycle. Handles issue queries, sub-issue creation from specs, structured comment posting, and label state management. Called by cw-heartbeat, not directly by users."
user-invocable: false
allowed-tools: Read, Glob, Grep, Bash
effort: low
---

# CW-Linear-Sync: Linear API Abstraction Layer

## Context Marker

Always begin your response with: **CW-LINEAR-SYNC**

## Overview

You are an internal skill that provides structured Linear operations for the heartbeat lifecycle. You abstract away raw Linear MCP tool calls so the heartbeat skill can focus on phase logic rather than API details.

The heartbeat invokes you with a specific **operation** and **payload**. You execute the operation and return structured results.

## Critical Constraints

- **NEVER** modify issue state without explicit instruction from the heartbeat
- **NEVER** create sub-issues without a completed spec to source from
- **NEVER** post comments that don't follow the structured format
- **ALWAYS** return structured results the heartbeat can parse
- **ALWAYS** handle MCP tool errors gracefully (report, don't crash)

## Operations

### 1. QUERY_QUEUE

Fetch actionable issues assigned to the configured agent.

**Input** (in invocation args):
```
operation: QUERY_QUEUE
team: {team_key}
user_name: {agent_name}
```

**Process:**
1. Query Linear for issues assigned to `user_name` in team `team`
2. Categorize each issue:
   - **Parent issues**: Issues without `cw-managed` label
   - **Sub-issues**: Issues with `cw-managed` label
3. For each issue, determine phase (see Phase Detection in heartbeat-protocol.md)
4. Filter out issues with `agent-working` label (unless lock is stale)
5. For `agent-blocked` issues: include only if a new comment exists since the last agent comment
6. Sort: In Progress first, then by priority (Urgent > High > Medium > Low > No priority)

**Return:**
```
QUEUE_RESULT
parent_issues:
  - id: ENG-100
    title: "JWT Authentication"
    phase: SPEC
    status: Todo
    priority: High
    labels: []
sub_issues:
  - id: ENG-456
    title: "Add login endpoint"
    phase: EXECUTE
    status: Todo
    priority: High
    parent_id: ENG-100
    labels: [cw-managed]
total: {N}
```

### 2. CREATE_SUB_ISSUES

Create Linear sub-issues from a spec's demoable units.

**Input:**
```
operation: CREATE_SUB_ISSUES
parent_id: {parent_issue_id}
spec_path: {path_to_spec_file}
team: {team_key}
```

**Process:**
1. Read the spec file at `spec_path`
2. Extract each **Demoable Unit** section:
   - Title
   - Purpose
   - Functional Requirements (become the sub-issue description)
   - Proof Artifacts (become acceptance criteria)
3. For each demoable unit, create a sub-issue in Linear:
   - **Title**: Demoable unit title
   - **Description**: Formatted markdown with:
     ```markdown
     ## Purpose
     {purpose from spec}

     ## Requirements
     {functional requirements list}

     ## Acceptance Criteria
     {proof artifact definitions}

     ## Spec Reference
     Spec: `{spec_path}`
     Unit: {unit_number}
     ```
   - **Parent**: Set to `parent_id` (makes it a sub-issue)
   - **Status**: Backlog (not Todo — human must approve by moving to Todo)
   - **Labels**: `cw-managed`
   - **Team**: `team`
4. Apply `spec-complete` phase label to the parent issue

**Return:**
```
SUB_ISSUES_CREATED
parent_id: ENG-100
sub_issues:
  - id: ENG-456
    title: "Add login endpoint"
    unit: 1
  - id: ENG-457
    title: "Add token refresh"
    unit: 2
  - id: ENG-458
    title: "Add logout endpoint"
    unit: 3
count: 3
```

### 3. POST_COMMENT

Post a structured comment to a Linear issue following the heartbeat protocol format.

**Input:**
```
operation: POST_COMMENT
issue_id: {issue_id}
phase: {RESEARCH | SPEC | EXECUTE | REVIEW | TEST | VALIDATE}
result: {completed | blocked | error}
body: {structured markdown body}
```

**Process:**
1. Determine the heartbeat number by counting previous agent comments on this issue + 1
2. Format the comment:
   ```markdown
   **Heartbeat #{N}** — {phase} — {timestamp}

   **Result:** {result}

   {body}
   ```
3. Post the comment to the issue via Linear MCP tools

**Return:**
```
COMMENT_POSTED
issue_id: ENG-456
heartbeat_number: 3
```

### 4. UPDATE_LABELS

Add or remove labels on a Linear issue.

**Input:**
```
operation: UPDATE_LABELS
issue_id: {issue_id}
add: [label1, label2]
remove: [label3]
```

**Process:**
1. Fetch current labels on the issue
2. Add requested labels (skip if already present)
3. Remove requested labels (skip if not present)
4. Respect label group single-select rules:
   - `cw-state` group: adding `agent-working` removes `agent-blocked` and vice versa
   - `cw-phase` group: adding `ready-for-spec` removes `needs-research`, etc.

**Return:**
```
LABELS_UPDATED
issue_id: ENG-456
current_labels: [cw-managed, agent-working]
```

### 5. UPDATE_STATUS

Change the status of a Linear issue.

**Input:**
```
operation: UPDATE_STATUS
issue_id: {issue_id}
status: {Backlog | Todo | In Progress | In Review | Done | Canceled}
```

**Process:**
1. Update the issue status via Linear MCP tools

**Return:**
```
STATUS_UPDATED
issue_id: ENG-456
status: Done
```

### 6. GET_ISSUE_CONTEXT

Fetch full context for an issue (used before spec generation or sub-issue execution).

**Input:**
```
operation: GET_ISSUE_CONTEXT
issue_id: {issue_id}
```

**Process:**
1. Fetch the issue: title, description, status, labels, priority
2. Fetch comments (chronological)
3. Fetch parent issue context (if this is a sub-issue)
4. Fetch sub-issues (if this is a parent issue)
5. Fetch linked/related issues

**Return:**
```
ISSUE_CONTEXT
id: ENG-100
title: "JWT Authentication"
description: |
  {full markdown body}
status: Todo
priority: High
labels: [needs-research]
comments:
  - author: "user@example.com"
    date: "2026-04-01T10:00:00Z"
    body: "We need JWT with refresh tokens..."
  - author: "claude-agent"
    date: "2026-04-02T14:00:00Z"
    body: "Heartbeat #1 — RESEARCH — ..."
parent: null
sub_issues:
  - id: ENG-456
    title: "Add login endpoint"
    status: Backlog
    labels: [cw-managed]
```

### 7. CHECK_CHILDREN_STATUS

Check if all sub-issues of a parent issue are complete.

**Input:**
```
operation: CHECK_CHILDREN_STATUS
parent_id: {parent_issue_id}
```

**Process:**
1. Fetch all sub-issues with `cw-managed` label
2. Check status of each

**Return:**
```
CHILDREN_STATUS
parent_id: ENG-100
total: 3
done: 2
in_progress: 1
blocked: 0
all_done: false
sub_issues:
  - id: ENG-456, status: Done
  - id: ENG-457, status: Done
  - id: ENG-458, status: In Progress
```

## Error Handling

If any Linear MCP call fails:
1. Log the error with the operation name and issue ID
2. Return a structured error result:
   ```
   ERROR
   operation: {operation_name}
   issue_id: {issue_id}
   error: {error message}
   ```
3. Do NOT retry — let the heartbeat decide whether to retry or mark blocked
