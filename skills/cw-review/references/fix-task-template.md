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

## Step 2.5: Toolchain Auto-Detection

Before creating any tasks, detect the project's test/lint/build commands by scanning for config files at the repo root. Run this detection **once per review session**, not per task.

| Config file | Test command | Lint command | Build command |
|---|---|---|---|
| `package.json` | `npm test` | `npm run lint` | `npm run build` |
| `Cargo.toml` | `cargo test` | `cargo clippy` | `cargo build` |
| `go.mod` | `go test ./...` | `golangci-lint run` | `go build ./...` |
| `pyproject.toml` | `pytest` | `ruff check .` | — |
| `Makefile` | `make test` | `make lint` | `make build` |
| `.csproj` / `.sln` | `dotnet test` | `dotnet format --verify-no-changes` | `dotnet build` |

Check `package.json` scripts for custom names (e.g., `"test:unit"`, `"lint:fix"`). If no config files found, use generic placeholders and note "toolchain not detected — update commands manually."

Store detected commands for reuse across all FIX tasks in this session.

## Step 3a: Detect patterns_to_follow

For each finding's file, identify 1-2 other files in the same directory that are NOT being fixed. These serve as style references for the implementing agent. Prefer files with similar names or purpose.

## Step 3b: Task Creation

```
TaskCreate({
  subject: "FIX-REVIEW: [concise description of the issue]",
  description: "## Issue\n\n[What is wrong]\n\n## Location\n\n- File: [path]\n- Line(s): [line numbers]\n- Function/Component: [name]\n\n## Evidence\n\n[finding.evidence]\n\n## Expected\n\n[What the code should do]\n\n## Actual\n\n[What the code currently does]\n\n## Suggested Fix\n\n[Concrete fix suggestion]\n\n## Category\n\n[A: Correctness | B: Security | C: Spec Compliance]",
  activeForm: "Fixing review issue"
})
```

## Step 3c: Task Metadata

Set metadata on the FIX task. All fields from the original schema are preserved. New fields are additive.

```
TaskUpdate({
  taskId: "<fix-task-id>",
  metadata: {
    task_type: "review-fix",
    task_id: "FIX-{finding.id}",
    category: "A|B|C",
    severity: "blocking",
    role: "implementer",
    complexity: "<critical/high severity → 'standard', medium/low → 'trivial'>",
    model: "<standard → 'sonnet', trivial → 'haiku'>",
    file_path: "<path>",
    line_numbers: "<line_start>-<line_end>",
    scope: {
      files_to_modify: ["<path>"],
      patterns_to_follow: ["<1-2 nearby files from Step 3a>"]
    },
    requirements: [{
      id: "R-{finding.id}.1",
      text: "Fix: <description of what to fix>",
      testable: true
    }],
    proof_artifacts: [
      { type: "test", command: "<detected test command from Step 2.5>", expected: "All pass" },
      { type: "file", path: "<finding.file>", contains: "<key pattern from suggested fix>" }
    ],
    verification: {
      pre: ["<detected lint command>", "<detected build command>"],
      post: ["<detected test command>"]
    },
    commit: { template: "fix({scope-from-file-path}): <description>" },
    review_context: {
      finding_id: "<finding.id>",
      dimension: "<finding.dimension>",
      confidence: "<finding.confidence>",
      blame_classification: "<finding.blame_classification>",
      validation_status: "<finding.validation_status>"
    }
  }
})
```

If a finding has `cross_file_refs`, include them in `scope.files_to_modify`.

### How cw-execute consumes this metadata

- `scope` → Phase 3 (CONTEXT): load patterns and identify files
- `requirements` → Phase 4 (IMPLEMENT): each requirement = one implementation unit
- `proof_artifacts` → Phase 6 (PROOF): test commands are pre-detected
- `verification` → Phases 2, 5, 9 (BASELINE, VERIFY-LOCAL, VERIFY-FULL)
- `commit.template` → Phase 8 (COMMIT): conventional commit format
- `complexity` + `model` → cw-dispatch routes to appropriate model tier
- `review_context` → traceability back to the review finding

### Backward Compatibility

All original fields (`task_type`, `category`, `severity`, `role`, `file_path`, `line_numbers`, `scope`, `requirements`, `proof_artifacts`, `verification`, `commit`) are preserved. New fields (`task_id`, `complexity`, `model`, `review_context`, enriched `requirements` format, `proof_artifacts` with file type) are additive. `get_pending_fix_count()` matches on subject prefix `^FIX` — unchanged. `cw-execute` reads `scope`, `requirements`, `proof_artifacts`, `verification`, `commit` — all unchanged.

## Concern Roster

Both orchestrators use the same concern agents. Model assignments depend on the selected model tier.

**Always-on (5):**

| Concern | Optimized | Frontier | Focus |
|---------|-----------|----------|-------|
| `bug-detector` | sonnet | opus | Correctness bugs + error handling defects |
| `security-reviewer` | **opus** | **opus** | OWASP top 10, injection, auth, crypto |
| `cross-file-impact` | sonnet | opus | Ripple effects beyond the diff |
| `test-analyzer` | sonnet | opus | Coverage gaps, test quality, integration points |
| `spec-and-conventions` | sonnet | opus | CLAUDE.md rules + spec compliance + comment accuracy |

**Conditional (only when new types detected):**

| Concern | Optimized | Frontier | Focus |
|---------|-----------|----------|-------|
| `type-design` | sonnet | opus | Encapsulation, invariant expression, enforcement |

Security always gets opus regardless of tier.

## Consolidation Rules

After collecting findings from all concern agents, execute the full validation pipeline from `validation-pipeline.md` (steps 4a through 4j). The pipeline replaces the previous simple filter/dedup/sort.
