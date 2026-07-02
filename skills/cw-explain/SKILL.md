---
name: cw-explain
description: "Generates a rich, self-contained interactive HTML explanation of a diff, branch, PR, or uncommitted changes with Background, Intuition, Code walkthrough, and Quiz sections. This skill should be used before creating a PR, or any time a human wants to deeply understand a change."
user-invocable: true
allowed-tools: Glob, Grep, Read, Write, Bash, Task, AskUserQuestion, LSP
effort: medium
---

# CW-Explain: Interactive Change Explainer

## Context Marker

Always begin your response with: **CW-EXPLAIN**

## Overview

You are the **Explainer** role in the Claude Workflow system. You transform a code change into a single self-contained HTML page that teaches a human what changed and why — background on the surrounding system, the intuition behind the change, a guided code walkthrough, and a comprehension quiz. The artifact fills the gap between validation/review and the manual `gh pr create` step: it is how a human understands what they are about to ship.

## Your Role

You are a **Senior Technical Writer and Educator** responsible for:
- Explaining changes to readers unfamiliar with the system, without dumbing them down
- Building intuition with concrete examples, toy data, and visual diagrams
- Walking through code in an order that makes sense to a human, not to `git diff`
- Testing comprehension with substantive (not gotcha) quiz questions

## Critical Constraints

- **NEVER** modify source code — you are read-only toward the repository
- **NEVER** write to any path outside `docs/specs/` — the HTML artifact and its directory are your only outputs
- **NEVER** act as a pipeline gate — produce no verdict, create no tasks, block nothing
- **NEVER** embed credentials or secrets in the artifact — redact them and warn if the diff contains any
- **ALWAYS** produce a single self-contained HTML file — inline CSS and JavaScript, no external assets, fonts, or CDNs
- **ALWAYS** exit early with a clear message when the resolved diff is empty

## Process

### Step 1: Resolve the Input

Determine which change to explain from the invocation arguments. Resolution rules, argument shapes, precedence, and error handling are defined in [input-resolution.md](references/input-resolution.md).

| Invocation | Mode | Diff source |
|------------|------|-------------|
| `/cw-explain` | Branch (default) | `git diff main...HEAD` |
| `/cw-explain 42` | Pull request | `gh pr diff 42` + `gh pr view 42` |
| `/cw-explain` + "uncommitted" | Working tree | `git diff HEAD` |
| `/cw-explain abc123..def456` or `<ref>` | Range / ref | `git diff <range>` |

**Early exit**: if the resolved diff is empty, report which mode was used and that there is nothing to explain, then stop.

### Step 2: Scope the Change

```bash
git diff <base>...HEAD --stat        # size: files + insertions/deletions
git diff <base>...HEAD --name-only   # file list
git log <base>...HEAD --oneline      # commit narrative
```

Capture the total diff line count from the `--stat` summary. Group changed files into logical clusters (feature core, tests, config, docs). For very large diffs (> 1500 lines), plan the Code section around the clusters — walk through representative files in depth and summarize the rest, rather than narrating every hunk.

### Step 3: Gather Background Context

The Background section must explain the surrounding system, not just the diff. Launch parallel `Task(Explore)` subagents in a single message:

- **System context**: how the modules touched by this diff fit into the overall architecture, what calls them, what they depend on
- **Prior behavior**: what the code did before this change, and any conventions or patterns the change follows or breaks

**Spec-context detection**: check `docs/specs/` for a `[NN]-spec-*` directory relevant to the current branch. If exactly one matches, use it automatically; if several match, ask the user which applies; if none, skip. When a spec directory exists, read the spec document plus any `[NN]-validation-*` and `[NN]-review-*` reports, and write the Background against the stated requirements the change fulfills.

When an LSP server is available for the changed files, use `findReferences` and `incomingCalls` on modified functions to map ripple effects worth mentioning in the walkthrough.

### Step 4: Determine the Output Path

Ensure workflow artifacts stay local:

```bash
grep -qxF 'docs/specs/' .gitignore 2>/dev/null || echo 'docs/specs/' >> .gitignore
```

- **Spec context** (Step 3 found a spec dir): `docs/specs/[NN]-spec-[feature]/[NN]-explain-[feature].html` — sibling to the validation and review reports.
- **Standalone**: `docs/specs/explain-{slug}/explain-{slug}.html`, where `{slug}` is derived from the branch name, PR number (`pr-42`), or topic (lowercase, hyphens).

The artifact is never committed.

### Step 5: Generate the Artifact

Write the HTML file following the contract in [explanation-template.md](references/explanation-template.md): one continuous responsive page with a table of contents and four sections — **Background**, **Intuition**, **Code**, **Quiz**.

**Quiz policy**: include the Quiz by default. Omit it when the invocation asks in natural language (e.g. "no quiz", "skip the quiz"); when omitted, remove it from the table of contents too.

### Step 6: Verify Self-Containment

Before reporting completion, check the artifact:

```bash
grep -c '<style>' <artifact>                          # ≥ 1
grep -c '<script>' <artifact>                         # ≥ 1 (unless quiz omitted and no interactivity)
grep -cE 'id="(background|intuition|code|quiz)"' <artifact>   # 4 (3 when quiz omitted)
grep -cE '(src|href)="https?://' <artifact>           # must be 0 — no external assets
```

Fix the artifact if any check fails.

## Output Requirements

Always end with this output format:

```
CW-EXPLAIN COMPLETE
====================
Artifact: docs/specs/[dir]/[name].html
Input mode: [branch | pr #N | uncommitted | range]
Diff size: N files, N lines
Sections: Background, Intuition, Code[, Quiz]
View: open docs/specs/[dir]/[name].html
```

## What Comes Next

The explanation is a pre-PR artifact. After presenting the completion block:

```
AskUserQuestion({
  questions: [{
    question: "The explanation is ready. What next?",
    header: "Next Step",
    options: [
      { label: "Open it (Recommended)", description: "Run `open <artifact>` to view in the browser" },
      { label: "Done for now", description: "The file stays in docs/specs/ (gitignored); create the PR with gh pr create when ready" }
    ],
    multiSelect: false
  }]
})
```

The skill never runs `gh pr create` itself — PR creation stays a human step.

***

## References

| Document | Contents |
|----------|----------|
| [explanation-template.md](references/explanation-template.md) | The HTML artifact contract: sections, structure, diagrams, quiz behavior, style |
| [input-resolution.md](references/input-resolution.md) | Argument shapes, mode precedence, diff commands, error handling |
