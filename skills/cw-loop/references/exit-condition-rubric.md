# Exit-Condition Rubric

The audit checklist for `/cw-loop check`. Score each rule PASS or CONCERN against the target loop/prompt/script, citing the specific line or phrase. One rule is a hard gate: a loop with no external check is an automatic **FAIL** regardless of the others.

## Rules

### RULE 1: External check (HARD GATE)

**Pass when**: the loop's success condition is a check that is external to the generator and re-runnable by anyone — a test, a command's exit code, a rubric scored by a *separate* judge, a finite scenario set, or a reviewer decision.

**CONCERN → escalate to FAIL when**: the only stop is the agent's own satisfaction — "until it looks good," "when you're confident," "until the output seems correct," or any self-graded condition with no independent signal.

**Why it gates**: intrinsic self-correction (an LLM revising its own work with no external feedback) does not reliably improve output and can degrade it. This is the single most important property of a loop. If it fails, nothing else matters — fix this first.

**Fix**: replace the self-judgment with the nearest external signal. "until the code is right" → "until `npm test` exits 0"; "until the summary is good" → "until a separate judge scores it ≥ 4/5 on <rubric>"; "until done" → "until every scenario in <set> passes."

### RULE 2: Hard cap present

**Pass when**: there is an explicit iteration cap and/or budget ceiling (tokens, dollars, wall-clock).

**CONCERN when**: the loop can iterate without any upper bound.

**Fix**: add `cap=N` (3–5 for refine loops) or a budget ceiling. A loop with no cap is an infinite-loop / runaway-cost risk.

### RULE 3: No-progress stop present

**Pass when**: the loop detects stagnation — the check result not improving for K consecutive iterations — and stops.

**CONCERN when**: the loop only stops on success or cap, so a stalled loop grinds to the cap wasting budget.

**Fix**: track the last check result; stop with `no-progress` if it is unchanged for K iterations (K=2 default).

### RULE 4: Cap is a non-success terminal state

**Pass when**: hitting the cap/budget surfaces as `exhausted` (a reported non-success outcome with the last check result).

**CONCERN when**: hitting the cap silently returns, logs nothing, or is treated as success.

**Fix**: on cap, emit `exhausted` with how close it got, so a human can raise the cap or change approach. Mirror `error_max_turns`.

### RULE 5: Check is immutable to the loop

**Pass when**: the loop cannot modify its own check to pass — it may not edit the test, lower the threshold, or reinterpret the rubric.

**CONCERN when**: the same agent both runs the check and can edit it, with no rule forbidding self-weakening (reward-hacking risk).

**Fix**: state explicitly that the check is the oracle and out of scope for the loop's edits (as `cw-testing` does: "never modify test assertions"). For high-stakes loops, run the check in a separate, read-only context.

### RULE 6: Every reachable terminal state is named

**Pass when**: each way the loop can stop maps to exactly one of the six terminal states (`success`, `clean-noop`, `blocked`, `needs-approval`, `exhausted`, `no-progress`), printed on exit.

**CONCERN when**: the loop can stop in an unnamed way (e.g., falls through, or "just returns").

**Fix**: enumerate stops and label each. The usual missing ones are `exhausted` (no cap) and `no-progress` (no stagnation stop) — fixing rules 2 and 3 usually closes this.

### RULE 7: Check signal is deterministic and cache-immune

**Pass when**: the value the no-progress detector diffs (and the success check itself) is a *stable projection* of the check — it ignores volatile noise (timestamps, durations, run order, absolute paths, PIDs) and is immune to stale caches (compiled bytecode, build/test caches, memoized results).

**CONCERN when**: the loop hashes raw check output containing volatile fields, or the check can read a stale cache after the system changed. Either way the no-progress signal mis-fires — a jittering timestamp reads as "always progressing" so the loop **never stops**, and a stale cache reads as "never changed" so the loop **stops early** on work that did advance.

**Why it matters**: the no-progress stop is only as trustworthy as the signal it diffs. A non-deterministic or cacheable signal breaks it in *both* directions, silently. (Found the hard way: a Python loop hashed unittest's full output — the `Ran N tests in 0.00Xs` timing line jittered, so identical code looked like progress; separately, same-second edits of equal byte-length reused stale `.pyc` bytecode, so changed code looked unchanged.)

**Fix**: fingerprint a stable projection — strip volatile lines before hashing (e.g. `grep -vE '^Ran [0-9]+ tests? in'` for unittest; filter timing/PID/path noise) — and make the check cache-immune (`python3 -B` plus clearing `__pycache__`; `--no-cache`; a clean build dir). Diff the *outcome* (pass/fail set, scores), not the raw transcript.

## Verdict

| Result | Condition |
|--------|-----------|
| **FAIL** | RULE 1 is CONCERN (no external check) — automatic, regardless of other rules |
| **FAIL** | Two or more of RULES 2–7 are CONCERN |
| **CONCERN** | Exactly one of RULES 2–7 is CONCERN |
| **PASS** | All seven rules PASS |

## Red Flags (auto-escalate to FAIL)

- Success condition is self-graded with no external signal (RULE 1)
- No cap *and* no no-progress stop — the loop can run forever (RULES 2+3)
- The agent can edit the test/threshold it is being judged against (RULE 5)
- The no-progress detector diffs a non-deterministic or cacheable signal — it never stops, or stops early (RULE 7)

## Output Shape

```
CW-LOOP CHECK
=============
Target: <path or description>
RULE 1 External check:        PASS | CONCERN — <cite + fix>
RULE 2 Hard cap:              PASS | CONCERN — <cite + fix>
RULE 3 No-progress stop:      PASS | CONCERN — <cite + fix>
RULE 4 Cap = non-success:     PASS | CONCERN — <cite + fix>
RULE 5 Check immutable:       PASS | CONCERN — <cite + fix>
RULE 6 Terminal states named: PASS | CONCERN — <cite + fix>
RULE 7 Signal deterministic:  PASS | CONCERN — <cite + fix>

Verdict: PASS | CONCERN | FAIL
```
