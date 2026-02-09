# Regression Checking Protocol

This document describes how regression checking works in `/cw-testing run` to ensure previously passing tests continue to pass.

## Overview

Regression checking is a critical feature that distinguishes E2E testing from simple task completion. Before executing each new test step, the system re-verifies ALL previously passed steps to detect if recent changes have broken existing functionality.

## When Regression Checks Run

```
For each iteration of the test loop:
  1. BEFORE executing the next pending test
  2. AFTER the previous test completes
  3. Only if regression_check: true on parent suite
```

### Flow Diagram

```
START
  │
  ├─ Get next pending test
  │
  ├─ Are there any passed tests?
  │   │
  │   ├─ NO → Execute next test
  │   │
  │   └─ YES → Run regression check
  │             │
  │             ├─ All passed tests still pass?
  │             │   │
  │             │   ├─ YES → Execute next test
  │             │   │
  │             │   └─ NO → STOP (regression detected)
  │
  └─ Continue loop
```

## Regression Check Process

### Step 1: Collect Passed Tests

```
passed_tests = []
for each task in TaskList():
  if task.metadata.test_type == "e2e" and
     task.metadata.test_status == "passed":
    passed_tests.append(task)

# Sort by step_number to verify in order
passed_tests.sort(key=lambda t: t.metadata.step_number)
```

### Step 2: Re-Execute Proof Artifacts

For each passed test, re-execute its proof artifacts:

```
for task in passed_tests:
  for artifact in task.metadata.proof_artifacts:
    result = execute_artifact(artifact)

    if result.failed:
      # Regression detected!
      return RegressionFailure(
        task_id=task.id,
        artifact=artifact,
        error=result.error
      )
```

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

### For Each Proof Artifact Type

| Type | Regression Check |
|------|-----------------|
| navigate | Page loads without error |
| click | Element exists and is clickable |
| fill | Element exists and accepts input |
| assert | Expected text/element is present |
| screenshot | Page renders (check for error states) |
| wait | Expected content appears within timeout |

### Regression Check Modes

**Full Mode (Default)**
- Re-execute all actions in proof_artifacts
- Verify expected outcomes match
- Most thorough but slowest

**Quick Mode (`--regression=quick`)**
- Only check assertions (skip navigate/click/fill)
- Faster but less thorough
- Good for frequent runs

**Skip Mode (`--no-regression`)**
- Skip regression checking entirely
- Fastest but risky
- Use only for development/debugging

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
  3. Run `/cw-testing status` to see full test state

Test loop stopped. Fix the regression and run `/cw-testing run` again.
════════════════════════════════════════════════════════
```

## Handling Edge Cases

### Test Depends on State

Some tests may depend on state created by earlier tests (e.g., "logged in" state). The regression check should:

1. Run tests in order (by step_number)
2. Allow state to accumulate
3. Reset state between regression check rounds if needed

### Flaky Tests

If a test occasionally fails due to timing:

```json
{
  "proof_artifacts": [
    {
      "action": "wait",
      "text": "Dashboard",
      "timeout": 10000,
      "retry": 3
    }
  ]
}
```

The `retry` field allows re-attempting before marking as failed.

### Parallel Tests

Tests with no dependencies can be marked as parallelizable:

```json
{
  "metadata": {
    "parallel_safe": true
  }
}
```

However, regression checks always run sequentially to ensure state consistency.

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CW_REGRESSION_MODE` | `full` | "full", "quick", or "skip" |
| `CW_REGRESSION_RETRY` | `1` | Retries per artifact before failing |
| `CW_REGRESSION_TIMEOUT` | `30000` | Max time per test (ms) |

### Parent Suite Metadata

```json
{
  "regression_check": true,
  "regression_config": {
    "mode": "full",
    "retry_count": 2,
    "timeout_ms": 30000,
    "stop_on_first_failure": true
  }
}
```

## Why Regression Checking Matters

### Without Regression Checking

```
Step 1: PASS (login page loads)
Step 2: PASS (can enter credentials)
Step 3: PASS (can submit form)  ← Changes introduced here break Step 1
Step 4: PASS (can see dashboard)
Step 5: FAIL (can log out)

Result: Test 5 fails, but the real issue is in Step 3's changes
```

### With Regression Checking

```
Step 1: PASS (login page loads)
Step 2: PASS (can enter credentials)
Step 3: PASS (can submit form)  ← Changes break Step 1

Regression check before Step 4:
  Step 1: FAIL - Login page no longer loads!

Result: Immediately identifies Step 3's changes broke Step 1
```

## Best Practices

1. **Keep Tests Atomic**: Each test should verify one thing
2. **Use Stable Selectors**: Prefer `data-testid` over CSS classes
3. **Set Appropriate Timeouts**: Long enough for real scenarios, short enough to fail fast
4. **Document Dependencies**: Make test order explicit via blockedBy
5. **Review Regressions Promptly**: Don't let regressions accumulate
6. **Consider Test Isolation**: Reset state between test runs if needed
