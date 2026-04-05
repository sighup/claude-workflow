# Heartbeat Protocol Reference

## Two-Tier Decomposition Model

```
Linear Epic (Feature)
  ↓ cw-spec decomposes
Linear Stories (Demoable Units)    ← human reviews/approves here
  ↓ heartbeat picks up each story
Native Task Board (per worktree)   ← agent-internal, ephemeral
  ↓ cw-dispatch executes
Proof Artifacts + Commits          ← reported back to Linear
```

## Lifecycle Phases

```
Phase 0: Trigger         Human creates/assigns Linear epic
Phase 1: Research        cw-research → post summary → label transition       (optional)
Phase 2: Decompose       cw-spec → create Linear stories from demoable units (one cycle)
     ─── HUMAN GATE ───  Human reviews stories, reorders, approves by moving to Todo
Phase 3: Execute         Per-story: worktree → cw-plan → cw-dispatch → cw-validate
Phase 4: Review          Per-story: cw-review → FIX tasks → re-review loop
Phase 5: Test            Per-story: cw-testing with story's .feature file
Phase 6: Story PR        Per-story: create PR from story branch              (optional)
Phase 7: Epic Validate   All stories done → cw-validate on full feature      (optional)
Phase 8: Epic Review     cw-review-team on full diff (cross-story issues)    (optional)
Phase 9: Complete        Epic → Done, final PR if integration branch
```

## Phase Detection Logic

```
determine_phase(issue):

  ── Epics (no agent-story label) ──

  if has_label("needs-research") and not has_label("agent-ready-for-spec"):
    → RESEARCH

  if has_label("agent-ready-for-spec"):
    → SPEC

  if status == "Todo" and not has_label("agent-spec-complete"):
    → SPEC

  if has_label("agent-spec-complete") and all_children_done():
    → EPIC_VALIDATE

  else:
    → WAITING (stories in progress)

  ── Stories (has agent-story label) ──

  if status == "Todo":
    → STORY_EXECUTE

  if status == "In Review":
    → STORY_REVIEW

  if status == "Done":
    → SKIP

  else:
    → SKIP
```

## Label State Machine

### Labels

| Label | Applied To | Purpose |
|---|---|---|
| `agent-working` | Epic or Story | Mutex — agent is actively processing this issue |
| `agent-blocked` | Epic or Story | Agent cannot proceed without human input |
| `needs-research` | Epic | Triggers Phase 1 (research) before spec |
| `agent-ready-for-spec` | Epic | Phase 1 complete, ready for Phase 2 |
| `agent-spec-complete` | Epic | Phase 2 complete, stories created |
| `agent-story` | Story | Marks this as an agent-managed child of an epic |

### Transitions

```
Epic lifecycle:
  (new, assigned)
    → [needs-research]      if auto_research or manually tagged
    → SPEC phase             if no research needed

  [needs-research]
    → RESEARCH phase
    → [agent-ready-for-spec] on success
    → [agent-blocked]        on failure

  [agent-ready-for-spec]  or  (Todo, no labels)
    → SPEC phase
    → [agent-spec-complete]  on success (stories created in Backlog)
    → [agent-blocked]        on failure

  [agent-spec-complete]
    → WAITING                while stories are in progress
    → EPIC_VALIDATE          when all stories are Done
    → Done                   on validation pass

Story lifecycle:
  (Backlog, agent-story)
    → WAITING                until human moves to Todo

  (Todo, agent-story)
    → STORY_EXECUTE          heartbeat picks up
    → Done                   on success
    → [agent-blocked]        on failure

  (In Review, agent-story)
    → STORY_REVIEW           heartbeat runs review + test
    → Done                   on pass
    → [agent-blocked]        on failure
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

### Demoable Units → Stories
| # | Story | Linear ID |
|---|-------|-----------|
| 1 | {title} | {ID} |
| 2 | {title} | {ID} |

### Goals
{goals from spec}

### Next
Stories created in Backlog. Move stories to Todo to approve for execution.
```

**STORY_EXECUTE:**
```markdown
### Execution Complete
**Worktree:** `.worktrees/feature-{epic}-{story}/`
**Branch:** `feature/{epic}/{story}`

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

**STORY_REVIEW:**
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

**EPIC_VALIDATE:**
```markdown
### Epic Validation
**All stories complete.** Running cross-story validation.

### Story Summary
| Story | Status | Commits |
|-------|--------|---------|
| {title} | Done | {N} |
| {title} | Done | {N} |

### Overall
{PASS or FAIL with details}
```

## Lockfile Format

`.claude-workflow/heartbeat.lock`:
```json
{
  "pid": 12345,
  "started_at": "2026-04-05T10:30:00Z",
  "issue_id": "ENG-123",
  "phase": "STORY_EXECUTE"
}
```

## Heartbeat Log Format

`.claude-workflow/heartbeat-log.jsonl` (append-only):
```json
{"timestamp":"2026-04-05T10:30:00Z","issue_id":"ENG-456","issue_title":"Add login endpoint","phase":"STORY_EXECUTE","duration_seconds":340,"result":"completed","commits":["abc1234"],"spec_path":"docs/specs/01-spec-auth/01-spec-auth.md"}
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
| `direct` | Each story creates a PR directly to main. Stories can ship independently. |
| `integration` | Stories merge into `feature/{epic-slug}`. One final PR to main when epic validates. |
