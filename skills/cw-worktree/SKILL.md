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

Shape the question by candidate count:

- **≤ 4 candidates** → one `AskUserQuestion` (multiSelect) listing each feature.
- **5–16 candidates** → split across up to 4 questions (the per-call max), grouped by semantic affinity (e.g. interfaces vs. services); each question needs ≥ 2 options. Don't drop any.
- **> 16 candidates** → say so plainly and ask the user to prune or group by domain first; never silently drop.

After selection, create worktrees for every chosen feature sequentially. Full `AskUserQuestion` JSON for both gates: **[references/interactive-gates.md](references/interactive-gates.md)**.

## Starter Prompt Generation

When prior discussion gives enough signal, **construct a starter prompt** to seed each new worktree's first claude session; the **Drive-Mode Selection** gate (below) then decides — once for the whole batch — what is forwarded. Classify intent into one of three shapes:

- **Research-mode** → `/cw-research {topic}` (user wants to investigate before scoping).
- **Spec/build-mode** → a `Build {feature}…` directive ending in `Run: /cw-spec {feature}` (concrete components/routes/APIs identified).
- **No starter prompt** → `STARTER_PROMPT=""` (bare create, user will self-drive, or ambiguous — a wrong guess is worse than none).

Whenever `STARTER_PROMPT` is non-empty, also construct an autonomous variant `STARTER_PROMPT_GOAL` — a `/goal`-prefixed directive that drives the whole pipeline hands-off (cw-spec → … → cw-testing), delivered as a committed `docs/specs/goal-<worktree>.md` file (≤ 4000 chars, authoring budget) and forwarded inline.

The full templates, the autonomous `/goal` variants, the 4000-char budget, and the file+inline delivery mechanics live in **[references/starter-prompts.md](references/starter-prompts.md)** — apply them during `create` (see worktree-commands.md step 9).

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

### Question shape

Present a **single-select** with the surfaced options (Starter prompt = Recommended; Autonomous (/goal); Empty session; Skip herdr), each option's `preview` showing the relevant `STARTER_PROMPT` / `STARTER_PROMPT_GOAL` for the first feature. Full JSON: **[references/interactive-gates.md](references/interactive-gates.md)**.

Map the chosen label to `DRIVE_MODE`:

| Label | `DRIVE_MODE` | Step-9 behavior |
|---|---|---|
| Starter prompt (or **Other** with edited text) | `starter` | Forward `STARTER_PROMPT` via `cw-herdr-open --prompt` |
| Autonomous (/goal) | `autonomous` | Write `docs/specs/goal-<worktree>.md`, then inline-forward it: `cw-herdr-open --prompt "$(cat <goal file>)"` (see "Delivery: committed goal file + inline forward") |
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

Retrospectively attaches a herdr pane to an existing worktree. On current herdr it opens a dedicated workspace per worktree via the native `worktree open` command; on older herdr it falls back to one workspace per repo with a tab per worktree. Either way, if a claude session is already running for that worktree (cwd match), it focuses it rather than spawning a duplicate. If herdr is unavailable, prints the legacy manual `cd ... && claude` instructions and exits 0 — open is not a hard failure when herdr is missing. If the named worktree does not exist, exits non-zero and references `/cw-worktree list`.

See [worktree-commands.md](references/worktree-commands.md#open) for full implementation.

***

### /cw-worktree cleanup

Removes completed or orphaned worktrees. Identifies merged branches and orphaned directories, presents cleanup options, confirms with user, removes worktrees/branches, and prunes references.

See [worktree-commands.md](references/worktree-commands.md#cleanup) for full implementation.

***

## Integration with Claude Workflow

Each worktree is a **self-contained feature unit**: one worktree = one spec + one implementation = one PR to main. The main session stays open as a **control center** (`create` / `list` / `cleanup`); each worktree runs its own pipeline (`/cw-spec → /cw-plan → /cw-dispatch → /cw-validate → gh pr create`) on an isolated, persistent task board (`~/.claude/tasks/{worktree-name}/`, configured via `.claude/settings.local.json`, restored just by re-running `claude` in the worktree).

When herdr is installed, running, and **this session is inside a herdr pane**, `create` opens a Claude session in each new worktree automatically (current herdr: one workspace per worktree; older herdr: tabs under one repo workspace). From a plain terminal the manual `cd … && claude` flow is used — a tab spawned in a detached herdr window would be invisible to you.

See [worktree-lifecycle.md](references/worktree-lifecycle.md) for states, transitions, persistence, and concurrent-worktree guidance.

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

After `create` (keep the main session open as control center):

- **In the worktree session** — the auto-opened herdr tab, or `cd .claude/worktrees/{dir} && claude`: run `/cw-spec → /cw-plan → /cw-dispatch → /cw-validate → /cw-worktree sync → gh pr create`. The task board persists across sessions; resume any time by re-running `claude` in the worktree.
- **From the main session** — `/cw-worktree list`, `create <other>`, or `cleanup` (after PRs merge).

> **Legacy worktrees:** Worktrees created before this naming scheme (e.g. `feature-auth`) are fully supported — discovery, list, cleanup, and all subcommands match by value (prefix-agnostic lookup).
