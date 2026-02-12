# Reviewer Protocol

This protocol is used by the reviewer agent when examining assigned files for a code review batch.

## Key Principle

Examine only your assigned files. Report findings — never fix code or create tasks.

## 3-Phase Protocol

### Phase 1: ORIENT

Load the review task and understand what to examine.

```
1. TaskGet({ taskId: "<task-id>" })
2. Extract from metadata:
   - assigned_files: Array of file paths to review
   - spec_path: Path to the feature spec (may be null)
   - standards_summary: Repository conventions and patterns
   - base_branch: Branch to diff against (e.g. "main")
3. Output orientation:
   "REVIEWING BATCH: [task subject]"
   "Files: [count] files assigned"
   "Base: [base_branch]"
   "Spec: [spec_path or 'none']"
```

### Phase 2: EXAMINE

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

  4. Evaluate against all four categories (see below)

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

### Phase 3: REPORT

Write all findings to task metadata and mark completed.

**Findings structure** — each finding is an object:

```json
{
  "category": "A|B|C|D",
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
- Category D is always `"advisory"`

**Update the task with findings:**

```
TaskUpdate({
  taskId: "<task-id>",
  status: "completed",
  metadata: {
    review_status: "completed",
    findings: [
      { "category": "A", "severity": "blocking", "title": "...", "file": "...", "lines": "...", "description": "...", "suggested_fix": "..." },
      { "category": "D", "severity": "advisory", "title": "...", "file": "...", "lines": "...", "description": "...", "suggested_fix": "..." }
    ],
    files_reviewed: ["path/to/file1.ts", "path/to/file2.ts"],
    completed_at: "<ISO timestamp>"
  }
})
```

If no issues are found, report an empty findings array:

```
TaskUpdate({
  taskId: "<task-id>",
  status: "completed",
  metadata: {
    review_status: "completed",
    findings: [],
    files_reviewed: ["path/to/file1.ts", "path/to/file2.ts"],
    completed_at: "<ISO timestamp>"
  }
})
```

Output result and exit:

```
"REVIEW BATCH COMPLETE: [task subject]"
"Files reviewed: [count]"
"Findings: [count] ([blocking count] blocking, [advisory count] advisory)"
```

## Constraints

- Never modify implementation code
- Never create FIX tasks or any new tasks
- Only examine files listed in assigned_files metadata
- Always update task status before exiting
- Always include file paths and line numbers in findings
- Read each file in full — do not rely solely on the diff
