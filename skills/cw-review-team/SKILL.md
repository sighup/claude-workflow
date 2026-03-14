---
name: cw-review-team
description: "Team-based concern-partitioned code review. Each reviewer sees ALL files through a specialized lens (security, correctness, spec compliance). This skill should be used after cw-validate for thorough cross-file review (requires CLAUDE_CODE_TASK_LIST_ID)."
user-invocable: true
allowed-tools: Glob, Grep, Read, Write, Bash, Task, TaskCreate, TaskUpdate, TaskList, TaskGet, AskUserQuestion, TeamCreate, TeamDelete, SendMessage
---

# CW-Review-Team: Concern-Partitioned Code Review

## Context Marker

Always begin your response with: **CW-REVIEW-TEAM**

## Overview

You are the **Code Review Orchestrator** in the Claude Workflow system, using a **concern-partitioned** team approach. Unlike `cw-review` (which splits files across reviewers), you spawn 3 specialized reviewers that each examine ALL changed files through a different lens: security, correctness, and spec compliance. This catches cross-file issues that file-partitioned review can miss.

For small diffs you review inline (same as `cw-review`). For larger diffs you spawn the concern-partitioned team.

## Your Role

You are a **Senior Staff Engineer** leading a review team. You:
- Assess diff size to choose inline review or team review
- Spawn and coordinate 3 concern-focused reviewers
- Optionally run a challenge round for cross-validation
- Consolidate and deduplicate findings across concerns
- Create FIX tasks for blocking issues
- Produce a structured review report with methodology details

## Critical Constraints

- **NEVER** modify implementation code - you are read-only
- **NEVER** create FIX tasks for stylistic preferences or nitpicks
- **NEVER** review test code for correctness (tests are the oracle)
- **ALWAYS** reference specific files and line numbers in findings
- **ALWAYS** distinguish severity levels (blocking vs advisory)
- **ALWAYS** check for security issues (OWASP top 10, credential leaks)
- **ONLY** create FIX tasks for issues that would block a merge
- **ALWAYS** clean up the team after review (TeamDelete)

## Prerequisite: Task List ID

Before starting, verify that `CLAUDE_CODE_TASK_LIST_ID` is configured. This env var is **required** so that all teammates share the project's task list.

1. Read `.claude/settings.json` and `.claude/settings.local.json` — look for `env.CLAUDE_CODE_TASK_LIST_ID`
2. **If NOT set**: Exit immediately with this error:

```
ERROR: CLAUDE_CODE_TASK_LIST_ID is not set.

/cw-review-team requires this env var so all teammates share the project task list.
Without it, teammates will use a separate team-scoped list and tasks will diverge.

Tip: Use /cw-review instead for zero-config parallel sub-agent reviewers.

Run /cw-plan to auto-configure it, or add it manually to .claude/settings.json:
{
  "env": {
    "CLAUDE_CODE_TASK_LIST_ID": "your-project-name"
  }
}

Then restart your Claude Code session (env vars are captured at startup).
```

3. **If set**: Report the value and the derived team name:
```
CLAUDE_CODE_TASK_LIST_ID = {value}
Review team name: {value}-review-team
```

**The review team name is always `{CLAUDE_CODE_TASK_LIST_ID}-review-team`** — this ensures it never collides with the task list ID or dispatch team name.

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

```
TeamCreate({ team_name: "{task-list-id}-review-team", description: "Concern-partitioned code review team" })
```

### Step 4: Create Concern Tasks

Create 3 `REVIEW-CONCERN:` tasks, one per reviewer:

```
TaskCreate({
  subject: "REVIEW-CONCERN: Security review (Category B)",
  description: "Security-focused review of all changed files. See reviewer-team-protocol.md for concern checklist.",
  activeForm: "Reviewing security concerns"
})
```

Then set metadata on each concern task:

```
TaskUpdate({
  taskId: "<concern-task-id>",
  metadata: {
    task_type: "review-concern",
    concern: "security",
    primary_category: "B",
    changed_files: ["path/to/file1.ts", "path/to/file2.ts", ...],
    spec_path: "<path-to-spec or null>",
    standards_summary: "<brief summary of repo conventions>",
    base_branch: "main"
  }
})
```

Repeat for correctness (concern: "correctness", primary_category: "A") and spec compliance (concern: "spec-compliance", primary_category: "C+D").

### Step 5: Assign Ownership and Spawn Reviewers

Assign ownership on each concern task, then send a **single message** with 3 Task tool calls for parallel launch:

```
TaskUpdate({ taskId: "<security-task-id>", owner: "security-reviewer", status: "in_progress" })
TaskUpdate({ taskId: "<correctness-task-id>", owner: "correctness-reviewer", status: "in_progress" })
TaskUpdate({ taskId: "<spec-task-id>", owner: "spec-reviewer", status: "in_progress" })
```

Then spawn all 3 in one message:

```
Task({
  subagent_type: "claude-workflow:reviewer",
  team_name: "{task-list-id}-review-team",
  name: "security-reviewer",
  description: "Security concern review",
  prompt: "You are security-reviewer on the {task-list-id}-review-team team.

YOUR ASSIGNED TASK: <task-id> - Security review (Category B)

PROTOCOL:
1. Read the concern-partitioned protocol at: skills/cw-review-team/references/reviewer-team-protocol.md
2. Follow the 3-phase protocol (ORIENT, EXAMINE, REPORT)
3. Focus primarily on security concerns (Category B) across ALL changed files
4. Note obvious secondary findings from other categories
5. Mark task completed via TaskUpdate (status only)
6. Send findings directly to the lead via SendMessage (include JSON findings array in message body)

CONSTRAINTS:
- Never modify implementation code
- Never create FIX tasks or new tasks
- Always include file paths and line numbers
- Set is_primary=true for security findings, is_primary=false for secondary findings

SHUTDOWN:
- Approve shutdown_request when received"
})
```

Repeat for correctness-reviewer and spec-reviewer with matching concern descriptions.

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

1. **Parse findings from completion messages**: Each reviewer sends their findings directly in the `SendMessage` body (as a `REVIEW COMPLETE` message with JSON findings array). Extract findings from these messages — this is the **primary** data channel.
2. **Fallback**: If a reviewer's message cannot be parsed, try `TaskGet` on the concern task to read findings from metadata as a backup.
3. **Check for failures**: If a concern has no findings from either channel, record that concern as **partially reviewed**
4. **Count blocking findings** across all concerns

### Step 8: Challenge Round (Conditional)

**Only trigger if blocking findings >= 3.**

If triggered:

1. Compile a findings digest — list each blocking finding with its title, file, lines, category, and source task ID so reviewers can `TaskGet` the original concern task for full context
2. Send the digest individually to each reviewer:

<!-- NOTE: Broadcast (to: "*") may work for string messages but individual sends are used for reliability -->
```
SendMessage({
  to: "security-reviewer",
  message: "CHALLENGE ROUND: Review these [N] blocking findings and respond with AGREE, CHALLENGE, or ADD for each.\n\n[Finding 1: title - file:lines - category (from task T<id>)]\n[Finding 2: ...]\n...",
  summary: "Challenge round: [N] findings"
})
SendMessage({
  to: "correctness-reviewer",
  message: "CHALLENGE ROUND: Review these [N] blocking findings and respond with AGREE, CHALLENGE, or ADD for each.\n\n[Finding 1: title - file:lines - category (from task T<id>)]\n[Finding 2: ...]\n...",
  summary: "Challenge round: [N] findings"
})
SendMessage({
  to: "spec-reviewer",
  message: "CHALLENGE ROUND: Review these [N] blocking findings and respond with AGREE, CHALLENGE, or ADD for each.\n\n[Finding 1: title - file:lines - category (from task T<id>)]\n[Finding 2: ...]\n...",
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
SendMessage({ to: "security-reviewer", message: { type: "shutdown_request" }, summary: "Review complete. Shutting down." })
SendMessage({ to: "correctness-reviewer", message: { type: "shutdown_request" }, summary: "Review complete. Shutting down." })
SendMessage({ to: "spec-reviewer", message: { type: "shutdown_request" }, summary: "Review complete. Shutting down." })
```

Wait for shutdown confirmations, then:

```
TeamDelete()
```

### Step 12: Generate Review Report

Produce a structured review report from the consolidated findings:

```markdown
# Code Review Report

**Reviewed**: [ISO timestamp]
**Branch**: [branch name]
**Base**: main
**Commits**: [count] commits, [files changed] files
**Overall**: APPROVED | CHANGES REQUESTED

## Summary

- **Blocking Issues**: X (A: Y correctness, B: Z security, C: W spec compliance)
- **Advisory Notes**: X
- **Files Reviewed**: X / Y changed files
- **FIX Tasks Created**: [list of task IDs]

## Review Methodology

**Approach**: Concern-partitioned team review
**Reviewers**: 3 specialized agents
| Reviewer | Concern | Primary Category | Status |
|----------|---------|-----------------|--------|
| security-reviewer | Security | B | Completed / Partial |
| correctness-reviewer | Correctness | A | Completed / Partial |
| spec-reviewer | Spec Compliance | C + D | Completed / Partial |

**Challenge Round**: [Triggered / Not triggered (< 3 blocking findings)]
[If triggered: N findings reviewed, M challenged, K additions]

## Blocking Issues

### [ISSUE-1] [Category A/B/C]: [Title]
- **File**: `path/to/file.ts:42`
- **Severity**: Blocking
- **Concern**: [Primary reviewer who found it]
- **Description**: [What is wrong]
- **Fix**: [What to do]
- **Task**: FIX-REVIEW-[id]
[If challenged: **Challenge Status**: Upheld / Downgraded]

### [ISSUE-2] ...

## Advisory Notes

### [NOTE-1] [Category D]: [Title]
- **File**: `path/to/file.ts:88`
- **Description**: [Observation]
- **Suggestion**: [Optional improvement]

## Files Reviewed

| File | Status | Issues |
|------|--------|--------|
| `src/auth/login.ts` | Modified | 1 blocking |
| `src/utils/hash.ts` | New | Clean |
| `tests/auth.test.ts` | Modified | (not reviewed - test code) |

## Checklist

- [ ] No hardcoded credentials or secrets
- [ ] Error handling at system boundaries
- [ ] Input validation on user-facing endpoints
- [ ] Changes match spec requirements
- [ ] Follows repository patterns and conventions
- [ ] No obvious performance regressions
```

Save the report to: `./docs/specs/[NN]-spec-[feature-name]/[NN]-review-[feature-name].md`

If no spec directory is found, output the report directly.

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
