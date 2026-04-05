# Heartbeat Protocol Reference

## Two-Tier Decomposition Model

```
Linear Parent Issue (Feature)
  ↓ cw-spec decomposes
Linear Sub-issues (Demoable Units)   ← human reviews/approves here
  ↓ heartbeat picks up each sub-issue
Native Task Board (per worktree)     ← agent-internal, ephemeral
  ↓ cw-dispatch executes
Proof Artifacts + Commits            ← reported back to Linear
```

## Lifecycle Phases

```
Phase 0: Trigger         Human creates/assigns Linear issue
Phase 1: Research        cw-research → post summary → label transition       (optional)
Phase 2: Decompose       cw-spec → create sub-issues from demoable units     (one cycle)
     ─── HUMAN GATE ───  Human reviews sub-issues, reorders, approves by moving to Todo
Phase 3: Execute         Per sub-issue: worktree → cw-plan → cw-dispatch → cw-validate
Phase 4: Review          Per sub-issue: cw-review → FIX tasks → re-review    (optional)
Phase 5: Test            Per sub-issue: cw-testing with .feature file        (optional)
Phase 6: Sub-issue PR    Per sub-issue: create PR from unit branch           (optional)
Phase 7: Auto-complete   All sub-issues Done → Linear auto-completes parent
Phase 8: Parent Review   cw-review-team on full diff (cross-unit issues)     (optional)
```

## Phase Detection Logic

```
determine_phase(issue):

  ── Parent issues (no cw-managed label) ──

  if has_label("needs-research") and not has_label("ready-for-spec"):
    → RESEARCH

  if has_label("ready-for-spec"):
    → SPEC

  if status == "Todo" and not has_label("spec-complete"):
    → SPEC

  if has_label("spec-complete"):
    → WAITING (sub-issues in progress; Linear auto-completes parent)

  ── Sub-issues (has cw-managed label) ──

  if status == "Todo":
    → EXECUTE

  if status == "In Progress":
    → EXECUTE (resume)

  if status == "Done":
    → SKIP
```

## Label Design

Linear label groups are **single-select** (only one label from a group per issue). This enforces correct state transitions.

### Label Group: `cw-state` (single-select)

| Label | Meaning |
|---|---|
| `agent-working` | Agent is actively processing this issue |
| `agent-blocked` | Agent cannot proceed without human input |

### Label Group: `cw-phase` (single-select)

| Label | Applied To | Meaning |
|---|---|---|
| `needs-research` | Parent issue | Triggers research phase before spec |
| `ready-for-spec` | Parent issue | Research done, ready for spec generation |
| `spec-complete` | Parent issue | Spec generated, sub-issues created |

### Standalone Label

| Label | Applied To | Meaning |
|---|---|---|
| `cw-managed` | Sub-issue | Marks this as an agent-created sub-issue |

### Transitions

```
Parent issue lifecycle:
  (new, assigned to agent, Todo)
    → [needs-research]     if auto_research or manually tagged
    → SPEC phase           if no research needed

  [needs-research]
    → RESEARCH phase
    → [ready-for-spec]     on success
    → [agent-blocked]      on failure

  [ready-for-spec]  or  (Todo, no phase label)
    → SPEC phase
    → [spec-complete]      on success (sub-issues created in Backlog)
    → [agent-blocked]      on failure

  [spec-complete]
    → WAITING              while sub-issues are in progress
    → Auto-completed       when all sub-issues are Done (Linear built-in)

Sub-issue lifecycle:
  (Backlog, cw-managed)
    → WAITING              until human moves to Todo

  (Todo, cw-managed)
    → EXECUTE              heartbeat picks up
    → Done                 on success
    → [agent-blocked]      on failure
```

## Linear Comment Format

Every heartbeat phase posts a structured comment:

```markdown
**Heartbeat #{N}** — {PHASE} — {YYYY-MM-DD HH:MM UTC}

**Duration:** {Xm Ys}
**Result:** {completed | blocked | error}

### {Phase-specific content}

{body varies by phase — see below}
```

### Phase-Specific Comment Bodies

**RESEARCH:**
```markdown
### Research Summary
{condensed findings from cw-research report}

**Report:** `{report_file_path}`

### Key Findings
- {finding 1}
- {finding 2}

### Next
Proceeding to spec generation.
```

**SPEC:**
```markdown
### Specification Complete
**Spec:** `{spec_file_path}`

### Demoable Units → Sub-issues
| # | Sub-issue | Linear ID |
|---|-----------|-----------|
| 1 | {title} | {ID} |
| 2 | {title} | {ID} |

### Goals
{goals from spec}

### Next
Sub-issues created in Backlog. Move to Todo to approve for execution.
```

**EXECUTE:**
```markdown
### Execution Complete
**Worktree:** `.worktrees/feature-{feature}-{unit}/`
**Branch:** `feature/{feature}/{unit}`

### Tasks
{completed}/{total} tasks completed

### Commits
- `{sha}` {message}
- `{sha}` {message}

### Proof Artifacts
- `{proof_file_1}`
- `{proof_file_2}`

### Validation Gates
| Gate | Result |
|------|--------|
| A. No critical issues | PASS |
| B. Coverage complete | PASS |
| ... | ... |
```

**REVIEW (per sub-issue):**
```markdown
### Code Review
**Result:** {APPROVED | CHANGES REQUESTED}

{If APPROVED:}
No blocking issues found.

{If CHANGES REQUESTED:}
### Blocking Issues
- {issue 1}
- {issue 2}

### Fix Attempts
{N} FIX tasks created and executed. {M} resolved.
```

## Lockfile Format

`.claude-workflow/heartbeat.lock`:
```json
{
  "pid": 12345,
  "started_at": "2026-04-05T10:30:00Z",
  "issue_id": "ENG-123",
  "phase": "EXECUTE"
}
```

## Heartbeat Log Format

`.claude-workflow/heartbeat-log.jsonl` (append-only):
```json
{"timestamp":"2026-04-05T10:30:00Z","issue_id":"ENG-456","issue_title":"Add login endpoint","phase":"EXECUTE","duration_seconds":340,"result":"completed","commits":["abc1234"],"spec_path":"docs/specs/01-spec-auth/01-spec-auth.md"}
```

## Retry Logic

An `agent-blocked` issue becomes eligible for retry when:
1. A new comment has been added since the last agent comment
2. The `agent-blocked` label is still present

This allows human feedback to unblock the agent without manual label management.

## Quiet Hours

When `heartbeat.quiet_hours.enabled` is true, the heartbeat checks the current time against the configured window and exits immediately if within quiet hours.

## Branch Strategy

| Strategy | Behavior |
|---|---|
| `direct` | Each sub-issue creates a PR directly to main. Units can ship independently. |
| `integration` | Sub-issue branches merge into `feature/{feature-slug}`. One final PR to main. |
