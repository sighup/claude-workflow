# Bug Fixer Protocol

This protocol is used by the test-fixer agent when investigating and fixing application bugs detected by E2E tests.

## Key Principle

**The test is the oracle.** Tests define expected behavior from the spec. When a test fails, the **application code** has a bug - the test is correct by definition. This protocol fixes application bugs, never test code.

## 5-Phase Protocol

### Phase 1: ORIENT

Load fix task and understand the failure context.

```
1. TaskGet({ taskId: "<fix-task-id>" })
2. Extract from metadata:
   - failed_test_id: The test that failed
   - attempt_number: Which fix attempt this is (1-based)
   - failure_context.failure_reason: What the application actually did (the bug)
   - failure_context.spec_requirement: What the spec says should happen
   - failure_context.action: The action that was attempted
   - failure_context.verify: The verification that failed
   - failure_context.artifacts: Screenshots and logs from failure
3. Output orientation:
   "BUG FIX ATTEMPT [N]: [test_id] failed"
   "Expected: [spec_requirement]"
   "Actual: [failure_reason]"
```

### Phase 2: INVESTIGATE

Identify the application bug causing the test failure.

```
Investigation checklist:
1. Read failure artifacts (screenshots, logs, console errors)
2. Understand what the spec requires vs what app does
3. Search APPLICATION code for the bug:
   - Glob for component/service files related to the feature
   - Grep for relevant function names, API endpoints
   - Read source files in the implementation
4. Check recent git history:
   - git log --oneline -10 -- <relevant-files>
5. Identify the root cause in APPLICATION code:
   - Missing functionality?
   - Incorrect logic?
   - Wrong state management?
   - API returning wrong data?
   - UI not rendering correctly?

IMPORTANT: The bug is in the APPLICATION, not the test.

Output investigation summary:
"ROOT CAUSE: [description of the application bug]"
"AFFECTED FILES: [list of application files to fix]"
"FIX APPROACH: [description of the minimal fix]"
```

### Phase 3: IMPLEMENT

Fix the application bug with minimal changes.

```
1. Make ONLY the necessary changes to APPLICATION code
2. NEVER modify test files - the tests are correct
3. Follow existing code patterns and style
4. Run linter if available:
   - npm run lint --fix (if package.json has lint script)
5. Verify the change is minimal:
   - Touch as few files as possible
   - Change as few lines as possible
   - Only implement what the spec requires

Anti-patterns to avoid:
- Modifying test code or assertions
- Adding try/catch to hide errors
- Adding timeouts/sleeps to mask race conditions
- Over-engineering beyond spec requirements
- Refactoring unrelated code
```

### Phase 4: COMMIT

Create a descriptive fix commit.

```
1. Stage only the changed files:
   git add <specific-application-files>

2. Create commit with descriptive message:
   git commit -m "$(cat <<'EOF'
   fix([area]): [short description of bug fixed]

   - [bullet point explaining the change]
   - Fixes: [test_id] - [what spec requirement is now satisfied]

   Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
   EOF
   )"

3. Capture commit SHA:
   git rev-parse --short HEAD
```

### Phase 5: REPORT

Update tasks with fix results.

**If fix succeeded:**
```
TaskUpdate({
  taskId: "<fix-task-id>",
  status: "completed",
  metadata: {
    fix_result: "success",
    fix_description: "[what bug was fixed]",
    commit_sha: "[sha]",
    files_changed: ["path/to/app/file.ts"],
    completed_at: "<ISO timestamp>"
  }
})

TaskUpdate({
  taskId: "<linked-test-task-id>",
  status: "pending",
  metadata: {
    test_status: "pending",
    linked_fix_task: "<fix-task-id>",
    fix_history: [...existing, {
      fix_task_id: "<fix-task-id>",
      attempt: N,
      result: "success",
      commit_sha: "[sha]",
      description: "[what was fixed]",
      timestamp: "<ISO timestamp>"
    }]
  }
})
```

**If fix failed (cannot determine solution):**
```
TaskUpdate({
  taskId: "<fix-task-id>",
  status: "completed",
  metadata: {
    fix_result: "failed",
    fix_description: "Unable to determine fix: [reason]",
    investigation_notes: "[what was tried, what was found]",
    completed_at: "<ISO timestamp>"
  }
})

TaskUpdate({
  taskId: "<linked-test-task-id>",
  metadata: {
    fix_history: [...existing, {
      fix_task_id: "<fix-task-id>",
      attempt: N,
      result: "failed",
      reason: "[why fix couldn't be determined]",
      timestamp: "<ISO timestamp>"
    }]
  }
})
```

Output result and exit.

## Common Bug Patterns

| Symptom | Spec Says | Bug Location | Fix |
|---------|-----------|--------------|-----|
| Element not found | User should see X | Component missing element | Add element to component |
| No redirect | After action, go to Y | Handler missing redirect | Add redirect logic |
| Wrong data shown | Display user's Z | State not passed to component | Fix props/state flow |
| API returns wrong data | API returns X | API handler bug | Fix API logic |
| Validation wrong | Reject if < 8 chars | Validation checks wrong value | Fix validation logic |

## Constraints

- Fix APPLICATION code only, NEVER test code
- Make the SMALLEST change that satisfies the spec
- Do NOT refactor unrelated code
- Do NOT add features beyond spec requirements
- If cannot determine fix, report failure with investigation notes
- Always update both fix task and test task before exiting
