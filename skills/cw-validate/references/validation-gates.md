# Validation Gates Reference

Six mandatory gates that determine PASS/FAIL for implementation validation.

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

Gate E has two layers: **static checks** (always run) and **build hygiene checks** (skippable when freshness holds).

**How to check**:

1. Read repository standards from the spec
2. **Static checks — always run:**
   - File organization (correct directories) — Glob/Read against the spec's structure section
   - Naming conventions (consistent with codebase) — read sample files and compare
   - Testing patterns (tests follow convention) — read test files and check structure
3. **Build hygiene checks — lint, build, full test suite:**
   - **If Step 4a's freshness check passed** (HEAD ∈ TASK_SHAS, all reachable, tree clean): trust the implementer's `verification.pre`/`verification.post` results from the same SHA. The `cw-execute` 11-phase protocol blocks commits that fail Phase 5 (lint+build) or Phase 9 (test) — a committed task at the trusted SHA is a guarantee that lint, build, and tests passed at exactly that tree state. Do NOT re-run. Record evidence as `Trusted from implementer Phase 5/9 at sha=<HEAD_SHA>`.
   - **If freshness failed** (HEAD moved, tree dirty, or any task missing `commit_sha`): re-run lint, build, and the test suite as before. Record evidence as `Re-executed: lint=<status> build=<status> test=<status>`.

**Why this trust is valid:** the cw-execute protocol's Phase 5 + Phase 9 are functionally equivalent to Gate E's build hygiene check. Phase 5 cannot proceed past lint/build failure. Phase 9 cannot leave a successful commit if `verification.post` failed (the commit gets amended). Therefore: a task in `completed` state with a `commit_sha` reachable from a clean HEAD is a proof-by-construction that lint/build/test passed at that SHA.

**Trust scope:** the implementer's guarantee covers exactly the commands listed in the task's `metadata.verification.pre` and `metadata.verification.post`. If the spec's repository standards section names additional build hygiene commands not present in `verification.pre`/`verification.post`, those additional commands must still be run regardless of freshness — they were never verified by the implementer protocol. Most projects align these (cw-plan derives both from the same project config), but if you find a mismatch, run only the unaligned subset and still trust the aligned commands.

**Why static checks always run:** file organization, naming, and pattern conformance are static analyses against the spec's standards section. They are not part of `verification.pre`/`verification.post` and therefore have no implementer guarantee to trust. They are also cheap (file reads), so there is no incentive to skip them.

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

## Red Flags (Auto-Escalate to CRITICAL/HIGH)

These findings automatically escalate regardless of other scoring:

- Real credentials in any committed file
- Missing proof artifacts for entire demoable units
- Files changed outside scope with no justification
- Test suite failing after implementation
- Build broken after implementation
