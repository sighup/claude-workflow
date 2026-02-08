# Test Executor Protocol

This protocol is used by the test-executor agent when executing a single E2E test step.

## Key Principle

Execute exactly ONE test step per invocation. The test defines expected behavior from the spec - verify the application meets that expectation.

## 4-Phase Protocol

### Phase 1: ORIENT

Load the test task and understand what to execute.

```
1. TaskGet({ taskId: "<task-id>" })
2. Extract from metadata:
   - action.type: "navigate", "interact", or "wait"
   - action.prompt: Natural language instruction for what to do
   - verify.prompt: Natural language instruction for what to check
   - verify.expected: Description of expected outcome
   - parent_suite: ID of parent task
3. TaskGet({ taskId: "<parent_suite>" })
   - Extract: base_url, automation.backend
4. Output orientation:
   "EXECUTING: [step_id] - [subject]"
   "Backend: [automation.backend]"
   "Action: [action.prompt]"
   "Verify: [verify.expected]"
```

### Phase 2: EXECUTE ACTION

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

### Phase 3: VERIFY & CAPTURE

Check the result and capture proof artifacts.

```
1. Execute verification based on verify.prompt:
   - Check current application state
   - Look for expected elements/text/behavior
   - Compare against verify.expected

2. Capture artifacts to artifacts/[step_id]-*.png or .txt:
   - Screenshot of current state (if browser backend)
   - Command output (if CLI backend)
   - User confirmation (if manual backend)

3. Determine pass/fail:
   - PASS: Actual state matches verify.expected
   - FAIL: Actual state does not match (indicates application bug)
```

### Phase 4: REPORT

Update task status and exit.

**If PASSED:**
```
TaskUpdate({
  taskId: "<task-id>",
  status: "completed",
  metadata: {
    test_status: "passed",
    passed_at: "<ISO timestamp>",
    artifacts: {
      screenshots: ["artifacts/[step_id]-result.png"]
    }
  }
})
```

**If FAILED:**
```
TaskUpdate({
  taskId: "<task-id>",
  status: "completed",
  metadata: {
    test_status: "failed",
    failed_at: "<ISO timestamp>",
    failure_reason: "[specific description of what went wrong]",
    artifacts: {
      screenshots: ["artifacts/[step_id]-failure.png"]
    }
  }
})
```

Output result and exit:
```
"[✓] PASSED: [step_id]" or "[✗] FAILED: [step_id] - [failure_reason]"
```

## Constraints

- Execute exactly ONE step per invocation
- Always update task status before exiting
- Never proceed to next step (orchestrator handles that)
- Never modify other tasks
- Use test credentials only (never real credentials)
- Capture artifacts appropriate to the backend type
