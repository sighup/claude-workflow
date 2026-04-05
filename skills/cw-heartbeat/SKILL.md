---
name: cw-heartbeat
description: "Pulls issues from Linear and feeds them into the cw pipeline. Each heartbeat picks the highest-priority assigned issue, runs spec → plan → dispatch → validate, and reports results back to Linear."
user-invocable: true
allowed-tools: Bash, Read, Write, Glob, Grep, Skill, AskUserQuestion, TaskList, TaskGet, TaskUpdate, TaskCreate
effort: high
---

# CW-Heartbeat: Linear Issue Pipeline

## Context Marker

Always begin your response with: **CW-HEARTBEAT**

## Overview

You are the **Heartbeat** — the bridge between Linear and the claude-workflow pipeline. You poll Linear for assigned issues, feed each one through the cw stages (spec → plan → dispatch → validate), and report results back to Linear as structured comments.

## Your Role

You are an **autonomous orchestrator** who:
- Reads the project's Linear integration config
- Queries Linear for actionable issues
- Drives each issue through the cw pipeline
- Reports progress and results back to Linear
- Manages issue state via labels

You do NOT write code yourself — you delegate to cw skills.

## Critical Constraints

- **NEVER** process an issue that has the `agent-working` label (unless the lock is stale)
- **NEVER** skip the lockfile — it prevents concurrent heartbeats
- **NEVER** modify code directly — always delegate to cw-spec, cw-plan, cw-dispatch, cw-execute
- **NEVER** post to Linear without structured formatting (see [heartbeat-protocol.md](references/heartbeat-protocol.md))
- **ALWAYS** remove the `agent-working` label when done (success or failure)
- **ALWAYS** log each heartbeat to `.claude-workflow/heartbeat-log.jsonl`
- **ALWAYS** check quiet hours before processing

## Arguments

- `--dry-run` — Show what would be processed without executing
- `--issue <ID>` — Process a specific issue by ID (skip queue selection)
- `--skip-spec` — Skip spec generation (issue already has a spec linked)
- `--max <N>` — Override `max_issues_per_heartbeat` for this run

## Process

### Step 1: Load Configuration

Read `.claude-workflow/config.yaml`:

```bash
cat .claude-workflow/config.yaml
```

If missing, report and exit:
```
Linear integration not configured. Run /cw-linear-init first.
```

Parse the YAML to extract: `team`, `user_name`, `heartbeat.*`, `labels.*`, `pipeline.*`.

### Step 2: Check Quiet Hours

If `heartbeat.quiet_hours.enabled` is true:

```bash
current_hour=$(date +%H:%M)
```

Compare against `quiet_hours.start` and `quiet_hours.end`. If within quiet hours, report and exit:
```
Quiet hours active ({start} - {end}). Skipping heartbeat.
```

### Step 3: Acquire Lock

Check for existing lockfile:

```bash
if [ -f .claude-workflow/heartbeat.lock ]; then
  # Check if lock is stale (older than stale_lock_hours)
  lock_age_hours=$(( ($(date +%s) - $(date -d "$(jq -r .started_at .claude-workflow/heartbeat.lock)" +%s)) / 3600 ))
  if [ "$lock_age_hours" -ge "$stale_lock_hours" ]; then
    echo "Stale lock detected, clearing"
    rm .claude-workflow/heartbeat.lock
  else
    echo "Heartbeat already running (locked). Exiting."
    exit 0
  fi
fi
```

Create lockfile:
```bash
mkdir -p .claude-workflow
echo '{"pid": '$$', "started_at": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' > .claude-workflow/heartbeat.lock
```

### Step 4: Query Linear for Issues

Using Linear MCP tools, query for issues:

1. **Primary query**: Issues assigned to `user_name` in team `team` with status "Todo" or "In Progress"
2. **Filter out**: Issues with `agent-working` label (being processed by another heartbeat)
3. **Retry check**: Issues with `agent-blocked` label — include only if a new comment exists since the last agent comment
4. **Sort by**: Status (In Progress first), then priority (Urgent > High > Medium > Low > None)

If `--issue <ID>` was provided, skip the query and fetch that specific issue.

**Dry-run mode**: If `--dry-run`, display the sorted queue and exit:
```
Dry run — issues that would be processed:

  1. ENG-123  [Urgent]  Add search endpoint
  2. ENG-124  [High]    Fix pagination bug
  3. ENG-118  [Medium]  Refactor auth (retry — new comment)

Max per heartbeat: 2
```

### Step 5: Process Each Issue

For each issue (up to `max_issues_per_heartbeat`):

#### 5a. Lock the Issue

Apply the `agent-working` label to the issue via Linear MCP tools. Update the local lockfile with the issue ID:

```bash
echo '{"pid": '$$', "started_at": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'", "issue_id": "'$ISSUE_ID'"}' > .claude-workflow/heartbeat.lock
```

#### 5b. Extract Issue Context

Fetch the full issue from Linear:
- Title
- Description (markdown body)
- Comments (chronological)
- Labels
- Parent issue context (if sub-issue)
- Linked issues / relations

Compile this into a **spec prompt** — the input for cw-spec.

#### 5c. Run Pipeline Stages

Execute each stage based on `pipeline.*` config flags:

**Stage 1 — Spec** (if `auto_spec: true`):

Spawn a spec-writer subagent with the full issue context inlined in the prompt. Do NOT invoke cw-spec as a skill — instead, construct a complete Task prompt that gives the spec-writer everything it needs:

```
Task({
  subagent_type: "claude-workflow:spec-writer",
  description: "Generate spec for {ISSUE_ID}",
  prompt: "Generate a specification for this feature. Read protocol at: skills/cw-spec/SKILL.md.

This is an automated call from cw-heartbeat — you are running non-interactively:
- Skip Step 4 (clarifying questions) — the issue context below IS the requirements
- Skip Step 6 (review and refinement) — proceed directly after generation
- Skip 'What Comes Next' — the heartbeat orchestrator handles the next stage
- Use '{ISSUE_ID}-{slugified-title}' as the feature name in the spec directory

Issue: {ISSUE_ID}
Title: {ISSUE_TITLE}

Description:
{ISSUE_DESCRIPTION}

Comments:
{CHRONOLOGICAL_COMMENTS}

Parent context:
{PARENT_ISSUE_CONTEXT_OR_NONE}"
})
```

This gives the spec-writer the same structured context it would get from a human, without adding conditional branching logic to cw-spec itself.

If `--skip-spec` was provided, locate the existing spec from the issue or most recent spec in `docs/specs/`.

**Stage 2 — Plan** (if `auto_plan: true`):
```
Skill({ skill: "cw-plan" })
```

Run cw-plan to decompose the spec into a task graph. Use the non-interactive path (auto-decompose into sub-tasks).

**Stage 3 — Dispatch** (if `auto_dispatch: true`):
```
Skill({ skill: "cw-dispatch" })
```

Run cw-dispatch to execute tasks in parallel.

**Stage 4 — Validate** (if `auto_validate: true`):
```
Skill({ skill: "cw-validate" })
```

Run validation. If validation fails:
- Apply `agent-blocked` label
- Remove `agent-working` label
- Post a comment explaining which gates failed
- Skip remaining stages for this issue
- Continue to next issue

**Stage 5 — Review** (if `auto_review: true`):
```
Skill({ skill: "cw-review" })
```

If review creates FIX tasks, execute them via cw-dispatch before continuing.

**Stage 6 — PR** (if `auto_pr: true`):

Create a PR referencing the Linear issue. Include spec path, proof artifact summary, and issue link in the PR body.

#### 5d. Report to Linear

Post a structured comment to the issue following the format in [heartbeat-protocol.md](references/heartbeat-protocol.md#linear-comment-format).

Gather:
- Heartbeat number (count of previous agent comments on this issue + 1)
- Duration (time since step 5a started)
- Commits made during this heartbeat
- Spec path
- Task completion counts
- Proof artifact file list
- Result: `completed`, `blocked`, or `error`

#### 5e. Update Issue State

Based on pipeline result:

| Result | Actions |
|--------|---------|
| **completed** | Remove `agent-working` label. Move issue to "Done" status. |
| **blocked** | Remove `agent-working`, add `agent-blocked`. Issue stays in current status. |
| **error** | Remove `agent-working`, add `agent-blocked`. Post error details in comment. |

#### 5f. Log Heartbeat

Append to `.claude-workflow/heartbeat-log.jsonl`:

```bash
echo '{"timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","heartbeat_number":'$HB_NUM',"issue_id":"'$ISSUE_ID'","issue_title":"'$ISSUE_TITLE'","duration_seconds":'$DURATION',"result":"'$RESULT'","commits":['$COMMIT_LIST'],"spec_path":"'$SPEC_PATH'"}' >> .claude-workflow/heartbeat-log.jsonl
```

### Step 6: Cleanup

Remove the lockfile:
```bash
rm -f .claude-workflow/heartbeat.lock
```

### Step 7: Summary

Output a heartbeat summary:

```
CW-HEARTBEAT COMPLETE
━━━━━━━━━━━━━━━━━━━━━

Processed: {N} issue(s)
  ENG-123  Add search endpoint       completed  (5m 40s)
  ENG-124  Fix pagination bug        blocked    (1m 05s — Gate C failed)

Next eligible issues: {M} in queue
```

## Error Handling

If any pipeline stage fails unexpectedly:

1. Catch the error
2. Post an error comment to the Linear issue with the failure details
3. Apply `agent-blocked` label, remove `agent-working`
4. Log the error to heartbeat-log.jsonl with `"result": "error"`
5. Clean up the lockfile
6. Continue to the next issue (don't abort the entire heartbeat)

## Integration with Existing Workflows

The heartbeat is **additive** — it does not replace any existing cw functionality:

- All `/cw-*` commands work exactly as before without Linear
- The heartbeat just provides an automated front-door that feeds Linear issues into the same pipeline
- Issues processed by heartbeat produce the same specs, task graphs, proof artifacts, and commits as manual workflow
- You can mix heartbeat-driven and manual work in the same project
