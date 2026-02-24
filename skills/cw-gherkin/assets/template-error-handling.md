# Scenario Template: Error Handling / Recovery Feature

Use for features involving failure injection, invalid input rejection, error messages, recovery paths, or graceful degradation.

**Recommended test type:** Integration (for system errors) or E2E (for UI error states)

## Template

```gherkin
Feature: [Demoable Unit Title]

  Scenario: [System detects and handles specific failure]
    Given [precondition — valid initial state or partially set up environment]
    When [failure is injected — invalid input, missing dependency, resource unavailable]
    Then [error is detected — specific error message, non-zero exit, HTTP error status]
    And [system is in a safe state — no partial writes, no corrupted data, rollback applied]
    And [user receives actionable feedback — message, log entry, or recovery instruction]
```

## Example

```gherkin
Feature: File Upload Validation

  Scenario: Oversized file is rejected with clear error
    Given the upload form accepts files up to 10 MB
    When the user selects a 25 MB file and clicks Upload
    Then the upload is rejected before transmission begins
    And an error message "File exceeds 10 MB limit" is displayed
    And no partial file data is stored on the server

  Scenario: Corrupted config file prevents startup with diagnostic message
    Given a config file with invalid JSON syntax
    When the application starts
    Then the application exits with code 1
    And stderr contains "Config parse error at line [N]: [description]"
    And no partial initialization side effects remain
```

## Guidelines

- `Given`: Start from a valid state, then describe the fault condition separately in `When`
- `When`: Inject the failure precisely — don't say "an error occurs", specify what goes wrong
- `Then`: The error detection signal — specific message text, exit code, HTTP status
- `And`: Safe state verification — no partial writes, no corrupted data
- `And`: User-facing feedback — error must be actionable, not just logged internally

## Failure Types to Cover

| Failure type | `When` pattern |
|--------------|----------------|
| Invalid input | `When the user submits [specific bad value]` |
| Missing dependency | `When [required service] is unavailable` |
| Resource limit | `When [quota/size/rate] is exceeded` |
| Corrupted data | `When [file/record] contains invalid content` |
| Partial failure | `When the operation fails midway through [N] items` |

## Common Mistakes

- ❌ `Then the error is handled` (which error? how is it "handled"?)
- ❌ `Then no exception is thrown` (check from the user's perspective, not the runtime)
- ✅ `Then an error message "Upload failed: disk full" is displayed`
- ✅ `And the previously uploaded files are not affected`
