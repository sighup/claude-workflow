# Heartbeat Protocol Reference

## Issue Lifecycle

```
Linear Issue                     claude-workflow Pipeline
────────────                     ───────────────────────

 Assigned to agent                /cw-heartbeat picks it up
 (Todo status)                    ↓
       │                    ┌─────────────┐
       │                    │  Lock issue  │  Apply agent-working label
       │                    └──────┬──────┘
       │                           │
       │                    ┌──────▼──────┐
       │                    │  cw-spec     │  Generate spec from issue
       │                    └──────┬──────┘
       │                           │
       │                    ┌──────▼──────┐
       │                    │  cw-plan     │  Decompose into task graph
       │                    └──────┬──────┘
       │                           │
       │                    ┌──────▼──────┐
       │                    │ cw-dispatch  │  Parallel execution
       │                    └──────┬──────┘
       │                           │
       │                    ┌──────▼──────┐
       │                    │ cw-validate  │  6-gate verification
       │                    └──────┬──────┘
       │                           │
       ▼                    ┌──────▼──────┐
 Issue updated              │   Report    │  Post comment + update state
 (Done / Blocked)           └─────────────┘
```

## Label State Machine

| Current State | Event | New State |
|---|---|---|
| (none) | Heartbeat picks up issue | `agent-working` |
| `agent-working` | Pipeline completes | label removed, issue → Done |
| `agent-working` | Pipeline fails / validation blocked | `agent-blocked` |
| `agent-blocked` | Human adds comment | eligible for retry |
| `agent-blocked` | Next heartbeat sees new comment | `agent-working` (retry) |

## Linear Comment Format

Every heartbeat posts a structured comment to the issue:

```markdown
**Heartbeat #{N}** — {timestamp}

**Duration:** {Xm Ys}
**Result:** {completed | blocked | error}

### Work Done
- {Summary of pipeline stages completed}
- Spec: `{spec_path}`
- Tasks: {completed}/{total}
- Commits: {commit_sha_list}

### Proof Artifacts
- {proof_file_1}
- {proof_file_2}

### Next Steps
- {What happens next, or what's blocking}
```

## Lockfile Format

`.claude-workflow/heartbeat.lock`:
```json
{
  "pid": 12345,
  "started_at": "2026-04-04T10:30:00Z",
  "issue_id": "ENG-123"
}
```

## Heartbeat Log Format

`.claude-workflow/heartbeat-log.jsonl` (append-only):
```json
{"timestamp":"2026-04-04T10:30:00Z","heartbeat_number":42,"issue_id":"ENG-123","issue_title":"Add search endpoint","duration_seconds":340,"result":"completed","commits":["abc1234"],"spec_path":"docs/specs/01-spec-search/01-spec-search.md"}
```

## Retry Logic for Blocked Issues

An `agent-blocked` issue becomes eligible for retry when:
1. A new comment has been added since the last heartbeat comment
2. The `agent-blocked` label is still present

This allows human feedback to unblock the agent without manual label management.

## Quiet Hours

When `heartbeat.quiet_hours.enabled` is true, the heartbeat checks the current time against the configured window and exits immediately if within quiet hours. This prevents overnight processing.
