---
name: cw-review-team
description: "Thorough concern-partitioned code review with cross-validation. Requires CLAUDE_CODE_TASK_LIST_ID. This skill should be used after cw-validate when deeper review is needed — spawns persistent team reviewers with factual grounding and challenge rounds."
user-invocable: true
allowed-tools: Glob, Grep, Read, Write, Bash, Task, TaskCreate, TaskUpdate, TaskList, TaskGet, AskUserQuestion, TeamCreate, TeamDelete, SendMessage
---

# CW-Review-Team: Concern-Partitioned Code Review

## Context Marker

Always begin your response with: **CW-REVIEW-TEAM**

## Overview

You are the **Code Review Orchestrator** in the Claude Workflow system, using a **concern-partitioned** team approach. You spawn 5-6 specialized persistent team members that each examine ALL changed files through a different lens: bugs, security, cross-file impact, tests, conventions, and optionally type design. After collecting findings, you run factual grounding to verify claims, an optional challenge round for cross-validation, and contradiction resolution to handle agent disagreements.

For small diffs you review inline (same as `cw-review`). For larger diffs you spawn the concern-partitioned team.

## Your Role

You are a **Senior Staff Engineer** leading a review team. You:
- Assess diff size to choose inline review or team review
- Spawn and coordinate 5-6 concern-focused reviewers
- Run factual grounding on blocking findings (deterministic verification before LLM judgment)
- Optionally run a challenge round for cross-validation (3+ blocking findings)
- Resolve contradictions between agents (spec suppresses bugs, security wins ties)
- Consolidate and deduplicate findings across concerns
- Create FIX tasks for blocking issues with confidence above threshold
- Produce a structured review report with detailed methodology

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

### Orphaned Team Recovery

Before starting a new review, check if a review team from a previous session is still active:

```bash
ls ~/.claude/teams/{task-list-id}-review-team/config.json 2>/dev/null
```

If the team config exists, a previous review session was interrupted. Recover:

1. Check if any `REVIEW-CONCERN:` tasks have findings in metadata — those results are still valid
2. Send shutdown requests to any teammates that may still be alive (they will reject if already dead — that's fine)
3. Run `TeamDelete()` to clean up the orphaned team
4. Report to the user: "Cleaned up orphaned review team from previous session. [N] concern results recovered, [M] concerns incomplete."
5. Ask whether to proceed with a fresh review or use the recovered findings

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

**Capture the total diff line count** from the `--stat` summary line. Add insertions + deletions = total diff lines.

#### Type Detection

Check whether new types are introduced:

```bash
git diff main...HEAD -- '*.ts' '*.tsx' '*.js' '*.jsx' '*.py' '*.go' '*.java' '*.rs' | grep -E '^\+.*(interface |type |class |enum |abstract |struct )' | head -5
```

If results, set `has_new_types = true` (6 concerns). Otherwise `has_new_types = false` (5 concerns).

### Step 2: Choose Review Path

Get the list of all changed non-test files:

```bash
git diff main...HEAD --name-only | grep -v -E '(\.test\.|\.spec\.|__tests__|test/|tests/)'
```

**If total diff lines <= 200** -> **Inline review** (Step 2a)
**If total diff lines > 200** -> **Team review** (Steps 3-12)

### Step 2a: Inline Review (small diffs)

Review all changed non-test files directly. Read `../cw-review/references/review-categories.md` for category definitions. For each file:

1. Read the full file: `Read({ file_path: "<path>" })`
2. Get its diff: `git diff main...HEAD -- <path>`
3. Evaluate against categories A-D. Focus on correctness (A) and security (B) — these are blocking. For deeper investigation on a specific concern, read the corresponding reference file on demand:
   - `../cw-review/references/bug-detector.md` — only if you spot a suspicious correctness/error handling pattern
   - `../cw-review/references/security-reviewer.md` — only if you spot a potential security issue
   - `../cw-review/references/cross-file-impact.md` — only if changed functions have public callers
4. Record findings. Apply confidence thresholds: security >= 70, all others >= 80

After reviewing all files, skip to **Step 10: Create FIX Tasks**.

### Step 3: Create Team

Determine the lead name for teammate messaging (this is the current session — teammates will message back to this name):

```bash
# The lead name is used by teammates for SendMessage addressing
lead_name="lead"  # or derive from session context
```

```
TeamCreate({ team_name: "{task-list-id}-review-team", description: "Concern-partitioned code review team" })
```

### Step 4: Create Concern Tasks

Create a `REVIEW-CONCERN:` task for each reviewer. See `../cw-review/references/fix-task-template.md` for the full concern roster and model assignments. All agents receive the full list of changed non-test files.

For each concern (5 always-on + type-design if `has_new_types = true`), create the task and set metadata in sequence:

```
TaskCreate({
  subject: "REVIEW-CONCERN: {concern} ({focus})",
  description: "Concern-specialized review of all changed files. See references/{concern}.md for methodology.",
  activeForm: "Reviewing {concern} concerns"
})

TaskUpdate({
  taskId: "<concern-task-id>",
  status: "in_progress",
  metadata: {
    task_type: "review-concern",
    concern: "{concern}",
    changed_files: ["path/to/file1.ts", "path/to/file2.ts", ...],
    spec_path: "<path-to-spec or null>",
    standards_summary: "<brief summary of repo conventions>",
    base_branch: "main"
  }
})
```

### Step 5: Spawn Reviewers

Send a **single message** with 5-6 Task tool calls for parallel launch. Teammates load the `agents/reviewer.md` definition automatically (including protocol, tool usage, and constraints). The spawn prompt provides task-specific context the agent definition cannot know.

```
Task({
  subagent_type: "claude-workflow:reviewer",
  team_name: "{task-list-id}-review-team",
  model: "opus",
  name: "bug-detector",
  description: "Bug detector review",
  prompt: "Your assigned task ID: {task-id}.
Lead name for SendMessage: {lead_name}.
Reviewing branch: {branch} against {base_branch}.
Changed files: {count} non-test files.
Spec: {spec_path or 'none'}.
Focus: correctness bugs and error handling defects (Category A)."
})
```

Model assignments:
- **opus**: bug-detector, security-reviewer, cross-file-impact
- **sonnet**: test-analyzer, spec-and-conventions, type-design

Repeat for each concern in a single message for parallel execution. Adjust the "Focus:" line to match each concern's domain.

### Step 6: Monitor Loop

Messages from teammates are auto-delivered. Track reviewer completion:

**On review completion message from reviewer:**
1. Note the reviewer as done
2. If all reviewers complete: proceed to Step 7

**On error/blocker from reviewer:**
1. Log the error
2. Mark that concern as "partially reviewed" in the final report
3. If majority of reviewers complete, proceed (do not wait indefinitely)

### Step 7: Collect Findings

After all reviewers complete (or timeout):

1. **Collect findings**: `TaskGet` each concern task to read findings from metadata
2. **Check for failures**: If a concern task is not completed or has no `findings` in metadata, record that concern as **partially reviewed**
3. **Count blocking findings** across all concern tasks

### Step 8: Factual Grounding

For each **blocking** finding (categories A, B, C), the lead runs inline verification:

1. **File verification**: Read the cited `file` at `line_start`-`line_end`. Confirm the code matches the finding's `description` and `evidence`.
2. **Cross-reference check**: For findings with `cross_file_refs`, verify those files exist and contain the described patterns (use Grep or Read).
3. **CLAUDE.md rule check**: For findings with `claude_md_rule`, verify the quoted rule actually exists in CLAUDE.md/REVIEW.md.

**Disposition:**
- Finding's factual claims are verified -> set `validation_status: "verified"`
- Finding's factual claims are wrong (wrong line, function doesn't exist, code doesn't match) -> set `validation_status: "failed"`, downgrade to advisory
- Finding has no factual claims to verify -> set `validation_status: "skipped"`

### Step 9: Challenge Round (Conditional)

**Only trigger if verified blocking findings >= 3.**

If triggered:

1. Compile a findings digest — list each blocking finding with its `id`, `title`, `file`, `line_start`-`line_end`, `dimension`, `confidence`, and `evidence` summary
2. Broadcast the digest to all reviewers. Note: broadcast sends to all teammates simultaneously — costs scale with team size, but this is a single broadcast per review so it's acceptable:

```
SendMessage({
  to: "all",
  content: "CHALLENGE ROUND: Review these [N] blocking findings and respond with AGREE, CHALLENGE, or ADD for each.\n\n[Finding 1: id - title - file:lines - dimension - confidence]\n[Finding 2: ...]\n...",
  summary: "Challenge round: [N] findings"
})
```

3. Messages from teammates are auto-delivered — do not poll. Collect responses from all reviewers.
4. Process responses:
   - **AGREE**: Increases confidence (no change)
   - **CHALLENGE**: If 2+ reviewers challenge a finding, downgrade from blocking to advisory. If finding has `validation_status: "verified"`, require 3+ CHALLENGEs to downgrade (the lead already verified it).
   - **ADD**: Add the new finding to the list with proper categorization. ADD findings must pass the confidence threshold.

### Step 9.5: Contradiction Resolution

After challenge round (or after factual grounding if no challenge round), resolve contradictions:

- If **spec-and-conventions** confirms code is intentional per documented specs, but **bug-detector** flags the same code as a bug -> **suppress** the bug finding (documented intent wins)
- If **security-reviewer** flags something that another agent considers safe -> **escalate** the security finding (security wins ties)
- If **test-analyzer** flags missing tests for code that **spec-and-conventions** identifies as generated/scaffolding code -> **suppress** the test finding

Note all contradictions and their resolutions in the methodology section of the report.

### Step 9.6: Final Consolidation

1. **Flatten + Filter + Deduplicate + Sort**: Follow the consolidation rules in `../cw-review/references/fix-task-template.md`
2. **Apply challenge results**: Downgrade challenged findings, add new findings from ADD responses

Mark each concern task as completed (cleanup):

```
TaskUpdate({ taskId: "<concern-task-id>", status: "completed" })
```

### Step 10: Create FIX Tasks

Follow the FIX task creation template in `../cw-review/references/fix-task-template.md`. For each blocking finding that meets the threshold criteria and has `validation_status != "failed"`, create a FIX-REVIEW task with the standard metadata format required by cw-execute.

### Step 11: Shutdown Team and Cleanup

Send shutdown requests to each teammate. Teammates can approve (exit gracefully) or reject with an explanation if mid-work.

```
SendMessage({ to: "bug-detector", content: "shutdown_request: Review complete." })
SendMessage({ to: "security-reviewer", content: "shutdown_request: Review complete." })
SendMessage({ to: "cross-file-impact", content: "shutdown_request: Review complete." })
SendMessage({ to: "test-analyzer", content: "shutdown_request: Review complete." })
SendMessage({ to: "spec-and-conventions", content: "shutdown_request: Review complete." })
[If type-design was spawned:]
SendMessage({ to: "type-design", content: "shutdown_request: Review complete." })
```

Wait for shutdown confirmations (auto-delivered), then clean up:

```
TeamDelete()
```

**Important**: Always clean up via TeamDelete from the lead. Never let teammates run cleanup — their team context may not resolve correctly.

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
**Team**: {task-list-id}-review-team

| Concern | Model | Status | Findings | Blocking |
|---------|-------|--------|----------|----------|
| bug-detector | opus | Completed / Partial / Failed | N | M |
| security-reviewer | opus | Completed / Partial / Failed | N | M |
| cross-file-impact | opus | Completed / Partial / Failed | N | M |
| test-analyzer | sonnet | Completed / Partial / Failed | N | M |
| spec-and-conventions | sonnet | Completed / Partial / Failed | N | M |
| type-design | sonnet | Completed / Skipped (no new types) | N | M |

**Factual Grounding**: [N] findings verified, [M] failed verification (downgraded), [K] skipped
**Confidence Thresholds**: security >= 70, all others >= 80
**Findings filtered**: [N] below threshold

**Challenge Round**: [Triggered / Not triggered (< 3 verified blocking findings)]
[If triggered: N findings reviewed, M challenged, K additions, L downgrades]

**Contradictions Resolved**: [list or "none"]

## Blocking Issues

### [ISSUE-1] [Category A/B/C]: [Title]
- **File**: `path/to/file.ts:42`
- **Dimension**: [bug/security/cross-file-impact/conventions/intent-alignment]
- **Confidence**: [0-100]
- **Validation**: [Verified / Skipped]
- **Concern**: [Primary reviewer who found it]
- **Severity**: Blocking
- **Description**: [What is wrong]
- **Evidence**: [Specific code or context]
- **Fix**: [What to do]
- **Task**: FIX-REVIEW-[id]
[If challenged: **Challenge Status**: Upheld / Downgraded]

### [ISSUE-2] ...

## Advisory Notes

### [NOTE-1] [Category D]: [Title]
- **File**: `path/to/file.ts:88`
- **Dimension**: [test-coverage/type-design/comments]
- **Confidence**: [0-100]
- **Description**: [Observation]
- **Suggestion**: [Optional improvement]

## Files Reviewed

| File | Status | Issues |
|------|--------|--------|
| `src/auth/login.ts` | Modified | 1 blocking |
| `src/utils/hash.ts` | New | Clean |
| `tests/auth.test.ts` | Modified | (not reviewed - test code) |
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

Concerns: [list of concerns that ran]
Factual Grounding: [N verified, M failed, K skipped]
Challenge Round: [Triggered / Not triggered]
Contradictions: [N resolved]

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
| Critical concern fails (security/bugs) | Warn: "The {concern} agent failed. The {dimension} dimension was not fully covered." |
| TeamCreate fails | Fall back to inline review with a note in the report |
| TeamDelete fails | Log warning, report to user, proceed with results |
| Lead session interrupted | On next invocation, orphaned team recovery runs automatically (see Mandatory First Action). Completed findings are preserved in task metadata and lead inbox. |

## What Comes Next

After review:
- **APPROVED**: Implementation ready for PR creation or final validation
- **CHANGES REQUESTED**: Execute FIX tasks, then re-review
