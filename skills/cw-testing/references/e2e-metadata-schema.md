# E2E Test Task Metadata Schema

This document defines the metadata structure for E2E test tasks created by `/cw-testing init`. Each test task carries test-specific metadata enabling autonomous execution with regression checking.

## Full Schema

### Parent Suite Task

```json
{
  "test_type": "e2e",
  "test_suite": true,
  "base_url": "http://localhost:3000",

  "database": {
    "setup": "npx prisma db seed",
    "teardown": "npx prisma migrate reset --force"
  },

  "regression_check": true,
  "regression_failures": [],

  "automation": {
    "backend": "chrome-devtools",
    "detected_tools": ["chrome-devtools", "bash"],
    "user_selected": "chrome-devtools"
  },

  "loop_config": {
    "max_iterations": 50,
    "max_consecutive_failures": 3
  },

  "fix_config": {
    "enabled": true,
    "max_attempts": 2
  },

  "stats": {
    "total_steps": 5,
    "passed": 3,
    "failed": 1,
    "pending": 1,
    "blocked": 0,
    "last_run": "2026-01-15T10:35:00Z"
  }
}
```

### Test Step Task

Uses natural language prompts for action and verification:

```json
{
  "test_type": "e2e",
  "test_status": "pending",
  "parent_suite": "T01",
  "step_number": 2,

  "action": {
    "type": "interact",
    "prompt": "Enter 'test@example.com' in the email field, 'Password123!' in the password field, then click the Login button"
  },

  "verify": {
    "prompt": "Verify the dashboard is visible with a welcome message containing the user's email",
    "expected": "Dashboard visible with welcome message"
  },

  "artifacts": {
    "screenshots": [
      "artifacts/S02-action.png",
      "artifacts/S02-verify.png"
    ],
    "logs": [
      "artifacts/S02-log.txt"
    ]
  },

  "passed_at": null,
  "failed_at": null,
  "failure_reason": null,
  "execution_time_ms": null,

  "fix_attempt": 0,
  "max_fix_attempts": 2,
  "linked_fix_task": null,
  "fix_history": [],
  "blocked_reason": null
}
```

## Field Definitions

### Parent Suite Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `test_type` | string | Yes | Always "e2e" |
| `test_suite` | boolean | Yes | True for parent suite task |
| `base_url` | string | Yes | Application URL for testing |
| `database.setup` | string | No | Command to setup test database |
| `database.teardown` | string | No | Command to reset database after tests |
| `regression_check` | boolean | Yes | Enable regression checking between steps |
| `regression_failures` | array | Yes | List of detected regressions |
| `automation.backend` | string | Yes | Selected backend: "chrome-devtools", "playwright", "cli", or "manual" |
| `automation.detected_tools` | array | No | List of tools detected during init |
| `automation.user_selected` | string | No | User's explicit choice (if different from detected) |
| `loop_config.max_iterations` | number | No | Max test loop iterations (default 50) |
| `loop_config.max_consecutive_failures` | number | No | Stop after N consecutive failures (default 3) |
| `fix_config.enabled` | boolean | No | Enable auto-fix loop (default true) |
| `fix_config.max_attempts` | number | No | Max fix attempts per test (default 2) |
| `stats.total_steps` | number | No | Total test steps |
| `stats.passed` | number | No | Count of passed steps |
| `stats.failed` | number | No | Count of failed steps |
| `stats.pending` | number | No | Count of pending steps |
| `stats.last_run` | string | No | ISO timestamp of last run |

### Test Step Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `test_type` | string | Yes | Always "e2e" |
| `test_status` | string | Yes | "pending", "passed", "failed", or "blocked" |
| `parent_suite` | string | Yes | Task ID of parent suite |
| `step_number` | number | Yes | Order in test sequence (1-based) |
| `action.type` | string | Yes | Action type: "navigate", "interact", or "wait" |
| `action.prompt` | string | Yes | Natural language instruction for what to do |
| `verify.prompt` | string | Yes | Natural language instruction for what to check |
| `verify.expected` | string | Yes | Description of expected outcome |
| `artifacts.screenshots` | array | No | Paths to captured screenshots |
| `artifacts.logs` | array | No | Paths to captured logs |
| `passed_at` | string | No | ISO timestamp when passed |
| `failed_at` | string | No | ISO timestamp when failed |
| `failure_reason` | string | No | Description of why test failed |
| `execution_time_ms` | number | No | How long the test took |
| `fix_attempt` | number | No | Current fix attempt count (starts at 0) |
| `max_fix_attempts` | number | No | Max fix attempts allowed (default 2) |
| `linked_fix_task` | string | No | ID of current/last fix task |
| `fix_history` | array | No | History of fix attempts |
| `blocked_reason` | string | No | Why test is blocked (if status is blocked) |

## Action Types

Actions use natural language prompts that the test executor interprets.

### navigate

Go to a URL or click links that change pages.

```json
{
  "action": {
    "type": "navigate",
    "prompt": "Navigate to /login"
  }
}
```

**Example prompts:**
- "Navigate to /login"
- "Click the 'Dashboard' link in the navigation menu"
- "Go back to the previous page"

### interact

Fill forms, click buttons, type text, select options.

```json
{
  "action": {
    "type": "interact",
    "prompt": "Enter 'test@example.com' in the email field, 'Password123!' in the password field, then click the Login button"
  }
}
```

**Example prompts:**
- "Enter 'test@example.com' in the email field"
- "Click the Submit button"
- "Select 'United States' from the country dropdown"
- "Check the 'Remember me' checkbox"

### wait

Wait for elements, animations, or async operations.

```json
{
  "action": {
    "type": "wait",
    "prompt": "Wait for the loading spinner to disappear and the dashboard content to be visible"
  }
}
```

**Example prompts:**
- "Wait for the page to finish loading"
- "Wait for the success message to appear"
- "Wait for the modal to close"

## Verification Prompts

Verification uses natural language to describe what to check.

```json
{
  "verify": {
    "prompt": "Verify the dashboard is visible with a welcome message containing the user's email",
    "expected": "Dashboard visible with welcome message"
  }
}
```

**Good verification prompts:**
- "Verify the page title is 'Dashboard' and a welcome message containing the user's email is visible"
- "Verify an error message is displayed below the password field"
- "Verify the URL has changed to '/dashboard'"

**Bad verification prompts:**
- "Verify it works" (too vague)
- "Check the API returned 200" (not visually verifiable)

## Test Status Values

| Status | Meaning | Set When |
|--------|---------|----------|
| `pending` | Not yet executed | Initial state, after reset |
| `passed` | Test succeeded | All proof artifacts passed |
| `failed` | Test did not succeed | Any proof artifact failed |
| `blocked` | Cannot run due to dependencies | A blocking test failed |

## Fix Task Schema

When a test fails, it indicates an application bug. A fix task is created to track the bug investigation and fix:

```json
{
  "task_type": "e2e-fix",
  "fix_task_id": "FIX-T02-1",
  "failed_test_id": "T02",
  "attempt_number": 1,

  "failure_context": {
    "failure_reason": "Login button not found - no element matches expected UI",
    "spec_requirement": "User should see a Login button to submit credentials",
    "action": {
      "type": "interact",
      "prompt": "Click the Login button to submit the form"
    },
    "verify": {
      "prompt": "Verify the page redirects to /dashboard",
      "expected": "Dashboard visible with welcome message"
    },
    "artifacts": {
      "screenshots": ["artifacts/T02-failure.png"],
      "logs": ["artifacts/T02-console.log"]
    }
  },

  "fix_result": null,
  "fix_description": null,
  "commit_sha": null,
  "files_changed": [],
  "investigation_notes": null,
  "completed_at": null
}
```

**Key Principle**: The test is the oracle. `spec_requirement` describes what the spec says should happen. `failure_reason` describes what the application actually did. The bug is in the application code, not the test.
```

### Fix Task Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `task_type` | string | Yes | Always "e2e-fix" |
| `fix_task_id` | string | Yes | Unique ID: FIX-{test_id}-{attempt} |
| `failed_test_id` | string | Yes | ID of the test that failed |
| `attempt_number` | number | Yes | Which fix attempt (1-based) |
| `failure_context` | object | Yes | Context from failed test |
| `failure_context.failure_reason` | string | Yes | What the application actually did (the bug) |
| `failure_context.spec_requirement` | string | Yes | What the spec says should happen (expected) |
| `failure_context.action` | object | Yes | The action that was attempted |
| `failure_context.verify` | object | Yes | The verification that failed |
| `failure_context.artifacts` | object | No | Screenshots and logs from failure |
| `fix_result` | string | No | "success" or "failed" |
| `fix_description` | string | No | What bug was fixed or why fix failed |
| `commit_sha` | string | No | Git commit SHA if fix succeeded |
| `files_changed` | array | No | List of APPLICATION files modified |
| `investigation_notes` | string | No | Notes from investigation phase |
| `completed_at` | string | No | ISO timestamp when fix completed |

## Fix History Object

Each entry in a test's `fix_history` array:

```json
{
  "fix_task_id": "FIX-T02-1",
  "attempt": 1,
  "result": "success",
  "commit_sha": "abc1234",
  "description": "Updated login button selector",
  "timestamp": "2026-01-15T10:32:00Z"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `fix_task_id` | string | ID of the fix task |
| `attempt` | number | Fix attempt number |
| `result` | string | "success" or "failed" |
| `commit_sha` | string | Commit SHA (if success) |
| `description` | string | What was done |
| `timestamp` | string | When fix completed |

## Regression Failure Object

When a previously-passed test fails during regression checking:

```json
{
  "task_id": "T01.1",
  "detected_at": "2026-01-15T10:30:00Z",
  "error": "Element [data-testid='login-button'] not found",
  "screenshot": "artifacts/T01.1-regression-2026-01-15.png",
  "previous_passed_at": "2026-01-14T15:00:00Z"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `task_id` | string | ID of the regressed test |
| `detected_at` | string | When regression was detected |
| `error` | string | What went wrong |
| `screenshot` | string | Screenshot showing the regression |
| `previous_passed_at` | string | When this test last passed |

## Example: Complete Test Suite

### Parent Task

```
Subject: E2E: User Authentication Flow
Description: End-to-end tests for login, registration, and logout flows.
```

```json
{
  "test_type": "e2e",
  "test_suite": true,
  "base_url": "http://localhost:3000",
  "database": {
    "setup": "npm run db:seed:test",
    "teardown": null
  },
  "regression_check": true,
  "regression_failures": [],
  "stats": {
    "total_steps": 5,
    "passed": 0,
    "failed": 0,
    "pending": 5
  }
}
```

### Step 1: Navigate to Login

```
Subject: Test: User can navigate to login page
Description: Verify the login page is accessible and displays the login form.
```

```json
{
  "test_type": "e2e",
  "test_status": "pending",
  "parent_suite": "T01",
  "step_number": 1,
  "action": {
    "type": "navigate",
    "prompt": "Navigate to /login"
  },
  "verify": {
    "prompt": "Verify the login form is displayed with email and password fields and a Login button",
    "expected": "Login form visible with all fields"
  },
  "artifacts": {
    "screenshots": [],
    "logs": []
  }
}
```

### Step 2: Enter Credentials

```
Subject: Test: User can enter login credentials
Description: Verify user can type email and password into the form.
```

```json
{
  "test_type": "e2e",
  "test_status": "pending",
  "parent_suite": "T01",
  "step_number": 2,
  "action": {
    "type": "interact",
    "prompt": "Enter 'test@example.com' in the email field and 'TestPassword123!' in the password field"
  },
  "verify": {
    "prompt": "Verify both fields show the entered values (password may be masked)",
    "expected": "Form fields filled with credentials"
  },
  "artifacts": {
    "screenshots": [],
    "logs": []
  }
}
```

### Step 3: Submit Login

```
Subject: Test: User can submit login form
Description: Verify form submission redirects to dashboard.
```

```json
{
  "test_type": "e2e",
  "test_status": "pending",
  "parent_suite": "T01",
  "step_number": 3,
  "action": {
    "type": "interact",
    "prompt": "Click the Login button to submit the form"
  },
  "verify": {
    "prompt": "Verify the page redirects to /dashboard and displays a welcome message with the user's email",
    "expected": "Dashboard visible with welcome message"
  },
  "artifacts": {
    "screenshots": [],
    "logs": []
  }
}
```
