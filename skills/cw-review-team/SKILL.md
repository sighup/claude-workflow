---
name: cw-review-team
description: "Team-based concern-partitioned code review. Each reviewer sees ALL files through a specialized lens (security, correctness, spec compliance). This skill should be used after cw-validate for thorough cross-file review (requires CLAUDE_CODE_TASK_LIST_ID)."
user-invocable: true
allowed-tools: Glob, Grep, Read, Write, Bash, Task, TaskCreate, TaskUpdate, TaskList, TaskGet, AskUserQuestion, TeamCreate, TeamDelete, SendMessage
effort: medium
---

# CW-Review-Team: Concern-Partitioned Code Review

## Context Marker

Always begin your response with: **CW-REVIEW-TEAM**

## Overview

Concern-partitioned code review: spawn 3 specialized reviewers that each examine ALL changed files through a different lens (security, correctness, spec compliance). Unlike `cw-review` (file-partitioned), this catches cross-file issues. For small diffs (≤200 line change) review inline; for larger diffs spawn the team.

## Constraints

- **NEVER** modify implementation code — you are read-only
- **NEVER** create FIX tasks for stylistic nitpicks
- **NEVER** review test code for correctness (tests are the oracle)
- **ALWAYS** reference specific files and line numbers in findings
- **ALWAYS** check for security issues (OWASP top 10, credential leaks)
- **ALWAYS** clean up the team after review (TeamDelete)

## Prerequisite: Task List ID

Verify `CLAUDE_CODE_TASK_LIST_ID` is set in `.claude/settings.json` or `settings.local.json` so all teammates share one task list. If missing, **exit immediately** with this message and suggest the user run `/cw-plan` to auto-configure or use `/cw-review` instead (which has no env-var requirement). Env vars are captured at session startup, so the user must restart Claude Code after setting it.

The review team name is always `{CLAUDE_CODE_TASK_LIST_ID}-review-team` — never collides with the task list ID or dispatch team name.

## MANDATORY FIRST ACTION

**Call TaskList() immediately to understand the current task board state.**

```
TaskList()
```

Then determine the base branch for diff comparison:

```bash
git branch --show-current
git log --oneline -5
```

## Process

### Step 1: Gather Context

1. **Identify the spec**: Auto-discover in `docs/specs/` or accept user-provided path
2. **Get the diff**: `git diff main...HEAD --stat` for overview
3. **Load repository standards**: Check README.md, CONTRIBUTING.md, CLAUDE.md, lint configs, tsconfig, etc.
4. **Read task board**: Understand what was implemented and the intended scope

```bash
# Overview of all changes (note the total lines changed from the summary line)
git diff main...HEAD --stat

# Commit history on this branch
git log main...HEAD --oneline
```

**Early exit**: If `git diff main...HEAD --stat` shows no changes, report "No changes to review" and exit.

**Capture the total diff line count** from the `--stat` summary line (e.g. "10 files changed, 185 insertions(+), 42 deletions(-)"). Add insertions + deletions = total diff lines. This determines the review path.

### Step 2: Choose Review Path

Get the list of all changed non-test files:

```bash
# List changed files, excluding test files
git diff main...HEAD --name-only | grep -v -E '(\.test\.|\.spec\.|__tests__|test/|tests/)'
```

**If total diff lines <= 200** -> **Inline review** (Step 2a)
**If total diff lines > 200** -> **Team review** (Steps 3-9)

### Step 2a: Inline Review (small diffs)

Review all changed non-test files directly. For each file:

1. Read the full file: `Read({ file_path: "<path>" })`
2. Get its diff: `git diff main...HEAD -- <path>`
3. Evaluate against categories A-D (see [review-categories.md](../cw-review/references/review-categories.md))
4. Record findings

After reviewing all files, skip to **Step 10: Create FIX Tasks**.

### Step 3: Create Team

`TeamCreate({ team_name: "{task-list-id}-review-team", description: "Concern-partitioned code review team" })`

### Step 4: Create Concern Tasks

Create 3 `REVIEW-CONCERN:` tasks (security/correctness/spec-compliance) and populate their metadata. Templates and concern → category mapping in [team-setup.md](references/team-setup.md#create-concern-tasks).

### Step 5: Assign Ownership and Spawn Reviewers

Assign ownership on each concern task, then spawn all 3 reviewers in a **single message** with 3 parallel `Task()` calls. See [team-setup.md](references/team-setup.md#spawn-reviewers) for the exact reviewer prompt template.

### Step 6: Monitor Loop

Messages from teammates are auto-delivered. Track reviewer completion:

**On review completion message from reviewer:**
1. Note the reviewer as done
2. If all 3 reviewers complete: proceed to Step 7

**On error/blocker from reviewer:**
1. Log the error
2. Mark that concern as "partially reviewed" in the final report
3. If 2+ reviewers complete, proceed (do not wait indefinitely)

### Step 7: Collect Findings

After all reviewers complete (or timeout):

1. **Collect findings**: `TaskGet` each concern task to read findings from metadata
2. **Check for failures**: If a concern task is not completed or has no `findings` in metadata, record that concern as **partially reviewed**
3. **Count blocking findings** across all concern tasks

### Step 8: Challenge Round (Conditional)

**Only trigger if blocking findings >= 3.**

If triggered:

1. Compile a findings digest — list each blocking finding with its title, file, lines, and category
2. Broadcast the digest to all reviewers:

```
SendMessage({
  type: "broadcast",
  content: "CHALLENGE ROUND: Review these [N] blocking findings and respond with AGREE, CHALLENGE, or ADD for each.\n\n[Finding 1: title - file:lines - category]\n[Finding 2: ...]\n...",
  summary: "Challenge round: [N] findings"
})
```

3. Collect responses from all 3 reviewers
4. Process responses:
   - **AGREE**: Increases confidence in finding (no change)
   - **CHALLENGE**: Re-evaluate the finding. If 2+ reviewers challenge, downgrade from blocking to advisory
   - **ADD**: Add the new finding to the consolidated list with proper categorization

### Step 9: Consolidate Findings

1. **Flatten**: Merge all findings arrays from all concern tasks into one list
2. **Deduplicate**: Remove findings with the same file + overlapping line range + same category
3. **Sort**: Order by severity — B (Security) first, then A (Correctness), C (Spec Compliance), D (Quality)
4. **Apply challenge results**: Downgrade challenged findings, add new findings from ADD responses

Mark each concern task as completed (cleanup):

```
TaskUpdate({ taskId: "<concern-task-id>", status: "completed" })
```

### Step 10: Create FIX Tasks

This step is the same for both inline and team review paths.

For each **blocking** finding (Categories A, B, C), create a FIX task:

```
TaskCreate({
  subject: "FIX-REVIEW: [concise description of the issue]",
  description: "## Issue\n\n[What is wrong]\n\n## Location\n\n- File: [path]\n- Line(s): [line numbers]\n- Function/Component: [name]\n\n## Expected\n\n[What the code should do]\n\n## Actual\n\n[What the code currently does]\n\n## Suggested Fix\n\n[Concrete fix suggestion]\n\n## Category\n\n[A: Correctness | B: Security | C: Spec Compliance]",
  activeForm: "Fixing review issue"
})
```

Set metadata on the fix task (includes fields required by cw-execute):

```
TaskUpdate({
  taskId: "<fix-task-id>",
  metadata: {
    task_type: "review-fix",
    category: "A|B|C",
    severity: "blocking",
    role: "implementer",
    file_path: "<path>",
    line_numbers: "<range>",
    scope: {
      files_to_modify: ["<path>"],
      patterns_to_follow: []
    },
    requirements: ["Fix: <description of what to fix>"],
    proof_artifacts: [{ type: "test", command: "npm test", expected: "pass" }],
    verification: { pre: "git diff", post: "npm test" },
    commit: { template: "fix: <description>" }
  }
})
```

### Step 11: Shutdown Team and Cleanup

```
SendMessage({ type: "shutdown_request", recipient: "security-reviewer", content: "Review complete. Shutting down." })
SendMessage({ type: "shutdown_request", recipient: "correctness-reviewer", content: "Review complete. Shutting down." })
SendMessage({ type: "shutdown_request", recipient: "spec-reviewer", content: "Review complete. Shutting down." })
```

Wait for shutdown confirmations, then:

```
TeamDelete()
```

### Step 12: Generate Review Report

Produce a structured review report from the consolidated findings, following the markdown template and field guidance in [review-report-template.md](references/review-report-template.md).

Save to: `./docs/specs/[NN]-spec-[feature-name]/[NN]-review-[feature-name].md`. If no spec directory is found, output the report directly.

### Step 13: Output Summary

**CRITICAL**: Always output a summary so the caller can relay results.

```
CW-REVIEW-TEAM COMPLETE
========================
Overall: APPROVED | CHANGES REQUESTED
Review team: {task-list-id}-review-team (cleaned up)

Blocking Issues: X
  A (Correctness): Y
  B (Security): Z
  C (Spec Compliance): W
Advisory Notes: X

Challenge Round: [Triggered / Not triggered]

FIX Tasks Created: [task IDs or "none"]

[If CHANGES REQUESTED: List each blocking issue on one line]

Report saved: [path to review report]
```

Then offer next steps:

```
AskUserQuestion({
  questions: [{
    question: "Code review complete. What would you like to do next?",
    header: "Next Step",
    options: [
      { label: "Execute fixes (Recommended)", description: "Run /cw-dispatch to execute the FIX-REVIEW tasks" },
      { label: "Run /cw-validate", description: "Verify coverage against spec and run validation gates" },
      { label: "Create PR", description: "Proceed to pull request creation" },
      { label: "Done for now", description: "Review the report and decide later" }
    ],
    multiSelect: false
  }]
})
```

Based on user selection:
- **Execute fixes**: Invoke `/cw-dispatch` to process FIX-REVIEW tasks
- **Run /cw-validate**: Invoke the skill directly: `Skill({ skill: "cw-validate" })`
- **Create PR**: Summarize changes and suggest PR title/body
- **Done for now**: Summarize what was found and exit

## Error Handling

| Scenario | Action |
|----------|--------|
| No diff (branch matches main) | Report "No changes to review" and exit |
| Cannot find spec | Review without spec compliance checks, note in report |
| Git commands fail | Report error, suggest manual review |
| Reviewer fails to complete | List concern as "partially reviewed" in report, proceed with available findings |
| TeamCreate fails | Fall back to inline review with a note in the report |
| TeamDelete fails | Log warning, report to user, proceed with results |
| Too many files (>50) | Proceed — each reviewer handles all files but may take longer |

## What Comes Next

After review:
- **APPROVED**: Implementation ready for PR creation or final validation
- **CHANGES REQUESTED**: Execute FIX tasks, then re-review
