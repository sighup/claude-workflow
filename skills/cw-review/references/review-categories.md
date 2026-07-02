## Review Categories

#### Category A: Correctness (Blocking)

- Logic errors, off-by-one, wrong conditions
- Missing error handling at system boundaries (user input, external APIs)
- Race conditions or concurrency issues
- Incorrect data transformations
- Missing null/undefined checks where data could be absent

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

#### Category D: Quality (Advisory)

- Dead code or unreachable branches
- Overly complex logic that could be simplified
- Missing edge case handling
- Performance concerns (N+1 queries, unnecessary loops)
- Inconsistency with repository patterns

**Note:** This category subsumes cw-validate's Gate E (repository-standards conformance: coding style, testing patterns, file organization, naming conventions, CI/build status).

#### Category E: Reuse (Advisory)

- New utility functions that duplicate existing ones in the codebase
- Re-implemented patterns that an existing module already provides
- New abstractions where an existing framework feature or library call would suffice
- Copy-pasted logic from another file that should be extracted to a shared module
- New constants or configuration values that already exist elsewhere

**How to check for reuse opportunities:**
1. **Name search**: For each new function in the diff, `Grep` the codebase for the same function name (e.g., new `formatDate` → search for existing `formatDate`, `dateFormat`, `formatTimestamp`)
2. **Directory scan**: `Glob` for `**/utils/**`, `**/helpers/**`, `**/lib/**`, `**/common/**`, `**/shared/**` and read their exports — these are the most likely locations for existing utilities
3. **Pattern match**: If the new code implements a common pattern (debounce, retry, deep merge, slug generation, validation), search for that pattern name across the codebase and `package.json` dependencies
4. **Import check**: Look at what the new file already imports — the same package may export a function that replaces the hand-rolled version (e.g., writing a custom `pick()` when lodash is already a dependency)
5. Flag duplicates as advisory — the implementer may have had a good reason to create a new version

## Severity Guidelines

| Category | Creates FIX Task | Blocks Merge |
|----------|-----------------|--------------|
| A: Correctness bug | Yes | Yes |
| B: Security vulnerability | Yes | Yes |
| C: Missing spec requirement | Yes | Yes |
| D: Quality/style note | No | No |
| E: Reuse opportunity | No | No |

**Do NOT create FIX tasks for:**
- Code style preferences already handled by linters
- Minor naming disagreements
- "I would have done it differently" observations
- Test code (tests are the oracle)
- Documentation gaps (unless spec requires it)
