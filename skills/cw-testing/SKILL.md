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

1. `--features <dir>` provided → glob `*.feature` from that directory; source type = `gherkin`
2. `--spec <path>` provided → check for `*.feature` files in the same directory
   - Found → source type = `gherkin`
   - Not found → source type = `prose`
3. Natural language string provided → source type = `prose`
4. **No argument** → auto-discover:
   - Glob `docs/specs/*/` for spec directories, sorted by modification time
   - In the most recently modified directory, check for `*.feature` files
   - Found → source type = `gherkin`
   - Not found → source type = `prose`; use the spec `.md` file in that directory
   - Multiple directories modified at nearly the same time → use `AskUserQuestion` to confirm which spec

Record the resolved `gherkin_dir` (or `artifacts_dir: "artifacts"` for prose) before proceeding.

**Step 2: DETECT backends**

Check which tools are available:

```bash
# Chrome DevTools MCP
try: mcp__chrome-devtools__list_pages()

# Playwright MCP
try: mcp__playwright__* tools

# playwright-bdd (only offer if source type == gherkin)
command -v bddgen 2>/dev/null || npx bddgen --version 2>/dev/null
```

Build the list of available backends. Only include `playwright-bdd` if source type is `gherkin` and `bddgen` is found — it requires `.feature` files to function.

**Step 3: SELECT backend**

Present available backends via `AskUserQuestion`:

```
AskUserQuestion({
  questions: [{
    question: "Which automation backend should be used for this test suite?",
    header: "Backend",
    options: [
      // include only detected options from Step 2:
      {
        label: "playwright-bdd",
        description: "Compiled Gherkin → Playwright tests via bddgen. Deterministic, CI-friendly. Requires .feature files."
      },
      {
        label: "chrome-devtools",
        description: "AI-driven browser automation via Chrome DevTools MCP. Uses natural language test prompts."
      },
      {
        label: "playwright",
        description: "AI-driven browser automation via Playwright MCP. Uses natural language test prompts."
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

**Step 4: SETUP** (playwright-bdd only)

If backend == `playwright-bdd`, perform setup before creating any tasks:

1. **Check prerequisites** — verify `@playwright/test` is installed:
   ```bash
   npx playwright --version 2>/dev/null
   ```
   If missing, inform the user: "Run `npm install -g @playwright/test` (global) or `npm install @playwright/test` in your project root, then retry."

2. **Generate `playwright.config.ts`** — write to `[artifacts_dir]/playwright.config.ts`:
   ```typescript
   import { defineConfig, devices } from '@playwright/test';
   import { defineBddConfig, cucumberReporter } from 'playwright-bdd';

   const testDir = defineBddConfig({
     features: '../*.feature',
     steps: 'steps/*.ts',
     outputDir: '.features-gen',
   });

   export default defineConfig({
     testDir,
     reporter: [
       ['json', { outputFile: 'results.json' }],
       ['html', { outputFile: 'report.html', open: 'never' }],
     ],
     use: {
       screenshot: 'on',
       trace: 'on',
     },
     projects: [
       { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
     ],
   });
   ```
   If the file already exists, ask the user to confirm overwrite before writing.

3. **Generate step definitions** — spawn an implementer sub-agent:
   ```
   Task({
     subagent_type: "claude-workflow:implementer",
     prompt: "Read all .feature files in [gherkin_dir]. For each unique Given/When/Then step across all feature files, write a TypeScript step definition in [artifacts_dir]/steps/[feature-name].steps.ts using playwright-bdd's createBdd() pattern. Use semantic Playwright locators (getByRole, getByLabel, getByText). Feature files are at: [list of .feature file paths]. Reference: skills/cw-testing/references/playwright-bdd-backend.md"
   })
   ```

4. **Verify with bddgen** — run:
   ```bash
   npx bddgen --config [artifacts_dir]/playwright.config.ts
   ```
   - Exit 0 → proceed to Step 5
   - Exit non-zero → show the output (which includes TypeScript scaffolds for missing steps); prompt user to review the scaffolds and retry, or ask if you should implement the missing steps inline before retrying

**Step 5: PARSE source**

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

**Step 6: CREATE or UPDATE tasks**

**Suite task**: call `TaskList` and search for an existing task where `metadata.test_suite == true` and `metadata.gherkin_dir` matches the current spec directory.

- **Found** → update `automation` metadata only. Do not recreate. Use the existing task ID.
- **Not found** → create a new suite task:
  ```json
  {
    "test_type": "e2e",
    "test_suite": true,
    "base_url": "http://localhost:3000",
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
- **Not found** → create one step task per scenario using the fields extracted in Step 5.

**Step 7: Output summary** — see `references/output-examples.md`

***

## Subcommand: run

**Usage**: `/cw-testing run`

### 8-Phase Execution Loop

**playwright-bdd pre-check**: Before entering Phase 1, read the parent suite task and check `automation.backend`. If `playwright-bdd`, run `bddgen` once to ensure `.features-gen/` is current:

```bash
npx bddgen --config [automation.playwright_config]
```

If `bddgen` exits non-zero, stop immediately — missing step definitions must be resolved before the loop can proceed. Report the output to the user.

#### Phase 1: REGRESSION CHECK

Re-verify all passed tests. If any fail, stop immediately and report regression.

**playwright-bdd**: For each task with `test_status == "passed"`, run its scenario individually:

```bash
npx playwright test --config [playwright_config] --grep "Exact Scenario Title" --reporter=json
```

Escape any regex-special characters in the scenario title (`(`, `)`, `.`, `[`, `]`, `*`, `+`, `?`) with a backslash before passing to `--grep`. Parse `results.json` to confirm the scenario still passes.

#### Phase 2: SELECT NEXT TEST
Find next unblocked task with `test_status == "pending"` or failed test needing retry.

#### Phase 3: CHECK FIX ELIGIBILITY
- First execution → Phase 4
- Retry after fix → Phase 4
- Failed, attempts remain → Phase 6
- Failed, max attempts → mark BLOCKED, continue

#### Phase 4: SPAWN TEST EXECUTOR

> **Check `automation.backend` on the parent suite task first.**
> - If `automation.backend == "playwright-bdd"` → use **Phase 4b** instead.
> - Otherwise → use the standard flow below.

**REQUIRED**: Use the Task tool to spawn a sub-agent. Do NOT execute tests inline.

```
Task({
  subagent_type: "claude-workflow:test-executor",
  description: "Execute test [step_id]",
  prompt: "Execute test step [step_id]. Task ID: [native-task-id]. Read protocol at: skills/cw-testing/references/test-executor-protocol.md"
})
```

Wait for the sub-agent to complete, then read the task status via TaskGet.

#### Phase 4b: PLAYWRIGHT RUNNER (playwright-bdd backend only)

Instead of spawning a test-executor, run the current scenario individually via Bash using `--grep`:

```bash
npx playwright test --config [playwright_config] \
  --grep "Exact Scenario Title" \
  --reporter=json
```

Where `[playwright_config]` comes from `automation.playwright_config` on the parent suite task, and the scenario title comes from the current step task subject (strip the `Test: ` prefix). Escape any regex-special characters in the title before passing to `--grep`.

After the command completes, read `[artifacts_dir]/results.json` and find the matching scenario result:

- **Passed** (`spec.ok == true`): `TaskUpdate` with `test_status: "passed"` — proceed to Phase 8
- **Failed** (`spec.ok == false`): `TaskUpdate` with `test_status: "failed"`, set `failure_reason` from `tests[0].results[0].error.message` — proceed to Phase 5

Fixes target application code, **not** step definitions.

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
| `references/playwright-bdd-backend.md` | playwright-bdd config, step patterns, CLI, result parsing |
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
