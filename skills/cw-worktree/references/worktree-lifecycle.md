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
- Directory exists at `.worktrees/feature-{name}/`
- Branch `feature/{name}` created and checked out
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
# Check for commits on feature branch
COMMITS=$(git log main..feature/${FEATURE} --oneline | wc -l)

# Check for task board activity (in worktree session)
# Use TaskList to see pending/completed tasks

# Check for validation report
ls docs/specs/*-spec-*/validation-report.md

# Check if merged
git branch --merged main | grep "feature/${FEATURE}"
```

## State Indicators in `/cw-worktree list`

```
ACTIVE WORKTREES
================
PATH                          BRANCH              STATE           STATUS
----------------------------- ------------------- --------------- ------------------
.worktrees/feature-auth       feature/auth        READY           5 commits, clean
.worktrees/feature-billing    feature/billing     DEVELOPING      2 commits, modified
.worktrees/feature-search     feature/search      CREATED         0 commits, clean
```

## Persistence

**What persists between sessions:**
- Git commits on the feature branch
- Files in the worktree directory
- Spec documents in `docs/specs/`
- Proof artifacts in `docs/specs/*-proofs/`

**What does NOT persist:**
- Task board (session-scoped)
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
.worktrees/feature-auth     → READY (waiting for merge)
.worktrees/feature-billing  → DEVELOPING (3 tasks in progress)
.worktrees/feature-search   → VALIDATING (running validation)
```

**Important:** Each worktree has its own:
- Working directory
- Branch
- Claude Code session
- Task board (session-scoped)

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
