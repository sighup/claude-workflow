# Terminal States Reference

Every bounded loop terminates in exactly **one** of six named states. A loop that can stop without naming its state is under-specified — the missing state is almost always `exhausted` (no cap) or `no-progress` (no stagnation stop).

This vocabulary is canonical for `cw-loop`. The system's existing loops already implement these states under skill-local names; the mapping table below is the bridge. (A future refactor may repoint the existing skills at this file so the whole system speaks one dialect — until then, this table is the translation.)

## The Six States

### `success`
The external check passed. This is the only state that means "the goal was achieved." It requires evidence from the check — not the agent's assertion that it is done.

- **Fires when**: the test passes / the command exits 0 / the rubric clears its threshold / every scenario in the finite set passed.
- **Must carry**: the passing evidence (command output, exit code, score).

### `clean-noop`
There was nothing to do. The loop ran its check, found the goal already satisfied, and made no change. Distinct from `success` because no work was performed — useful for idempotent re-runs.

- **Fires when**: first-iteration check already passes, or the work queue is empty on entry.

### `blocked`
An **external** blocker prevents progress: a missing dependency, a permission denial, an unreachable service, a precondition the loop cannot satisfy itself. Not a failure of the loop's logic — a wall it cannot climb.

- **Fires when**: the action cannot be attempted at all (not "was attempted and failed" — that is a normal iteration).
- **Must carry**: what the blocker is and what would unblock it.

### `needs-approval`
The loop reached a boundary where a human must decide, judge, or sign off. This is the deliberate hand-back — the loop is bounded precisely so it stops here instead of guessing.

- **Fires when**: an irreversible or outward-facing action is next, a judgment call exceeds the loop's mandate, or the design specified a human gate.
- **Must carry**: the decision being requested and the options.

### `exhausted`
The loop hit its iteration or budget cap before the check passed. **This is a non-success outcome and must surface as one** — never silently treat a cap as done. Mirrors the Claude Agent SDK returning `error_max_turns` / `error_max_budget_usd` rather than a success result.

- **Fires when**: `iterations >= cap` or `spend >= budget` with the check still failing.
- **Must carry**: the last check result and how close it got, so the human can decide whether to raise the cap or change approach.

### `no-progress`
The check stopped improving across iterations (stagnation). The loop is not making the metric move, so continuing only burns budget. This is the antidote to "technically under the cap but spinning."

- **Fires when**: the check result is unchanged (or not improving) for K consecutive iterations.
- **Must carry**: the plateau value and the K it used.

## Mapping to the System's Existing Loops

| `cw-loop` state | cw-execute | cw-testing | cw-dispatch |
|---|---|---|---|
| `success` | `PASS` verdict (Step 9) | `test_result: passed` | task `completed` via harvest |
| `clean-noop` | clean tree, requirement already met | regression check already green | `Ready=0 + Pending=0` |
| `blocked` | `BLOCKED` (env issue, Step 2) | `test_result: blocked` (fix disabled) | `Ready=0 + Blocked>0` |
| `needs-approval` | n/a (autonomous worker) | the `AskUserQuestion` next-action gates | the post-loop `AskUserQuestion` (validate?) |
| `exhausted` | `max 3 attempts` then failure handler | `fix_attempt >= max_fix_attempts` → BLOCKED | n/a (count-driven, not capped) |
| `no-progress` | n/a | n/a | dead-worker / no-selectable-task reset |

The gaps in the table are deliberate and informative:

- **cw-execute** has no `needs-approval` — workers are fully autonomous and hand back only through evidence, never a prompt.
- **cw-dispatch** has no fixed `exhausted` cap — it loops on board/manifest state, not an iteration count, and relies on the [Manifest-Authoritative Exit Gate](../../cw-dispatch/references/dispatch-common.md) to avoid premature stopping rather than a hard cap.
- Only **cw-testing** uses `needs-approval` as a routine terminal state, via its conditional next-action prompts.

When designing a new loop, fill *every* applicable cell: if your loop can plausibly reach a state, it must name it on exit.
