# Scenario Template: Async / Concurrent Feature

Use for features involving parallel operations, background tasks, event queues, or operations with timing constraints.

**Recommended test type:** Integration

## Template

```gherkin
Feature: [Demoable Unit Title]

  Scenario: [Concurrent operations complete correctly]
    Given [N concurrent operations configured or triggered]
    When [all operations are started simultaneously or in parallel]
    Then [all N results are present and correct]
    And [no data corruption or partial writes occurred]
    And [ordering guarantees are maintained where required]
```

## Example

```gherkin
Feature: Parallel Report Generation

  Scenario: Concurrent report requests produce independent correct outputs
    Given 3 report requests for different datasets are queued
    When all 3 reports are generated concurrently
    Then 3 separate report files are created
    And each file contains data only from its corresponding dataset
    And no file contains mixed data from another dataset

  Scenario: Queue processes tasks in order when ordering is required
    Given 5 tasks submitted to the processing queue in sequence
    When the queue processes all tasks
    Then tasks are executed in submission order
    And each task's output references only its own input
    And the final state reflects all 5 tasks completed
```

## Guidelines

- `Given`: Specify N — the exact count of concurrent operations
- `When`: State that operations run simultaneously or in parallel (triggers real concurrency)
- `Then`: Verify all N results exist and each is correct (not just "some results exist")
- `And`: Explicitly check for data corruption — mixed outputs, partial writes, stale reads

## Common Mistakes

- ❌ Testing one operation at a time (doesn't surface race conditions)
- ❌ `Then the operations complete` (verify the outputs, not just completion)
- ✅ `Then 3 separate report files are created`
- ✅ `And no file contains data from another report`

## Why Integration Test Required

Race conditions and lock contention only manifest with real async execution. Mocks that resolve instantly cannot reproduce timing-dependent bugs.
