## Review Categories

#### Category A: Correctness (Blocking)

- Logic errors, off-by-one, wrong conditions
- Missing error handling at system boundaries (user input, external APIs)
- Race conditions or concurrency issues
- Incorrect data transformations
- Missing null/undefined checks where data could be absent
- Cross-file impact causing breakage in consumers of changed code

#### Category B: Security (Blocking)

- SQL injection, XSS, command injection
- Hardcoded credentials, API keys, secrets
- Missing authentication or authorization checks
- Insecure data handling (logging PII, exposing internals)
- Path traversal or file inclusion vulnerabilities
- Unsafe deserialization

#### Category C: Spec Compliance (Blocking)

- Requirements from the spec that were missed or incorrectly implemented
- Behavior that contradicts spec intent
- Missing functionality described in demoable units
- CLAUDE.md/REVIEW.md convention violations (must cite the specific rule)

#### Category D: Quality (Advisory)

- Dead code or unreachable branches
- Overly complex logic that could be simplified
- Missing edge case handling
- Performance concerns (N+1 queries, unnecessary loops)
- Inconsistency with repository patterns
- Test coverage gaps
- Type design issues
- Stale or inaccurate code comments

## Severity Guidelines

Categories A, B, C are **blocking** (create FIX tasks). Category D is **advisory** (no FIX tasks). See `finding-schema.md` for full severity rules, confidence thresholds, and FIX task exclusion criteria.

## Dimension Mapping

Each concern agent reports findings using a specific `dimension` value. These map to categories as follows. See `finding-schema.md` for the full enriched finding schema.

| Concern | Dimension(s) | Category |
|---------|-------------|----------|
| bug-detector | `bug`, `error-handling` | A |
| security-reviewer | `security` | B |
| cross-file-impact | `cross-file-impact` | A |
| spec-and-conventions | `conventions`, `intent-alignment` | C |
| spec-and-conventions | `comments` | D |
| test-analyzer | `test-coverage` | D |
| type-design | `type-design` | D |
