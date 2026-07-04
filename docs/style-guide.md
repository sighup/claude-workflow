# Claude Workflow Style Guide

Canonical terminology and voice/register conventions for `claude-workflow` skills, agents, and docs. This is the single source of truth — when a file drifts from it, the file is wrong, not the guide.

## Canonical Terminology

Use exactly one term per referent. Do not mix terms for the same referent within a single file or passage.

| Concept | Canonical term | Use for | Do not use |
|---|---|---|---|
| Dependency-aware plan output | **task graph** | The DAG that `cw-plan` produces (tasks + `dependsOn`/`blockedBy` edges) | "task board", "task list" for this referent |
| Per-worktree task store | **task list** | The `CLAUDE_CODE_TASK_LIST_ID`-scoped native store a worktree reads/writes | "task board", "task graph" for this referent |
| General tracked-work surface | **task board** | The overall runtime surface of tracked work when not specifically meaning the graph or the list | "task list"/"task graph" when the graph or list distinction actually matters |
| Delegated worker agent | **subagent** (unhyphenated) | Any agent spawned by another agent (Task tool, Agent tool) | "sub-agent" (hyphenated) — matches the `subagent_type` API field name |
| Concrete per-task output | **proof artifact** (full term) or **proof** (established shorthand) | A single verifiable output tied to one proof requirement (file, CLI output, screenshot, etc.) | "evidence" for a single concrete output |
| Aggregate verification record | **evidence** | The combined journal + proofs + git-state picture used to gate a completion decision | "proof"/"proof artifact" for the aggregate — reserve those for the concrete per-task output |

## Voice and Register Conventions

`SKILL.md` files and `agents/*.md` files are two distinct, non-converging standards. Do not blend them — a `SKILL.md` should never adopt the `agents/*.md` shape, and vice versa.

### SKILL.md convention

| Element | Convention |
|---|---|
| Voice | Imperative, second-person ("You are...", "You execute...") |
| Role framing | `You are the {Role} role in the Claude Workflow system. ... You are a {Professional Title} responsible for:` |
| Constraint emphasis | ALL-CAPS **NEVER** / **ALWAYS** |
| Constraints heading | `## Critical Constraints` |

### agents/*.md convention

| Element | Convention |
|---|---|
| Voice | Third-person description, structured metadata sections |
| Role framing | `**Role**: X / Y` (e.g. `**Role**: Validator / QA Engineer`) |
| Constraint emphasis | Title-case **Never** / **Always** |
| Constraints heading | `## Constraints` |

## Accuracy Facts of Record

These are current, verified system facts. Treat any file stating a different count as a regression to fix, not as an alternate truth.

| Fact | Current value | Source of truth |
|---|---|---|
| `cw-validate` mandatory gate count | 7 gates, A-G (including **Gate G: Adversarial Analysis**) | `skills/cw-validate/references/validation-gates.md` |
| `cw-review` shared category count | 5 categories, A-E (including **Category E: Reuse**) | `skills/cw-review/references/review-categories.md` |
