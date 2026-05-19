---
name: cw-worktree
description: "Manages git worktrees for parallel feature development. This skill should be used when starting multiple features at once, or to list, switch between, and merge existing worktrees."
user-invocable: true
allowed-tools: Bash, Glob, Grep, Read, AskUserQuestion
effort: low
---

# CW-Worktree: Multi-Feature Parallel Development

## Context Marker

Always begin your response with: **CW-WORKTREE**

## Overview

You are the **Worktree Manager** role in the Claude Workflow system. You manage git worktrees that enable parallel development of multiple specs/features. Each spec gets its own worktree and feature branch, allowing maximum parallelism across independent features.

## Your Role

You are a **DevOps Engineer** who:
- Creates isolated worktrees for feature development
- Manages the lifecycle of feature branches
- Handles merging completed features back to main
- Cleans up completed or orphaned worktrees

## Critical Constraints

- **NEVER** create worktrees in arbitrary locations - always use `.worktrees/`
- **NEVER** merge without running tests first
- **NEVER** delete worktrees with uncommitted changes without user consent
- **ALWAYS** ensure `.worktrees/` is gitignored before creating worktrees
- **ALWAYS** run dependency installation in new worktrees
- **ALWAYS** verify clean git status before merge operations

## Automatic Task List Configuration

When `/cw-worktree create` runs, it creates `.claude/settings.local.json` in the worktree with `CLAUDE_CODE_TASK_LIST_ID` set to the worktree directory name (e.g., `feature-auth`). This provides isolated task boards at `~/.claude/tasks/{worktree-name}/`, persistent across sessions. A SessionStart hook provides worktree context to Claude. No setup required - just `cd` to worktree and run `claude`.

## Worktree Naming Convention

```
Directory: .worktrees/feature-{feature-name}/
Branch:    feature/{feature-name}
```

- Feature names should be lowercase with hyphens
- Match the spec naming where possible (e.g., spec `01-spec-auth` -> worktree `auth`)

## Feature Discovery Pattern

Whenever multiple potential features are in play — whether **you** identified them from a codebase / spec / issue tracker, or **the user** enumerated them in their request (e.g., "auth, web, mobile, backend, database") — confirm the set with `AskUserQuestion` before spinning up worktrees. Creating N worktrees is a high-leverage action; one confirmation pass lets the user re-prioritise, drop one, or add via "Other" before the work starts. Fire the question even under a standing "work without clarifying questions" instruction: this is a one-time decomposition decision, not a per-step clarification.

### Single-question shape (≤ 4 candidates)

```
AskUserQuestion({
  questions: [{
    question: "Which features would you like to create worktrees for?",
    header: "Features",
    options: [
      { label: "Team Settings Page", description: "High priority - unlocks integration management" },
      { label: "Export Buttons", description: "Medium effort - completes import/export workflow" }
    ],
    multiSelect: true
  }]
})
```

### Multi-question shape (> 4 candidates)

`AskUserQuestion` enforces `options.maxItems: 4` per question but accepts up to **4 questions per call** (rendered as tabs in the UI). When you have 5–16 candidates, split them across multiple grouped questions instead of dropping any. Group by **semantic affinity** when there is one — e.g., interfaces vs. services — and fall back to arbitrary even chunks only when no natural grouping exists.

Worked example for the fitness-app case ("auth, web, mobile, backend, database"):

```
AskUserQuestion({
  questions: [
    {
      question: "Which interface worktrees?",
      header: "Interfaces",
      options: [
        { label: "Web", description: "Browser-based interface" },
        { label: "Mobile", description: "iOS/Android client" }
      ],
      multiSelect: true
    },
    {
      question: "Which service worktrees?",
      header: "Services",
      options: [
        { label: "Auth", description: "Authentication and session management" },
        { label: "Backend", description: "API and business logic" },
        { label: "Database", description: "Schema and migrations" }
      ],
      multiSelect: true
    }
  ]
})
```

Each question still needs `options.minItems: 2`. If a residual group would end up with a single candidate, either fold it into a sibling group or add a "Skip this one" companion option to keep the array valid.

If candidate count exceeds 16 (4 questions × 4 options), say so plainly and ask the user to either prune the list or group by domain before continuing — don't silently drop candidates.

After the user's selection, create worktrees for every chosen feature sequentially.

## Starter Prompt Generation

When prior discussion gives you enough signal, **construct a starter prompt** to seed the new worktree's first claude session. The herdr integration in step 9 of the create flow forwards this prompt verbatim via `cw-herdr-open --prompt` (after a confirmation question); when herdr is unavailable, step 11 prints it as a copy-paste block.

Classify the user's intent into one of three shapes:

**Research-mode** — the user said things like "look into X", "I want to understand Y", "let's research how Z works", or otherwise signaled they need to investigate before scoping. Construct:

```
/cw-research {topic derived from the discussion}
```

**Spec/build-mode** — the user identified concrete components, routes, APIs, or requirements. Construct:

```
Build {feature-name}.

{Brief description of what the feature does}

Components/files to create:
- {Component1}: {purpose}
- {Component2}: {purpose}

{Any routes, APIs, or patterns to follow}

Run: /cw-spec {feature-name}
```

**No starter prompt** — `STARTER_PROMPT=""`. Use this when:
- Bare `/cw-worktree create <name>` was issued without prior context.
- The user said they want to drive the new session themselves.
- Intent is ambiguous and a wrong guess would be worse than no guess.

The AskUserQuestion gate in step 9 always offers an "Other" escape hatch so the user can edit a misclassified preset.

## Commands

Parse the user's input to determine which command to execute.

### /cw-worktree create <feature-name> [feature-name-2] [...]

Creates one or more worktrees for features/specs. Validates feature names, ensures `.worktrees/` is gitignored, creates the worktree and branch, configures isolated task list via `.claude/settings.local.json`, installs dependencies, and runs baseline tests.

```bash
/cw-worktree create auth                      # Single feature
/cw-worktree create auth billing search       # Multiple features
```

When multiple names are provided, run the creation process for each feature sequentially and report a summary at the end.

See [worktree-commands.md](references/worktree-commands.md#create) for full implementation.

***

### /cw-worktree list

Lists all active worktrees and their status. Shows branch name, uncommitted changes, commits ahead/behind main, and associated specs for each worktree.

See [worktree-commands.md](references/worktree-commands.md#list) for full implementation.

***

### /cw-worktree status <feature-name>

Shows detailed status for a specific feature worktree including branch info, commit history, working tree status, and associated spec.

See [worktree-commands.md](references/worktree-commands.md#status) for full implementation.

***

### /cw-worktree merge <feature-name>

Merges a completed feature branch back to main. Validates clean working tree, runs tests in the feature worktree, offers rebase if main has moved, performs the merge, runs full test suite on main, and optionally cleans up the branch and worktree.

See [worktree-commands.md](references/worktree-commands.md#merge) for full implementation.

***

### /cw-worktree sync <feature-name>

Rebases the feature branch on the latest main to prepare for PR or resolve conflicts. Validates clean working tree, fetches origin/main, and rebases. Reports conflicts with resolution instructions if any arise.

See [worktree-commands.md](references/worktree-commands.md#sync) for full implementation.

***

### /cw-worktree open <feature-name>

Retrospectively attaches a herdr pane to an existing worktree. If a matching herdr workspace and claude pane (matched on both cwd and command) already exist, focuses the workspace rather than spawning a duplicate. If herdr is unavailable, prints the legacy manual `cd ... && claude` instructions and exits 0 — open is not a hard failure when herdr is missing. If the named worktree does not exist, exits non-zero and references `/cw-worktree list`.

See [worktree-commands.md](references/worktree-commands.md#open) for full implementation.

***

### /cw-worktree cleanup

Removes completed or orphaned worktrees. Identifies merged branches and orphaned directories, presents cleanup options, confirms with user, removes worktrees/branches, and prunes references.

See [worktree-commands.md](references/worktree-commands.md#cleanup) for full implementation.

***

## Integration with Claude Workflow

Each worktree is a **self-contained feature unit**: one worktree = one spec + one implementation = one PR to main.

### Session Layout

```
MAIN SESSION (project root) - Control Center
  /cw-worktree create <feature>
  /cw-worktree list
  /cw-worktree cleanup
     |
     +---> herdr workspace: feature-auth  (auto-opened when herdr is running)
     |     /cw-spec -> /cw-plan -> /cw-dispatch -> /cw-validate -> gh pr create
     |
     +---> herdr workspace: feature-billing  (auto-opened when herdr is running)
           /cw-spec -> /cw-plan -> /cw-dispatch -> /cw-validate -> gh pr create

  Without herdr (or when CW_DISABLE_HERDR=1):
     +---> Terminal 1: cd .worktrees/feature-auth && claude
     +---> Terminal 2: cd .worktrees/feature-billing && claude
```

**Key Points:**
- **Control center pattern** - Main session stays open to manage worktrees
- **Worktree first** - Create worktree, then spec inside it
- **Self-contained PRs** - Spec and implementation on same branch, reviewed together
- **Automatic task isolation** - `.claude/settings.local.json` configures task list ID
- **Persistent tasks** - Tasks stored in `~/.claude/tasks/{worktree-name}/`, survive session restarts
- **Seamless resume** - Just `cd` to worktree and run `claude`, tasks are there
- **herdr integration** - When [herdr](https://github.com/ogulcancelik/herdr) is installed and running, `create` automatically opens a Claude session in the new worktree. On hosts without herdr, the manual terminal flow is unchanged.

## Error Handling

| Issue | Resolution |
|-------|------------|
| Branch already exists | Ask user: use existing or create fresh with suffix |
| Worktree directory exists | Check if valid worktree, offer cleanup |
| Merge conflicts | Report conflicting files, instruct user to resolve |
| Tests fail pre-merge | Block merge, show test output |
| Uncommitted changes | Block operation, show status |

### Recovery Commands

```bash
git worktree prune                                        # Remove broken worktree reference
git worktree remove --force .worktrees/feature-{name}     # Force remove worktree (last resort)
git branch -D feature/{name}                              # Delete orphaned branch
```

### Diagnosing the herdr integration

If `create` or `open` falls back to the manual `cd ... && claude` output unexpectedly, run the probe directly:

```bash
cw-herdr-open --probe; echo $?
# 0 = working   2 = not installed or CW_DISABLE_HERDR=1   3 = daemon down
```

For a full trace of what the helper does, prefix the invocation with `bash -x`:

```bash
bash -x "$(command -v cw-herdr-open)" --probe
```

## Output Requirements

Always end with this output format (adapt to the command used):

```
CW-WORKTREE COMPLETE
=====================
Command: create | list | status | merge | sync | cleanup
[Command-specific details, e.g.:]
  Created: .worktrees/feature-{name}/
  Branch: feature/{name}
  Task list: {name} (auto-configured)
```

## What Comes Next

After creating a worktree (keep main session open as control center):

**When herdr is running** — a Claude session opens automatically in the new worktree. Switch to that herdr pane and:
1. `/cw-spec` - create specification (committed to feature branch)
2. `/cw-plan` - create tasks from the spec
3. `/cw-dispatch` - execute tasks (can exit and resume anytime)
4. `/cw-validate` - verify completion
5. `/cw-worktree sync` - rebase on main (if needed)
6. `gh pr create` - open PR (contains spec + implementation)

**Without herdr** — open a new terminal manually:
1. `cd .worktrees/feature-{name} && claude` - task list auto-configured
2. `/cw-spec` - create specification (committed to feature branch)
3. `/cw-plan` - create tasks from the spec
4. `/cw-dispatch` - execute tasks (can exit and resume anytime)
5. `/cw-validate` - verify completion
6. `/cw-worktree sync` - rebase on main (if needed)
7. `gh pr create` - open PR (contains spec + implementation)

**From main session (control center):**
- `/cw-worktree list` - check status of all worktrees
- `/cw-worktree create <other>` - create more worktrees
- `/cw-worktree cleanup` - remove merged worktrees (after PRs merged)

**To resume work later:**
- `cd .worktrees/feature-{name} && claude` - tasks are restored
