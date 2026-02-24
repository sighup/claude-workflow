# Regression Checking Protocol

This document describes how regression checking works in `/cw-testing run` to ensure previously passing tests continue to pass.

## Overview

Regression checking is a critical feature that distinguishes E2E testing from simple task completion. At session start and after each bug fix, the system re-verifies ALL previously passed steps to detect if recent changes have broken existing functionality.

## When Regression Checks Run

Once at session start (before the first test) and after each bug fix, if `regression_check: true` on the parent suite.

### Flow Diagram

```
START
  │
  ├─ Pre-run regression check (all passed tests)
  │   │
  │   ├─ All pass → begin loop
  │   └─ Any fail → STOP (regression detected)
  │
  ├─ Loop: select → execute → verify
  │
  ├─ Bug fix applied?
  │   │
  │   └─ YES → regression check (all passed tests)
  │             │
  │             ├─ All pass → continue loop
  │             └─ Any fail → STOP (regression detected)
  │
  └─ Continue loop
```

## Regression Check Process

### Step 1: Collect Passed Tests

Call `TaskList`. For each task with `test_type == "e2e"` and `test_result == "passed"`, collect it. Sort by `step_number` ascending.

### Step 2: Re-Execute Passed Tests

For each passed test, re-execute it using the suite's automation backend (read from parent suite `automation.backend`):

**playwright-bdd backend:**
```bash
npx playwright test --config [playwright_config] \
  --grep "[scenario title]" --reporter=json
```
Parse `results.json`: `spec.ok == true` → pass; `spec.ok == false` → regression detected.

**Other backends (chrome-devtools, cli, manual):**
Spawn a `test-executor` sub-agent per passed test:
```
Task({
  subagent_type: "claude-workflow:test-executor",
  prompt: "Execute test step [step_id]. Task ID: [native-task-id]. Read protocol at: skills/cw-testing/references/test-executor-protocol.md"
})
```
Read `test_result` via `TaskGet`. If `test_result != "passed"` → regression detected.

### Step 3: Handle Results

**All Passed:**
```
Output: "✓ Regression check: N passed tests verified"
Continue to execute next pending test
```

**Regression Detected:**
```
1. Stop the loop immediately
2. Capture screenshot of current state
3. Update parent suite metadata:
   {
     regression_failures: [
       {
         task_id: "<regressed-task>",
         detected_at: "<ISO timestamp>",
         error: "<what failed>",
         screenshot: "artifacts/<task>-regression.png"
       }
     ]
   }
4. Output regression report
5. Exit with non-zero status
```

## What to Check During Regression

Re-run the full test (action + verify) just as during initial execution. The test's `verify.prompt` defines what must still be true. A passed test that fails on re-execution is a regression regardless of which specific element changed.

## Output Format

### During Regression Check

```
[✓] Regression check: 3 passed tests
    T01.1: User can navigate to login .......... PASS
    T01.2: User can enter credentials ........... PASS
    T01.3: User can submit login form ........... PASS
```

### On Regression Failure

```
[!] REGRESSION DETECTED
════════════════════════════════════════════════════════
Task: T01.2 - User can enter credentials
Previously Passed: 2026-01-14T15:00:00Z

Failing Artifact:
  Action: fill
  Selector: [data-testid='email-input']
  Expected: Email is entered

Error: Element not found: [data-testid='email-input']
  The email input field is no longer present on the page.
  This may indicate a UI change or rendering issue.

Screenshot: artifacts/T01.2-regression-2026-01-15.png

Recommendation:
  1. Check recent commits for changes to the login form
  2. Verify the data-testid attribute is still present
  3. Invoke `/cw-testing` to see current test state

Test loop stopped. Fix the regression and invoke `/cw-testing` again.
════════════════════════════════════════════════════════
```

## Handling Edge Cases

### Test Depends on State

Some tests may depend on state created by earlier tests (e.g., "logged in" state). The regression check should:

1. Run tests in order (by step_number)
2. Allow state to accumulate
3. Reset state between regression check rounds if needed

### Flaky Tests

If a test occasionally fails due to timing, increase the timeout in `action.prompt` (e.g., "Wait up to 10 seconds for the spinner to disappear") or add an explicit `wait` step before the flaky action.

### Parallel Tests

Regression checks always run sequentially in `step_number` order to ensure state consistency. Tests are re-executed one at a time regardless of how they were originally run.

