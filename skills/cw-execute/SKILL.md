---
name: cw-execute
description: "Executes a single task from the task board using the 11-step implementation protocol. This skill should be used after cw-plan or cw-dispatch assigns a task, or when manually implementing a specific task by ID."
user-invocable: true
allowed-tools: Glob, Grep, Read, Edit, Write, Bash, Task, AskUserQuestion, LSP
effort: high
---

# CW-Execute: Single Task Execution

## Context Marker

Always begin your response with: **CW-EXECUTE**

## Overview

You are the **Implementer** role in the Claude Workflow system. You execute exactly ONE task from the native task board, following an 11-step protocol that ensures consistent, verifiable, autonomous execution. Each invocation leaves the codebase in a clean, committable state.

## Your Role

You are an **autonomous coding agent**. You hold no Task tools and never read or write the board. Your entire context comes from:
1. Your spawn prompt — the complete assignment inline: `task_id`, requirements, scope (files to create/modify, patterns to follow), proof artifacts, and verification commands
2. Git history
3. The codebase itself

You have no memory of previous executions. You hand your result off through an uncommitted `{task_id}.result.json` journal written to the run's gitignored results directory (`docs/specs/<run>/results/`) and a final-message RESULT BLOCK; the orchestrator is the sole board writer and applies your completion from that evidence.

## Critical Constraints

- **ALWAYS** execute exactly ONE task per invocation
- **NEVER** skip verification steps — they prevent regressions
- **ALWAYS** commit on success — partial work is lost between sessions
- **ALWAYS** hand off via the journal + RESULT BLOCK — the orchestrator depends on it to apply your completion
- **ALWAYS** leave codebase clean — no uncommitted changes after completion
- **NEVER** proceed to commit without proof files — proof artifacts are BLOCKING
- **NEVER** commit unsanitized proofs — security sanitization is BLOCKING
- **NEVER** report a task completed without a PASS verification verdict recorded in the journal (Step 9)
- **NEVER** read or write the task board — you hold no Task tools; your assignment is fully inline

## MANDATORY FIRST ACTION

**Read your assignment from the spawn prompt before any other action.**

Your prompt carries the complete assignment inline: `task_id`, requirements, scope, proof artifacts, and verification commands. If the prompt carries no assignment, report that and exit.

## Proof File Requirements (MANDATORY)

Every task execution MUST produce proof artifacts on disk under:

```
docs/specs/[spec-dir]/[NN]-proofs/
├── {task_id}-01-{type}.txt    # First proof artifact
├── {task_id}-02-{type}.txt    # Second proof artifact
├── {task_id}-proofs.md        # Summary file (REQUIRED)
└── ...
```

Sanitize in Step 7 before exit — proofs live on disk and could leak if inspected.

## The 11-Step Protocol

### Step 1: Orient

Understand current state without making changes.

1. `cd "$(git rev-parse --show-toplevel)"` — always operate from the repo root. All metadata paths (scope files, proof dirs, spec paths) are repo-root-relative; running from a subpackage cwd will create files in the wrong location.
2. Parse your assignment from the spawn prompt: `task_id`, requirements, scope (`files_to_create`, `files_to_modify`, `patterns_to_follow`), proof artifacts, `proof_capture`, and the `verification.pre`/`verification.post` commands — all delivered inline. This is your sole source of task metadata; you hold no Task tools.
3. Verify git status is clean: `git status --porcelain`
4. Read recent history: `git log --oneline -10`

The orchestrator set this task to `in_progress` on the board before dispatching you; you do not write status yourself.

### Step 2: Baseline

Confirm a clean starting state. **Do not run the full test suite here** — Step 9 (Verify Full) catches regressions caused by your work. 

1. `git status --porcelain` — must be empty (clean tree)
2. `git log --oneline -5` — sanity check recent history
3. If anything looks wrong (dirty tree, missing deps surfaced by Step 3 reads):
   - Environment issue: attempt fix (install deps, etc.)
   - Unfixable: update task description with blocker, exit

Pre-existing test failures (if any) will surface in Step 9 and be documented there.

### Step 3: Context

Load patterns and understand conventions.

1. Read each file in `metadata.scope.patterns_to_follow`
2. Extract: structure, naming, error handling, test patterns
3. Read files in `metadata.scope.files_to_modify`
4. Verify parent directories exist for `metadata.scope.files_to_create`

#### LSP Availability Check

After loading patterns, probe whether an LSP server is available. Pick a file from `metadata.scope.files_to_modify` or `metadata.scope.patterns_to_follow` and attempt a single `documentSymbol` operation:

```
LSP({
  operation: "documentSymbol",
  filePath: "{file from scope}",
  line: 1,
  character: 1
})
```

- **LSP available**: The operation returned symbols. Set `lsp_available = true`.
- **LSP unavailable**: The operation returned an error. Set `lsp_available = false`.

When `lsp_available = true`, use LSP alongside Glob/Grep/Read in this step and Step 4:
- `documentSymbol` on pattern files to understand their structure and exported symbols
- `goToDefinition` to trace types and interfaces referenced in files being modified
- `findReferences` to understand how modified functions/exports are consumed elsewhere

### Step 4: Implement

Create/modify files to satisfy requirements.

For each requirement in `metadata.requirements`:
1. Implement the requirement following extracted patterns
2. Write corresponding tests alongside implementation
3. Run linter incrementally if available

When `lsp_available = true`, use LSP to guide implementation:
- `hover` to check type signatures before modifying function parameters or return types
- `goToImplementation` to find all implementations of interfaces being extended
- `findReferences` before renaming or changing function signatures to understand impact

Rules:
- Follow patterns exactly - don't introduce new conventions
- Keep changes minimal - only what requirements demand
- If unclear, implement most reasonable interpretation and note it
- Max 3 retry attempts for failing tests

### Step 5: Verify Local

Run pre-commit checks.

1. Execute each command in `metadata.verification.pre`
2. Fix any lint or build issues
3. Max 3 retry attempts per command

### Step 6: Proof

Execute proof artifacts and capture evidence.

1. Determine proof directory from `spec_path`: `docs/specs/[spec-dir]/[NN]-proofs/` (repo-root-relative)
2. Create the proof directory if it doesn't exist
3. Read `metadata.proof_capture` for the capture method decided during planning
4. For each proof artifact in `metadata.proof_artifacts`:

**Automated proofs** (test, cli, file, url):
   a. Execute the command/check per artifact type
   b. Capture output to `{task_id}-{index+1:02d}-{type}.txt`
   c. Include header: type, command, expected, timestamp
   d. Compare result against expected
   e. Record PASS or FAIL

**Visual proofs** (browser):

Based on `metadata.proof_capture.visual_method`:

| Method | Action |
|--------|--------|
| `auto` | Use the tool specified in `metadata.proof_capture.tool` to capture |
| `manual` | Prompt user: "Please verify: [description]. Confirmed? (yes/no)" |
| `skip` | Mark as "Skipped - code verification only" |

**Auto-capture with available tools:**

```
# chrome-devtools (web pages)
mcp__chrome-devtools__take_screenshot(filePath: "{proof_dir}/{task_id}-{index+1:02d}-screenshot.png")

# screencapture (macOS native apps)
screencapture -w {proof_dir}/{task_id}-{index+1:02d}-screenshot.png

# scrot (Linux)
scrot -s {proof_dir}/{task_id}-{index+1:02d}-screenshot.png
```

**Manual verification flow:**

```
MANUAL VERIFICATION REQUIRED
============================
Proof: {description}
Expected: {expected}

Please verify this is working correctly.
Enter 'yes' to confirm, 'no' if it fails, or describe the issue:
>
```

Record user response in proof file:
```
Type: visual (manual)
Description: {description}
Expected: {expected}
Timestamp: {ISO timestamp}
User Confirmed: yes|no
User Notes: {any notes provided}
Status: PASS|FAIL
```

5. Create summary: `{task_id}-proofs.md` (REQUIRED)

**Step 6 Gate Check (BLOCKING):**

Before proceeding to Step 7, verify:

```bash
# Check proof directory exists
ls -la docs/specs/[spec-dir]/[NN]-proofs/

# Verify required files exist
ls docs/specs/[spec-dir]/[NN]-proofs/{task_id}-*.txt
ls docs/specs/[spec-dir]/[NN]-proofs/{task_id}-proofs.md
```

| Check | Required | Action if Missing |
|-------|----------|-------------------|
| Proof directory exists | Yes | Create it |
| At least one `{task_id}-*.txt` file | Yes | Execute proof artifacts |
| `{task_id}-proofs.md` summary | Yes | Create summary |
| All proof artifacts have status | Yes | Re-run failed proofs |

**BLOCK**: Do not proceed to Step 7 until all proof files exist.

If proof artifacts cannot be executed (e.g., environment issues):
1. Create proof file with status `BLOCKED` and reason
2. Document workaround or manual steps needed
3. Still create the summary file

See [proof-artifact-types.md](references/proof-artifact-types.md) for type-specific instructions.

**Independent re-verification:** proof commands run inline here because the on-disk artifacts must be written (the verifier child is read-only). Step 9 spawns one proof-verifier child that independently re-runs these same proof commands alongside the post checks — keep each command and its expected result for that spawn prompt.

### Step 7: Sanitize (Blocking)

Remove sensitive data from proof files. **Cannot proceed until clean.**

1. Scan all `{task_id}-*` files for:
   - API keys (`sk-`, `pk_`, `api_key`, `apiKey`)
   - Tokens (Bearer, JWT, session, access_token)
   - Passwords (password, secret, credential fields)
   - Connection strings (with embedded credentials)
   - Private keys (PEM blocks, SSH keys)
2. Replace found values with `[REDACTED]`
3. Re-scan to confirm clean
4. **BLOCK**: Do not proceed to Step 8 until scan is clean

### Step 8: Commit

Atomic path-mode commit of implementation files.

**Pre-Commit Checklist:**

```bash
test -d "docs/specs/[spec-dir]/[NN]-proofs" || { echo "ERROR: Proof directory missing"; exit 1; }
test -f "docs/specs/[spec-dir]/[NN]-proofs/{task_id}-proofs.md" || { echo "ERROR: Proof summary missing"; exit 1; }
ls docs/specs/[spec-dir]/[NN]-proofs/{task_id}-*.txt >/dev/null 2>&1 || { echo "ERROR: No proof artifacts"; exit 1; }
grep -r "sk-\|pk_\|api_key\|Bearer \|password=" docs/specs/[spec-dir]/[NN]-proofs/{task_id}-* && { echo "ERROR: Unsanitized secrets"; exit 1; }
```

**Commit Steps:**

1. Enumerate your files: `FILES="<file1> <file2> ..."` from `metadata.scope.files_to_create` + `files_to_modify`
2. Stage: `git add -- $FILES`
3. Commit: `git commit -m "<metadata.commit.template>" -- $FILES`
4. Verify: `git show --name-only HEAD -- $FILES`

### Step 8.5: Write Result Journal

The Step 8 commit carries an ordinary implementation message — no metadata trailers — and the journal is never committed. After it lands, write the durable handoff record the dispatcher harvests:

1. Capture the now-known sha: `commit_sha=$(git rev-parse HEAD)`
2. Resolve the run's gitignored results dir `docs/specs/[spec-dir]/results/` (create it if absent)
3. Write `{task_id}.result.json` there, conforming to [result-journal-schema.md](references/result-journal-schema.md). Key it on the stable `task_id` (e.g. `T02.2`), never the native task-store integer. Include `commit_sha`, `status: "completed"`, and the Step 6 proof paths/results. The verifier fields (`verifier_verdict`, `verifier_tokens`, `verification_mode`) are filled in once Step 9 produces its verdict; finalize the journal at the end of Step 9, before the Step 10 RESULT BLOCK.

The journal is written once and never edited after finalization. `commit_sha` is the sole commit-to-task link; the dispatcher verifies it against git before accepting the record.

### Step 9: Verify Full

Post-commit verification, independently confirmed by one [proof-verifier](../../agents/proof-verifier.md) child covering both the Step 6 proof commands and `metadata.verification.post`. Policy: [nesting guardrails](../cw-dispatch/references/nesting-guardrails.md).

**Spawn the verifier:**

1. One verifier per verification attempt — never concurrent verifiers, never implementer-type children
2. Pin the model explicitly: `model: haiku` — unpinned children inherit yours
3. Spawn prompt contains: the task id, the repo root path, each proof command with its expected result, each `verification.post` command, and "Do not spawn subagents"
4. Spawn prompt must NOT contain this skill's all-caps context marker or raw task metadata JSON — the SubagentStop hook pattern-matches both (see the [verifier's stop-hook contract](../../agents/proof-verifier.md))

**Gate on the verdict (BLOCKING):**

| Verdict | Action |
|---------|--------|
| `Overall: PASS` | Record verdict + verifier tokens, proceed to Step 10 |
| `Overall: FAIL` | Task must NOT be marked completed. Fix the issue, amend commit, re-verify with a fresh verifier — existing loop, max 3 attempts |
| No usable verdict (spawn error, timeout, malformed) | Re-run the checks inline for this attempt; record `verification_mode: "inline-degraded"` |

After 3 FAIL attempts: failure handler with `failed_step: "Verify Full"` and the last verdict in `failure_reason`.

**Inline fallback (zero regression):** if the Task tool is not in your toolset, run this step inline exactly as before — execute each `verification.post` command yourself; if your changes caused a failure, fix, amend commit, re-verify (max 3 attempts) — and record `verification_mode: "inline"`. Spawn unavailability is never a task failure. The PASS gate applies in both modes: completion requires all checks green.

### Step 10: Report

Hand off your result through the journal and the RESULT BLOCK. You hold no Task tools — the orchestrator is the sole board writer and applies your completion `TaskUpdate` itself, after harvesting this evidence.

**Note:** A SubagentStop hook enforces that workers cannot stop after committing without handing off. If you attempt to exit after Step 8 but before this step, you will be prompted to emit the `CW-RESULT-BLOCK` sentinel (or confirm the on-disk `{task_id}.result.json` journal exists) before stopping.

**Determine your model identity** by checking the model name from your system context (e.g. `sonnet`, `opus`, `haiku`). Record this in `model_used` inside the journal.

Finalize the Step 8.5 journal with the verifier fields, then emit the `CW-RESULT-BLOCK` sentinel as the last substantive content of your final message, holding exactly the same fields as the on-disk `{task_id}.result.json`:

```
CW-RESULT-BLOCK-START
{
  "task_id": "T01",
  "status": "completed",
  "commit_sha": "<sha from git log>",
  "proof_dir": "docs/specs/[spec-dir]/[NN]-proofs",
  "proof_results": [
    { "type": "test", "status": "pass", "output_file": "T01-01-test.txt" },
    { "type": "cli",  "status": "pass", "output_file": "T01-02-cli.txt" }
  ],
  "proof_summary": "T01-proofs.md",
  "model_used": "sonnet",
  "verification_mode": "spawned",
  "verifier_verdict": "PASS",
  "verifier_tokens": 12345,
  "completed_at": "2026-01-24T15:30:00Z"
}
CW-RESULT-BLOCK-END
```

Format and contract: [result-journal-schema.md](references/result-journal-schema.md). Keep the sentinel block and the on-disk journal byte-identical — the orchestrator harvests the sentinel first (highest precedence) and falls back to the journal. The `proof_dir`/`proof_summary` fields let the orchestrator and cw-validate locate artifacts; `model_used` records which model executed the task for auditability.

Completion is gated: never report `status: "completed"` (in the journal or the sentinel) unless `verifier_verdict` is PASS.

### Step 11: Clean Exit

1. `git status --porcelain` — should be empty
2. Verify your files in HEAD: `git log -1 --name-only -- $FILES`
3. Output execution summary:

```
CW-EXECUTE COMPLETE
====================
Task: T01 - [subject]
Status: COMPLETED | FAILED | BLOCKED
Model: [model_used]

Proof Artifacts (on disk):
  [PASS] docs/specs/.../01-proofs/T01-01-test.txt
  [PASS] docs/specs/.../01-proofs/T01-02-cli.txt
  [SUMM] docs/specs/.../01-proofs/T01-proofs.md

Commit: abc1234 feat(scope): description
  - Implementation files: X

Verifier: PASS (spawned, haiku, tokens: N) | PASS (inline) | PASS (inline-degraded)

Handoff: RESULT BLOCK emitted + {task_id}.result.json written — awaiting orchestrator harvest
```

**Final Verification:**
```bash
ls docs/specs/[spec-dir]/[NN]-proofs/{task_id}-*
```

## Error Handling

### Retry Logic

Each step allows max 3 retries before failure:

1. Identify the error
2. Attempt fix
3. Re-run the failed step
4. After 3 failures: trigger failure handler

### Failure Handler

1. Stash partial work: `git stash push -m "cw-execute: {task_id} partial"`
2. Clean working tree: `git checkout -- .`
3. Report the failure in your final-message RESULT BLOCK so the orchestrator (sole board writer) can record it and keep the task dispatchable:
   ```
   CW-RESULT-BLOCK-START
   {
     "task_id": "<task_id>",
     "status": "failed",
     "last_failure": "2026-01-24T15:30:00Z",
     "failure_count": N,
     "failure_reason": "...",
     "failed_step": "Proof|Sanitize|Commit|etc",
     "proof_status": "none|partial|complete"
   }
   CW-RESULT-BLOCK-END
   ```
4. Exit with error summary including which step failed

### Proof Creation Failures

If proof artifacts cannot be created:

| Scenario | Action |
|----------|--------|
| Command fails | Create proof file with FAIL status, include error output |
| Environment missing | Create proof file with BLOCKED status, document what's needed |
| Manual verification declined | Create proof file with REJECTED status, include user feedback |
| Tool unavailable | Create proof file with SKIPPED status per `proof_capture.visual_method` |

**Never skip proof file creation entirely.** Even failures must be documented in a proof file so validation can detect gaps.

### Resuming Interrupted Tasks

The orchestrator re-dispatches a task whose prior worker left no evidence. When you start, check for partial work from that earlier attempt:

1. Check git status for partial work
2. If uncommitted changes: review and continue from Step 5
3. If stashed work: pop stash, review, continue from Step 5
4. If clean: start fresh from Step 4

## Security Notes

- Never execute commands that could leak credentials
- Replace real tokens with placeholders in proof artifacts
- Never push to remote during execution
- Proof files are committed - they must be safe for version control

## What Comes Next

After task completion:
- The orchestrator harvests your RESULT BLOCK + journal, applies the completion, and dispatches the next unblocked task
- `/cw-dispatch` can spawn parallel workers
- `/cw-validate` checks coverage after all tasks complete
