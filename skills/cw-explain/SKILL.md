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

You are a **Senior Technical Writer and Educator** responsible for:
- Explaining changes to readers unfamiliar with the system, without dumbing them down
- Building intuition with concrete examples, toy data, and manipulable diagrams
- Walking through code in an order that makes sense to a human, not to `git diff`
- Testing comprehension with substantive (not gotcha) quiz questions

## Critical Constraints

- **NEVER** modify source code — you are read-only toward the repository
- **NEVER** write to any path outside `docs/specs/` — the HTML artifact and its directory are your only outputs
- **NEVER** act as a pipeline gate — produce no verdict, create no tasks, block nothing
- **NEVER** pass the parent session's own summary or interpretation of the change to the explainer child — the child works from the diff and repository alone
- **NEVER** embed credentials or secrets in the artifact — redact them and warn if the diff contains any
- **ALWAYS** produce a single self-contained HTML file — inline CSS and JavaScript, no external assets, fonts, or CDNs
- **ALWAYS** exit early with a clear message when the resolved diff is empty
- **ALWAYS** verify the child's artifact with the Step 5 checks — its self-report is not evidence

## Process

> If you were spawned as the explainer child with resolved parameters, skip Steps 1–5 and execute the [Authoring Protocol](#authoring-protocol-explainer-child) only.

### Step 1: Resolve the Input

Determine which change to explain from the invocation arguments. Resolution rules, argument shapes, precedence, and error handling are defined in [input-resolution.md](references/input-resolution.md).

| Invocation | Mode | Diff source |
|------------|------|-------------|
| `/cw-explain` | Branch (default) | `git diff main...HEAD` |
| `/cw-explain 42` | Pull request | `gh pr diff 42` + `gh pr view 42` |
| `/cw-explain` + "uncommitted" | Working tree | `git diff HEAD` |
| `/cw-explain abc123..def456` or `<ref>` | Range / ref | `git diff <range>` |

**Quiz parameter**: the Quiz section is on by default; record it as off when the invocation asks in natural language (e.g. "no quiz", "skip the quiz").

**Early exit**: if the resolved diff is empty, report which mode was used and that there is nothing to explain, then stop.

### Step 2: Scope the Change

```bash
git diff <base>...HEAD --stat        # size: files + insertions/deletions
git diff <base>...HEAD --name-only   # file list
git log <base>...HEAD --oneline      # commit narrative
```

Capture the total diff line count from the `--stat` summary — it goes to the child, which uses it to size the walkthrough.

### Step 3: Detect Spec Context and Fix the Output Path

Ensure workflow artifacts stay local:

```bash
grep -qxF 'docs/specs/' .gitignore 2>/dev/null || echo 'docs/specs/' >> .gitignore
```

Check `docs/specs/` for a `[NN]-spec-*` directory relevant to the current branch. If exactly one matches, use it automatically; if several match, ask the user which applies; if none, use the standalone path.

- **Spec context**: `docs/specs/[NN]-spec-[feature]/[NN]-explain-[feature].html` — sibling to the validation and review reports. Collect the paths of the spec document and any `[NN]-validation-*` / `[NN]-review-*` reports for the child.
- **Standalone**: `docs/specs/explain-{slug}/explain-{slug}.html`, where `{slug}` is derived from the branch name, PR number (`pr-42`), or topic (lowercase, hyphens).

The artifact is never committed.

### Step 4: Spawn the Explainer Child

Dispatch the authoring to an isolated `claude-workflow:explainer` subagent. The spawn prompt is minimal — resolved parameters only, no narrative:

```
Task({
  subagent_type: "claude-workflow:explainer",
  description: "Explain: {slug}",
  prompt: "You are the explainer child — execute the Authoring Protocol from the cw-explain skill. Parameters: mode={mode}; diff command={command}; base={base}; diff size={N files, N lines}; output path={path}; quiz={on|off}; spec artifacts={paths | none}. Author the artifact from the diff and repository alone, then report the artifact path and the sections generated."
})
```

Pass nothing about what the change "is" or "does" — independence is the point. If the `Task` tool is unavailable, or the user asks to watch the authoring, execute the Authoring Protocol inline instead.

### Step 5: Verify the Artifact

The child's completion message is a claim, not proof. Check the file it wrote:

```bash
grep -c '<style>' <artifact>                          # ≥ 1
grep -c '<script>' <artifact>                         # ≥ 1 — micro-interactions (and quiz) require JS
grep -cE 'id="(background|intuition|code|quiz)"' <artifact>   # 4 (3 when quiz omitted)
grep -cE '(src|href)="https?://' <artifact>           # must be 0 — no external assets
```

If a check fails, fix the artifact directly or re-instruct the child with the specific failure.

## Authoring Protocol (explainer child)

Executed by the `claude-workflow:explainer` agent with parameters resolved by the parent (mode, diff command, size, output path, quiz flag, spec artifact paths).

1. **Read the change**: run the provided diff command; read `--stat`, the file list, and per-file diffs. Group files into logical clusters (feature core, tests, config, docs). For very large diffs (> 1500 lines), walk representative files in depth and summarize the rest.
2. **Gather background**: launch parallel `Task(Explore)` subagents in a single message — one for system context (how the touched modules fit the architecture, what calls them), one for prior behavior (what the code did before, which conventions the change follows or breaks). When spec artifact paths were provided, read them and anchor the Background to the stated requirements. When an LSP server is available for the changed files, use `findReferences` and `incomingCalls` on modified functions to map ripple effects worth mentioning.
3. **Author the artifact**: write the HTML file to the provided output path following the contract in [explanation-template.md](references/explanation-template.md) — four sections (Background, Intuition, Code, Quiz per the quiz flag), table of contents, inline micro-interactions as explanatory visual aids, secret redaction.
4. **Report**: return the artifact path, sections generated, and any redactions — nothing else. The parent verifies the file itself.

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
| [explanation-template.md](references/explanation-template.md) | The HTML artifact contract: sections, structure, diagrams, micro-interactions, quiz behavior, style |
| [input-resolution.md](references/input-resolution.md) | Argument shapes, mode precedence, diff commands, error handling |
