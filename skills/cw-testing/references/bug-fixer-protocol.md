# Bug Fixer Protocol

This protocol is used by the test-fixer agent when investigating and fixing application bugs detected by E2E tests.

## Key Principle

**The test is the oracle.** Tests define expected behavior from the spec. When a test fails, the **application code** has a bug - the test is correct by definition. This protocol fixes application bugs, never test code.

## 5-Step Protocol

### Step 1: Orient

Read the fix assignment from the spawn prompt and understand the failure context. You hold no Task tools — the orchestrator delivers the fix context and linked test-task id inline.

```
1. Read the fix assignment from the spawn prompt:
   - fix_task_id: stable id of this fix task
   - failed_test_id / linked_test_task_id: the test that failed
   - attempt_number: Which fix attempt this is (1-based)
   - failure_context.failure_reason: What the application actually did (the bug)
   - failure_context.spec_requirement: What the spec says should happen
   - failure_context.action: The action that was attempted
   - failure_context.verify: The verification that failed
   - failure_context.artifacts: Screenshots and logs from failure
2. Output orientation:
   "BUG FIX ATTEMPT [N]: [test_id] failed"
   "Expected: [spec_requirement]"
   "Actual: [failure_reason]"
```

### Step 2: Investigate

Identify the application bug causing the test failure.

#### LSP Availability Check

At the start of investigation, probe whether an LSP server is available. Pick a source file related to the failing feature and attempt a single `documentSymbol` operation:

```
LSP({
  operation: "documentSymbol",
  filePath: "{source file related to failing feature}",
  line: 1,
  character: 1
})
```

- **LSP available**: The operation returned symbols. Set `lsp_available = true`.
- **LSP unavailable**: The operation returned an error. Set `lsp_available = false`.

```
Investigation checklist:
1. Read failure artifacts (screenshots, logs, console errors)
2. Understand what the spec requires vs what app does
3. Search APPLICATION code for the bug:
   - Glob for component/service files related to the feature
   - Grep for relevant function names, API endpoints
   - Read source files in the implementation
   - When lsp_available = true, use LSP for deeper analysis:
     - goToDefinition to trace types/functions from the failing code path
     - findReferences to understand how the buggy function is used
     - incomingCalls/outgoingCalls to map the call chain leading to the bug
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

### Step 3: Implement

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

### Step 4: Commit

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

### Step 5: Report

Emit the fix result as a RESULT BLOCK and exit. You hold no Task tools; the testing orchestrator harvests this block and applies **both** the fix-task update and the linked test-task reset/increment itself (sole writer).

**If fix succeeded:**
```
CW-RESULT-BLOCK-START
{
  "task_id": "<fix_task_id>",
  "status": "completed",
  "commit_sha": "[sha]",
  "fix_result": "success",
  "fix_description": "[what bug was fixed]",
  "files_changed": ["path/to/app/file.ts"],
  "linked_test_task_id": "<linked-test-task-id>",
  "attempt": N,
  "completed_at": "<ISO timestamp>"
}
CW-RESULT-BLOCK-END
```

**If fix failed (cannot determine solution):**
```
CW-RESULT-BLOCK-START
{
  "task_id": "<fix_task_id>",
  "status": "failed",
  "fix_result": "failed",
  "fix_description": "Unable to determine fix: [reason]",
  "investigation_notes": "[what was tried, what was found]",
  "linked_test_task_id": "<linked-test-task-id>",
  "attempt": N,
  "completed_at": "<ISO timestamp>"
}
CW-RESULT-BLOCK-END
```

The orchestrator uses `linked_test_task_id` + `attempt` + `fix_result` to reset/increment the linked test task's `fix_history`. Output result and exit.

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
- Always emit the RESULT BLOCK before exiting; the orchestrator applies both the fix-task and linked test-task updates from it
