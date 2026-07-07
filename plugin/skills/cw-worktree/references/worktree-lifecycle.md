# Worktree Lifecycle Reference

## Overview

This document describes the states and transitions of worktrees throughout the feature development lifecycle.

## Worktree States

```
┌─────────────┐
│   CREATED   │  Initial state after /cw-worktree create
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  PLANNING   │  /cw-plan running in worktree session
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ DEVELOPING  │  /cw-dispatch executing tasks
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ VALIDATING  │  /cw-validate checking implementation
└──────┬──────┘
       │
       ├──────────────┐
       ▼              ▼
┌─────────────┐ ┌─────────────┐
│   READY     │ │   BLOCKED   │  Validation failed
└──────┬──────┘ └──────┬──────┘
       │               │
       │               └──→ (return to DEVELOPING)
       ▼
┌─────────────┐
│   MERGED    │  /cw-worktree merge completed
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  CLEANED    │  Worktree and branch removed
└─────────────┘
```

## State Descriptions

### CREATED

The worktree has been created but development hasn't started.

**Characteristics:**
- Directory exists at `.claude/worktrees/{type}-{repo}-{slug}/` (e.g. `.claude/worktrees/fix-myrepo-login/`)
- Branch `{type}/{slug}` created and checked out (e.g. `fix/login`)
- Dependencies installed
- Baseline tests passing
- No feature-specific commits yet

**Transitions:**
- → PLANNING: When `/cw-plan` is invoked in the worktree session

### PLANNING

Task planning is in progress for the spec.

**Characteristics:**
- `/cw-plan` has been invoked
- Tasks are being created on the native task board
- No implementation work yet

**Transitions:**
- → DEVELOPING: When `/cw-dispatch` is invoked

### DEVELOPING

Active implementation work is happening.

**Characteristics:**
- One or more tasks are in progress
- Workers are executing via `/cw-execute`
- Commits being made to the feature branch

**Transitions:**
- → VALIDATING: When all tasks complete and `/cw-validate` is invoked

### VALIDATING

The implementation is being validated against the spec.

**Characteristics:**
- All tasks marked complete on task board
- `/cw-validate` running the 6-gate validation

**Transitions:**
- → READY: Validation passes all gates
- → BLOCKED: Validation fails one or more gates

### BLOCKED

Validation failed; issues need resolution.

**Characteristics:**
- One or more validation gates failed
- Issues documented in validation report
- Feature cannot be merged until resolved

**Transitions:**
- → DEVELOPING: When fixes are applied and `/cw-dispatch` re-run

### READY

Feature is complete and validated; ready for merge.

**Characteristics:**
- All validation gates passed
- Coverage matrix complete
- No uncommitted changes
- All tests passing

**Transitions:**
- → MERGED: When `/cw-worktree merge` completes successfully

### MERGED

Feature branch has been merged to main.

**Characteristics:**
- Merge commit exists on main
- Feature branch still exists (until cleanup)
- Worktree directory still exists (until cleanup)

**Transitions:**
- → CLEANED: When cleanup is performed (automatic or manual)

### CLEANED

Worktree and branch have been removed.

**Characteristics:**
- Worktree directory deleted
- Feature branch deleted
- Only the merge commit on main remains

**Terminal state.**

## Determining Current State

Use `/cw-worktree status <feature-name>` to see:

```bash
# Check for commits on branch (branch name is {type}/{slug}, e.g. fix/login)
# Resolve the worktree path via git (matches both .claude/worktrees/ and legacy .worktrees/)
WT=$(git worktree list --porcelain | awk '/^worktree /{sub(/^worktree /,""); print}' \
  | grep -E "/(\.claude/worktrees|\.worktrees)/" \
  | while IFS= read -r _wt; do _b=$(basename "$_wt"); case "$_b" in ("$FEATURE"|*-"$FEATURE") printf '%s\n' "$_wt"; break;; esac; done)
BRANCH=$(cd "$WT" && git branch --show-current)
COMMITS=$(git log main..${BRANCH} --oneline | wc -l)

# Check for task board activity (in worktree session)
# Use TaskList to see pending/completed tasks

# Check for validation report
ls docs/specs/*-spec-*/validation-report.md

# Check if merged
git branch --merged main | grep "${BRANCH}"
```

## State Indicators in `/cw-worktree list`

```
ACTIVE WORKTREES
================
PATH                                      BRANCH              STATE           STATUS
----------------------------------------- ------------------- --------------- ------------------
.claude/worktrees/fix-myrepo-login        fix/login           READY           5 commits, clean
.claude/worktrees/feature-myrepo-auth     feature/auth        DEVELOPING      2 commits, modified
.claude/worktrees/feature-myrepo-search   feature/search      CREATED         0 commits, clean
```

> **Legacy worktrees:** Worktrees with the old `feature-*` naming (e.g. `.worktrees/feature-auth`) continue to appear here. The list command is prefix-agnostic and matches all registered worktrees by value.

## Session Identification

Worktree sessions are automatically assigned a title derived from the task-list ID when the session starts or resumes. This behavior is consistent across all worktree entry points.

### Auto-Titling on Startup/Resume

When you open a Claude Code session in a worktree via any of these methods:
- `cw-herdr-open` (CLI command to open in a herdr pane)
- `/cw-worktree create` (creating a new worktree)
- Plain `cd <worktree-path> && claude` (starting a session in the worktree directory)

The **SessionStart hook** (registered in `.claude-plugin/plugin.json` with matcher `startup|resume`) automatically sets the session title to the resolved task-list ID. This occurs only when:
- The session is being started (not resumed with an existing title)
- The source is `startup` or `resume` (not programmatic)
- No `session_title` was already set on the session input

**Example:** If your worktree has a task-list ID of `task-list-abc123`, the session title will be automatically set to `task-list-abc123` on startup.

### Explicit Session Title Takes Precedence

If you provide an explicit session title via either method:
- `--name <title>` flag when starting the session
- `/rename <new-title>` slash command during the session

The hook will **never overwrite** these explicit values. Once set, an explicit session title persists across session restarts and takes full precedence over the auto-titling behavior.

**Example:** `claude --name my-session` in a worktree will set the title to `my-session`, and the SessionStart hook will leave it unchanged on subsequent resumes.

## Persistence

**What persists between sessions:**
- Git commits on the feature branch
- Files in the worktree directory
- Spec documents in `docs/specs/`
- Proof artifacts in `docs/specs/*-proofs/`

**What does NOT persist (unless configured):**
- Task board — session-scoped by default, but persists via `~/.claude/tasks/{task-list-id}/` when `CLAUDE_CODE_TASK_LIST_ID` is set (see `/cw-plan` Step 0)
- In-progress state markers
- Worker assignments

When resuming work in a worktree:
1. Open terminal in worktree directory
2. Start new Claude Code session
3. `/cw-plan` will re-create tasks from the spec (or continue if tasks exist)
4. `/cw-dispatch` will find unblocked tasks

## Handling Interruptions

### Session Closed During DEVELOPING

1. Re-open worktree session
2. Check `git status` for uncommitted work
3. Either commit WIP or stash
4. Run `/cw-dispatch` to continue

### Session Closed During VALIDATING

1. Re-open worktree session
2. Run `/cw-validate` again
3. It will re-run all validation gates

### Merge Interrupted

1. Return to project root
2. Check `git status` for merge state
3. Either complete merge or abort: `git merge --abort`
4. Re-run `/cw-worktree merge <feature-name>`

## Concurrent Worktrees

Multiple worktrees can exist in different states simultaneously:

```
.claude/worktrees/fix-myrepo-login        → READY (waiting for merge)
.claude/worktrees/feature-myrepo-auth     → DEVELOPING (3 tasks in progress)
.claude/worktrees/feature-myrepo-search   → VALIDATING (running validation)
```

**Important:** Each worktree has its own:
- Working directory
- Branch
- Claude Code session
- Task board (session-scoped by default; persistent when `CLAUDE_CODE_TASK_LIST_ID` is configured)

**Shared across worktrees:**
- Git history (via refs)
- Spec documents (once committed)
- Main branch updates (via rebase/merge)

## Best Practices

1. **One spec per worktree** - Keep features isolated
2. **Complete before starting new** - Avoid too many parallel worktrees
3. **Merge frequently** - Don't let worktrees diverge too far from main
4. **Clean up promptly** - Remove merged worktrees to reduce clutter
5. **Rebase before merge** - Keep history clean
