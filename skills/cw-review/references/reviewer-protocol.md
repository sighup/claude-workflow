# Reviewer Protocol

This protocol is used by the reviewer agent when examining assigned files for a code review batch.

## Key Principle

Examine only your assigned files. Report findings — never fix code or create tasks.

## 3-Step Protocol

### Step 1: Orient

Read the review assignment from the spawn prompt and understand what to examine. You hold no Task tools — the orchestrator delivers the assignment inline.

```
1. Read the assignment from the spawn prompt:
   - task_id / batch: stable id of this review batch
   - assigned_files: Array of file paths to review
   - spec_path: Path to the feature spec (may be null)
   - standards_summary: Repository conventions and patterns
   - base_branch: Branch to diff against (e.g. "main")
2. Output orientation:
   "REVIEWING BATCH: [batch subject]"
   "Files: [count] files assigned"
   "Base: [base_branch]"
   "Spec: [spec_path or 'none']"
```

### Step 2: Examine

For each file in `assigned_files`, read the full file and its diff, then evaluate.

```
For each file in assigned_files:
  1. Read the full file:
     Read({ file_path: "<file>" })

  2. Get the diff for this file:
     Bash: git diff <base_branch>...HEAD -- <file>

  3. If spec_path is set, reference the spec for compliance checks:
     Read({ file_path: "<spec_path>" })
     (Only read spec once, on first file)

  4. Evaluate against all five categories (see below).
     When LSP is available (check by probing `documentSymbol` on the first file — if it returns symbols, `lsp_available = true`):
     - `findReferences` to trace call sites of changed functions and detect ripple effects
     - `goToImplementation` to verify interface contracts are maintained after changes
     - `incomingCalls` to map consumers of modified functions

  5. Record any findings
```

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

#### Category E: Reuse (Advisory)

- New utility functions that duplicate existing ones in the codebase
- Re-implemented patterns that an existing module already provides
- Copy-pasted logic that should be extracted to a shared module
- New constants or configuration values that already exist elsewhere

**Reuse check** for each new function in the diff:
1. `Grep` for its name and common synonyms across the codebase
2. `Glob` for `**/utils/**` and `**/helpers/**` to check for existing utilities
3. Check `package.json` dependencies for libraries that already provide the pattern
4. Flag duplicates as advisory — the implementer may have had a good reason to create a new version

### Step 3: Report

Write all findings to task metadata and mark completed.

**Findings structure** — each finding is an object:

```json
{
  "category": "A|B|C|D|E",
  "severity": "blocking|advisory",
  "title": "Short description of the issue",
  "file": "path/to/file.ts",
  "lines": "42-48",
  "description": "Detailed explanation of what is wrong and why",
  "suggested_fix": "Concrete suggestion for how to fix it"
}
```

Severity rules:
- Categories A, B, C are always `"blocking"`
- Categories D and E are always `"advisory"`

**Report findings via the RESULT BLOCK** (and an uncommitted `{batch}.findings.json` journal written to `docs/specs/<run>/results/` with the same content). You hold no Task tools; the orchestrator harvests this block and records the findings on the board itself.

```
CW-RESULT-BLOCK-START
{
  "task_id": "<batch>",
  "status": "completed",
  "review_status": "completed",
  "findings": [
    { "category": "A", "severity": "blocking", "title": "...", "file": "...", "lines": "...", "description": "...", "suggested_fix": "..." },
    { "category": "D", "severity": "advisory", "title": "...", "file": "...", "lines": "...", "description": "...", "suggested_fix": "..." }
  ],
  "files_reviewed": ["path/to/file1.ts", "path/to/file2.ts"],
  "completed_at": "<ISO timestamp>"
}
CW-RESULT-BLOCK-END
```

If no issues are found, report an empty `findings` array in the same block.

Output result and exit:

```
"REVIEW BATCH COMPLETE: [task subject]"
"Files reviewed: [count]"
"Findings: [count] ([blocking count] blocking, [advisory count] advisory)"
```

**Segment append note**: you hold no Task tools and never create FIX tasks. The review orchestrator (SKILL.md Step 3) harvests your RESULT BLOCK, creates each FIX task, and appends one line to `~/.claude/tasks/.manifest/<list-id>/manifest.fix.jsonl` per FIX task so the dispatch exit gate's completion predicate includes those tasks. You have no action here — this note documents the handoff so the orchestrator's append responsibility is visible at both ends of the protocol.

## Constraints

- Never modify implementation code
- Never create FIX tasks or any new tasks
- Only examine files in your spawn-prompt assignment
- Always emit the RESULT BLOCK before exiting
- Never spawn subagents — sub-reviewers are leaf children ([nesting-guardrails.md](../../cw-dispatch/references/nesting-guardrails.md))
- Always include file paths and line numbers in findings
- Read each file in full — do not rely solely on the diff
