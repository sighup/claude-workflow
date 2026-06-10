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

- **NEVER** create worktrees in arbitrary locations - always use `.claude/worktrees/`
- **NEVER** merge without running tests first
- **NEVER** delete worktrees with uncommitted changes without user consent
- **ALWAYS** ensure `.claude/worktrees/` is gitignored before creating worktrees
- **ALWAYS** run dependency installation in new worktrees
- **ALWAYS** verify clean git status before merge operations

## Automatic Task List Configuration

When `/cw-worktree create` runs, it creates `.claude/settings.local.json` in the worktree with `CLAUDE_CODE_TASK_LIST_ID` set to the worktree directory name (e.g., `feature-myrepo-auth` or `fix-myrepo-login`). This provides isolated task boards at `~/.claude/tasks/{worktree-name}/`, persistent across sessions. A SessionStart hook provides worktree context to Claude. No setup required - just `cd` to worktree and run `claude`.

## Worktree Naming Convention

```
Directory: .claude/worktrees/{type}-{repo}-{slug}/
Branch:    {type}/{slug}
```

Type is inferred from the leading keyword of the slug (first matching rule wins):
- `fix`, `bug`, `hotfix` → `fix`
- `research`, `spike`, `explore` → `research`
- `chore`, `refactor`, `docs`, `build`, `ci` → `chore`
- anything else → `feature`

The matching keyword and its separating hyphen are stripped from the slug. `{repo}` is the basename of the main worktree directory, sanitized to `[a-z0-9-]`.

Examples:
- slug `auth` → dir `feature-{repo}-auth`, branch `feature/auth`
- slug `fix-login` → dir `fix-{repo}-login`, branch `fix/login`
- slug `research-auth` → dir `research-{repo}-auth`, branch `research/auth`

The `CLAUDE_CODE_TASK_LIST_ID` written to `.claude/settings.local.json` equals the worktree directory basename (`{type}-{repo}-{slug}`).

The naming computation lives in `cw_worktree_names()` in `scripts/lib/cw-common.sh`; the `/cw-worktree create` protocol in `references/worktree-commands.md` step 1 mirrors that logic exactly.

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

When prior discussion gives you enough signal, **construct a starter prompt** to seed the new worktree's first claude session. After every feature has its `STARTER_PROMPT` (and, where applicable, `STARTER_PROMPT_GOAL`), the **Drive-Mode Selection** gate decides — once for the whole batch — what gets forwarded to each tab. When herdr is available the chosen prompt is forwarded via `cw-herdr-open --prompt`; when herdr is unavailable, step 11 prints it as a copy-paste block.

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

The Drive-Mode Selection gate always offers an "Other" escape hatch so the user can edit a misclassified preset before it is forwarded.

### Autonomous variant (`STARTER_PROMPT_GOAL`)

Whenever `STARTER_PROMPT` is non-empty, **also** construct an autonomous variant `STARTER_PROMPT_GOAL`. This wraps the same intent in a `/goal`-prefixed directive that drives the full pipeline end-to-end (cw-research → cw-spec → cw-plan → cw-dispatch → cw-validate → cw-review → cw-testing). The Drive-Mode Selection gate surfaces this as the autonomous option so the user can promote the whole batch to hands-off execution without restating the request. `/goal` is a semantic marker, not a registered slash command — the spawned claude session reads it as plain text and follows the structured steps.

**Template — when base mode is Research-mode** (no spec exists, greenfield or large-unknown task):

```
/goal Pipeline complete for `{feature-name}`: research done, spec committed, plan executed, all non-test tasks have status `completed` (verified via TaskList), `cw-validate` passes, `cw-review` has no blocking issues, and `cw-testing` is green.

Workflow (research → spec → plan → dispatch → validate → review → testing):
1. Invoke `cw-research` with the topic below. It saves a report under `docs/specs/research-*/` and appends a Meta-Prompt section ready for `cw-spec`.
2. Without pausing for review, extract the meta-prompt from the research report and invoke `cw-spec` with it.
3. Commit the spec and research artifacts (`git add docs/specs && git commit -m "spec: {feature-name}"`).
4. Invoke `cw-plan` against the spec to populate this worktree's task list.
5. Use `cw-dispatch` to advance ready tasks until non-test tasks are complete.
6. Invoke `cw-validate`, then `cw-review`, then `cw-testing`. Treat their findings as new FIX tasks on the board and keep dispatching until the goal condition holds.

Topic: {topic derived from the discussion — same text as Research-mode STARTER_PROMPT, minus the `/cw-research` prefix}

Stop and report if three consecutive turns make no progress on task transitions.
```

**Template — when base mode is Spec/build-mode** (concrete build directive, no research needed):

```
/goal Pipeline complete for `{feature-name}`: spec committed, plan executed, all non-test tasks have status `completed` (verified via TaskList), `cw-validate` passes, `cw-review` has no blocking issues, and `cw-testing` is green.

Workflow (spec → plan → dispatch → validate → review → testing):
1. Invoke `cw-spec` with the build directive below as input.
2. Commit the spec (`git add docs/specs && git commit -m "spec: {feature-name}"`).
3. Invoke `cw-plan` against the spec to populate this worktree's task list.
4. Use `cw-dispatch` to advance ready tasks until non-test tasks are complete.
5. Invoke `cw-validate`, then `cw-review`, then `cw-testing`. Treat their findings as new FIX tasks on the board and keep dispatching until the goal condition holds.

Build directive:
{STARTER_PROMPT body without the trailing `Run: /cw-spec` line}

Stop and report if three consecutive turns make no progress on task transitions.
```

When `STARTER_PROMPT=""`, leave `STARTER_PROMPT_GOAL=""` too — without a topic or build directive there is nothing concrete to drive the goal toward.

## Drive-Mode Selection

After feature discovery and starter-prompt classification — but **before any worktree is created** — present a **single** `AskUserQuestion` that establishes how the whole batch will be driven. Cache the answer as `DRIVE_MODE ∈ {starter, autonomous, empty, skip_herdr}`. Step 9 of the create flow reads `DRIVE_MODE` and forwards accordingly; there is no per-worktree confirmation.

Fire this question even under a standing "work without clarifying questions" instruction. It is a one-time, batch-level commitment, not a per-step clarification — same rationale as the feature-discovery question above.

The choice applies uniformly to every feature in the call. If a user wants to mix modes (e.g. autonomous for one, manual for another) they should split into separate `/cw-worktree create` invocations.

### When and what to ask

The available options collapse based on (a) whether **any** feature in the batch has a non-empty `STARTER_PROMPT` and (b) whether herdr is available (the once-per-invocation probe from worktree-commands.md `create` § per-invocation setup). The probe reports available **only when this session is running inside a herdr pane** (`HERDR_ENV` set); from a plain terminal it reports unavailable, so the herdr options never surface and the batch falls through to the manual flow.

| Any STARTER_PROMPT? | herdr available? | Options surfaced |
|---|---|---|
| Yes | Yes | starter (Recommended), autonomous, empty, skip herdr |
| Yes | No | starter (Recommended), autonomous — choice changes what gets printed in step 11 |
| No  | Yes | empty, skip herdr |
| No  | No  | **Skip the question.** Nothing to forward, nothing to open — fall through to legacy print. |

Drop the **autonomous** option when `STARTER_PROMPT_GOAL` is empty for every feature. If only one meaningful option remains after collapsing, skip the question and use that option as `DRIVE_MODE`.

### Question shape (full 4-option variant)

```
AskUserQuestion({
  questions: [{
    question: "How should the {N} worktree(s) be driven after creation?",
    header: "Drive mode",
    options: [
      { label: "Starter prompt (Recommended)",
        description: "Forward the classified /cw-spec or /cw-research kickoff to each tab; you steer from there",
        preview: "<STARTER_PROMPT verbatim for first feature; if N>1 add '\\n\\n…and similar for the other {N-1} worktree(s).'>" },
      { label: "Autonomous (/goal)",
        description: "Drive end-to-end through cw-spec → cw-plan → cw-dispatch → cw-validate → cw-review → cw-testing without further input",
        preview: "<STARTER_PROMPT_GOAL verbatim for first feature; if N>1 add '\\n\\n…and similar for the other {N-1} worktree(s).'>" },
      { label: "Empty session",
        description: "Open the herdr tab(s) with no auto-prompt" },
      { label: "Skip herdr",
        description: "Just create the worktree(s); start sessions manually with cd ... && claude" }
    ],
    multiSelect: false
  }]
})
```

Map the chosen label to `DRIVE_MODE`:

| Label | `DRIVE_MODE` | Step-9 behavior |
|---|---|---|
| Starter prompt (or **Other** with edited text) | `starter` | Forward `STARTER_PROMPT` via `cw-herdr-open --prompt` |
| Autonomous (/goal) | `autonomous` | Forward `STARTER_PROMPT_GOAL` via `cw-herdr-open --prompt` |
| Empty session | `empty` | Invoke `cw-herdr-open` without `--prompt` |
| Skip herdr | `skip_herdr` | Set `HERDR_EXIT=2`; do not invoke the helper. Step 11 prints the copy-paste block when a starter exists. |

When the user picks **Other** under "Starter prompt", treat the edited text as the new `STARTER_PROMPT` for all features in the batch — or, if it clearly only applies to one feature, ask a follow-up to choose. (Editing the autonomous variant is rare; treat its **Other** the same way.)

## Commands

Parse the user's input to determine which command to execute.

### /cw-worktree create <feature-name> [feature-name-2] [...]

Creates one or more worktrees for features/specs. Validates feature names, ensures `.claude/worktrees/` is gitignored, creates the worktree and branch under `.claude/worktrees/`, configures isolated task list via `.claude/settings.local.json`, installs dependencies, and runs baseline tests.

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

Retrospectively attaches a herdr tab to an existing worktree. The helper uses one workspace per repo and one tab per worktree; if a claude session is already running in the matching tab (cwd match), it focuses that workspace+tab rather than spawning a duplicate. If herdr is unavailable, prints the legacy manual `cd ... && claude` instructions and exits 0 — open is not a hard failure when herdr is missing. If the named worktree does not exist, exits non-zero and references `/cw-worktree list`.

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
     +---> herdr workspace: {repo-name}   (one per repo, reused across calls)
             |
             +-- tab: fix-myrepo-login      (auto-opened when herdr is running)
             |   /cw-spec -> /cw-plan -> /cw-dispatch -> /cw-validate -> gh pr create
             |
             +-- tab: feature-myrepo-auth   (auto-opened when herdr is running)
                 /cw-spec -> /cw-plan -> /cw-dispatch -> /cw-validate -> gh pr create

  Without herdr (or when CW_DISABLE_HERDR=1):
     +---> Terminal 1: cd .claude/worktrees/fix-myrepo-login && claude
     +---> Terminal 2: cd .claude/worktrees/feature-myrepo-auth && claude
```

**Key Points:**
- **Control center pattern** - Main session stays open to manage worktrees
- **Worktree first** - Create worktree, then spec inside it
- **Self-contained PRs** - Spec and implementation on same branch, reviewed together
- **Automatic task isolation** - `.claude/settings.local.json` configures task list ID
- **Persistent tasks** - Tasks stored in `~/.claude/tasks/{worktree-name}/`, survive session restarts
- **Seamless resume** - Just `cd` to worktree and run `claude`, tasks are there
- **herdr integration** - When [herdr](https://github.com/ogulcancelik/herdr) is installed, running, and **this session is inside a herdr pane**, `create` automatically opens a Claude session in the new worktree. From a plain terminal (not inside herdr) the manual terminal flow is used — a tab spawned in a detached herdr window would be invisible to you.

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
git worktree prune                                             # Remove broken worktree reference
git worktree remove --force .claude/worktrees/fix-myrepo-login  # Force remove worktree (last resort)
git branch -D fix/login                                        # Delete orphaned branch
```

### Diagnosing the herdr integration

If `create` or `open` falls back to the manual `cd ... && claude` output unexpectedly, run the probe directly:

```bash
cw-herdr-open --probe; echo $?
# 0 = working   2 = not installed, not inside herdr, or CW_DISABLE_HERDR=1   3 = daemon down
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
  Created: .claude/worktrees/{type}-{repo}-{slug}/
  Branch: {type}/{slug}
  Task list: {type}-{repo}-{slug} (auto-configured)
```

## What Comes Next

After creating a worktree (keep main session open as control center):

**When running inside herdr** — a Claude session opens automatically in the new worktree's tab (inside the repo's workspace). Switch to that tab and:
1. `/cw-spec` - create specification (committed to feature branch)
2. `/cw-plan` - create tasks from the spec
3. `/cw-dispatch` - execute tasks (can exit and resume anytime)
4. `/cw-validate` - verify completion
5. `/cw-worktree sync` - rebase on main (if needed)
6. `gh pr create` - open PR (contains spec + implementation)

**Without herdr** — open a new terminal manually:
1. `cd .claude/worktrees/fix-myrepo-login && claude` - task list auto-configured
2. `/cw-spec` - create specification (committed to fix branch)
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
- `cd .claude/worktrees/fix-myrepo-login && claude` - tasks are restored

> **Legacy worktrees:** Worktrees created before this naming scheme (e.g. `feature-auth`) are fully supported. Discovery, list, cleanup, and all subcommands match by value — the lookup is prefix-agnostic.
