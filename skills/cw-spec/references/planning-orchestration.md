# Planning Orchestration Protocol

When the user selects **Run /cw-plan**, use this two-pass flow to create and refine the task graph before handing off to execution.

## Frontier Planner Spawn

Use the `frontier` value resolved in cw-spec Step 2. When `frontier = true`, spawn the planner with `model: "fable"`; otherwise use `model: "opus"`. This applies to every planner spawn in this file.

**Fable Fallback**: If a planner spawn with `model: "fable"` fails for an availability-class reason (unknown model, permission/org-policy error, credit exhaustion, API error, or `refusal` stop reason), respawn that planner exactly once with `model: "opus"`. Record the substitution. A Fable failure never aborts the flow.

## Pass 1 — Parent Task Creation

Spawn the planner for Steps 1 and 2 only:

```
Task({ subagent_type: "claude-workflow:planner", model: frontier ? "fable" : "opus", description: "Create parent tasks (Step 1+2)", prompt: "The spec is ready. Run /cw-plan to complete Step 1 and Step 2 (parent task creation) only. Output the CW-PLAN COMPLETE summary and exit — do not proceed to Step 3." })
```

Relay the CW-PLAN COMPLETE summary to the user, then present the decomposition question. Use the planner's `Recommendation` field to mark the suggested option:

```
AskUserQuestion({
  questions: [{
    question: "I've created [N] parent tasks. [Planner's Reason sentence]. How would you like to proceed?",
    header: "Tasks",
    options: [
      { label: "Generate sub-tasks (Recommended)", description: "Decompose parent tasks into atomic implementation steps" },
      { label: "Execute as-is", description: "Run parent tasks directly — workers handle internal decomposition via cw-execute" },
      { label: "Adjust tasks", description: "Provide feedback to revise the task graph before proceeding" }
    ],
    multiSelect: false
  }]
})
```

> Mark `(Recommended)` on whichever option matches the planner's `Recommendation` field. If "Execute as-is" is recommended, move the label to that option instead.

## Based on User Selection

- **Generate sub-tasks**: spawn planner for Step 3:
  ```
  Task({ subagent_type: "claude-workflow:planner", model: frontier ? "fable" : "opus", description: "Generate sub-tasks (Step 3)", prompt: "The parent tasks are already on the board. Run /cw-plan Step 3 only — create sub-tasks for each parent task, then exit." })
  ```

- **Execute as-is**: proceed directly to execution options below.

- **Adjust tasks**: ask the user for their feedback, then re-run Pass 1 with that feedback:
  ```
  Task({ subagent_type: "claude-workflow:planner", model: frontier ? "fable" : "opus", description: "Revise parent tasks (Step 1+2)", prompt: "Revise the parent task graph based on this feedback: [user feedback]. Clear existing tasks if needed, recreate them, output an updated CW-PLAN COMPLETE summary, and exit." })
  ```
  Then re-present the decomposition question with the updated summary.

## Execution Dispatch

After Step 3 completes (or if executing as-is), present execution options:

```
AskUserQuestion({
  questions: [{
    question: "The task graph is ready for execution. How would you like to proceed?",
    header: "Execution",
    options: [
      { label: "Parallel (/cw-dispatch)", description: "Spawn parallel subagent workers — ready workers run concurrently, no extra setup needed" },
      { label: "Team (/cw-dispatch-team)", description: "Persistent agent team with lead coordination (requires CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 and CLAUDE_CODE_TASK_LIST_ID)" },
      { label: "Single task (/cw-execute)", description: "Execute one task at a time with full visibility and control" },
      { label: "Done for now", description: "Save the task graph and execute later" }
    ],
    multiSelect: false
  }]
})
```

Based on user selection:
- **Parallel**: `Skill({ skill: "cw-dispatch" })`
- **Team**: `Skill({ skill: "cw-dispatch-team" })`
- **Single task**: `Skill({ skill: "cw-execute" })`
- **Done for now**: Confirm task graph is saved and exit
