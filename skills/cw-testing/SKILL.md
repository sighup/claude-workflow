---
name: cw-testing
description: "E2E testing with auto-fix. Generate tests from specs, execute in isolated sub-agents, and auto-fix application bugs. Use after implementation to verify end-to-end behavior."
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
- **Regression check** - verify passed tests still pass before each new test
- **Update task status** - always update via TaskUpdate before exiting

## Subcommands

```
/cw-testing [subcommand] [args]

  init    Generate test scenario from prompt or spec
  run     Execute test loop with auto-fix
  status  Show test progress and results
  reset   Reset test progress for re-run
```

Parse user input to determine subcommand. If none provided, show help and ask.

***

## Subcommand: init

**Usage**:
```
/cw-testing init                      # auto-discover current spec directory
/cw-testing init --spec <path>        # use specific spec dir (globs *.feature first)
/cw-testing init --features <dir>     # use a directory of .feature files directly
/cw-testing init "Test login"         # derive from natural language
```

### Process

**Step 1: LOCATE source**

Determine the test source in this order:

1. `--features <dir>` provided → glob `*.feature` from that directory (skip to step 1b)
2. `--spec <path>` provided → check for `*.feature` files in the same directory
   - Found → use them (skip to step 1b)
   - Not found → derive from spec prose (skip to step 2)
3. Natural language string provided → derive from prompt (skip to step 2)
4. **No argument** → auto-discover:
   - Glob `docs/specs/*/` for spec directories, sorted by modification time
   - In the most recently modified directory, check for `*.feature` files
   - Found → use them (skip to step 1b)
   - Not found → use the spec `.md` file in that directory (derive from prose, skip to step 2)
   - Multiple directories modified at nearly the same time → use `AskUserQuestion` to confirm which spec

**Step 1b: Parse Gherkin source**

Glob all `*.feature` files from the located directory. Read each file in turn. For each `Feature:` block, collect all `Scenario:` entries across all files. Map clauses to task fields:

| Gherkin clause | Task field | Notes |
|----------------|------------|-------|
| `When` | `action.prompt` | Rewrite as imperative instruction; prepend `Given` context if it clarifies the precondition |
| `When` verb | `action.type` | `navigate` if contains "Navigate to / Visit / Go to / Open" + URL or path; `wait` if contains "Wait for / until"; `interact` otherwise |
| `Then` + all `And` clauses | `verify.prompt` | Join into a single verification instruction |
| Scenario title | `verify.expected` | Concise label for the expected outcome |

One step task per `Scenario:`. Step task subject: `Test: [scenario title]`.

**Step 2: Detect automation tools** — check for chrome-devtools MCP, playwright MCP

**Step 3: Ask user to select backend** — see `references/automation-backends.md`

**Step 4: Create parent suite task** with metadata:
```json
{
  "test_type": "e2e",
  "test_suite": true,
  "base_url": "http://localhost:3000",
  "gherkin_dir": "docs/specs/<spec-name>",
  "artifacts_dir": "docs/specs/<spec-name>/testing",
  "automation": { "backend": "chrome-devtools" },
  "fix_config": { "enabled": true, "max_attempts": 2 }
}
```
- `artifacts_dir`: derive from `gherkin_dir` when set (e.g., `docs/specs/01-spec-login` → `docs/specs/01-spec-login/testing`). Use `artifacts` for ad-hoc natural language suites.
- Omit `gherkin_dir` and use `artifacts_dir: "artifacts"` when the suite was derived from prose or natural language.

**Step 5: Create test step tasks** with natural language action/verify:
```json
{
  "test_status": "pending",
  "action": { "type": "interact", "prompt": "Click the Login button" },
  "verify": { "prompt": "Verify dashboard is visible", "expected": "Dashboard shown" }
}
```

**Step 6: Output summary** — see `references/output-examples.md`

***

## Subcommand: run

**Usage**: `/cw-testing run`

### 8-Phase Execution Loop

#### Phase 1: REGRESSION CHECK
Re-verify all passed tests. If any fail, stop immediately and report regression.

#### Phase 2: SELECT NEXT TEST
Find next unblocked task with `test_status == "pending"` or failed test needing retry.

#### Phase 3: CHECK FIX ELIGIBILITY
- First execution → Phase 4
- Retry after fix → Phase 4
- Failed, attempts remain → Phase 6
- Failed, max attempts → mark BLOCKED, continue

#### Phase 4: SPAWN TEST EXECUTOR

**REQUIRED**: Use the Task tool to spawn a sub-agent. Do NOT execute tests inline.

```
Task({
  subagent_type: "claude-workflow:test-executor",
  description: "Execute test [step_id]",
  prompt: "Execute test step [step_id]. Task ID: [native-task-id]. Read protocol at: skills/cw-testing/references/test-executor-protocol.md"
})
```

Wait for the sub-agent to complete, then read the task status via TaskGet.

#### Phase 5: VERIFY RESULT
Check task metadata for pass/fail. If failed, continue to Phase 6.

#### Phase 6: FIX DECISION GATE
If `fix_config.enabled` and `fix_attempt < max_attempts`, proceed to Phase 7.

#### Phase 7: SPAWN BUG FIXER

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

#### Phase 8: PROGRESS CHECK
Check stopping conditions (all passed, max iterations, all blocked). If continuing, return to Phase 1.

### Output
See `references/output-examples.md` for run output format.

***

## Subcommand: status

**Usage**: `/cw-testing status`

List all test tasks with their status, pass/fail timestamps, and fix history.
See `references/output-examples.md` for format.

***

## Subcommand: reset

**Usage**: `/cw-testing reset` or `/cw-testing reset --keep-passed` or `/cw-testing reset --step T04`

Reset test tasks to pending. Options:
- `--keep-passed` - only reset failed/blocked tests
- `--step <id>` - reset specific test only

Ask user whether to delete fix tasks and clear artifacts.

***

## References

| Document | Contents |
|----------|----------|
| `references/e2e-metadata-schema.md` | Task metadata schema |
| `references/test-executor-protocol.md` | Test executor 4-phase protocol |
| `references/bug-fixer-protocol.md` | Bug fixer 5-phase protocol |
| `references/automation-backends.md` | Backend detection and usage |
| `references/output-examples.md` | Output format examples |

***

## Error Handling

| Error | Action |
|-------|--------|
| Browser action fails | Capture screenshot, mark failed, trigger fix |
| Regression detected | Stop loop, report regression |
| Network/timeout | Retry 3x, then mark failed |
| Fix cannot determine cause | Report failure with investigation notes |

***

## What Comes Next

After testing:
- **All passed** → Consider committing artifacts
- **Some blocked** → Review fix task notes, manually fix, then `/cw-testing reset --step <id>`
- **Regression** → Investigate recent changes, fix, reset and re-run
