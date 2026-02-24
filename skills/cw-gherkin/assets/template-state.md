# Scenario Template: State Persistence Feature

Use for features that maintain data across system boundaries — restarts, external edits, crashes, or process lifecycle transitions.

**Recommended test type:** Integration

## Template

```gherkin
Feature: [Demoable Unit Title]

  Scenario: [State] persists across [boundary]
    Given [initial state — create files, initialize data with specific values]
    When [state modification — user action or system event that changes state]
    And [boundary crossed — restart, external edit, crash, power loss simulation]
    Then [state retained — data integrity verified after boundary]
    And [no corruption — merge logic or locking preserved consistency]
    And [constraints maintained — business rules still enforced]
```

## Example

```gherkin
Feature: Task Progress Persistence

  Scenario: Completed tasks are not re-run after restart
    Given a task list with 3 tasks
    And task-1 has been completed
    When the application process is restarted
    Then task-1 status remains "completed"
    And task-2 is the next task to execute
    And task-1 is not executed again

  Scenario: External edits to progress file are preserved
    Given a task list in progress with a valid checksum
    When an operator adds a "notes" field to the progress file externally
    And updates the checksum to match
    And the application continues to the next task
    Then the "notes" field remains in the progress file
    And no checksum validation error is logged
    And subsequent iterations preserve the custom field
```

## Guidelines

- `Given`: Create initial state with specific, verifiable values (not just "data exists")
- `When`: The state modification followed by the boundary crossing as a separate `And`
- `Then`: Verify data integrity — specific field values, not just "file exists"
- `And`: Verify no data loss, conflict, or constraint violation

## Boundaries to Test

| Boundary | Example `And` clause |
|----------|----------------------|
| Process restart | `And the application is restarted` |
| External file edit | `And an operator modifies the file outside the application` |
| Crash (mid-write) | `And the process is killed mid-operation` |
| Concurrent access | `And a second process writes to the same file simultaneously` |

## Common Mistakes

- ❌ No boundary crossing — just `Given initial state` → `When modified` → `Then updated` (not testing persistence)
- ❌ `Then the file exists` (check the content, not just existence)
- ✅ `Then the "status" field in the file is "completed"`
- ✅ `And the "notes" field added externally is still present`
