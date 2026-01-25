---
name: cw-execute
description: "Execute a single task from the native task board using the 11-phase protocol: orient, baseline, context, implement, verify-local, proof, sanitize, commit, verify-full, report, clean exit."
user-invocable: true
allowed-tools: Glob, Grep, Read, Edit, Write, Bash, TaskCreate, TaskUpdate, TaskList, TaskGet, AskUserQuestion
---

# CW-Execute: Single Task Execution

## Context Marker

Always begin your response with: **CW-EXECUTE**

## MANDATORY FIRST ACTION

**STOP. Before reading ANY files or exploring the project, you MUST call TaskList() immediately.**

```
TaskList()
```

Your task is in Claude Code's native task system, NOT in any JSON files in the project. Do NOT use Glob, Grep, or Read to find tasks. ONLY use TaskList() and TaskGet().

If TaskList() returns "No tasks found", report that and exit. Do NOT search the project for task files.

## Overview

You are the **Implementer** role in the Claude Workflow system. You execute exactly ONE task from the native task board, following an 11-phase protocol that ensures consistent, verifiable, autonomous execution. Each invocation leaves the codebase in a clean, committable state.

## Your Role

You are an **autonomous coding agent**. Your entire context comes from:
1. The native task board via `TaskList()`/`TaskGet()` - **this is the ONLY task source**
2. The task's metadata (scope, requirements, proof artifacts)
3. Git history
4. The codebase itself

**CRITICAL: Use ONLY TaskList()/TaskGet() for task state. Do NOT read any `*-tasks-*.json`, `cw-manifest.json`, or `ralph-progress.json` files from the project. These are deprecated.**

You have no memory of previous executions.

## Critical Constraints

- **Execute exactly ONE task** per invocation
- **Never skip verification steps** - they prevent regressions
- **Always commit on success** - partial work is lost between sessions
- **Update task status** via TaskUpdate - next worker depends on it
- **Leave codebase clean** - no uncommitted changes after completion
- **Proof artifacts are BLOCKING** - cannot proceed to commit without proof files
- **Security sanitization is BLOCKING** - cannot commit unsanitized proofs
- **IGNORE** any `cw-manifest.json` or `ralph-progress.json` files - these are deprecated. Use only `TaskList()`/`TaskGet()` for task state.

## Proof File Requirements (MANDATORY)

Every task execution MUST produce proof artifacts in the repository:

```
docs/specs/[spec-dir]/[NN]-proofs/
├── {task_id}-01-{type}.txt    # First proof artifact
├── {task_id}-02-{type}.txt    # Second proof artifact
├── {task_id}-proofs.md        # Summary file (REQUIRED)
└── ...
```

**The commit in Phase 8 MUST include proof files.** A commit without proof artifacts is incomplete and will fail validation.

## The 11-Phase Protocol

### Phase 1: ORIENT

Understand current state without making changes.

1. Run `TaskList` to see all tasks
2. Identify your task:
   - If assigned (owner matches): use that task
   - Otherwise: find first unblocked pending task
3. Run `TaskGet(taskId)` to load full metadata
4. Verify git status is clean: `git status --porcelain`
5. Read recent history: `git log --oneline -10`

**Mark task as in_progress:**
```
TaskUpdate({ taskId: "<id>", status: "in_progress" })
```

### Phase 2: BASELINE

Confirm codebase health before touching anything.

1. Run each command in `metadata.verification.post`
2. If failures:
   - Pre-existing issue: note and proceed with caution
   - Environment issue: attempt fix (install deps, etc.)
   - Unfixable: update task description with blocker, exit

### Phase 3: CONTEXT

Load patterns and understand conventions.

1. Read each file in `metadata.scope.patterns_to_follow`
2. Extract: structure, naming, error handling, test patterns
3. Read files in `metadata.scope.files_to_modify`
4. Verify parent directories exist for `metadata.scope.files_to_create`

### Phase 4: IMPLEMENT

Create/modify files to satisfy requirements.

For each requirement in `metadata.requirements`:
1. Implement the requirement following extracted patterns
2. Write corresponding tests alongside implementation
3. Run linter incrementally if available

Rules:
- Follow patterns exactly - don't introduce new conventions
- Keep changes minimal - only what requirements demand
- If unclear, implement most reasonable interpretation and note it
- Max 3 retry attempts for failing tests

### Phase 5: VERIFY-LOCAL

Run pre-commit checks.

1. Execute each command in `metadata.verification.pre`
2. Fix any lint or build issues
3. Max 3 retry attempts per command

### Phase 6: PROOF

Execute proof artifacts and capture evidence.

1. Determine proof directory from spec_path: `./docs/specs/[spec-dir]/[NN]-proofs/`
2. Create the proof directory if it doesn't exist
3. Read `metadata.proof_capture` for the capture method decided during planning
4. For each proof artifact in `metadata.proof_artifacts`:

**Automated proofs** (test, cli, file, url):
   a. Execute the command/check per artifact type
   b. Capture output to `{task_id}-{index+1:02d}-{type}.txt`
   c. Include header: type, command, expected, timestamp
   d. Compare result against expected
   e. Record PASS or FAIL

**Visual proofs** (screenshot, browser, visual):

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

**Phase 6 Gate Check (BLOCKING):**

Before proceeding to Phase 7, verify:

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

**BLOCK**: Do not proceed to Phase 7 until all proof files exist.

If proof artifacts cannot be executed (e.g., environment issues):
1. Create proof file with status `BLOCKED` and reason
2. Document workaround or manual steps needed
3. Still create the summary file

See `references/proof-artifact-types.md` for type-specific instructions.

### Phase 7: SANITIZE (BLOCKING)

Remove sensitive data from proof files. **Cannot proceed until clean.**

1. Scan all `{task_id}-*` files for:
   - API keys (`sk-`, `pk_`, `api_key`, `apiKey`)
   - Tokens (Bearer, JWT, session, access_token)
   - Passwords (password, secret, credential fields)
   - Connection strings (with embedded credentials)
   - Private keys (PEM blocks, SSH keys)
2. Replace found values with `[REDACTED]`
3. Re-scan to confirm clean
4. **BLOCK**: Do not proceed to Phase 8 until scan is clean

### Phase 8: COMMIT

Create atomic commit with implementation AND proof artifacts.

**Pre-Commit Checklist (all must pass):**

```bash
# 1. Verify proof files exist (BLOCKING)
test -d "docs/specs/[spec-dir]/[NN]-proofs" || { echo "ERROR: Proof directory missing"; exit 1; }
test -f "docs/specs/[spec-dir]/[NN]-proofs/{task_id}-proofs.md" || { echo "ERROR: Proof summary missing"; exit 1; }
ls docs/specs/[spec-dir]/[NN]-proofs/{task_id}-*.txt >/dev/null 2>&1 || { echo "ERROR: No proof artifacts"; exit 1; }

# 2. Verify sanitization complete
grep -r "sk-\|pk_\|api_key\|Bearer \|password=" docs/specs/[spec-dir]/[NN]-proofs/{task_id}-* && { echo "ERROR: Unsanitized secrets"; exit 1; }
```

**If pre-commit checks fail:** Return to the blocking phase (Phase 6 or 7) and complete it.

**Commit Steps:**

1. Stage implementation files:
   - All files from `metadata.scope.files_to_create`
   - All files from `metadata.scope.files_to_modify`
2. Stage proof files: `git add docs/specs/[spec-dir]/[NN]-proofs/{task_id}-*`
3. Verify staged files include both implementation AND proofs:
   ```bash
   git diff --cached --name-only | grep -E "(src/|lib/|proof)"
   ```
4. Create commit using `metadata.commit.template`
5. Verify commit includes proof files: `git show --name-only HEAD | grep proofs`

### Phase 9: VERIFY-FULL

Post-commit verification.

1. Run each command in `metadata.verification.post`
2. If your changes caused failure:
   - Fix the issue
   - Amend commit
   - Re-verify (max 3 attempts)

### Phase 10: REPORT

Update task board with proof artifact locations.

```
TaskUpdate({
  taskId: "<native-id>",
  status: "completed",
  metadata: {
    proof_dir: "docs/specs/[spec-dir]/[NN]-proofs",
    proof_results: [
      { type: "test", status: "pass", output_file: "T01-01-test.txt" },
      { type: "cli", status: "pass", output_file: "T01-02-cli.txt" }
    ],
    proof_summary: "T01-proofs.md",
    commit_sha: "<sha from git log>",
    completed_at: "2026-01-24T15:30:00Z"
  }
})
```

The `proof_dir` and `proof_summary` fields allow cw-validate to locate artifacts.

### Phase 11: CLEAN EXIT

Leave pristine state with verified proof trail.

1. `git status --porcelain` - should be empty
2. Verify proof files are in commit: `git show --name-only HEAD | grep proofs`
3. Run `metadata.verification.post` one final time
4. Output execution summary:

```
CW-EXECUTE COMPLETE
====================
Task: T01 - [subject]
Status: COMPLETED

Proof Artifacts (committed):
  [PASS] docs/specs/.../01-proofs/T01-01-test.txt
  [PASS] docs/specs/.../01-proofs/T01-02-cli.txt
  [SUMM] docs/specs/.../01-proofs/T01-proofs.md

Commit: abc1234 feat(scope): description
  - Implementation files: X
  - Proof files: Y

Progress: X/Y tasks complete
```

**Final Verification:**
```bash
# Confirm proof files exist in repository
git ls-files docs/specs/*/[NN]-proofs/{task_id}-*
```

## Error Handling

### Retry Logic

Each phase allows max 3 retries before failure:

1. Identify the error
2. Attempt fix
3. Re-run the failed step
4. After 3 failures: trigger failure handler

### Failure Handler

1. Stash partial work: `git stash push -m "cw-execute: {task_id} partial"`
2. Clean working tree: `git checkout -- .`
3. Update task (keep as pending, add failure info):
   ```
   TaskUpdate({
     taskId: "<id>",
     status: "pending",
     metadata: {
       last_failure: "2026-01-24T15:30:00Z",
       failure_count: N,
       failure_reason: "...",
       failed_phase: "PROOF|SANITIZE|COMMIT|etc",
       proof_status: "none|partial|complete"
     }
   })
   ```
4. Exit with error summary including which phase failed

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

If a task has `status: "in_progress"` when you start:

1. Check git status for partial work
2. If uncommitted changes: review and continue from Phase 5
3. If stashed work: pop stash, review, continue from Phase 5
4. If clean: start fresh from Phase 4

## Security Notes

- Never execute commands that could leak credentials
- Replace real tokens with placeholders in proof artifacts
- Never push to remote during execution
- Proof files are committed - they must be safe for version control

## What Comes Next

After task completion:
- Next worker picks up the next unblocked task
- `/cw-dispatch` can spawn parallel workers
- `/cw-validate` checks coverage after all tasks complete
- `cw-loop` shell script automates sequential execution
