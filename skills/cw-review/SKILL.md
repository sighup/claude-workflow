---
name: cw-review
description: "Reviews implementation code for bugs, security issues, and quality problems. Creates FIX tasks for issues found. This skill should be used after cw-validate to catch issues before merge."
user-invocable: true
allowed-tools: Glob, Grep, Read, Write, Bash, Task, TaskCreate, TaskUpdate, TaskList, TaskGet, AskUserQuestion, LSP
effort: medium
---

# CW-Review: Code Review Orchestrator

## Context Marker

Always begin your response with: **CW-REVIEW**

## Overview

You are the **Code Review Orchestrator** in the Claude Workflow system. For small diffs you review inline; for larger diffs you partition changed files into batches and spawn parallel reviewer sub-agents. In both cases you create actionable FIX tasks for anything that needs correction. You are the last quality gate before a PR is created.

## Your Role

You are a **Senior Staff Engineer** conducting a thorough code review. You:
- Assess diff size to choose inline review or parallel sub-agents
- Review files directly (small diffs) or consolidate findings from sub-agents (large diffs)
- Create FIX tasks for blocking issues
- Produce a structured review report

## Critical Constraints

- **NEVER** modify implementation code - you are read-only
- **NEVER** create FIX tasks for stylistic preferences or nitpicks
- **NEVER** review test code for correctness (tests are the oracle)
- **ALWAYS** reference specific files and line numbers in findings
- **ALWAYS** distinguish severity levels (blocking vs advisory)
- **ALWAYS** check for security issues (OWASP top 10, credential leaks)
- **ONLY** create FIX tasks for issues that would block a merge

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
3. **Load repository standards**: Check shared memory first (see memory-read below); fall back to README.md, CONTRIBUTING.md, CLAUDE.md, lint configs, tsconfig, etc. only when shared memory is absent or stale
4. **Read task board**: Understand what was implemented and the intended scope

```bash
# Overview of all changes (note the total lines changed from the summary line)
git diff main...HEAD --stat

# Commit history on this branch
git log main...HEAD --oneline
```

**Early exit**: If `git diff main...HEAD --stat` shows no changes, report "No changes to review" and exit.

#### Memory Read

Before loading standards from source files, check for cached memory:

1. Read `.claude/agent-memory/shared/MEMORY.md` if it exists — use the cached `Repository Standards` section to skip re-reading README/CONTRIBUTING/CLAUDE.md
2. Read `.claude/agent-memory/reviewer/MEMORY.md` if it exists — load prior severity classifications and common issue patterns
3. Read `.claude/agent-memory/reviewer/severity-map.md` if it exists — apply accumulated severity heuristics when classifying new findings
4. Read `.claude/agent-memory/reviewer/common-issues.md` if it exists — reference known patterns when evaluating files of the same type

If no memory files exist, proceed with standard standards discovery (README/CONTRIBUTING/CLAUDE.md). Treat all memory as hints — verify repository standards that appear stale or inconsistent with current project files.

#### LSP Availability Check

After loading context and before choosing the review path, probe whether an LSP server is available. Pick one of the changed non-test files and attempt a single `documentSymbol` operation:

```
LSP({
  operation: "documentSymbol",
  filePath: "{changed non-test source file}",
  line: 1,
  character: 1
})
```

- **LSP available**: The operation returned symbols. Set `lsp_available = true`.
- **LSP unavailable**: The operation returned an error. Set `lsp_available = false`.

**Capture the total diff line count** from the `--stat` summary line (e.g. "10 files changed, 185 insertions(+), 42 deletions(-)"). Add insertions + deletions = total diff lines. This determines the review path.

### Step 2: Choose Review Path

Get the list of all changed non-test files:

```bash
# List changed files, excluding test files
git diff main...HEAD --name-only | grep -v -E '(\.test\.|\.spec\.|__tests__|test/|tests/)'
```

**If total diff lines ≤ 200** → **Inline review** (Step 2a)
**If total diff lines > 200** → **Parallel review** (Steps 2b–2d)

### Step 2a: Inline Review (small diffs)

Review all changed non-test files directly. For each file:

1. Read the full file: `Read({ file_path: "<path>" })`
2. Get its diff: `git diff main...HEAD -- <path>`
3. Evaluate against categories A–D (see [review-categories.md](references/review-categories.md))
4. When `lsp_available = true`, use LSP to deepen the review:
   - `findReferences` to check if changes have ripple effects beyond the diff (e.g., callers of a modified function that now need updating)
   - `incomingCalls` to understand the impact of modified functions on their consumers
5. Record findings

After reviewing all files, skip to **Step 3: Create FIX Tasks**.

### Step 2b: Partition Files into Batches (large diffs)

Group files into batches:
- Group by directory where possible (related files reviewed together)
- Maximum **8 files** per batch
- Maximum **3 batches** (extra files go into the last batch)
- Exclude test files (tests are the oracle, not reviewed for correctness)

Create a `REVIEW-BATCH:` task per batch with metadata:

```
TaskCreate({
  subject: "REVIEW-BATCH: [directory or description] ([N] files)",
  description: "Review batch for code review. Files assigned in metadata.",
  activeForm: "Reviewing batch"
})
```

Then set metadata on each batch task:

```
TaskUpdate({
  taskId: "<batch-task-id>",
  metadata: {
    task_type: "review-batch",
    assigned_files: ["path/to/file1.ts", "path/to/file2.ts"],
    spec_path: "<path-to-spec or null>",
    standards_summary: "<brief summary of repo conventions>",
    base_branch: "main"
  }
})
```

### Step 2c: Spawn Reviewer Sub-Agents

Send a **single message** with multiple Task tool calls for parallel execution. Spawn up to 3 reviewers.

```
Task({
  subagent_type: "claude-workflow:reviewer",
  description: "Review batch [N]",
  prompt: "Review assigned files. Task ID: [batch-task-id]. Read protocol at: skills/cw-review/references/reviewer-protocol.md"
})
```

Repeat for each batch in a single message for parallel execution.

### Step 2d: Consolidate Findings

After all reviewers complete:

1. **Collect findings**: `TaskGet` each review-batch task to read findings from metadata
2. **Check for failures**: If a batch task is not completed or has no `findings` in metadata, record those files as **unreviewed** (do not attempt to review them inline)
3. **Flatten**: Merge all findings arrays into one list
4. **Deduplicate**: Remove findings with the same file + overlapping line range
5. **Sort**: Order by severity — B (Security) first, then A (Correctness), C (Spec Compliance), D (Quality)

Mark each review-batch task as completed (cleanup):

```
TaskUpdate({
  taskId: "<batch-task-id>",
  status: "completed"
})
```

### Step 3: Create FIX Tasks

This step is the same for both inline and parallel review paths.

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

### Step 4: Generate Review Report

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

## Blocking Issues

### [ISSUE-1] [Category A/B/C]: [Title]
- **File**: `path/to/file.ts:42`
- **Severity**: Blocking
- **Description**: [What is wrong]
- **Fix**: [What to do]
- **Task**: FIX-REVIEW-[id]

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

### Step 4b: Write Review Intelligence Memory

After saving the review report, write accumulated intelligence to `.claude/agent-memory/reviewer/` so future reviews benefit from patterns discovered in this run.

**Create directories if absent:**

```bash
mkdir -p .claude/agent-memory/reviewer
```

**Write or update `.claude/agent-memory/reviewer/MEMORY.md`** — index file with a summary of accumulated intelligence. Append new entries; never overwrite prior content:

```markdown
---
cached_at: {ISO timestamp}
---

# Reviewer Memory

## Repository Standards

- cached_at: {ISO timestamp}
- summary: {1-2 sentences on coding style, commit format, PR conventions discovered in this review}
- details: .claude/agent-memory/shared/repository-standards.md (if shared memory exists)

## Severity Map

- cached_at: {ISO timestamp}
- details: severity-map.md

## Common Issues

- cached_at: {ISO timestamp}
- details: common-issues.md
```

**Write or update `.claude/agent-memory/reviewer/severity-map.md`** — append new severity classification examples from this review. Each example includes the category (A/B/C/D), a description of the pattern, and whether it is blocking or advisory:

```markdown
---
cached_at: {ISO timestamp}
---

# Severity Map

## Blocking Patterns

- category: {A|B|C}
  pattern: {description of the issue type}
  example: {brief, generalized description — no specific task or file details}
  cached_at: {ISO timestamp}

## Advisory Patterns

- category: D
  pattern: {description of the issue type}
  example: {brief, generalized description}
  cached_at: {ISO timestamp}
```

**Write or update `.claude/agent-memory/reviewer/common-issues.md`** — append new issue patterns grouped by file type. Only add patterns that appeared in this review and are not already present:

```markdown
---
cached_at: {ISO timestamp}
---

# Common Issues by File Type

## .{ext} files

- pattern: {generalized description of the issue}
  severity: blocking|advisory
  category: {A|B|C|D}
  cached_at: {ISO timestamp}
```

**Memory-write rules:**

- Write only generalized patterns and heuristics — never individual findings, specific file paths, task IDs, or author details
- Append new entries to existing files; never delete or overwrite prior intelligence
- Include `cached_at` timestamps on every new entry
- Never write credentials, API keys, tokens, or verbatim code snippets to memory files

### Step 5: Output Summary

**CRITICAL**: Always output a summary so the caller can relay results.

```
CW-REVIEW COMPLETE
===================
Overall: APPROVED | CHANGES REQUESTED

Blocking Issues: X
  A (Correctness): Y
  B (Security): Z
  C (Spec Compliance): W
Advisory Notes: X

FIX Tasks Created: [task IDs or "none"]

[If CHANGES REQUESTED: List each blocking issue on one line]

Report saved: [path to review report]
```

## Error Handling

| Scenario | Action |
|----------|--------|
| No diff (branch matches main) | Report "No changes to review" and exit |
| Cannot find spec | Review without spec compliance checks, note in report |
| Git commands fail | Report error, suggest manual review |
| Sub-agent failure | List unreviewed files in report, let user decide (re-run or manual review) |
| Too many files (>24) | Cap at 3 batches of 8, prioritize new files and security-sensitive paths |

## What Comes Next

After review, prompt the user with context-sensitive options based on the review outcome.

### When CHANGES REQUESTED (blocking issues found)

```
AskUserQuestion({
  questions: [{
    question: "Code review complete — changes requested. What would you like to do next?",
    header: "Next Step",
    options: [
      { label: "Execute fixes (Recommended)", description: "Run /cw-dispatch to execute the FIX-REVIEW tasks" },
      { label: "Re-run /cw-testing", description: "Re-run tests to check for regressions before fixing" },
      { label: "Create PR", description: "Proceed to pull request creation without fixing" },
      { label: "Done for now", description: "Review the report and decide later" }
    ],
    multiSelect: false
  }]
})
```

### When APPROVED (no blocking issues)

```
AskUserQuestion({
  questions: [{
    question: "Code review complete — approved. What would you like to do next?",
    header: "Next Step",
    options: [
      { label: "Create PR (Recommended)", description: "Proceed to pull request creation" },
      { label: "Re-run /cw-testing", description: "Re-run tests to confirm nothing regressed" },
      { label: "Run /cw-validate", description: "Verify coverage against spec and run validation gates" },
      { label: "Done for now", description: "Review the report and decide later" }
    ],
    multiSelect: false
  }]
})
```

### Based on user selection

- **Execute fixes**: Invoke `/cw-dispatch` to process FIX-REVIEW tasks
- **Re-run /cw-testing**: Invoke the skill directly: `Skill({ skill: "cw-testing", args: "run" })`
- **Run /cw-validate**: Invoke the skill directly: `Skill({ skill: "cw-validate" })`
- **Create PR**: Summarize changes and suggest PR title/body
- **Done for now**: Summarize what was found and exit
