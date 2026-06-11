# Execution Protocol Reference

Detailed step-by-step instructions for the implementer worker.

## Step 1: Orient

**Goal**: Understand current state without making changes.

1. `cd "$(git rev-parse --show-toplevel)"` — all metadata paths are repo-root-relative
2. Run `TaskList` to see all tasks and their statuses
3. Identify your assigned task (by owner or next unblocked pending task)
4. Run `TaskGet(taskId)` to load full task metadata
5. Check git status - ensure clean working tree
6. Read recent git history (`git log --oneline -10`)

**Exit criteria**: You know which task to execute and the codebase is clean.

## Step 2: Baseline

**Goal**: Confirm a clean starting state. **Do not run the full test suite** 

1. `git status --porcelain` — must be empty
2. `git log --oneline -5` — sanity-check recent history
3. If environment looks broken (missing deps, etc.): attempt fix or mark task blocked

Pre-existing test failures are documented in Step 9 when they surface.

**Exit criteria**: Clean tree, environment usable.

## Step 3: Context

**Goal**: Understand conventions before writing code.

1. Read each file in `metadata.scope.patterns_to_follow`
2. Extract:
   - File structure and organization
   - Naming conventions (variables, functions, files)
   - Error handling patterns
   - Test structure and assertion style
   - Import/export patterns
3. Read files in `metadata.scope.files_to_modify` to understand current state
4. Check if `metadata.scope.files_to_create` parent directories exist

**Exit criteria**: You understand the patterns and can write consistent code.

## Step 4: Implement

**Goal**: Create/modify files to satisfy all requirements.

For each requirement in `metadata.requirements`:

1. Identify which files need changes
2. Implement the requirement following extracted patterns
3. Write corresponding tests
4. Run linter incrementally if available

Rules:
- Follow patterns exactly - don't introduce new conventions
- Keep changes minimal - only what requirements demand
- Write tests alongside implementation, not after
- If a requirement is unclear, implement the most reasonable interpretation and note it

**Exit criteria**: All requirements have corresponding implementation and tests.

## Step 5: Verify Local

**Goal**: Confirm your changes don't break anything locally.

1. Run each command in `metadata.verification.pre` (typically lint + build)
2. If lint fails: fix issues and re-run
3. If build fails: fix compilation errors and re-run
4. Max 3 retry attempts per command

**Exit criteria**: All verification.pre commands pass.

## Step 6: Proof

**Goal**: Execute proof artifacts and capture evidence.

1. Create proof directory: `docs/specs/[spec-dir]/[NN]-proofs/` (repo-root-relative)
2. For each item in `metadata.proof_artifacts`:
   a. Execute the command/check
   b. Capture output to `{task_id}-{index+1:02d}-{type}.txt`
   c. Compare result against `expected`
   d. Record PASS or FAIL
3. Create summary file `{task_id}-proofs.md`

See [proof-artifact-types.md](proof-artifact-types.md) for type-specific guidance.

Proof commands run inline here because the on-disk artifacts must be written (the verifier child is read-only). Step 9's proof-verifier child independently re-runs these same commands — keep each command and its expected result for that spawn prompt.

**Exit criteria**: All proof artifacts collected, all PASS.

## Step 7: Sanitize

**Goal**: Remove sensitive data from proof artifacts. THIS IS BLOCKING.

1. Scan all proof files for patterns:
   - API keys (strings matching `sk-`, `pk_`, `api_key`, etc.)
   - Tokens (Bearer tokens, JWT tokens, session tokens)
   - Passwords (any field named password, secret, credential)
   - Connection strings (database URLs with credentials)
   - Private keys (PEM blocks, SSH keys)
2. Replace found values with `[REDACTED]`
3. Re-scan to confirm sanitization complete

**Exit criteria**: No sensitive data in any proof file. CANNOT proceed until clean.

## Step 8: Commit

**Goal**: Atomic path-mode commit of implementation files.

1. Enumerate: `FILES="<files_to_create + files_to_modify>"`
2. Stage: `git add -- $FILES`
3. Commit: `git commit -m "<metadata.commit.template>" -- $FILES`
4. Verify: `git show --name-only HEAD -- $FILES`

**Exit criteria**: Implementation files committed.

## Step 9: Verify Full

**Goal**: Confirm nothing broke after commit, with the result independently confirmed by one proof-verifier child ([proof-verifier.md](../../../agents/proof-verifier.md)) covering both the Step 6 proof commands and `verification.post`. Policy: [nesting guardrails](../../cw-dispatch/references/nesting-guardrails.md).

1. Spawn one proof-verifier child per verification attempt (never concurrent, never an implementer-type child), with `model: haiku` pinned explicitly
2. Spawn prompt: task id, repo root path, each proof command with its expected result, each `verification.post` command, and "Do not spawn sub-agents" — never the skill's all-caps context marker or raw task metadata JSON (SubagentStop hook pattern-matches both)
3. Gate on the verdict:
   - `Overall: PASS`: record verdict + verifier tokens, proceed to Step 10
   - `Overall: FAIL`: do NOT mark completed; if your changes caused it: fix, amend commit, re-verify with a fresh verifier (max 3 attempts); if pre-existing: document in proof_results
   - No usable verdict (spawn error, timeout, malformed): re-run checks inline for this attempt, record `verification_mode: "inline-degraded"`
4. **Inline fallback**: if the Task tool is not in your toolset, run each `verification.post` command yourself exactly as before (fix, amend, re-verify on failure, max 3 attempts) and record `verification_mode: "inline"` — spawn unavailability is never a task failure

**Exit criteria**: PASS verdict (spawned) or all checks green (inline). The completion gate applies in both modes.

## Step 10: Report

**Goal**: Update task board with results.

1. Construct proof_results:
   ```json
   [
     { "type": "test", "status": "pass", "output_file": "T01-01-test.txt" },
     { "type": "cli", "status": "pass", "output_file": "T01-02-cli.txt" }
   ]
   ```
2. Update task:
   ```
   TaskUpdate({
     taskId: "<native-id>",
     status: "completed",
     metadata: {
       proof_dir: "docs/specs/[spec-dir]/[NN]-proofs",
       proof_results: [...],
       proof_summary: "X/Y proofs passed",
       commit_sha: "<sha from git log --oneline -1>",
       completed_at: "<ISO timestamp>",
       verification_mode: "spawned | inline | inline-degraded",
       verifier_verdict: "PASS",
       verifier_tokens: "<number (relayed child usage) when spawned; literal n/a when inline or inline-degraded>"
     }
   })
   ```

Never set `status: "completed"` unless `verifier_verdict` is PASS.

**Exit criteria**: Task marked completed with proof_dir, proof_results, proof_summary, commit_sha, completed_at, verification_mode, and verifier_verdict in metadata.

## Step 11: Clean Exit

**Goal**: Leave codebase in pristine state for next worker.

1. Run `git status --porcelain` - should be empty
2. If uncommitted changes exist: stash or commit as appropriate
3. Output execution summary

**Exit criteria**: Clean git status, summary output. 

## Error Recovery

### Retry Logic (Max 3 per step)

```
attempt = 0
while attempt < 3:
  result = execute_phase()
  if result.success:
    break
  attempt += 1
  fix_issue(result.error)

if attempt >= 3:
  handle_failure()
```

### Failure Handling

1. `git stash push -m "cw-execute: {task_id} partial work"`
2. `git checkout -- .` (clean working tree)
3. Update task:
   ```
   TaskUpdate({
     taskId: "<native-id>",
     status: "pending",
     metadata: {
       proof_results: [{ status: "failed", error: "..." }],
       last_failure: "<ISO timestamp>",
       failure_count: N
     }
   })
   ```
4. Exit with error summary
