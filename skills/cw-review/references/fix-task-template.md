# FIX Task Creation Template

Shared template for creating FIX-REVIEW tasks from review findings. Used by both `cw-review` and `cw-review-team` orchestrators.

## When to Create FIX Tasks

Create a FIX task for each **blocking** finding meeting ALL conditions:
- Category A (Correctness), B (Security), or C (Spec Compliance)
- Severity `critical` or `high`
- Confidence >= dimension threshold (security: 70, all others: 80)
- `validation_status != "failed"` (if factual grounding was performed)

**Do NOT create FIX tasks for:**
- Category D (Quality/advisory) findings
- Code style preferences already handled by linters
- Minor naming disagreements
- "I would have done it differently" observations
- Test code (tests are the oracle)
- Documentation gaps (unless spec requires it)

## Task Creation

```
TaskCreate({
  subject: "FIX-REVIEW: [concise description of the issue]",
  description: "## Issue\n\n[What is wrong]\n\n## Location\n\n- File: [path]\n- Line(s): [line numbers]\n- Function/Component: [name]\n\n## Expected\n\n[What the code should do]\n\n## Actual\n\n[What the code currently does]\n\n## Suggested Fix\n\n[Concrete fix suggestion]\n\n## Category\n\n[A: Correctness | B: Security | C: Spec Compliance]",
  activeForm: "Fixing review issue"
})
```

## Task Metadata

Set metadata on the FIX task with fields required by cw-execute:

```
TaskUpdate({
  taskId: "<fix-task-id>",
  metadata: {
    task_type: "review-fix",
    category: "A|B|C",
    severity: "blocking",
    role: "implementer",
    file_path: "<path>",
    line_numbers: "<line_start>-<line_end>",
    scope: {
      files_to_modify: ["<path>"],
      patterns_to_follow: []
    },
    requirements: ["Fix: <description of what to fix>"],
    proof_artifacts: [{ type: "test", command: "npm test", expected: "pass" }],
    verification: { pre: "git diff", post: "npm test" },
    commit: { template: "fix: <description>" }
  }
})
```

If a finding has `cross_file_refs`, include them in `scope.files_to_modify`.

## Concern Roster

Both orchestrators use the same concern agents:

**Always-on (5):**

| Concern | Model | Focus |
|---------|-------|-------|
| `bug-detector` | opus | Correctness bugs + error handling defects |
| `security-reviewer` | opus | OWASP top 10, injection, auth, crypto |
| `cross-file-impact` | opus | Ripple effects beyond the diff |
| `test-analyzer` | sonnet | Coverage gaps, test quality, integration points |
| `spec-and-conventions` | sonnet | CLAUDE.md rules + spec compliance + comment accuracy |

**Conditional (only when new types detected):**

| Concern | Model | Focus |
|---------|-------|-------|
| `type-design` | sonnet | Encapsulation, invariant expression, enforcement |

## Consolidation Rules

After collecting findings from all concern agents:

1. **Filter by confidence**: Remove findings below dimension threshold (security: 70, all others: 80)
2. **Deduplicate**: Remove findings with the same `file` + overlapping `line_start`-`line_end` + same `dimension`. When merging: keep highest confidence, most specific description, combine evidence, use higher severity
3. **Sort**: Order by category — B (Security) first, then A (Correctness), C (Conventions), D (Quality)
