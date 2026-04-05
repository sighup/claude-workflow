---
name: cw-heartbeat
description: "Phase-aware dispatcher that pulls issues from Linear and drives them through the cw lifecycle. Decomposes parent issues into Linear sub-issues, executes each in isolated worktrees, and reports results back. Each heartbeat cycle detects an issue's current phase and runs only that phase."
user-invocable: true
allowed-tools: Bash, Read, Write, Glob, Grep, Skill, AskUserQuestion, TaskList, TaskGet, TaskUpdate, TaskCreate
effort: high
---

# CW-Heartbeat: Linear Lifecycle Dispatcher

## Context Marker

Always begin your response with: **CW-HEARTBEAT**

## Overview

You are the **Heartbeat** — the phase-aware dispatcher that bridges Linear and the claude-workflow pipeline. Each heartbeat cycle:

1. Queries Linear for actionable issues (parent issues and sub-issues)
2. Determines each issue's current phase from status + labels
3. Runs **one phase** per issue per cycle
4. Reports results back to Linear

You do NOT write code yourself — you delegate to cw skills and bin scripts.

## Architecture

The heartbeat operates on a **two-tier decomposition**:

- **Parent issues** go through: Research → Spec → Decompose into sub-issues
- **Sub-issues** (marked with `cw-managed` label) go through: Plan → Execute → Validate → Review → Test → Done
- When all sub-issues are Done, **Linear auto-completes the parent issue**

**Every phase runs in a subprocess** via bin scripts, keeping each phase's context window clean. The heartbeat skill is a pure routing layer — it reads config, queries Linear, detects phases, dispatches to bin scripts, and posts results. It never accumulates research content, spec text, or codebase exploration in its own context.

```
/cw-heartbeat (this skill — routing layer only)
│
├── Query Linear, detect phases         (lightweight — labels + status only)
│
├── Parent issue phases: delegate to bin scripts with fresh sessions
│   ├── RESEARCH  → Bash("cw-heartbeat-phase --phase research ...")
│   ├── SPEC      → Bash("cw-heartbeat-phase --phase spec ...")
│   └── DECOMPOSE → cw-linear-sync CREATE_SUB_ISSUES
│
├── Sub-issue phases: delegate to bin script with worktree isolation
│   └── EXECUTE → Bash("cw-heartbeat-execute ...")
│       └── Creates worktree, runs plan→dispatch→validate→review→test
│
└── Parent completion: Linear auto-completes when all sub-issues Done
    └── Optional VALIDATE → Bash("cw-heartbeat-phase --phase validate ...")
```

Each `Bash(...)` call launches a fresh Claude process. The heartbeat skill's context stays minimal (config + queue + phase routing), avoiding context window pressure even when processing many issues.

## Critical Constraints

- **NEVER** process an issue with `agent-working` label (unless the lock is stale)
- **NEVER** skip the lockfile — it prevents concurrent heartbeats
- **NEVER** modify code directly — always delegate to cw skills or bin scripts
- **NEVER** run multiple phases for the same issue in one heartbeat cycle
- **ALWAYS** remove `agent-working` label when a phase completes (success or failure)
- **ALWAYS** log each heartbeat to `.claude-workflow/heartbeat-log.jsonl`
- **ALWAYS** check quiet hours before processing
- **ALWAYS** post a structured comment to Linear after each phase

## Arguments

- `--dry-run` — Show the queue and detected phases without executing
- `--issue <ID>` — Process a specific issue by ID (skip queue selection)
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

Parse: `linear.team`, `linear.user_name`, `heartbeat.*`, `labels.*`, `pipeline.*`.

### Step 2: Check Quiet Hours

If `heartbeat.quiet_hours.enabled` is true, check if current time is within the quiet window. If so, report and exit:
```
Quiet hours active ({start} - {end}). Skipping heartbeat.
```

### Step 3: Acquire Lock

Check `.claude-workflow/heartbeat.lock`:
- If exists and not stale (< `stale_lock_hours`): exit — another heartbeat is running
- If exists and stale: clear it with a warning
- Create lockfile with PID and timestamp

```bash
mkdir -p .claude-workflow
echo '{"pid": '$$', "started_at": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' > .claude-workflow/heartbeat.lock
```

### Step 4: Query Linear

Invoke cw-linear-sync with operation `QUERY_QUEUE` to get the prioritized issue list:

```
Task({
  subagent_type: "claude-workflow:spec-writer",
  description: "Query Linear queue",
  prompt: "Read protocol at: skills/cw-linear-sync/SKILL.md. Execute operation QUERY_QUEUE with team={team} user_name={user_name}."
})
```

Parse the result to get the list of parent issues and sub-issues with their detected phases.

**Dry-run mode**: If `--dry-run`, display the queue with phases and exit:
```
Dry run — actionable issues:

  Parent issues:
    ENG-100  [High]   JWT Authentication         phase: SPEC
    ENG-200  [Medium] Search redesign            phase: RESEARCH

  Sub-issues:
    ENG-456  [High]   Add login endpoint         phase: EXECUTE  (parent: ENG-100)
    ENG-457  [Medium] Add token refresh          phase: EXECUTE  (parent: ENG-100)

Max per heartbeat: 2
```

### Step 5: Phase Detection

For each issue, determine the phase using labels and status:

```
determine_phase(issue):
  if is_parent_issue (not has_label("cw-managed")):
    if has_label("needs-research") and not has_label("ready-for-spec"):
      → RESEARCH
    if has_label("ready-for-spec") or (status == "Todo" and not has_label("spec-complete")):
      → SPEC
    if has_label("spec-complete"):
      → WAITING (sub-issues in progress; Linear auto-completes parent when all done)
    else:
      → SKIP

  if is_sub_issue (has_label("cw-managed")):
    if status == "Todo":
      → EXECUTE
    if status == "In Progress":
      → EXECUTE (resume)
    else:
      → SKIP
```

### Step 6: Process Issues

Process up to `max_issues_per_heartbeat` actionable issues. For each:

#### 6a. Lock the Issue

Apply `agent-working` label via cw-linear-sync `UPDATE_LABELS`.

#### 6b. Execute Phase

Route to the appropriate handler:

---

**RESEARCH Phase** (parent issue, fresh subprocess):

```
Bash("cw-heartbeat-phase \
  --phase research \
  --issue-id {ISSUE_ID} \
  --title '{ISSUE_TITLE}' \
  --model {model}")
```

The bin script:
1. Invokes `claude --print` with a prompt to run cw-research non-interactively
2. Returns JSON: `{"result": "completed", "report_path": "docs/specs/research-.../..."}`

Then the heartbeat skill (still in its lightweight context):
3. Posts research summary as a comment on the parent issue (reads the report file)
4. Updates labels: remove `needs-research`, add `ready-for-spec`

---

**SPEC Phase** (parent issue, fresh subprocess):

```
Bash("cw-heartbeat-phase \
  --phase spec \
  --issue-id {ISSUE_ID} \
  --title '{ISSUE_TITLE}' \
  --description '{ISSUE_DESCRIPTION}' \
  --model {model}")
```

The bin script:
1. Checks for existing research report in `docs/specs/research-*/`
2. Invokes `claude --print` with a prompt to run cw-spec non-interactively (issue context inlined, skip clarifying questions and review)
3. Locates the generated spec file
4. Returns JSON: `{"result": "completed", "spec_path": "docs/specs/01-spec-.../...", "unit_count": 3}`

Then the heartbeat skill:
5. Creates Linear sub-issues from the spec via cw-linear-sync `CREATE_SUB_ISSUES`
6. Posts spec summary + sub-issue list as a comment on the parent issue
7. Updates labels: add `spec-complete`, remove `ready-for-spec` if present

---

**EXECUTE Phase** (sub-issue, delegates to bin script):

1. Fetch sub-issue context via cw-linear-sync `GET_ISSUE_CONTEXT`
2. Determine the feature name and unit slug from the issue hierarchy
3. Locate the spec file (from the parent issue's spec or from the sub-issue description)
4. Determine which demoable unit number this sub-issue corresponds to
5. Build pipeline flags from config:
   ```bash
   FLAGS=""
   if [ "$auto_review" = "true" ]; then FLAGS="$FLAGS --review"; fi
   if [ "$auto_testing" = "true" ]; then FLAGS="$FLAGS --testing"; fi
   if [ "$auto_pr" = "true" ]; then FLAGS="$FLAGS --pr"; fi
   ```
6. Execute via bin script:
   ```
   Bash("cw-heartbeat-execute \
     --feature {feature_slug} \
     --unit-slug {unit_slug} \
     --spec {spec_path} \
     --unit {unit_number} \
     --model {model} \
     $FLAGS")
   ```
7. Parse the JSON result from stdout
8. Based on result:
   - **completed**: Post success comment with commits + proof links, move sub-issue to Done
   - **blocked**: Post failure comment with gate details, add `agent-blocked` label
   - **error**: Post error comment, add `agent-blocked` label

---

**PARENT_VALIDATE Phase** (optional, fresh subprocess):

Linear auto-completes parent issues when all sub-issues are Done. This optional phase runs cross-unit validation when `pipeline.parent_review` is true:

1. Verify all sub-issues are Done via cw-linear-sync `CHECK_CHILDREN_STATUS`
2. If not all done, skip — still WAITING
3. Run validation in a subprocess:
   ```
   Bash("cw-heartbeat-phase \
     --phase validate \
     --issue-id {ISSUE_ID} \
     --spec {spec_path} \
     --parent-review {true|false} \
     --model {model}")
   ```
   The bin script runs cw-validate (and optionally cw-review-team if `parent_review` is true) on the full diff across all sub-issue branches.
4. Post validation summary as a comment on the parent issue

---

#### 6c. Unlock the Issue

Remove `agent-working` label.

#### 6d. Log Heartbeat

Append to `.claude-workflow/heartbeat-log.jsonl`:

```json
{
  "timestamp": "2026-04-05T10:30:00Z",
  "issue_id": "ENG-456",
  "issue_title": "Add login endpoint",
  "phase": "EXECUTE",
  "duration_seconds": 340,
  "result": "completed",
  "commits": ["abc1234"],
  "spec_path": "docs/specs/01-spec-auth/01-spec-auth.md"
}
```

### Step 7: Cleanup

Remove the lockfile:
```bash
rm -f .claude-workflow/heartbeat.lock
```

### Step 8: Summary

Output a heartbeat summary:

```
CW-HEARTBEAT COMPLETE
━━━━━━━━━━━━━━━━━━━━━

Processed: {N} issue(s)
  ENG-100  JWT Authentication        SPEC      completed  (2m 15s)
  ENG-456  Add login endpoint        EXECUTE   completed  (5m 40s)

Waiting:
  ENG-200  Search redesign           RESEARCH  (next cycle)
  ENG-457  Add token refresh         EXECUTE   (next cycle)
```

## Error Handling

If any phase fails unexpectedly:

1. Catch the error
2. Post an error comment to the Linear issue with failure details
3. Apply `agent-blocked` label, remove `agent-working`
4. Log the error to heartbeat-log.jsonl with `"result": "error"`
5. Clean up the lockfile
6. Continue to the next issue (don't abort the entire heartbeat)

## Integration with Existing Workflows

The heartbeat is **additive** — it does not replace any existing cw functionality:

- All `/cw-*` commands work exactly as before without Linear
- The heartbeat provides an automated front-door feeding Linear issues into the same pipeline
- Issues processed by heartbeat produce the same specs, task graphs, proof artifacts, and commits
- You can mix heartbeat-driven and manual work in the same project
- The `cw-heartbeat-execute` bin script can also be run standalone for debugging
