# Funnel Accounting Sub-Protocol

Shared fan-out accounting used by any skill that spawns parallel subagents (`cw-research`, `cw-dispatch`, `cw-review-team`). The orchestrator is a control plane; agents are an untrusted data plane. A fan-out's coverage is the number of subagents that **actually returned usable work** — never the number you intended to spawn.

## Key Principle

Measure `{returned}/{spawned}`. Never fabricate coverage. A spawn that fails, returns empty, or times out did not contribute — count it as a loss and name it. Partial coverage must be propagated downstream so a thin run does not silently become authoritative.

## The Funnel

| Stage | What to record |
|-------|----------------|
| Spawned | `N` = count of subagents dispatched. Record before fan-in. |
| Returned | Count of subagents that returned non-empty, usable output. |
| Lost | `spawned - returned`, partitioned by reason: failed (error), empty (no findings), timed-out (no response). |

`returned + lost = spawned` must always hold. If it does not, the missing agents are losses, not returns.

## Protocol

### Step 1: Record the spawn count

Before launching, set `spawned = N` from the actual count of dispatch calls. Do not derive it from the plan or the dimension list — derive it from what was sent.

### Step 2: Account on fan-in

After all subagents settle (or the wait budget expires), classify each:

- **returned**: produced non-empty, on-topic output.
- **failed**: raised an error or never started.
- **empty**: returned but contributed no findings.
- **timed-out**: did not respond within the wait budget.

Filter the loss reasons into a `degraded` list, each entry carrying the subagent name/dimension and its reason.

### Step 3: Emit the measured stat

Replace any hardcoded coverage line with the measured one:

```
Coverage: {returned}/{spawned}
degraded: [{name}: {failed|empty|timed-out}, ...]   # omit line if none
```

Examples:

```
Coverage: 5/5
```

```
Coverage: 3/5
degraded: [Dependencies & Integrations: timed-out, Data Models & API Surface: empty]
```

Never report `5/5` when fewer than 5 returned. The stat is computed, not asserted.

### Step 4: Propagate coverage downstream

When the fan-out's output feeds another stage, carry a coverage/confidence flag into that handoff so partial coverage cannot be mistaken for complete:

| Caller | Downstream carrier |
|--------|--------------------|
| `cw-research` | Meta-prompt `Context Assessment` — emit `Coverage: {returned}/{spawned}` and, if degraded, a `Confidence: partial` note listing un-covered dimensions. |
| `cw-dispatch` | Completion report `Workers spawned` / integration block — name workers that failed or were skipped. |
| `cw-review-team` | Report `Files Reviewed: X / Y` and per-concern `Completed / Partial` — a degraded concern is `Partial`, never silently `Completed`. |

A downstream stage that sees `Confidence: partial` must treat the gaps as unverified, not as confirmed-absent.

## Constraints

- Always derive `spawned` from dispatched calls, never from intent.
- Always emit the measured `{returned}/{spawned}` stat, even when it equals `N/N`.
- Always list degraded subagents by name and reason when `returned < spawned`.
- Never fabricate coverage or round a partial run up to complete.
- Never drop the coverage flag at a stage boundary — partial coverage propagates until a stage explicitly closes the gap.
