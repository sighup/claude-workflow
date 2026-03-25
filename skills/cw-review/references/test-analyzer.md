# Test Analyzer Reference

Expertise for identifying critical test coverage gaps — places where missing tests mean real bugs could ship undetected. Focus on behavioral coverage, not line counts.

## Quick Reference

**Missing tests for new functionality** — New public functions/methods/endpoints with no corresponding tests. New code paths (branches, error cases) with no coverage. New integrations or external service calls with no tests validating the contract.

**Critical untested edge cases** — Boundary conditions (empty input, zero, max values, null). Error paths in new code — what happens when it fails? Concurrency scenarios in async code. State transitions and their ordering constraints.

**Test quality issues** — Tests asserting on implementation details instead of behavior (brittle). Tautological assertions (always pass). Missing negative test cases. Mock/stub overuse masking broken integrations. Tests violating DAMP principles (Descriptive And Meaningful Phrases) — test code should prioritize readability over DRY; each test should tell a complete story; if understanding a test requires jumping to shared helpers, the abstraction hurts. Shared mutable state between tests (class-level variables, module-level fixtures, global state modified by one test and relied on by another — order-dependent and flaky).

**Integration point coverage** — For each integration point (API calls, DB queries, external services, message queues, file system), verify tests cover: expected request format, success response handling, error response handling, and timeout/unavailability. If tests only mock the happy path, that's a gap.

**Regression risk** — Changed behavior with no updated tests. Deleted tests without replacement — was the tested behavior removed or just the test? Modified assertions that weaken coverage. **Regression litmus test**: For each test, ask — if someone introduced a subtle bug in the tested function tomorrow (off-by-one, wrong conditional, missing null check), would this test catch it? If it only checks the happy path with simple inputs, the answer is probably no.

## Investigation Methodology

1. Read the changed production code. Understand what it does and what could go wrong.
2. Read the changed/added test files. Map which behaviors they cover.
3. Identify gaps: for each significant behavior or failure mode in the production code, is there a test?
4. Apply the regression litmus test: for each test, if someone broke this behavior tomorrow, would the test catch it?
5. Check integration point coverage: for each external call in production code, verify tests exercise the contract.
6. Check for test isolation: look for shared mutable state that could make tests order-dependent.
7. Check that existing tests still make sense after the production code changes.

## What You Do NOT Report

- Missing tests for trivial code (simple getters, one-line wrappers, boilerplate)
- Test style preferences (naming conventions, describe/it vs test())
- Missing tests in unchanged code
- Coverage percentage targets — evaluate whether the *right* things are tested, not line counts
- Testing infrastructure improvements unless actively broken

## Calibration

WARNING: LLMs are systematically overconfident, clustering scores in the 80-100 range. Calibrate carefully: 90-100 = exact trigger identifiable, 70-89 = likely real but needs more context, 50-69 = suspicious but uncertain. Use the full range.

Report findings with confidence >= 60. The validation pipeline will apply stricter dimension-specific thresholds (80 for test coverage).

### Criticality Ratings (1-10)

- **9-10**: Missing tests for functionality that could cause data loss, security issues, financial impact, or system failures. Must add before merge.
- **7-8**: Missing tests for important business logic that could cause user-facing errors or silent incorrect behavior.
- **5-6**: Missing edge case tests that could cause confusing behavior in uncommon scenarios.
- **3-4**: Nice-to-have coverage. Low risk of not having it.
- **1-2**: Optional thoroughness.

Only report gaps rated 5 or above. Lower-priority gaps are not worth the noise.

### Confidence

Map criticality to confidence: a 9-10 criticality gap is 90-100 confidence. A 5-6 criticality gap is 70-80 confidence. This ensures only genuinely important gaps surface through the filter.

- **90-100**: New public function with zero tests, or new error path with no coverage.
- **80-89**: Modified function, existing tests do not cover new branch.
- **70-79**: Integration point with only unit tests covering the happy path.
- **60-69**: Possible gap but uncertain whether existing tests cover it indirectly.
