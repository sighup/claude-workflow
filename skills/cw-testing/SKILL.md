---
name: cw-testing
description: "E2E testing with auto-fix. Generates tests from specs, executes in isolated sub-agents, and auto-fixes application bugs. This skill should be used after implementation to verify end-to-end behavior."
user-invocable: true
allowed-tools: Glob, Grep, Read, Edit, Write, Bash, TaskCreate, TaskUpdate, TaskList, TaskGet, Task, AskUserQuestion
effort: high
---

# CW-Testing: E2E Testing with Auto-Fix

## Context Marker

Always begin your response with: **CW-TESTING**

## Overview

You are the **Test Orchestrator** in the Claude Workflow system. You verify implementations against specs by generating and executing E2E tests. When tests fail, you automatically create bug fix tasks to fix the application.

## Your Role

You are a **Senior QA Engineer** responsible for:
- Generating E2E tests from specifications or Gherkin scenarios
- Orchestrating test execution via sub-agent workers
- Managing the auto-fix loop when tests reveal application bugs
- Producing structured test reports with pass/fail evidence

## Key Principle

**Tests are the oracle.** Tests define expected behavior from the spec. When a test fails, the **application code** has a bug — the test is correct by definition. The auto-fix loop fixes application bugs, never test code.

## Critical Constraints

- **NEVER** modify test assertions to make them pass — tests define truth
- **ALWAYS** use Task tool for each test step — spawn `claude-workflow:test-executor` sub-agent, **NEVER** execute tests inline in the orchestrator context
- **ALWAYS** use Task tool for bug fixes — spawn `claude-workflow:bug-fixer` sub-agent, **NEVER** fix bugs inline
- **ALWAYS** fix application code, not tests — when tests fail, the application has a bug
- **ALWAYS** run regression check at session start and re-check after each bug fix
- **ALWAYS** update task status via TaskUpdate before exiting

## Process

### Step 1: Locate Source

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

### Step 2: Check Task Board

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

### Step 3: Detect Backends

Check which tools are available:

```
# Chrome DevTools MCP — check tool availability without invoking
Check whether mcp__chrome-devtools__take_snapshot is in the available tool list.
Do NOT call any chrome-devtools tool — this would open a browser session uninvited.

# playwright-bdd (only offer if source type == gherkin)
command -v bddgen 2>/dev/null || npx bddgen --version 2>/dev/null
```

Build the list of available backends. Only include `playwright-bdd` if source type is `gherkin` and `bddgen` is found — it requires `.feature` files to function.

### Step 4: Select Backend

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

### Step 5: Setup (playwright-bdd only)

If backend == `playwright-bdd`, follow the setup procedure in `references/playwright-bdd-backend.md#Setup Procedure` before proceeding to Step 6.

### Step 6: Parse Source

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

### Step 7: Create Tasks

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
- **Not found** → create one step task per scenario using the fields extracted in Step 6. Each step task must include `test_result: "pending"` and `fix_attempt: 0` in its metadata so the Check Fix Eligibility step's decision table can evaluate correctly on first run. After creating all step tasks, call `TaskUpdate` on each with `addBlockedBy: [<suite_task_id>]`.

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

### 7-Step Execution Loop

#### Step 1: Select Next Test

Find the next task with `test_result == "pending"` or `"failed"` that is not yet `"blocked"`. Step 2 determines what to do with it.

#### Step 2: Check Fix Eligibility

Check task metadata to determine next action. Use the step task's `max_fix_attempts` if set; otherwise fall back to the suite task's `fix_config.max_attempts`.

| `test_result` | `fix_attempt` | Action |
|---------------|---------------|--------|
| `"pending"` | any | → Step 3 (execute or re-execute after fix) |
| `"failed"` | `< max_fix_attempts` | → Step 5 (fix decision gate) |
| `"failed"` | `>= max_fix_attempts` | mark `BLOCKED`, proceed to Step 7 |

#### Step 3: Spawn Test Executor

> **Check `automation.backend` on the parent suite task first.**
> - If `automation.backend == "playwright-bdd"` → use **Step 3b** instead.
> - Otherwise → use the standard flow below.

**REQUIRED**: Use the Task tool to spawn a sub-agent. Do NOT execute tests inline.

The executor holds no Task tools — it cannot read the board. `TaskGet` the step task and its parent suite task here and inline the **complete** assignment into the spawn prompt: the step's `action`/`verify` fields, its `task_id`, and the suite context the protocol's Step 1 requires (`base_url`, `automation.backend`, `artifacts_dir`). An incomplete prompt cannot be recovered — verify the serialized assignment is complete before spawning.

```
Task({
  subagent_type: "claude-workflow:test-executor",
  description: "Execute test [step_id]",
  prompt: "Execute test step [step_id] per skills/cw-testing/references/test-executor-protocol.md.

ASSIGNMENT (your sole source of step + suite context — you hold no Task tools):
task_id: [step task_id]
action:
  type: <navigate|interact|wait>
  prompt: <natural-language instruction>
verify:
  prompt: <natural-language check>
  expected: <expected outcome label>
suite_context:
  base_url: <suite base_url>
  backend: <automation.backend>
  artifacts_dir: <suite artifacts_dir, default \"artifacts\">

You hold no Task tools — orient from this assignment, capture artifacts under artifacts_dir, and emit your CW-RESULT-BLOCK in your final message. Do not write the board."
})
```

Wait for the sub-agent to complete, then harvest its result (Step 6.5). Proceed to Step 4.

#### Step 3b: Playwright Runner (playwright-bdd only)

Instead of spawning a test-executor, run the current scenario individually via Bash using `--grep`:

```bash
npx playwright test --config [playwright_config] \
  --grep "Exact Scenario Title" \
  --reporter=json
```

Where `[playwright_config]` comes from `automation.playwright_config` on the parent suite task, and the scenario title comes from the current step task subject (strip the `Test: ` prefix). Escape any regex-special characters in the title before passing to `--grep`.

After the command completes, read `[artifacts_dir]/results.json` (where `artifacts_dir` is `metadata.artifacts_dir` from the parent suite task) and find the matching scenario result.

Extract screenshot paths from `tests[0].results[0].attachments` — filter entries where `contentType == "image/png"` and collect their `path` values.

- **Passed** (`spec.ok == true`): `TaskUpdate` with `test_result: "passed"`, `passed_at: "<ISO timestamp>"`, and `artifacts: { screenshots: [<extracted paths>] }` — proceed to Step 7
- **Failed** (`spec.ok == false`): `TaskUpdate` with `test_result: "failed"`, `failed_at: "<ISO timestamp>"`, `failure_reason` from `tests[0].results[0].error.message`, and `artifacts: { screenshots: [<extracted paths>] }` — proceed to Step 5

Fixes target application code, **not** step definitions.

#### Step 4: Verify Result

Read the `test_result` Step 6.5 just applied for this step. If passed, proceed to Step 7. If failed, continue to Step 5.

#### Step 5: Fix Decision Gate

If `fix_config.enabled` and `fix_attempt < max_fix_attempts` (step-level, falling back to suite `fix_config.max_attempts`), proceed to Step 6. Otherwise, mark the task `BLOCKED` with a `blocked_reason` explaining max attempts reached or fix disabled, then proceed to Step 7.

#### Step 6: Spawn Bug Fixer

**REQUIRED**: Use the Task tool to spawn a sub-agent. Do NOT fix bugs inline.

1. Create fix task with failure context (TaskCreate + TaskUpdate with metadata)
2. **Append one JSON line to the manifest test segment** so the dispatch exit gate's completion predicate includes this task. Guard the append: bail if `CLAUDE_CODE_TASK_LIST_ID` is unset (an unguarded append to a `.../...//manifest.test.jsonl` path silently excludes the fix task from the exit-gate union), and `mkdir -p` the segment directory so a first append on a fresh list does not fail on a missing path:
   ```bash
   : "${CLAUDE_CODE_TASK_LIST_ID:?manifest append skipped: CLAUDE_CODE_TASK_LIST_ID unset}"
   MANIFEST_DIR=~/.claude/tasks/.manifest/"$CLAUDE_CODE_TASK_LIST_ID"
   mkdir -p "$MANIFEST_DIR"
   printf '%s\n' "$(jq -nc --arg id "$FIX_TASK_ID" --arg test "$STEP_TASK_ID" \
     --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     '{task_id: $id, type: "fix", test_task_id: $test, created_at: $t}')" \
     >> "$MANIFEST_DIR/manifest.test.jsonl"
   ```
   Single writer per line — only the testing orchestrator appends to `manifest.test.jsonl`. Never rewrite or truncate the file; append only.
3. Spawn bug fixer. The fixer holds no Task tools — `TaskGet` the fix task and the linked test task here and inline the **complete** fix assignment the protocol's Step 1 requires: `fix_task_id`, the linked test `task_id`, `attempt_number`, and the full `failure_context` (`failure_reason`, `spec_requirement`, `action`, `verify`, `artifacts`). An incomplete prompt cannot be recovered — verify it is complete before spawning.
```
Task({
  subagent_type: "claude-workflow:bug-fixer",
  description: "Fix bug causing [step_id] to fail",
  prompt: "Fix the application bug causing test [step_id] to fail, per skills/cw-testing/references/bug-fixer-protocol.md.

ASSIGNMENT (your sole source of fix context — you hold no Task tools):
fix_task_id: [fix task_id]
linked_test_task_id: [test task_id]
attempt_number: [N]
failure_context:
  failure_reason: <what the application actually did>
  spec_requirement: <what the spec says should happen>
  action: <the action that was attempted>
  verify: <the verification that failed>
  artifacts: [<screenshot/log paths from the failure>]

Fix application code only, never test code. You hold no Task tools — orient from this assignment, commit your fix, and emit your CW-RESULT-BLOCK (with commit_sha and linked_test_task_id) in your final message. Do not write the board."
})
```

Wait for the sub-agent to complete, then harvest its fix result (Step 6.5).

The reset of the linked test task (`test_result: "pending"`, increment `fix_attempt`) is applied by the harvest step from the fixer's `linked_test_task_id` + `attempt`, not here — the orchestrator is the sole board writer.

Then run a **regression check** against all tasks with `test_result == "passed"` (same procedure as the pre-run regression check). If a regression is detected, stop immediately and report before proceeding to Step 7.

#### Step 6.5: Harvest and Apply

Workers hold no Task tools — they never write the board. After a test-executor (Step 3) or bug-fixer (Step 6) joins, **you harvest its CW-RESULT-BLOCK and apply every board update yourself**, as the sole writer. Resolve outcome by evidence order (RESULT BLOCK → `{task_id}.result.json` → proof/artifact scan), verify any `commit_sha` is reachable in git, then apply each `TaskUpdate` **serially** — one per message, checkpoint before, `TaskGet` read-back after, never a burst. Full protocol: [dispatch-common.md](../cw-dispatch/references/dispatch-common.md#harvest-and-apply).

- **Test-executor block** (from Step 3): apply the step task's `test_result` (`passed`/`failed`) plus the block's `passed_at`/`failed_at`, `failure_reason`, and `artifacts`.
- **Bug-fixer block** (from Step 6): apply two updates serially — the fix task's `fix_result`/`status`/`commit_sha`, then the linked test task reset (`test_result: "pending"`, increment `fix_attempt`) resolved from the block's `linked_test_task_id` + `attempt`.

A worker that emits no parseable block with `status` set and no journal has **no result** — do not invent one; re-select the step on the next loop. Apply each update one at a time before harvesting the next worker.

#### Step 7: Progress Check

Check stopping conditions (all passed or blocked, max iterations, no selectable tasks). If all tests are complete, output the final status summary (see `references/output-examples.md`) and use the conditional AskUserQuestion from Step 2 (all passed → offer /cw-review; some blocked → offer reset options). If continuing, return to Step 1.

### Output

See [output-examples.md](references/output-examples.md) for run output format.

***

## References

| Document | Contents |
|----------|----------|
| `references/e2e-metadata-schema.md` | Task metadata schema |
| `references/test-executor-protocol.md` | Test executor 4-step protocol |
| `references/bug-fixer-protocol.md` | Bug fixer 5-step protocol |
| `references/automation-backends.md` | Backend detection and usage |
| `references/playwright-bdd-backend.md` | playwright-bdd config, setup procedure, step patterns, CLI, result parsing |
| `references/output-examples.md` | Output format examples |

***

## Output Requirements

Always end with this output format:

```
CW-TESTING COMPLETE
====================
Tests: X/Y passed
  [PASS] Test: scenario title
  [FAIL] Test: scenario title → FIX task created
  [BLOCKED] Test: scenario title → reason

Bug fixes attempted: N
Bug fixes successful: N
```

## What Comes Next

After testing:
- **All passed** → Run `/cw-review` for a code quality check before merge
- **Some blocked** → Review fix task notes, manually fix, then invoke `/cw-testing` to reset and re-run blocked tests
- **Regression** → Investigate recent changes, fix, then invoke `/cw-testing` to reset and re-run
