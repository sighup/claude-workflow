# Guard decision fixtures

A deterministic regression suite for `scripts/task-store-guard.sh` — the
filesystem backstop that restores a task board after the native-store
concurrent-write wipe. It exercises the guard's per-tick decision logic branch
by branch with a fast, hermetic, stable oracle (no real `sleep`, no wall-clock
dependence, isolated temp tasks root per case).

## Why this exists

The end-to-end wipe is non-deterministic and only reproduces under heavy real
concurrency, so it can't gate the guard cheaply. The guard's *decision logic*,
however, is deterministic and finite. These fixtures pin that logic:

- wipe-signature detection (`≥MIN_TASKS → 0`) and the boundary at exactly `MIN_TASKS`
- below-signature drops (`1 → 0`): never restored; audit-logged only when a manifest still expects tasks
- writer-lease deferral and the cross-tick `WIPE_PENDING` latch (restore fires after release)
- stale-lease override
- evidence-newer skip (never clobber a newer `{task_id}.result.json`)
- manifest-expected prune skip vs. ordinary gradual-delete prune
- symlink safety on restore
- legitimate board growth (mirror, never restore)

## Run it

```bash
scripts/guard-fixtures/run.sh                 # test the in-repo guard
scripts/guard-fixtures/run.sh path/to/guard   # test a specific variant
```

Exit 0 iff every scenario passes. The suite is discriminating — verified by
mutation testing: disabling the wipe signature, the evidence guard, the lease
defer, or the manifest prune-skip each flips exactly the scenarios that assert
those behaviours.

## How it stays deterministic

`task-store-guard.sh`'s poll-loop body is factored into a `guard_tick` function
that runs one decision and echoes the next `LAST_COUNT WIPE_PENDING` state. The
daemon carries that state across ticks; the fixtures call `guard_tick` directly,
single-stepping the tick-transition-sensitive branches one controlled tick at a
time instead of racing the daemon's real sleeps. The guard is sourceable (its
CLI dispatch is guarded by a `BASH_SOURCE`/`$0` check) so the harness loads its
functions without launching the daemon.

Each scenario self-grades against its own known-correct outcome and emits one
`SCENARIO_RESULT: pass|fail — reason` line, so the grading oracle is uniform.

## AutoResearch integration

`.autoresearch/config.json` (custom-runner mode) points the optimization loop at
this suite:

- `runner.sh` runs one scenario (by `AUTORESEARCH_TEST_ID`) against the variant under assessment
- `assertions.py` grades the `SCENARIO_RESULT` line
- `test_cases.jsonl` is one line per scenario

Scope the loop to tuning thresholds and bounded branch conditions — not
free-form rewrites of the stat/symlink/lease internals, where shell-correctness
traps (BSD-vs-GNU `stat`, `$()` subshell `exit`, the mkdir+rename reclaim race)
make a plausible-but-broken variant worse than no change.

To add a scenario: add a `scenario_<id>` function, register it in
`GF_SCENARIOS` (scenarios.sh) and as a line in `test_cases.jsonl`.
