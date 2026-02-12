# Reviewer Team Protocol (Concern-Partitioned)

This protocol is used by the reviewer agent when operating in concern-partitioned mode under `cw-review-team`. Each reviewer examines ALL changed files but through a specialized concern lens.

## Key Principle

Examine all changed files through your primary concern lens. Report findings — never fix code or create tasks. Communicate with the lead when complete.

## Concern Assignments

| Reviewer | Primary Concern | Category | Checklist Focus |
|----------|----------------|----------|-----------------|
| security-reviewer | Security | B | Injection (SQL, XSS, command), auth/authz gaps, credential leaks, path traversal, unsafe deserialization, insecure data handling |
| correctness-reviewer | Correctness | A | Logic errors, off-by-one, missing error handling, race conditions, incorrect transforms, null/undefined gaps |
| spec-reviewer | Spec Compliance | C + D | Missing requirements, behavior contradicting spec, missing demoable units, dead code, complexity, performance, pattern inconsistency |

Each reviewer may note **secondary findings** outside their primary concern when issues are obvious, but the primary concern is the focus.

## 3-Phase Protocol

### Phase 1: ORIENT

Load the review task and understand your concern assignment.

```
1. TaskGet({ taskId: "<task-id>" })
2. Extract from metadata:
   - concern: "security" | "correctness" | "spec-compliance"
   - primary_category: "B" | "A" | "C+D"
   - changed_files: Array of ALL changed non-test file paths
   - spec_path: Path to the feature spec (may be null)
   - standards_summary: Repository conventions and patterns
   - base_branch: Branch to diff against (e.g. "main")
3. Output orientation:
   "REVIEWING: [concern] concern"
   "Files: [count] changed files"
   "Primary category: [primary_category]"
   "Base: [base_branch]"
   "Spec: [spec_path or 'none']"
```

### Phase 2: EXAMINE

Read ALL changed non-test files and their diffs, evaluating through your primary concern lens.

```
For each file in changed_files:
  1. Read the full file:
     Read({ file_path: "<file>" })

  2. Get the diff for this file:
     Bash: git diff <base_branch>...HEAD -- <file>

  3. If spec_path is set (and this is spec-reviewer or the spec is relevant):
     Read({ file_path: "<spec_path>" })
     (Only read spec once, on first file)

  4. Evaluate primarily against your assigned concern checklist (below)
     Also note any obvious secondary findings from other categories

  5. Record any findings with is_primary flag
```

#### Security Concern Checklist (security-reviewer, Category B)

- SQL injection, XSS, command injection vectors
- Hardcoded credentials, API keys, secrets in code or config
- Missing authentication or authorization checks on endpoints
- Insecure data handling (logging PII, exposing internals in errors)
- Path traversal or file inclusion vulnerabilities
- Unsafe deserialization of untrusted input
- Missing input validation at system boundaries
- Insecure cryptographic practices (weak hashing, no salt)

#### Correctness Concern Checklist (correctness-reviewer, Category A)

- Logic errors, off-by-one, wrong boolean conditions
- Missing error handling at system boundaries (user input, external APIs)
- Race conditions or concurrency issues
- Incorrect data transformations or type coercions
- Missing null/undefined checks where data could be absent
- Resource leaks (unclosed handles, missing cleanup)
- Broken control flow (unreachable code after early return, missing break)
- Edge cases in arithmetic (overflow, division by zero)

#### Spec Compliance Concern Checklist (spec-reviewer, Categories C + D)

**Category C (Blocking):**
- Requirements from the spec that were missed or incorrectly implemented
- Behavior that contradicts spec intent
- Missing functionality described in demoable units

**Category D (Advisory):**
- Dead code or unreachable branches
- Overly complex logic that could be simplified
- Missing edge case handling
- Performance concerns (N+1 queries, unnecessary loops)
- Inconsistency with repository patterns

### Phase 3: REPORT

Write all findings to task metadata, message the lead, and mark completed.

**Findings structure** — each finding is an object:

```json
{
  "category": "A|B|C|D",
  "severity": "blocking|advisory",
  "is_primary": true,
  "title": "Short description of the issue",
  "file": "path/to/file.ts",
  "lines": "42-48",
  "description": "Detailed explanation of what is wrong and why",
  "suggested_fix": "Concrete suggestion for how to fix it"
}
```

Fields:
- `is_primary`: `true` if the finding falls within your assigned concern, `false` for secondary findings
- Severity rules: Categories A, B, C are always `"blocking"`. Category D is always `"advisory"`.

**Update the task with findings:**

```
TaskUpdate({
  taskId: "<task-id>",
  status: "completed",
  metadata: {
    review_status: "completed",
    findings: [ ... ],
    files_reviewed: ["path/to/file1.ts", "path/to/file2.ts"],
    completed_at: "<ISO timestamp>"
  }
})
```

**Message the lead:**

```
SendMessage({
  type: "message",
  recipient: "lead",
  content: "Review complete for [concern] concern. Found [N] findings ([M] blocking, [K] advisory). Results in task metadata.",
  summary: "[concern] review done, [N] findings"
})
```

## Challenge Round Protocol

When the lead broadcasts a findings digest for the challenge round, respond with one of:

**AGREE** — Finding is valid:
```
SendMessage({
  type: "message",
  recipient: "lead",
  content: "AGREE with [finding title]. [Optional corroborating evidence from my review.]",
  summary: "Agree with [finding]"
})
```

**CHALLENGE** — Finding is incorrect or overstated:
```
SendMessage({
  type: "message",
  recipient: "lead",
  content: "CHALLENGE [finding title]. Reason: [why the finding is incorrect or overstated]. Evidence: [specific code reference].",
  summary: "Challenge [finding]"
})
```

**ADD** — Related finding discovered during challenge review:
```
SendMessage({
  type: "message",
  recipient: "lead",
  content: "ADD related to [finding title]. Found: [new finding description]. File: [path], Lines: [range].",
  summary: "Add related finding"
})
```

After responding to all findings in the digest, message the lead:
```
SendMessage({
  type: "message",
  recipient: "lead",
  content: "Challenge round complete. [N] AGREE, [M] CHALLENGE, [K] ADD.",
  summary: "Challenge round done"
})
```

## Constraints

- Never modify implementation code
- Never create FIX tasks or any new tasks
- Examine ALL files in changed_files — do not skip any
- Always update task status before exiting
- Always include file paths and line numbers in findings
- Read each file in full — do not rely solely on the diff
- Always set `is_primary` correctly on each finding
- Always message the lead via SendMessage when review is complete
