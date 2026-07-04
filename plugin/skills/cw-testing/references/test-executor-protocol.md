# Test Executor Protocol

This protocol is used by the test-executor agent when executing a single E2E test step.

## Key Principle

Execute exactly ONE test step per invocation. The test defines expected behavior from the spec - verify the application meets that expectation.

## 4-Step Protocol

### Step 1: Orient

Read the test step from the spawn prompt and understand what to execute. You hold no Task tools — the orchestrator delivers the step and its parent-suite context inline.

```
1. Read the step assignment from the spawn prompt:
   - action.type: "navigate", "interact", or "wait"
   - action.prompt: Natural language instruction for what to do
   - verify.prompt: Natural language instruction for what to check
   - verify.expected: Description of expected outcome
   - task_id: stable id of this step
2. Read the parent-suite context (also inline in the prompt):
   - base_url, automation.backend, artifacts_dir (default to "artifacts" if absent)
3. Output orientation:
   "EXECUTING: [step_id] - [subject]"
   "Backend: [automation.backend]"
   "Action: [action.prompt]"
   "Verify: [verify.expected]"
```

### Step 2: Execute Action

Perform the action described in `action.prompt` using the configured `automation.backend`.

**Interpret the natural language prompt and execute using available tools:**

| Action Type | Intent |
|-------------|--------|
| `navigate` | Go to a URL or change pages |
| `interact` | Fill forms, click buttons, type text |
| `wait` | Wait for elements, content, or state |

**Backend determines which tools to use:**
- Browser backends → Use browser automation tools available in your context
- CLI backend → Use Bash for curl, scripts, API calls
- Manual backend → Output instructions, ask user to confirm via AskUserQuestion

The action prompt is natural language - interpret it and execute the appropriate operations. For example:
- "Navigate to /login" → Load the login page
- "Enter 'test@example.com' in the email field" → Find email input, fill it
- "Click the Submit button" → Find and click the submit button
- "Wait for the dashboard to load" → Wait for expected content

### Step 3: Verify and Capture

Check the result and capture proof artifacts.

```
1. Execute verification based on verify.prompt:
   - Check current application state
   - Look for expected elements/text/behavior
   - Compare against verify.expected

2. Capture artifacts to [artifacts_dir]/[step_id]-*.png or .txt:
   - Screenshot of current state (if browser backend)
   - Command output (if CLI backend)
   - User confirmation (if manual backend)

3. Determine pass/fail:
   - PASS: Actual state matches verify.expected
   - FAIL: Actual state does not match (indicates application bug)
```

### Step 4: Report

Emit the result as a RESULT BLOCK and exit. You hold no Task tools; the testing orchestrator harvests this block and applies the `test_result` `TaskUpdate` itself (sole writer).

**If PASSED:**
```
CW-RESULT-BLOCK-START
{
  "task_id": "<task_id>",
  "status": "completed",
  "test_result": "passed",
  "passed_at": "<ISO timestamp>",
  "artifacts": { "screenshots": ["[artifacts_dir]/[step_id]-result.png"] }
}
CW-RESULT-BLOCK-END
```

**If FAILED:**
```
CW-RESULT-BLOCK-START
{
  "task_id": "<task_id>",
  "status": "completed",
  "test_result": "failed",
  "failed_at": "<ISO timestamp>",
  "failure_reason": "[specific description of what went wrong]",
  "artifacts": { "screenshots": ["[artifacts_dir]/[step_id]-failure.png"] }
}
CW-RESULT-BLOCK-END
```

Output result and exit:
```
"[✓] PASSED: [step_id]" or "[✗] FAILED: [step_id] - [failure_reason]"
```

## Constraints

- Execute exactly ONE step per invocation
- Always emit the RESULT BLOCK before exiting
- Never proceed to next step (orchestrator handles that)
- Never write the board — the orchestrator applies every update
- Use test credentials only (never real credentials)
- Capture artifacts appropriate to the backend type
