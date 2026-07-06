# Validation Gates Reference

Seven mandatory gates that determine PASS/FAIL for implementation validation.

## Gate Definitions

### GATE A: Critical Issues (BLOCKER)

**Rule**: Any CRITICAL or HIGH severity issue triggers immediate FAIL.

**How to check**:
1. Review all findings from the validation process
2. Score each finding using the rubric (0=CRITICAL, 1=HIGH, 2=MEDIUM, 3=OK)
3. If any score is 0 or 1, gate FAILS

**Common triggers**:
- Missing implementation for a functional requirement
- Proof artifacts that don't execute
- Real credentials in committed files

### GATE B: Coverage Completeness (REQUIRED)

**Rule**: Coverage matrix must have NO `Unknown` entries for functional requirements.

**How to check**:
1. List all functional requirements from the spec
2. For each, verify there's a corresponding proof result in task metadata
3. Each must be `Verified` or `Failed` (not `Unknown`)

**Common triggers**:
- Requirements that were never implemented
- Proof artifacts that weren't collected
- Tasks that were skipped

### GATE C: Proof Artifacts Functional (REQUIRED)

**Rule**: All proof artifacts must be accessible and produce expected results.

**How to check**:
1. Read `proof_results` from each completed task's metadata
2. Re-execute proof artifact commands where possible
3. Verify outputs match expected patterns

**Verification by type**:
- `test`: Re-run test command, confirm passes
- `cli`: Re-run CLI command, confirm output matches
- `url`: Make HTTP request, confirm status and content
- `file`: Check file exists with expected content
- `browser`: Verify page state matches expected

### GATE D: File Scope (REQUIRED)

**Rule**: All changed files must be in task scope OR justified in commit messages.

**How to check**:
1. Run `git log --name-only` for implementation commits
2. Collect all files from task `scope.files_to_create` + `scope.files_to_modify`
3. Any file changed but not in scope must have justification in commit message

**Common triggers**:
- Modifying shared utilities without declaring in scope
- Creating helper files not anticipated in planning
- Accidental changes to unrelated files

### GATE E: Repository Standards (REQUIRED)

**Rule**: Implementation must follow identified repository patterns and conventions.

**How to check**:
1. Read repository standards from the spec
2. For each standard, verify compliance:
   - Coding style (linting passes)
   - Testing patterns (tests follow convention)
   - File organization (correct directories)
   - Naming conventions (consistent with codebase)
   - Build/CI passes

### GATE F: Credential Safety (REQUIRED)

**Rule**: No real API keys, tokens, passwords, or credentials in proof artifacts.

**How to check**:
1. Scan all proof artifact files for sensitive patterns:
   - Strings matching `sk-`, `pk_`, `api_key`, `apiKey`, `API_KEY`
   - Bearer tokens, JWT tokens
   - Password values, secret values
   - Database connection strings with credentials
   - Private keys (PEM, SSH)
2. Any real credential found = immediate FAIL

**Note**: `[REDACTED]` placeholders are acceptable and expected.

### GATE G: Adversarial Analysis (REQUIRED)

**Rule**: Code analysis must not reveal unhandled critical boundary conditions or security gaps.

**How to check**:
1. Read the implementation code and analyze it for gaps in these categories:
   - **Boundary values**: Are edge cases (empty, zero, negative, max-length, Unicode) handled at input boundaries?
   - **Concurrency**: Is shared mutable state protected? Are critical sections guarded?
   - **Idempotency**: Do create/update handlers check for existing records? Are operations safe to retry?
   - **Error propagation**: Do error paths produce meaningful messages? Do they leak internals (stack traces, paths)?
   - **State cleanup**: Are multi-step operations atomic? Do partial failures leave orphan data?
   - **Input validation**: Are injection vectors (SQL, XSS, command injection) handled at system boundaries?
2. Not all categories apply to every feature — skip irrelevant ones
3. Each finding references specific files and line numbers
4. Mark as PASS (correctly handled) or CONCERN (gap found)
5. Any CONCERN with CRITICAL or HIGH impact = gate FAILS

**Mindset**: Review the code like an attacker looking for gaps, not a verifier confirming it works. This is static analysis, not runtime testing — read the code, trace the paths, find the holes.

**Common triggers**:
- Input validation missing on a public-facing endpoint
- No uniqueness check before INSERT (idempotency gap)
- Error handler catches and re-throws without sanitizing sensitive details
- Shared state accessed without synchronization

## Severity Rubric

| Score | Severity | Meaning |
|-------|----------|---------|
| 0 | CRITICAL | Blocks merge, fundamental issue |
| 1 | HIGH | Blocks merge, significant gap |
| 2 | MEDIUM | Should fix before merge |
| 3 | OK | No issues found |

## Rubric Dimensions

| Dimension | 0 (CRITICAL) | 1 (HIGH) | 2 (MEDIUM) | 3 (OK) |
|-----------|--------------|----------|------------|--------|
| R1 Spec Coverage | Multiple requirements unimplemented | One requirement missing proofs | Minor coverage gap | Full coverage |
| R2 Proof Artifacts | Proofs don't execute | Some proofs fail | Minor output mismatch | All pass |
| R3 File Integrity | Major undeclared changes | Some undeclared files | Justified extras | Perfect match |
| R4 Git Traceability | No commit-to-task mapping | Incomplete mapping | Minor gaps | Clear mapping |
| R5 Evidence Quality | No evidence collected | Partial evidence | Minor gaps | Complete evidence |
| R6 Repository Compliance | Major pattern violations | Some violations | Minor deviations | Full compliance |
| R7 Adversarial Analysis | Unhandled critical boundary/security gaps | Some unhandled edge cases | Minor gaps with low impact | All analyzed categories clean |

## Red Flags (Auto-Escalate to CRITICAL/HIGH)

These findings automatically escalate regardless of other scoring:

- Real credentials in any committed file
- Missing proof artifacts for entire demoable units
- Files changed outside scope with no justification
- Test suite failing after implementation
- Build broken after implementation
