# Task Metadata Schema Reference

This document defines the metadata structure for tasks created by `cw-plan`. Each task in the native task board carries self-contained metadata enabling autonomous execution by any worker.

## Full Schema

```json
{
  // Identity
  "task_id": "T01",                      // Sequential ID (T01, T02, T03...)
  "demoable_unit": 1,                    // Which demoable unit from the spec (integer)
  "demoable_unit_title": "User Registration",  // Human-readable unit title
  "spec_path": "docs/specs/01-spec-auth/01-spec-auth.md",  // Path to source spec
  "parent_task": null,                   // null = top-level demoable unit; "T01" = sub-task of T01

  // Worker Instructions
  "scope": {
    "files_to_create": ["src/auth/login.ts", "src/auth/login.test.ts"],
    "files_to_modify": ["src/routes/index.ts"],
    "patterns_to_follow": ["src/routes/health.ts"],  // Reference files for style/structure
    "affected_areas": ["src/auth/", "src/routes/index.ts"]  // Optional — directional hints from spec
  },

  "requirements": [
    {
      "id": "R1.1",                      // Spec R-ID format: R{unit}.{seq}
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
    "pre": ["npm run lint", "npm run build"],     // Must pass before commit (empty [] for greenfield pre-bootstrap tasks)
    "post": ["npm test"],                         // Must pass after commit (empty [] for greenfield pre-bootstrap tasks)
    "greenfield_note": null                       // Optional: e.g. "Unit 1 establishes toolchain — earlier tasks use empty arrays"
  },

  // Worker Assignment
  "role": "implementer",                 // implementer | validator | spec-writer
  "complexity": "standard",             // trivial | standard | complex
  "model": "sonnet",                    // Model: "haiku" (trivial) | "sonnet" (standard) | "opus" (complex) | "fable" (fallback)

  // Results (filled by worker after execution)
  "proof_results": null,                 // Filled with pass/fail per artifact
  "completed_at": null                   // ISO timestamp when completed
}
```

## Field Definitions

### Identity Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `task_id` | string | Yes | Format `T##` (T01, T02...). Sub-tasks use `T01.1`, `T01.2` |
| `demoable_unit` | integer | Yes | Which demoable unit from the spec this task belongs to (1-indexed). Sub-tasks inherit the parent's value. |
| `demoable_unit_title` | string | Yes | Human-readable title of the demoable unit from the spec |
| `spec_path` | string | Yes | Relative path to the specification file |
| `parent_task` | string\|null | Yes | null for top-level tasks, parent task_id for sub-tasks |

### Scope Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `scope.files_to_create` | string[] | Yes | New files this task will create |
| `scope.files_to_modify` | string[] | Yes | Existing files this task will modify |
| `scope.patterns_to_follow` | string[] | No | Reference files demonstrating conventions |
| `scope.affected_areas` | string[] | Yes | Directories and key files the unit touches, from the spec's Affected areas field. Greenfield paths marked `(new)`. |

### Requirements

Each requirement must be:
- **Unique**: Format `R{unit}.{seq}` (e.g., R1.1, R1.2, R2.1) — carried from the spec's requirement IDs
- **Testable**: Can be verified through proof artifacts
- **Atomic**: One requirement per entry

### Worker Assignment Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `role` | string | Yes | Worker role: `implementer`, `validator`, `spec-writer` |
| `complexity` | string | Yes | Task complexity: `trivial`, `standard`, `complex` |
| `model` | string | Yes | Intended model: `"haiku"` (trivial), `"sonnet"` (standard), `"opus"` (complex), `"fable"` (fallback). After execution, the worker records the actual model in `model_used` (see Result Schema). If a substitution occurred, also fill `model_requested` and `fallback_reason` (see Result Schema). |

### Proof Artifact Types

| Type | Fields | Purpose |
|------|--------|---------|
| `test` | `command`, `expected` | Run test suite/file |
| `cli` | `command`, `expected` | Execute CLI command |
| `url` | `url`, `method`, `expected` | HTTP request verification |
| `file` | `path`, `contains` | File existence/content check |
| `browser` | `prompt`, `expected` | Browser-based verification |

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
  "completed_at": "2026-01-24T15:30:00Z",
  "model_used": "sonnet",                  // Actual model that executed this task
  "model_requested": "opus",               // Optional: original tier if substitution occurred
  "fallback_reason": "spawn-failed"        // Optional: category if substitution occurred (e.g. spawn-failed, model-unavailable)
}
```

### Result Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `proof_results` | array | Yes | Pass/fail per proof artifact with output file references |
| `completed_at` | string | Yes | ISO 8601 timestamp when task was completed |
| `model_used` | string | Yes | The model that actually executed the task (e.g. `sonnet`, `opus`, `haiku`, `fable`). Filled by the worker at completion. |
| `model_requested` | string | No | Original intended model tier if a substitution occurred (e.g. `opus`, `sonnet`). Omitted if no substitution. |
| `fallback_reason` | string | No | Short category describing why substitution occurred (e.g. `spawn-failed`, `model-unavailable`). Omitted if no substitution. |
