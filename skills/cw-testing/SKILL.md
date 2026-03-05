---
name: cw-testing
description: "E2E testing with auto-fix. Generates tests from specs, executes in isolated sub-agents, and auto-fixes application bugs. This skill should be used after implementation to verify end-to-end behavior."
user-invocable: true
allowed-tools: Glob, Grep, Read, Edit, Write, Bash, TaskCreate, TaskUpdate, TaskList, TaskGet, Task, AskUserQuestion
---

# CW-Testing: E2E Testing with Auto-Fix

## Context Marker

Always begin your response with: **CW-TESTING**

## Overview

You are the **Test Orchestrator** in the Claude Workflow system. You verify implementations against specs by generating and executing E2E tests. When tests fail, you automatically create bug fix tasks to fix the application.

## Key Principle

**Tests are the oracle.** Tests define expected behavior from the spec. When a test fails, the **application code** has a bug - the test is correct by definition. The auto-fix loop fixes application bugs, never test code.

## Critical Constraints

- **Tests define truth** - never modify test assertions to make them pass
- **MUST use Task tool for each test step** - spawn `claude-workflow:test-executor` sub-agent, NEVER execute tests inline in the orchestrator context
- **MUST use Task tool for bug fixes** - spawn `claude-workflow:bug-fixer` sub-agent, NEVER fix bugs inline
- **Fix application, not tests** - when tests fail, fix the application code
- **Regression check** - run once at session start; re-check after each bug fix
- **Update task status** - always update via TaskUpdate before exiting

## Process

### Step 1: LOCATE source

Determine the test source in this order:

1. User mentioned a specific directory containing `.feature` files → glob `*.feature` from that directory; source type = `gherkin`
2. User mentioned a specific spec path or spec name → locate matching `docs/specs/*/` directory, check for `*.feature` files
   - Found → source type = `gherkin`
   - Not found → source type = `prose`
3. User described a test scenario in natural language → source type = `prose`
4. **No source specified** → auto-discover:
   - Glob `docs/specs/*/` for spec directories, sorted by modification time
   - In the most recently modified directory, check for `*.feature` files
   - Found → source type = `gherkin`
   - Not found → source type = `prose`; use the spec `.md` file in that directory
   - Multiple directories modified at nearly the same time → use `AskUserQuestion` to confirm which spec

Record the resolved `gherkin_dir` before proceeding. For spec-linked suites, derive `artifacts_dir` as `gherkin_dir + "/testing"` immediately. For prose or ad-hoc suites where there is no spec directory, use `"artifacts"` as the `artifacts_dir`.

### Step 2: CHECK TASK BOARD

Call `TaskList`. For each task whose subject starts with `E2E:`, call `TaskGet` to check if `metadata.test_suite == true` and `metadata.gherkin_dir` matches the resolved spec directory.

- **Not found** → proceed to Setup (Step 3)
- **Found, tests pending or failed** → proceed to Execute
- **Found, all tests complete** (all `test_result` values are `"passed"` or `"blocked"`) → show status summary (see `references/output-examples.md`), then ask using the conditional prompt below

**If all passed (none blocked):**
```
AskUserQuestion({
  questions: [{
    question: "All tests passed! What would you like to do next?",
    header: "Next action",
    options: [
      { label: "Run /cw-review", description: "Review code for bugs, security issues, and quality problems (recommended)" },
      { label: "Reset and re-run all", description: "Reset all test results to pending and re-execute the full suite" },
      { label: "Done", description: "Exit — results are saved on the task board" }
    ],
    multiSelect: false
  }]
})
```

**If some blocked:**
```
AskUserQuestion({
  questions: [{
    question: "Testing complete with blocked tests. What would you like to do?",
    header: "Next action",
    options: [
      { label: "Reset and re-run all", description: "Reset all test results to pending and re-execute the full suite" },
      { label: "Reset failed/blocked only", description: "Re-run only the tests that failed or were blocked" },
      { label: "Done", description: "Exit — results are saved on the task board" }
    ],
    multiSelect: false
  }]
})
```

On reset: update affected step tasks with `test_result: "pending"`, `fix_attempt: 0`, then proceed to Execute.

***

## Setup

### Step 3: DETECT backends

Check which tools are available:

```
# Chrome DevTools MCP — check tool availability without invoking
Check whether mcp__chrome-devtools__take_snapshot is in the available tool list.
Do NOT call any chrome-devtools tool — this would open a browser session uninvited.

# playwright-bdd (only offer if source type == gherkin)
command -v bddgen 2>/dev/null || npx bddgen --version 2>/dev/null
```

Build the list of available backends. Only include `playwright-bdd` if source type is `gherkin` and `bddgen` is found — it requires `.feature` files to function.

### Step 4: SELECT backend

Present available backends via `AskUserQuestion`:

```
AskUserQuestion({
  questions: [{
    question: "Which automation backend should be used for this test suite?",
    header: "Backend",
    options: [
      // include only detected options from Step 3:
      {
        label: "playwright-bdd",
        description: "Compiled Gherkin → Playwright tests via bddgen. Deterministic, CI-friendly. Requires .feature files."
      },
      {
        label: "chrome-devtools",
        description: "AI-driven browser automation via Chrome DevTools MCP. Uses natural language test prompts."
      },
      {
        label: "cli",
        description: "Bash only — for API, CLI, or non-browser tests."
      },
      {
        label: "manual",
        description: "Step-by-step user confirmation. No automation tools required."
      }
    ],
    multiSelect: false
  }]
})
```

### Step 5: SETUP (playwright-bdd only)

If backend == `playwright-bdd`, follow the setup procedure in `references/playwright-bdd-backend.md#Setup Procedure` before proceeding to Step 6.

### Step 6: PARSE source

Parse scenarios from the source. What you extract depends on the backend:

**If source type == `gherkin` and backend == `playwright-bdd`:**

Glob all `.feature` files. For each `Scenario:`, extract only:
- Scenario title → step task subject: `Test: [scenario title]`
- Full Given/When/Then text → step task description (for bug-fixer context)

Do not map to `action`/`verify` fields — execution is handled by Playwright, not the test-executor.

**If source type == `gherkin` and backend != `playwright-bdd`:**

Glob all `.feature` files. For each `Scenario:`, map clauses to task fields:

| Gherkin clause | Task field | Notes |
|----------------|------------|-------|
| `When` | `action.prompt` | Rewrite as imperative instruction; prepend `Given` context if helpful |
| `When` verb | `action.type` | `navigate` / `wait` / `interact` |
| `Then` + all `And` clauses | `verify.prompt` | Join into a single verification instruction |
| Scenario title | `verify.expected` | Concise label for the expected outcome |

**If source type == `prose`:**

Derive scenarios from the spec text. Map to `action`/`verify` fields as above.

### Step 7: CREATE tasks

**Suite task**: call `TaskList` to get all tasks. `TaskList` does not support metadata filtering — for each task whose subject starts with `E2E:`, call `TaskGet` to read its full metadata and check if `metadata.test_suite == true` and `metadata.gherkin_dir` matches the current spec directory.

- **Found** → update `automation` metadata only. Do not recreate. Use the existing task ID.
- **Not found** → scan project config files (e.g., `package.json`, framework config files) for a dev server port or URL. Do not read `.env` files — they may contain credentials. If found, use it as `base_url`. If not found or ambiguous, ask the user to provide it — the user can type a custom value via the "Other" option. Create the suite task with the resolved URL as `base_url`:
  ```json
  {
    "test_type": "e2e",
    "test_suite": true,
    "base_url": "<user-selected URL>",
    "gherkin_dir": "docs/specs/<spec-name>",
    "artifacts_dir": "docs/specs/<spec-name>/testing",
    "automation": { "backend": "<selected>" },
    "fix_config": { "enabled": true, "max_attempts": 2 }
  }
  ```

For `playwright-bdd`, `automation` is:
```json
{ "backend": "playwright-bdd", "playwright_config": "docs/specs/<spec-name>/testing/playwright.config.ts" }
```

**Step tasks**: check `TaskList` for tasks already blocked by the suite task ID.

- **Found** → skip creation. Report the count to the user.
- **Not found** → create one step task per scenario using the fields extracted in Step 6. Each step task must include `test_result: "pending"` and `fix_attempt: 0` in its metadata so Phase 2's decision table can evaluate correctly on first run. After creating all step tasks, call `TaskUpdate` on each with `addBlockedBy: [<suite_task_id>]`.

### Step 8: Output summary — see `references/output-examples.md`

***

## Execute

### Pre-run

Before entering the loop, read the parent suite task and check `automation.backend`:

- **If `automation.backend` is absent or unset**: the suite task was created by cw-gherkin without a backend selection. Detect available backends (same as Setup Step 3), present them via `AskUserQuestion` (same as Setup Step 4), then update the suite task with `automation: { "backend": "<selected>" }`. For `playwright-bdd`, follow the full Setup flow (Steps 3–8) before entering the execution loop — `playwright.config.ts` and step definitions must be generated first.
- **If `automation.backend == "playwright-bdd"`**: run `bddgen` once to ensure `.features-gen/` is current:

```bash
npx bddgen --config [automation.playwright_config]
```

If `bddgen` exits non-zero, stop immediately — missing step definitions must be resolved before the loop can proceed. Report the output to the user.

**Regression check** (run once before the loop begins):

For each task with `test_result == "passed"`, verify it still passes:

- **playwright-bdd**: run each scenario individually via `--grep` (escape regex-special characters `(`, `)`, `.`, `[`, `]`, `*`, `+`, `?`); parse `results.json`
- **Other backends**: spawn a `claude-workflow:test-executor` sub-agent per passed task

If any regression is detected, stop immediately and report which test failed before beginning the loop.

### 7-Phase Execution Loop

#### Phase 1: SELECT NEXT TEST

Find the next task with `test_result == "pending"` or `"failed"` that is not yet `"blocked"`. Phase 2 determines what to do with it.

#### Phase 2: CHECK FIX ELIGIBILITY

Check task metadata to determine next action. Use the step task's `max_fix_attempts` if set; otherwise fall back to the suite task's `fix_config.max_attempts`.

| `test_result` | `fix_attempt` | Action |
|---------------|---------------|--------|
| `"pending"` | any | → Phase 3 (execute or re-execute after fix) |
| `"failed"` | `< max_fix_attempts` | → Phase 5 (fix decision gate) |
| `"failed"` | `>= max_fix_attempts` | mark `BLOCKED`, proceed to Phase 7 |

#### Phase 3: SPAWN TEST EXECUTOR

> **Check `automation.backend` on the parent suite task first.**
> - If `automation.backend == "playwright-bdd"` → use **Phase 3b** instead.
> - Otherwise → use the standard flow below.

**REQUIRED**: Use the Task tool to spawn a sub-agent. Do NOT execute tests inline.

```
Task({
  subagent_type: "claude-workflow:test-executor",
  description: "Execute test [step_id]",
  prompt: "Execute test step [step_id]. Task ID: [native-task-id]. Read protocol at: skills/cw-testing/references/test-executor-protocol.md"
})
```

Wait for the sub-agent to complete, then read the task status via TaskGet. Proceed to Phase 4.

#### Phase 3b: PLAYWRIGHT RUNNER (playwright-bdd backend only)

Instead of spawning a test-executor, run the current scenario individually via Bash using `--grep`:

```bash
npx playwright test --config [playwright_config] \
  --grep "Exact Scenario Title" \
  --reporter=json
```

Where `[playwright_config]` comes from `automation.playwright_config` on the parent suite task, and the scenario title comes from the current step task subject (strip the `Test: ` prefix). Escape any regex-special characters in the title before passing to `--grep`.

After the command completes, read `[artifacts_dir]/results.json` (where `artifacts_dir` is `metadata.artifacts_dir` from the parent suite task) and find the matching scenario result.

Extract screenshot paths from `tests[0].results[0].attachments` — filter entries where `contentType == "image/png"` and collect their `path` values.

- **Passed** (`spec.ok == true`): `TaskUpdate` with `test_result: "passed"`, `passed_at: "<ISO timestamp>"`, and `artifacts: { screenshots: [<extracted paths>] }` — proceed to Phase 7
- **Failed** (`spec.ok == false`): `TaskUpdate` with `test_result: "failed"`, `failed_at: "<ISO timestamp>"`, `failure_reason` from `tests[0].results[0].error.message`, and `artifacts: { screenshots: [<extracted paths>] }` — proceed to Phase 5

Fixes target application code, **not** step definitions.

#### Phase 4: VERIFY RESULT

Check task metadata for pass/fail. If passed, proceed to Phase 7. If failed, continue to Phase 5.

#### Phase 5: FIX DECISION GATE

If `fix_config.enabled` and `fix_attempt < max_fix_attempts` (step-level, falling back to suite `fix_config.max_attempts`), proceed to Phase 6. Otherwise, mark the task `BLOCKED` with a `blocked_reason` explaining max attempts reached or fix disabled, then proceed to Phase 7.

#### Phase 6: SPAWN BUG FIXER

**REQUIRED**: Use the Task tool to spawn a sub-agent. Do NOT fix bugs inline.

1. Create fix task with failure context (TaskCreate + TaskUpdate with metadata)
2. Spawn bug fixer:
```
Task({
  subagent_type: "claude-workflow:bug-fixer",
  description: "Fix bug causing [step_id] to fail",
  prompt: "Fix bug causing test [step_id] to fail. Fix Task ID: [fix-task-id]. Test Task ID: [test-task-id]. Read protocol at: skills/cw-testing/references/bug-fixer-protocol.md"
})
```

Wait for the sub-agent to complete, then read fix_result via TaskGet.

After the bug fixer completes (regardless of outcome), reset the test task via `TaskUpdate` with `test_result: "pending"` and increment `fix_attempt`.

Then run a **regression check** against all tasks with `test_result == "passed"` (same procedure as the pre-run regression check). If a regression is detected, stop immediately and report before proceeding to Phase 7.

#### Phase 7: PROGRESS CHECK

Check stopping conditions (all passed or blocked, max iterations, no selectable tasks). If all tests are complete, output the final status summary (see `references/output-examples.md`) and use the conditional AskUserQuestion from Step 2 (all passed → offer /cw-review; some blocked → offer reset options). If continuing, return to Phase 1.

### Output

See `references/output-examples.md` for run output format.

***

## References

| Document | Contents |
|----------|----------|
| `references/e2e-metadata-schema.md` | Task metadata schema |
| `references/test-executor-protocol.md` | Test executor 4-phase protocol |
| `references/bug-fixer-protocol.md` | Bug fixer 5-phase protocol |
| `references/automation-backends.md` | Backend detection and usage |
| `references/playwright-bdd-backend.md` | playwright-bdd config, setup procedure, step patterns, CLI, result parsing |
| `references/output-examples.md` | Output format examples |

***

## What Comes Next

After testing:
- **All passed** → Run `/cw-review` for a code quality check before merge
- **Some blocked** → Review fix task notes, manually fix, then invoke `/cw-testing` to reset and re-run blocked tests
- **Regression** → Investigate recent changes, fix, then invoke `/cw-testing` to reset and re-run
