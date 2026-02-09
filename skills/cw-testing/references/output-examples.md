# Output Examples

Examples of output formats for `/cw-testing` subcommands.

## Run Output

### Successful Iteration

```
Iteration 1/50
─────────────────────────────────────────
[✓] Regression check: 0 passed steps verified
[~] Executing: T01 - User can navigate to login page
[✓] T01 PASSED
```

### Failed Test with Bug Fix

```
Iteration 2/50
─────────────────────────────────────────
[✓] Regression check: T01 verified
[~] Executing: T02 - User can enter credentials
[✗] T02 FAILED: Login button not found

[⚙] BUG FIX ATTEMPT 1/2
    Creating fix task: FIX-T02-1
    Spawning bug fixer agent...
    Bug found: LoginForm component missing submit button
    Fix applied: Added submit button to LoginForm.tsx
    Commit: abc1234 fix(auth): add missing login submit button
[→] Resetting T02 to pending for regression test
```

### Bug Fix Failed

```
[⚙] BUG FIX ATTEMPT 1/2
    Creating fix task: FIX-T03-1
    Spawning bug fixer agent...
    Investigating: Dashboard component exists but not receiving user data
[✗] Could not fix: Multiple potential causes - state management unclear

[B] T03 BLOCKED: Max fix attempts (2) exceeded
    Manual intervention required
```

## Run Completion

### All Passed

```
CW-TESTING RUN COMPLETE
=======================
Suite: E2E: Login Flow Tests
Iterations: 8

Results:
  [✓] T01: User can navigate to login page
  [✓] T02: User can enter credentials (bug fixed: abc1234)
  [✓] T03: User can submit login form

Status: ALL PASSED (3/3)
Bugs fixed: 1 (abc1234 - Added missing login submit button)
```

### With Blocked Tests

```
CW-TESTING RUN COMPLETE
=======================
Suite: E2E: Login Flow Tests
Iterations: 15

Results:
  [✓] T01: User can navigate to login page
  [✓] T02: User can enter credentials (bug fixed: abc1234)
  [B] T03: User sees dashboard
       Blocked: Max fix attempts exceeded

Status: 2/3 PASSED, 1 BLOCKED
Bug fixes: 3 attempted (1 successful, 2 need manual intervention)

Review fix task investigation notes, then run `/cw-testing reset --step T03`.
```

## Status Output

```
CW-TESTING STATUS
=================
E2E Test Suite: [name]
Base URL: [url]
─────────────────────────────────────────
  [✓] T01: User can navigate to login page
       Passed: 2026-01-15T10:30:00Z

  [✓] T02: User can enter credentials
       Passed: 2026-01-15T10:30:15Z (after bug fix)
       Bug fixed: abc1234

  [~] T03: User can submit login form
       Status: in_progress

  [ ] T04: User sees error for invalid credentials
       Status: pending (blocked by T03)

  [B] T05: User can update profile
       Blocked: Max fix attempts exceeded
─────────────────────────────────────────
Progress: 2/5 passed, 1 in progress, 1 pending, 1 blocked
```

## Status Icons

| Icon | Meaning |
|------|---------|
| `[✓]` | Test passed |
| `[✗]` | Test failed |
| `[~]` | Test in progress |
| `[ ]` | Test pending |
| `[!]` | Regression detected |
| `[B]` | Test blocked |

## Init Output

```
CW-TESTING INIT COMPLETE
========================
Test Suite: E2E: [name]
Base URL: http://localhost:3000
Automation: chrome-devtools
Steps: 5

Test Steps Created:
  T01: User can navigate to login page
  T02: User can enter credentials (blocked by T01)
  T03: User can submit login form (blocked by T02)

Run `/cw-testing run` to execute the test suite.
```

## Reset Output

```
CW-TESTING RESET COMPLETE
=========================
Reset: 5 test tasks
Fix tasks: kept
Artifacts: cleared

Run `/cw-testing run` to start fresh.
```
