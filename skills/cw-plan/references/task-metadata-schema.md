# Task Metadata Schema Reference

This document defines the metadata structure for tasks created by `cw-plan`. Each task in the native task board carries self-contained metadata enabling autonomous execution by any worker.

## Full Schema

```json
{
  // Identity
  "task_id": "T01",                      // Sequential ID (T01, T02, T03...)
  "spec_path": "docs/specs/01-spec-auth/01-spec-auth.md",  // Path to source spec
  "parent_task": null,                   // null = top-level demoable unit; "T01" = sub-task of T01

  // Worker Instructions
  "scope": {
    "files_to_create": ["src/auth/login.ts", "src/auth/login.test.ts"],
    "files_to_modify": ["src/routes/index.ts"],
    "patterns_to_follow": ["src/routes/health.ts"]  // Reference files for style/structure
  },

  "requirements": [
    {
      "id": "R01.1",                     // Unique requirement ID
      "text": "POST /auth/login accepts {email, password}",
      "testable": true                   // Must be verifiable
    }
  ],

  "proof_artifacts": [
    {
      "type": "test",                    // test | cli | url | file | browser
      "command": "npm test -- src/auth/login.test.ts",
      "expected": "All pass"
    },
    {
      "type": "cli",
      "command": "curl -X POST localhost:3000/auth/login -d '{\"email\":\"test@example.com\",\"password\":\"test\"}'",
      "expected": "200 + JWT token in response"
    }
  ],

  "commit": {
    "template": "feat(auth): add login endpoint"  // Commit message template
  },

  "verification": {
    "pre": ["npm run lint", "npm run build"],     // Must pass before commit
    "post": ["npm test"]                          // Must pass after commit
  },

  // PR Configuration
  "pr_config": {
    "pr_group": "pr-01-auth-backend"     // Tasks with same group = intended for same PR
  },

  // Worker Assignment
  "role": "implementer",                 // implementer | validator | spec-writer
  "complexity": "standard",             // trivial | standard | complex

  // Results (filled by worker after execution)
  "proof_results": null,                 // Filled with pass/fail per artifact
  "commit_stats": null,                  // Filled with files_changed, insertions, deletions
  "completed_at": null                   // ISO timestamp when completed
}
```

## Field Definitions

### Identity Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `task_id` | string | Yes | Format `T##` (T01, T02...). Sub-tasks use `T01.1`, `T01.2` |
| `spec_path` | string | Yes | Relative path to the specification file |
| `parent_task` | string\|null | Yes | null for top-level tasks, parent task_id for sub-tasks |

### Scope Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `scope.files_to_create` | string[] | Yes | New files this task will create |
| `scope.files_to_modify` | string[] | Yes | Existing files this task will modify |
| `scope.patterns_to_follow` | string[] | No | Reference files demonstrating conventions |

### Requirements

Each requirement must be:
- **Unique**: ID format `R{task_number}.{seq}` (e.g., R01.1, R01.2)
- **Testable**: Can be verified through proof artifacts
- **Atomic**: One requirement per entry

### Proof Artifact Types

| Type | Fields | Purpose |
|------|--------|---------|
| `test` | `command`, `expected` | Run test suite/file |
| `cli` | `command`, `expected` | Execute CLI command |
| `url` | `url`, `method`, `expected` | HTTP request verification |
| `file` | `path`, `contains` | File existence/content check |
| `browser` | `prompt`, `expected` | Browser-based verification |

### PR Configuration

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `pr_config.pr_group` | string | No | Identifier for PR grouping. Tasks with the same `pr_group` are intended for the same PR. Format: `pr-NN-short-name` (e.g., `pr-01-auth-backend`) |

**Functional integrity rule**: PR groups must align with demoable unit boundaries. A demoable unit should never be split across multiple PRs.

Valid groupings:
- 1 demoable unit = 1 PR (smallest functional unit)
- N demoable units = 1 PR (larger but still functional)

Invalid grouping:
- 1 demoable unit split across 2+ PRs (breaks functionality)

## Dependency Representation

Dependencies use the native task system's `addBlockedBy` mechanism:

```
T01 (no deps)          <- can start immediately
T02 (blocked by T01)   <- waits for T01 completion
T03 (blocked by T02)   <- waits for T02 completion
T04 (blocked by T01)   <- can run in parallel with T02/T03
```

Sub-tasks block their parent:
```
T01.1 (no deps)        <- sub-task, blocks T01
T01.2 (blocked by T01.1) <- sub-task, blocks T01
T01 completion         <- blocked by T01.1 AND T01.2
```

## Result Schema (After Execution)

When a worker completes a task, it fills:

```json
{
  "proof_results": [
    { "type": "test", "status": "pass", "output_file": "T01-01-test.txt" },
    { "type": "cli", "status": "pass", "output_file": "T01-02-cli.txt" }
  ],
  "commit_stats": {
    "files_changed": 5,
    "insertions": 150,
    "deletions": 30
  },
  "completed_at": "2026-01-24T15:30:00Z"
}
```
