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

**No nested spawn without a corresponding task-board artifact.** Before spawning, the parent ensures the child's work is represented on the board — a task (via TaskCreate) or a metadata entry on the parent's task.

### Single-Writer Invariant

During execute, test, and review phases, exactly one process — the phase orchestrator — ever issues task-tool writes (`TaskCreate`, `TaskUpdate`). Workers and all sub-agents hold no Task-write tools. They carry their assignment inline, do their work, and hand off through two durable surfaces:

1. **A committed implementation** plus a per-task `{task_id}.result.json` journal written to the run's gitignored results directory (`docs/specs/<run>/results/`). The journal is the durable child artifact: it records `status`, `commit_sha`, and `proof_results`. The orchestrator verifies the `commit_sha` is reachable in git before crediting the completion.
2. **A `CW-RESULT-BLOCK` sentinel** in the worker's final message, carrying the same fields as the journal. The orchestrator harvests whichever surface arrives first (RESULT BLOCK → journal → proof-dir scan) and applies the completing `TaskUpdate` itself, serially.

**Consequence for Board-Mirroring**: the on-disk `result.json` is the durable child artifact, not a TaskUpdate. A read-only child (e.g., proof-verifier) that holds no Task tools reports in its final message; the parent records the result on the board. The board converges toward the on-disk state, never the other way around.

Children holding Task tools (orchestrator-mode reviewer, planner) record results via `TaskUpdate` — same single-writer obligation, applied serially with the write→checkpoint→read-back cadence, and **only while holding the writer lease themselves** per [Nested Phase Orchestrator Handoff](#nested-phase-orchestrator-handoff) below. Children without Task tools (implementer, test-executor, bug-fixer, sub-reviewer, proof-verifier) never touch the board directly; the orchestrator is their sole proxy and need not hold the lease.

The invariant eliminates the dominant board-wipe trigger: concurrent multi-process writes from a shared `CLAUDE_CODE_TASK_LIST_ID`. See [dispatch-common.md](dispatch-common.md#single-writer-discipline) for the full dispatch-phase protocol.

### Nested Phase Orchestrator Handoff

A nested phase orchestrator — a Task-tool child that runs its own phase and writes to the board (a cw-review child that `TaskCreate`s FIX tasks and appends `manifest.fix.jsonl`, a planner child that creates the task graph) — cannot share the parent's held lease. The parent holds the lease for the whole run; if the child wrote leaseless there would be two concurrent writers under one `CLAUDE_CODE_TASK_LIST_ID` (the wipe trigger), and if the child tried to acquire while the parent still held it the child would block forever, since `acquire` waits rather than proceeds. The lease is handed off, never shared:

1. **Parent releases before spawning.** Before spawning a nested phase orchestrator that needs board writes, the parent releases the writer lease so the child can acquire it. The parent issues no `TaskUpdate`/`TaskCreate` between releasing and re-acquiring.
2. **Child acquires with its own token and phase label.** The child writes its own owner token to a child-owned file and acquires the lease with that token and a distinct `--phase` label (e.g. `--phase review-fix`). It **never inherits the parent's token** — the owner-checked `release`/`refresh` compare against the token stored at `acquire`, so a borrowed token fails the owner check and strands the lease. The child does all its board writes serially under this lease.
3. **Child releases at its phase end.** The child releases the lease as the last action of its phase, on every termination path, before returning to the parent.
4. **Parent re-acquires after join.** Once the child has joined and released, the parent re-acquires the lease (with its own token, `--phase dispatch`) before resuming any board write.

A nested orchestrator **never writes leaseless** and **never inherits the parent's owner token**: each writer holds the lease under its own token for the span of its writes, and exactly one writer holds it at any moment. A child that needs no board writes (proof-verifier, sub-reviewer) acquires no lease — only board-writing orchestrators participate in the handoff. See [dispatch-common.md](dispatch-common.md#nested-phase-orchestrator-handoff) for the dispatch-phase commands.

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
