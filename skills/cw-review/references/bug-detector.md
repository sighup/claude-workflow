# Bug Detector Reference

Expertise for detecting correctness issues and error handling defects — things that cause wrong behavior, crashes, data corruption, silent failures, or unexpected results at runtime.

## Quick Reference

### Correctness Bugs

**Logic errors** — Off-by-one in loops/slices/array access. Incorrect boolean logic (flipped conditions, missing negation, wrong operator precedence). Wrong comparison operators (< vs <=, == vs ===). Unreachable code or dead branches. Infinite loops or missing termination.

**Null/undefined handling** — Dereferencing potentially null values without checks. Missing null propagation in chains. Assuming arrays/objects are populated when they might be empty. Optional values used as required without validation.

**Race conditions and concurrency** — Shared mutable state without synchronization. Time-of-check to time-of-use (TOCTOU) bugs. Missing awaits on async operations. Concurrent modifications to collections.

**Resource leaks** — File handles not closed on all paths (including error paths). DB connections not released in finally/defer blocks. Locks acquired without guaranteed release. Timers/intervals without cleanup on teardown. Event listeners added without corresponding removal. Memory held by closures that outlive their scope.

**Edge cases** — Empty inputs (empty string, empty array, zero, null). Boundary values (MAX_INT, negative numbers, Unicode). Missing default cases in switches or pattern matches. Unhandled promise rejections or uncaught exceptions.

**API misuse** — Wrong argument types or order. Ignoring return values that indicate errors. Using deprecated APIs or APIs with changed behavior. Mismatched resource acquire/release.

**Data flow** — Variables used before assignment. Stale closures capturing wrong value. Mutation of shared references when copy was intended. Type coercion causing unexpected behavior.

### Error Handling Defects

**Silent failures** — Empty catch blocks (absolutely forbidden). Catch blocks that swallow exceptions and return defaults without logging. Promises with no `.catch()` or missing `try/catch` around `await`. Error callbacks that ignore the error parameter. Functions returning null/undefined/false on failure without indicating why.

**Overly broad catches** — `catch (Exception e)` / `catch (error)` handling all types identically. Catch blocks masking unrelated errors. Pokemon exception handling hiding bugs behind generic messages. **For each broad catch, you MUST list 2-3 specific unexpected error types it could mask** (e.g., a `catch (error)` around a network call could hide: TypeError from bad response parsing, RangeError from buffer operations, ReferenceError from typos in the handler).

**Inadequate error context** — Error logs missing the failed operation, relevant IDs, or state. Generic messages like "something went wrong." Missing stack traces or causal chains. Wrong severity level (console.log for errors, warn for critical failures).

**Unjustified fallback behavior** — Falling back to defaults when an error indicates a real problem. Retry logic exhausting attempts without informing the user. Silent fallback chains. Using cached/stale data on failure without indicating staleness.

**Error propagation problems** — Errors re-thrown without preserving original cause. Errors converted to return codes that callers don't check. Async errors that fire-and-forget. Resource leaks in error paths (missing finally blocks).

**Missing error handling** — Operations that can fail (I/O, network, parsing) with no handling at all. Missing validation at system boundaries. No timeout handling on external calls.

## Investigation Methodology

1. **Trace the intent first.** Before looking for bugs, understand the INTENT from the change summary, PR title, description, and commit messages. Bugs are deviations from intent — you need to know what the author was trying to do before identifying where they failed.

2. **Cross-file investigation.** Use LSP `findReferences` (or Grep) to find all callers of changed functions. Read calling code to check for argument mismatches, missing error handling of new return types, or broken assumptions. If a function's signature, return type, or error behavior changed, every caller is a potential bug site.

3. **Trace data flow from input to output.** For each function in the diff, identify its inputs (parameters, globals, config, external data) and trace them forward through every branch to every output (return values, side effects, writes). At each step ask: can this value be in a state the next operation doesn't expect?

4. **Check boundary conditions.** What happens with the smallest input? The largest? An empty one?

5. **Trace error paths.** For each error that can occur, trace what happens: is it logged? Reported to monitoring? Told to the user? Or does it vanish? Check that the error path performs the same cleanup as the happy path (state reset, resource release, notification).

6. **Read CLAUDE.md first.** Look for error handling conventions — specific logging functions, error tracking IDs, monitoring integrations, custom error classes, required error response formats. Calibrate findings against the project's chosen patterns, not generic best practices.

7. **Check resource cleanup in error paths.** For every resource acquired before or within a try block, verify the error path releases it. Look for missing `finally` blocks, missing `defer` statements, or cleanup code that only runs on the happy path.

8. **Check timeout handling.** For each external call (HTTP, database, third-party APIs, message queues), verify: (a) timeout is configured, (b) timeout error is caught specifically, (c) timeout handler includes enough context to diagnose which call timed out.

## Output Requirements

For error handling findings, include:
1. The specific problem and its location
2. The **hidden error types** — list the specific unexpected exceptions the current code could catch/mask
3. A **corrected code example** showing how to fix the issue (use the project's conventions if CLAUDE.md specified them, otherwise use idiomatic patterns for the language)
4. Severity and confidence ratings

## What You Do NOT Report

- Style issues, naming conventions, or formatting
- Missing tests (test-analyzer handles that)
- Security vulnerabilities (security-reviewer handles that)
- Performance issues, unless they cause incorrect behavior (e.g., stack overflow from unbounded recursion)
- Issues in code the author didn't change, unless the changes create a new interaction bug
- Error handling in test code (test assertions are expected to throw)
- Intentional catch-and-continue patterns that are clearly documented
- Error handling style preferences that don't affect correctness
- Pre-existing error handling issues in unchanged code

## Calibration

WARNING: LLMs are systematically overconfident, clustering scores in the 80-100 range. Calibrate carefully: 90-100 = exact trigger identifiable, 70-89 = likely real but needs more context, 50-69 = suspicious but uncertain. Use the full range.

Report findings with confidence >= 60. The validation pipeline will apply stricter dimension-specific thresholds (80 for bugs).

### Severity

- **Critical**: Bug with specific triggerable input, or silent failure causing data loss/corruption/security issues. Empty catch blocks around critical operations. Resource leaks in error paths for long-lived processes.
- **High**: Highly likely bug based on code structure. Error swallowed causing confusing behavior. Missing error handling on external calls. Broad catches hiding potential bugs. Missing timeout on external calls.
- **Medium**: Suspicious pattern warranting attention. Poor error context making debugging difficult. Missing logging on non-critical paths.
- **Low**: Minor improvements to error messages or logging context.

### Confidence

- **90-100**: You can point to specific input that triggers the bug, and explain exactly what goes wrong.
- **80-89**: Bug is highly likely based on code structure, but needs more context for 100% certainty.
- **70-79**: Suspicious and warrants attention, but there might be handling you're not seeing.
- **60-69**: Plausible issue but significant uncertainty remains.

Be the reviewer who catches the bug that would cause a 2am page. But also the reviewer who doesn't waste the author's time with hypothetical issues that can't actually happen.
