# Execution Protocol Reference

Detailed step-by-step instructions for the implementer worker.

## Step 1: Orient

**Goal**: Understand current state without making changes.

1. `cd "$(git rev-parse --show-toplevel)"` — all metadata paths are repo-root-relative
2. Parse the complete assignment from your spawn prompt: `task_id`, requirements, scope (`files_to_create`, `files_to_modify`, `patterns_to_follow`), proof artifacts, `proof_capture`, and the `verification.pre`/`verification.post` commands — all delivered inline. This is your sole source of task metadata; you hold no Task tools and never read the board.
3. Check git status — ensure clean working tree
4. Read recent git history (`git log --oneline -10`)

The orchestrator set this task to `in_progress` on the board before dispatching you; you do not write status yourself.

**Exit criteria**: You have parsed the inline assignment and the codebase is clean.

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

**`index.lock` contention**: other workers and the orchestrator share this repository, so `git add`/`git commit` can fail with `Unable to create '.git/index.lock': File exists`. Retry the failed command after a 2-second wait, up to 3 attempts — the other process's git operation is sub-second and will have finished. Remove the lock file manually only after the retries fail AND `ps` shows no running `git` process (then it is a stale lock from a crashed process, not contention).

**Exit criteria**: Implementation files committed.

## Step 8.5: Write Result Journal

**Goal**: Record durable handoff evidence the dispatcher harvests to apply your board update.

The commit in Step 8 carries an ordinary implementation message — no metadata trailers, and the journal is never committed. After it lands, capture the now-known `commit_sha` and write the journal:

1. `commit_sha=$(git rev-parse HEAD)`
2. Resolve the results directory: `docs/specs/[spec-dir]/results/` (the run's gitignored results dir; create it if absent)
3. Write `{task_id}.result.json` into that directory, conforming to [result-journal-schema.md](result-journal-schema.md). Key it on the stable `task_id` (e.g. `T02.2`), never the native task-store integer. Include `commit_sha`, `status: "completed"`, and the proof paths/results from Step 6. The verifier fields (`verifier_verdict`, `verifier_tokens`, `verification_mode`) are filled in once Step 9 produces its verdict — the journal is finalized at the end of Step 9, before the Step 10 RESULT BLOCK.

The journal is written once and never edited after finalization. `commit_sha` is the sole commit-to-task link; the dispatcher verifies it against git before accepting the record.

**Exit criteria**: `{task_id}.result.json` exists under the gitignored results dir, carrying the implementation `commit_sha` and (after Step 9) the verifier verdict.

## Step 9: Verify Full

**Goal**: Confirm nothing broke after commit, with the result independently confirmed by one proof-verifier child ([proof-verifier.md](../../../agents/proof-verifier.md)) covering both the Step 6 proof commands and `verification.post`. Policy: [nesting guardrails](../../cw-dispatch/references/nesting-guardrails.md).

**Skip condition (low-risk, file-only proofs):** Before spawning, check every entry in `metadata.proof_artifacts` against its `type`, and check the task's declared file scope (`scope.files_to_create` + `scope.files_to_modify`) against the security-sensitive glob list below:

- **Skip the spawn** only when *both* hold: every proof artifact is type `file`, AND the file scope does not overlap the security-sensitive glob list. In that case, do not spawn a proof-verifier child at all — record `verification_mode: "skipped-low-risk"` in the journal (leave `verifier_verdict`/`verifier_tokens` per [result-journal-schema.md](result-journal-schema.md)'s guidance for this mode, never a fabricated PASS) and proceed straight to Step 10.
- **Spawn is unconditional** (this rule never skips it) when any proof artifact is type `cli`, `test`, `url`, or `browser` — regardless of file scope.
- **Spawn is unconditional** regardless of proof type when the task's declared file scope overlaps any entry in the security-sensitive glob list below. Overlap forces the spawn even if every proof artifact is type `file`.

Security-sensitive glob list (must stay in sync with `scripts/review-trigger.sh`'s list — duplicated here per the spec's Open Questions resolution rather than centralized, so update both together):

- `hooks/**`
- `scripts/*guard*`
- `scripts/*verify*`
- `agents/proof-verifier.md`
- `agents/validator.md`
- `scripts/review-trigger.sh`

When the skip condition does not apply, proceed with the spawn:

1. Spawn one proof-verifier child per verification attempt (never concurrent, never an implementer-type child), with `model: haiku` pinned explicitly
2. Spawn prompt: task id, repo root path, each proof command with its expected result, each `verification.post` command, and "Do not spawn sub-agents" — never the skill's all-caps context marker or raw task metadata JSON (SubagentStop hook pattern-matches both)
3. Gate on the verdict:
   - `Overall: PASS`: record verdict + verifier tokens, proceed to Step 10
   - `Overall: FAIL`: do NOT mark completed; if your changes caused it: fix, amend commit, re-verify with a fresh verifier (max 3 attempts); if pre-existing: document in proof_results
   - No usable verdict (spawn error, timeout, malformed): re-run checks inline for this attempt, record `verification_mode: "inline-degraded"`
4. **Inline fallback**: if the Task tool is not in your toolset, run each `verification.post` command yourself exactly as before (fix, amend, re-verify on failure, max 3 attempts) and record `verification_mode: "inline"` — spawn unavailability is never a task failure

Valid `verification_mode` values (keep in sync with [result-journal-schema.md](result-journal-schema.md)): `spawned`, `inline`, `inline-degraded`, and `skipped-low-risk` (this rule's low-risk file-only skip).

**Exit criteria**: PASS verdict (spawned), all checks green (inline), or the skip condition satisfied (skipped-low-risk). The completion gate applies in all three modes.

## Step 10: Report

**Goal**: Hand off your result to the orchestrator, the sole board writer.

You hold no Task tools. The orchestrator applies your completion `TaskUpdate` itself after harvesting your evidence: finalize the Step 8.5 journal, then emit the matching `CW-RESULT-BLOCK` sentinel as the last substantive content of your final message. The orchestrator harvests the sentinel first (highest precedence) and falls back to the on-disk journal.

1. Finalize `{task_id}.result.json` with the Step 9 verifier fields and `completed_at`, conforming to [result-journal-schema.md](result-journal-schema.md).
2. Emit the `CW-RESULT-BLOCK` sentinel holding exactly the same fields as the journal — keep the block and the on-disk journal byte-identical. Format and contract: [result-journal-schema.md](result-journal-schema.md).

Never report `status: "completed"` (in the journal or the sentinel) unless `verifier_verdict` is PASS — except when Step 9's skip condition applied, in which case `verification_mode: "skipped-low-risk"` with all Step 6 proof results PASS satisfies the completion gate instead.

**Exit criteria**: `{task_id}.result.json` finalized with proof_dir, proof_results, proof_summary, commit_sha, completed_at, verification_mode, and verifier_verdict; matching `CW-RESULT-BLOCK` sentinel emitted as the final message.

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
3. Write `{task_id}.result.json` with the failure record (same Step 8.5 mechanics) so the failure evidence is durable on disk, then emit a matching `status: "failed"` `CW-RESULT-BLOCK` as your final message. The orchestrator harvests it, records the diagnostics, and keeps the task dispatchable. Failure-record fields and the failed-block contract: [result-journal-schema.md](result-journal-schema.md):
   ```
   CW-RESULT-BLOCK-START
   {
     "task_id": "<task_id>",
     "status": "failed",
     "failed_step": "Proof|Sanitize|Commit|Verify Full|etc",
     "failure_reason": "...",
     "failure_count": N,
     "proof_status": "none|partial|complete",
     "last_failure": "<ISO timestamp>"
   }
   CW-RESULT-BLOCK-END
   ```
4. Exit with error summary
