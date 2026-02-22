# Behavioral vs Structural Testing

## The Core Rule

> **"If you can `grep` for it, it's not a behavioral test."**

Behavioral verification executes the feature and checks what a user or system can observe. Structural verification checks that code exists. Code can exist without ever running correctly.

## Decision Matrix

| Verification goal | Wrong (structural) | Correct (behavioral) |
|-------------------|--------------------|----------------------|
| Function works | Search for function name in source | Call function with input; verify output |
| Hook fires | Find hook registration code | Trigger event; verify hook artifact exists (file, log, message) |
| Config takes effect | Read config file contents | Apply config; run scenario; observe changed behavior |
| Module exports work | Check import statement exists | Import and invoke; verify operation |
| Process spawns | Review spawn call in source | Trigger action; verify process output file or exit code |
| State persists | Find variable assignment | Modify state; restart system; verify retention |
| Validation rejects bad input | Find validator function | Submit bad input; verify error message shown to user |

## Anti-Patterns to Reject

**1. Code existence checks**
```gherkin
# ❌ WRONG
Scenario: Validation function exists
  Given the codebase at src/auth/
  When I search for "validatePassword"
  Then the function is found in auth.ts
  And the function is exported from the module
```
Code can exist without ever being called or working correctly.

**2. Compilation / type checks only**
```gherkin
# ❌ WRONG
Scenario: Module compiles without errors
  Given the TypeScript source
  When I run tsc --noEmit
  Then no type errors are reported
```
Type-correct code can have logic errors.

**3. File-contains checks**
```gherkin
# ❌ WRONG
Scenario: Config file has correct field
  Given the config directory
  When I read config.json
  Then the file contains "feature_enabled: true"
```
The field can exist but be ignored at runtime.

## Correct Behavioral Patterns

**1. End-to-end execution**
```gherkin
# ✅ CORRECT
Scenario: Password validation rejects empty input
  Given the login form is displayed
  When the user submits the form with an empty password field
  Then an error message "Password is required" appears below the password field
  And the form is not submitted
```

**2. Observable state change**
```gherkin
# ✅ CORRECT
Scenario: Feature flag enables new behavior
  Given the feature flag "new_dashboard" is set to true in config
  When a user navigates to /dashboard
  Then the new dashboard layout is displayed with the "Beta" badge
  And the legacy dashboard is not rendered
```

**3. Output artifact verification**
```gherkin
# ✅ CORRECT
Scenario: Export generates valid CSV
  Given a dataset with 3 rows
  When the user clicks "Export as CSV"
  Then a file download begins
  And the downloaded file contains a header row and 3 data rows
  And each row has the correct number of comma-separated columns
```

## The Self-Check Questions

Before finalizing any scenario, ask:

1. **Could this test pass if the feature is completely broken?** → If yes, it's structural.
2. **Does this test execute the feature and verify observable outcomes?** → If no, rewrite it.
3. **Would a developer trust this test to catch real bugs?** → If not, it won't.

## Case Study: The Hook Execution Bug

A real example of structural verification causing a production bug:

**What was written (structural):**
```gherkin
Scenario: Hook spawning function exists
  Given the codebase at src/hooks/
  When I search for "spawnHook"
  Then the function is found in hooks.ts
  And the function is exported from the module
```

**What this missed:** The function existed but was never called during the main loop. It also had incorrect CLI arguments and failed silently.

**What should have been written (behavioral):**
```gherkin
Scenario: Hook executes after trigger event
  Given a configuration with the learning hook enabled
  And the trigger event has fired
  When the system processes the event
  Then a hook transcript file is created at the expected path
  And the transcript contains the expected output section
  And the downstream state reflects the hook's output
```

**Lesson:** The structural test gave false confidence. The behavioral test would have caught the bug immediately because the transcript file would not exist.

## When Structural Checks Are Acceptable

Structural checks are acceptable **only as supplementary documentation** after behavioral tests already prove the feature works. Never use them as the primary verification.

| Use case | Acceptable? |
|----------|-------------|
| Primary scenario verification | ❌ Never |
| After behavioral test passes, as documentation | ✅ Supplementary only |
| Checking generated file schema after generation is verified | ✅ OK as `And` clause |
