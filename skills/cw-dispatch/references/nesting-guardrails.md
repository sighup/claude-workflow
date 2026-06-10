# Nesting Guardrails Reference

Canonical policy for nested sub-agent spawning (sub-agents spawning their own sub-agents, available since Claude Code 2.1.172). Every skill or agent definition that grants or uses the Task tool below the top-level orchestrator cites this document instead of restating policy.

## Depth Policy

- **Platform ceiling: 5 levels**, per the Claude Code 2.1.172 release notes. Enforcement is currently absent (a 2026-06-10 probe chain reached level 10 without error), so the ceiling is **self-enforced** — treat the gap as a future breaking change, not headroom.
- **cw operating policy: depth ≤3** (orchestrator → worker → child). Levels 4–5 are reserved margin, never designed-in.
- **Every leaf-child prompt explicitly forbids further spawning.** A parent spawning at the policy's deepest level must include an instruction such as "Do not spawn sub-agents" in each child's prompt. The platform will not stop a runaway chain; prompts must.

## Fan-Out Caps

Per-parent caps, by role:

| Parent | Cap |
|---|---|
| reviewer | ≤3 sub-reviewers per fan-out |
| implementer | ≤1 proof-verifier child per task |

Roles without a Task grant (validator, bug-fixer, test-executor, spec-writer, planner) stay leaf-only.

## Board-Mirroring

**No nested spawn without a corresponding task-board artifact.** Before spawning, the parent ensures the child's work is represented on the board — a task (via TaskCreate) or a metadata entry on the parent's task. Children record results there (TaskUpdate). The board, not the transcript, is the observability plane: anything a grandchild produces is invisible to the orchestrator unless it lands on durable surfaces (board, proof files, git).

## Upward Relay: Funnel + Token Accounting

Every parent's final report MUST relay, for each fan-out it performed:

1. **Funnel accounting**: `returned/spawned` counts plus a degraded list (children that failed, timed out, or returned unusable output).
2. **Children's token usage**: each child's reported tokens, summed with the parent's own.

Rationale (probe-verified 2026-06-10): a parent's `subagent_tokens` covers only its **immediate** child — grandchild cost is invisible to the orchestrator and to top-level accounting. The chain of upward relays is the only cost telemetry the orchestrator gets. A worker's reported cost therefore **excludes** its children's cost unless relayed.

## Distinct Child Roles

**Never same-type recursion.** Spawn distinct roles with distinct prompts: implementer → proof-verifier, reviewer → sub-reviewer (distinct lens or file batch, never a clone of the parent's full assignment). Same-type recursive spawning is probe-verified (2026-06-10) to trip a harness security warning ("recursive sub-agent fork-bomb spawning") — non-blocking today, but pattern-matched even when bounded.

## Model Pinning

**Pin models explicitly for cost-tier children.** Children inherit the parent's model when unpinned (probe-verified, propagates through every level) — an unpinned verifier under a sonnet worker runs on sonnet. Spawn verifiers and explorers with `model: haiku` (or the intended tier) explicitly.

## SubagentStop Hook at Depth ≥2 (Verified Result)

**Verdict (probe T01.1, 2026-06-10, CC 2.1.172): the plugin's `SubagentStop` hook (`verify-task-update.sh`) fires for plugin-typed sub-agents spawned at depth ≥2, and its block is honored.**

Observed: a plugin-typed child at depth 2 that ended its turn without a TaskUpdate was blocked by the hook and re-prompted to update the board; a deterministic replay of `verify-task-update.sh` confirmed `{"decision":"block"}` on the trigger transcript and silent pass on completed and non-worker transcripts. The depth-1 parent was not blocked for its child's omission.

Design consequence: plugin-typed children at any depth carry the same board-update obligation as depth-1 workers — child definitions and prompts must have the child record its result via TaskUpdate before stopping, or its stop will be blocked. This is the enforcement half of the board-mirroring rule.

Raw observations: `docs/specs/01-spec-nested-subagent-adoption/proofs/T01.1-01-cli.txt` (transcript alongside at `proofs/subagentstop-probe.md`; spec-local, not committed).

## Fallback

Every nested path keeps an inline fallback: when the spawning tool is unavailable, the parent performs the child's step inline. Nesting is probe-verified to work in interactive, headless `claude -p`, and agent-team contexts, so the fallback is defensive robustness against tool-allowlist misconfiguration, not an SDK-compat requirement.
