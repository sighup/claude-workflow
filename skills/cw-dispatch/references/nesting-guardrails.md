# Nesting Guardrails Reference

Canonical policy for nested sub-agent spawning (sub-agents spawning their own sub-agents). Every skill or agent definition that grants or uses the Task tool below the top-level orchestrator cites this document instead of restating policy.

## Depth Policy

- **Platform ceiling: 5 levels**, per the platform release notes. Enforcement is not guaranteed, so the ceiling is **self-enforced** — never treat any enforcement gap as headroom.
- **cw operating policy: depth ≤3** (orchestrator → worker → child). Levels 4–5 are reserved margin, never designed-in.
- **Every leaf-child prompt explicitly forbids further spawning.** A parent spawning at the policy's deepest level must include an instruction such as "Do not spawn sub-agents" in each child's prompt. The platform will not stop a runaway chain; prompts must.

## Fan-Out Caps

Per-parent caps, by role:

| Parent | Cap |
|---|---|
| reviewer | ≤3 sub-reviewers per fan-out |
| implementer | ≤1 proof-verifier child per task |
| researcher | ≤5 Explore children per fan-out (cw-research wave), each leaf-pinned |

Roles without a Task grant (validator, bug-fixer, test-executor, spec-writer, planner) stay leaf-only.

## Board-Mirroring

**No nested spawn without a corresponding task-board artifact.** Before spawning, the parent ensures the child's work is represented on the board — a task (via TaskCreate) or a metadata entry on the parent's task. Children holding Task tools record results there (TaskUpdate); read-only children (no Task* tools, e.g. proof-verifier) report in their final message and the parent records the result on the board. The board, not the transcript, is the observability plane: anything a grandchild produces is invisible to the orchestrator unless it lands on durable surfaces (board, proof files, git).

## Upward Relay: Funnel + Token Accounting

Every parent's final report MUST relay, for each fan-out it performed:

1. **Funnel accounting**: `returned/spawned` counts plus a degraded list (children that failed, timed out, or returned unusable output).
2. **Children's token usage**: each child's reported tokens, summed with the parent's own.

Rationale: a parent's `subagent_tokens` covers only its **immediate** child — grandchild cost is invisible to the orchestrator and to top-level accounting. The chain of upward relays is the only cost telemetry the orchestrator gets. A worker's reported cost therefore **excludes** its children's cost unless relayed.

## Distinct Child Roles

**Never same-type recursion.** Spawn distinct roles with distinct prompts: implementer → proof-verifier, reviewer → sub-reviewer (distinct lens or file batch, never a clone of the parent's full assignment). Same-type recursive spawning pattern-matches the harness's recursive-spawn security warning even when bounded — expected and non-blocking, but distinct roles avoid it entirely.

## Model Pinning

**Pin models explicitly for cost-tier children.** Children inherit the parent's model when unpinned (inheritance propagates through every level) — an unpinned verifier under a sonnet worker runs on sonnet. Spawn verifiers and explorers with `model: haiku` (or the intended tier) explicitly.

## SubagentStop Hook at Any Depth

The plugin's `SubagentStop` hook (`verify-task-update.sh`) fires for plugin-typed sub-agents at every nesting depth, and its block is honored. A parent is not blocked for its child's omission.

The hook's trigger is conditional, not blanket. It blocks a stop only when the child's transcript shows the execution skill's all-caps context marker **plus** commit evidence (a commit invocation or a quoted commit-hash metadata key) **without** a completing TaskUpdate. Two compliance paths follow:

1. **Board-updating children** (Task tools granted) record their result via TaskUpdate(status: completed) before stopping — same obligation as depth-1 workers.
2. **Read-only children** (no Task* tools, e.g. proof-verifier) cannot call TaskUpdate and instead must never emit the trigger signature — no all-caps worker marker, no raw task-metadata JSON, no commit invocations in their output (see the verifier's stop-hook contract). Their transcript never matches the trigger, so they stop silently and the parent records the result.

This is the enforcement half of the board-mirroring rule.

## Fallback

Every nested path keeps an inline fallback: when the spawning tool is unavailable, the parent performs the child's step inline. Nesting works in interactive, headless `claude -p`, and agent-team contexts alike, so the fallback is defensive robustness against tool-allowlist misconfiguration, not a platform-compat requirement.
