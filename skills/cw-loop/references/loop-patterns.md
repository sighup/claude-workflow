# Loop Patterns Reference

Four named patterns cover almost every bounded loop. Each pairs a goal with an external check and a hard stop; they differ in **what the check is** and **how the loop knows it is done**. Pick by the shape of the check, then bound it.

The empirical headline across all four: loops help when the check is an **external, re-runnable signal** (test, command exit code, a *separate* judge, oracle feedback). Loops that close around the agent's own satisfaction do not reliably help and can degrade output. Every pattern below assumes an external check — that is non-negotiable.

---

## 1. Generate-Verify-Refine

**Shape**: generate an attempt → an independent check evaluates it → if it fails, feed the failure back and refine → repeat.

**Use when**: there is a crisp pass/fail or scored check that is *separate from the generator* — a test suite, a type-checker, a linter, a rubric scored by a different agent.

**Key rule**: the verifier must be independent of the generator. A generator grading its own work is intrinsic self-correction, which is the weak case. The system's own `cw-execute` Step 9 spawns a **read-only** `proof-verifier` child for exactly this reason.

**Bounds**: cap iterations (3–5 is typical); stop early on `no-progress` if the failing check is identical two iterations running.

```
attempt = generate(goal)
for i in 1..CAP:
    verdict = verify(attempt)          # external, independent
    if verdict.passed: return success(verdict)
    if verdict == last_verdict: return no_progress(verdict)
    attempt = refine(attempt, verdict) # feedback carried forward
    last_verdict = verdict
return exhausted(last_verdict)
```

---

## 2. Loop-Until-Dry

**Shape**: repeatedly run a finder/worker that surfaces remaining work → process it → stop when K consecutive passes surface nothing new.

**Use when**: the amount of work is unknown up front (find all bugs, fix every lint error, migrate every call site) and a simple "while count > 0" would miss the long tail.

**Key rule**: dedup against everything seen so far, not just the last batch, or rejected items reappear and the loop never converges. Stop on K dry passes (K=2 is a good default), not the first dry pass.

**Bounds**: the K-dry-passes condition is the `clean-noop`/`success` stop; still cap total iterations as a backstop against a finder that always surfaces noise.

```
seen = {}; dry = 0
for i in 1..CAP:
    fresh = find() - seen
    if fresh is empty:
        dry += 1
        if dry >= K: return success(seen)   # converged
        continue
    dry = 0; seen += fresh
    process(fresh)
return exhausted(seen)
```

---

## 3. Budget-Bounded

**Shape**: keep iterating toward the goal while spend (tokens, dollars, wall-clock, iterations) stays under a ceiling; stop the moment the ceiling is hit.

**Use when**: the goal is open-ended or improvement is incremental (deepen a search, accumulate findings toward a target count, polish until time runs out) and the real constraint is cost.

**Key rule**: hitting the ceiling is `exhausted`, not `success`. Report how far it got. Mirrors the Claude Agent SDK's `max_budget_usd` → `error_max_budget_usd`.

**Bounds**: the budget *is* the bound; add a `no-progress` stop so a stalled loop returns budget early instead of grinding to the ceiling.

```
while spend() < BUDGET:
    result = step()
    if check(result).passed: return success(result)
    if stalled(): return no_progress(result)
return exhausted(result)        # ran out of budget, not done
```

---

## 4. Self-Healing

**Shape**: run the system → detect a failure → diagnose and fix → re-run to confirm → guard against regressions → repeat.

**Use when**: the loop both detects and repairs (failing E2E test → fix the app → re-run; flaky deploy → remediate → re-verify). This is `cw-testing`'s auto-fix loop.

**Key rule**: fix the *system under test*, never the check. Editing the test to pass is reward hacking. After every fix, re-run the previously-passing checks — a fix that breaks a green check is a regression, and `no-progress`/`blocked` should fire rather than thrashing.

**Bounds**: cap fix attempts per failure (`cw-testing` uses `max_fix_attempts`); exceed it → `blocked`, not silent skip.

```
for failure in failures():
    for attempt in 1..MAX_FIX:
        fix(failure)              # fix the system, never the check
        if not check(failure).passed: continue
        if regressed(passing_set): return blocked("fix caused regression")
        break
    else:
        mark_blocked(failure)     # exhausted fix attempts
```

---

## Choosing

| If the check is… | …use |
|---|---|
| a separate pass/fail or scored evaluation | Generate-Verify-Refine |
| "is there anything left?" over an unknown-size set | Loop-Until-Dry |
| "keep improving while we can afford to" | Budget-Bounded |
| detect-and-repair with regression risk | Self-Healing |

Patterns compose: a self-healing loop's inner fix is often generate-verify-refine; a loop-until-dry sweep is often budget-bounded as a backstop. Name the **outer** pattern by the outer stop condition.
