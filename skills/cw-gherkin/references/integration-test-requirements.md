# Integration Test Requirements

When generating a `gherkin.md`, the `Recommended test type` header should reflect this decision framework. Use it to select between `Unit`, `Integration`, and `E2E`.

## Decision Tree

```
Does the scenario involve external systems?
(file system, spawned processes, APIs, databases, browsers)
├─ Yes → Integration or E2E test required
└─ No → Unit test may be sufficient

Can behavior be fully verified with mocks?
├─ Yes → Unit test sufficient
└─ No (timing, platform-specific behavior, real I/O needed) → Integration required

Does the scenario spawn processes or use IPC?
└─ Yes → Integration test required (always)

Does the scenario modify file system state?
└─ Yes → Integration test required (always)

Does the scenario involve a browser or UI workflow?
└─ Yes → E2E test (use cw-testing with chrome-devtools or playwright backend)

Is the scenario pure logic or computation?
└─ Yes → Unit test sufficient
```

## Categories Requiring Integration Tests

### 1. External Process Spawning

Features that spawn CLI commands, subagents, or shell scripts.

**Why:** Process spawning is platform-specific. IPC, output capture, and process lifecycle must be tested with real processes — mocks cannot reproduce timing or platform behavior.

**Gherkin signal:** `When [command/process] runs`, `Then [output file] is created`, `And exit code is [N]`

### 2. File System State Changes

Features that create, modify, or delete files and directories.

**Why:** File permissions, atomicity, race conditions, and change detection require actual file system operations.

**Gherkin signal:** `Then [file] is created at [path]`, `And [file] contains [content]`, `When [file] is modified`

### 3. Inter-Process Communication

Components that communicate via files, sockets, or message queues.

**Why:** Timing issues, serialization edge cases, and connection handling only appear with real IPC.

**Gherkin signal:** `When [component A] writes`, `Then [component B] reads`, `And [shared state] reflects`

### 4. Async / Parallel Operations

Features with concurrent execution and shared state.

**Why:** Race conditions and lock contention only manifest under real async execution.

**Gherkin signal:** `When [N] operations run concurrently`, `Then all [N] results are correct`, `And no data is corrupted`

### 5. Transaction / Recovery Scenarios

Features that maintain consistency across failures, crashes, or partial writes.

**Why:** Checksum validation, rollback logic, and crash recovery require real file I/O.

**Gherkin signal:** `When the process is killed`, `And the system is restarted`, `Then state is recovered`

## Categories Where Unit Tests Are Sufficient

| Scenario type | Reasoning |
|---------------|-----------|
| Pure functions (parse, validate, transform) | No I/O, fully deterministic |
| Business logic with no external deps | Can verify with input/output alone |
| Mocked external APIs | Non-deterministic component isolated; internal logic tested with real code |

## E2E vs Integration

| | Integration | E2E |
|--|-------------|-----|
| Scope | One or more components + real dependencies | Full system from user interface to data layer |
| Backend | Real file system, processes, APIs | Browser automation (chrome-devtools, playwright) |
| Speed | Medium (100ms–10s) | Slow (seconds–minutes) |
| Use when | No UI involved | Feature has a browser/UI entry point |

## Output Header Values

In `gherkin.md`, set `Recommended test type` to:

- `Unit` — pure logic, no I/O, fully mockable
- `Integration` — file system, processes, IPC, async, recovery
- `E2E` — browser/UI workflow, full-stack verification
- `Integration + E2E` — feature has both a UI entry point and non-UI verification needs
