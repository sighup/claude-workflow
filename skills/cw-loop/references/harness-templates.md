# Harness Templates

Copy-paste skeletons for the three ways a `cw-loop` design gets run. Each already encodes the Critical Constraints: an external check, a hard cap, a no-progress stop, `exhausted` as a non-success exit, a named terminal state printed on stop, and a **deterministic, cache-immune check signal** (RULE 7). Fill the `<...>` slots; do not remove the bounds.

Pick by what one iteration *is*:

| One iteration is… | Use template |
|---|---|
| a shell command (lint, build, test, script) | **A — Shell while-loop** |
| a coding task on the board | **B — cw-execute driver** |
| a prompt/command on an interval or self-paced | **C — /loop one-liner** |

---

## A — Shell while-loop

For wrapping a command (`/cw-loop wrap`) or any check expressible as an exit code. The check is the oracle and is never edited by the loop.

```bash
#!/usr/bin/env bash
# Loop: <goal>
# Check: <external check — e.g. `npm run lint` exits 0>
# RULE 7: the check must be DETERMINISTIC and CACHE-IMMUNE, or the no-progress
# detector mis-fires — volatile output (timestamps/durations) reads as endless
# progress (never stops); a stale cache reads as no change (stops early).
set -uo pipefail

CAP=<N>                 # hard iteration cap
NO_PROGRESS_K=2         # stop after K identical check results
<CACHE_IMMUNE_SETUP>    # disable stale caches, e.g.: export PYTHONDONTWRITEBYTECODE=1; rm -rf __pycache__ .pytest_cache

# fingerprint hashes a STABLE PROJECTION of the check — strip volatile lines first:
fingerprint() { <CHECK_CMD> 2>&1 | <STRIP_VOLATILE, e.g. grep -vE '^Ran [0-9]+ tests? in'> | shasum | awk '{print $1}'; }

i=0; stale=0; last=""
while :; do
  if <CHECK_CMD>; then echo "TERMINAL: success (check passed at i=$i)"; exit 0; fi

  i=$((i+1))
  if [ "$i" -gt "$CAP" ]; then
    echo "TERMINAL: exhausted (hit cap=$CAP, check still failing)"; exit 2
  fi

  cur="$(fingerprint)"
  if [ "$cur" = "$last" ]; then
    stale=$((stale+1))
    if [ "$stale" -ge "$NO_PROGRESS_K" ]; then
      echo "TERMINAL: no-progress (check unchanged for $NO_PROGRESS_K iterations)"; exit 3
    fi
  else
    stale=0
  fi
  last="$cur"

  <ACTION_CMD>          # the repair/work step — must NOT modify the check
done
```

Exit codes: `0` success · `2` exhausted · `3` no-progress. A non-zero exit is a real, surfaced outcome — wire it into whatever calls the harness.

---

## B — cw-execute driver

For loops whose iteration is a board task — each pass is one `/cw-execute`, which is already verify-gated (its Step 9 spawns the read-only `proof-verifier`). The harness adds the outer cap and no-progress stop; the per-iteration check is `cw-execute`'s own PASS verdict.

```bash
#!/usr/bin/env bash
# Loop: drive the board to green, <N> tasks max
# Per-iteration check: cw-execute's PASS verdict (external, via proof-verifier)
set -uo pipefail

CAP=<N>
i=0; last_open=""
while :; do
  open="$(<list-unblocked-task-ids>)"          # e.g. via TaskList tooling
  [ -z "$open" ] && { echo "TERMINAL: clean-noop (no unblocked tasks)"; exit 0; }

  i=$((i+1))
  [ "$i" -gt "$CAP" ] && { echo "TERMINAL: exhausted (cap=$CAP)"; exit 2; }

  if [ "$open" = "$last_open" ]; then
    echo "TERMINAL: no-progress (task set unchanged — likely all blocked)"; exit 3
  fi
  last_open="$open"

  # one iteration = one verify-gated task; cw-execute fails non-zero if its
  # proof-verifier returns FAIL, which surfaces here rather than passing silently
  claude -p "/cw-execute $(echo "$open" | head -n1)" || \
    { echo "TERMINAL: blocked (cw-execute failed verification)"; exit 4; }
done
```

> For the *full* spec pipeline, prefer `/cw-dispatch` — it is already this loop with a hardened Manifest-Authoritative Exit Gate and single-writer discipline. Use this driver only for a narrow, single-task-at-a-time loop.

---

## C — /loop one-liner

For interval-driven or self-paced runs. `/loop` supplies the cadence; `cw-loop` supplies the exit condition `/loop` alone lacks. State the external check and the stop inside the prompt so the model self-terminates on a real signal, not vibes.

```
/loop Run <CHECK_CMD>. If it exits 0, stop and report TERMINAL: success.
If it has failed <N> times total, stop and report TERMINAL: exhausted.
If the failure output (ignoring volatile noise like timestamps and durations)
is identical to the previous run, stop and report TERMINAL: no-progress.
Otherwise apply the smallest fix to <system>
— never edit the check itself — and continue.
```

Self-paced variant (omit the interval): same prompt, let the model pace iterations; the three TERMINAL conditions are what stop it.

---

## Loop Spec template

The companion `docs/loops/<slug>.md` that `/cw-loop design` writes alongside the harness:

```markdown
# Loop: <name>

- **Goal**: <what it accomplishes>
- **Check**: <external, re-runnable check>
- **Learn**: <what carries between iterations>
- **Pattern**: <generate-verify-refine | loop-until-dry | budget-bounded | self-healing>

## Bounds
- Cap: <N iterations / $budget>
- No-progress stop: <check unchanged for K=<k> iterations>

## Terminal states
- success → <what evidence>
- exhausted → <surfaced how>
- no-progress → <plateau condition>
- <blocked / needs-approval / clean-noop as applicable>

## Harness
See `<slug>.sh` (template <A|B|C>).
```
