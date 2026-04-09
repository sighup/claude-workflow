# Team Setup Reference

## Contents
- Create the review team
- Create concern tasks
- Spawn reviewers
- Reviewer prompt template

## Create the review team

```
TeamCreate({
  team_name: "{task-list-id}-review-team",
  description: "Concern-partitioned code review team"
})
```

The team name is always `{CLAUDE_CODE_TASK_LIST_ID}-review-team` so it never collides with the task list ID or dispatch team name.

## Create concern tasks

Create 3 `REVIEW-CONCERN:` tasks — one per reviewer (security, correctness, spec compliance):

```
TaskCreate({
  subject: "REVIEW-CONCERN: {Concern} review (Category {X})",
  description: "{Concern}-focused review of all changed files. See reviewer-team-protocol.md for concern checklist.",
  activeForm: "Reviewing {concern} concerns"
})
```

Then set metadata on each:

```
TaskUpdate({
  taskId: "<concern-task-id>",
  metadata: {
    task_type: "review-concern",
    concern: "security|correctness|spec-compliance",
    primary_category: "B|A|C+D",
    changed_files: ["path/to/file1.ts", ...],
    spec_path: "<path-to-spec or null>",
    standards_summary: "<brief summary of repo conventions>",
    base_branch: "main"
  }
})
```

Concern → category mapping:
- `security` → `B`
- `correctness` → `A`
- `spec-compliance` → `C+D`

## Spawn reviewers

Assign ownership, then spawn all 3 reviewers in a **single message** for parallel launch:

```
TaskUpdate({ taskId: "<security-task-id>", owner: "security-reviewer", status: "in_progress" })
TaskUpdate({ taskId: "<correctness-task-id>", owner: "correctness-reviewer", status: "in_progress" })
TaskUpdate({ taskId: "<spec-task-id>", owner: "spec-reviewer", status: "in_progress" })
```

Then in one message, three Task() calls (template below).

## Reviewer prompt template

```
Task({
  subagent_type: "claude-workflow:reviewer",
  team_name: "{task-list-id}-review-team",
  name: "{concern}-reviewer",
  description: "{Concern} concern review",
  prompt: "You are {concern}-reviewer on the {task-list-id}-review-team team.

YOUR ASSIGNED TASK: <task-id> - {Concern} review (Category {X})

PROTOCOL:
1. Read the concern-partitioned protocol at: skills/cw-review-team/references/reviewer-team-protocol.md
2. Follow the 3-phase protocol (ORIENT, EXAMINE, REPORT)
3. Focus primarily on {concern} concerns (Category {X}) across ALL changed files
4. Note obvious secondary findings from other categories
5. Write findings to task metadata via TaskUpdate
6. Message the lead via SendMessage when complete

CONSTRAINTS:
- Never modify implementation code
- Never create FIX tasks or new tasks
- Always include file paths and line numbers
- Set is_primary=true for findings in your concern, is_primary=false for secondary findings

SHUTDOWN:
- Approve shutdown_request when received"
})
```

Substitute `{concern}` and `{X}` for each reviewer (security/B, correctness/A, spec/C+D).
