---
name: cw-linear-init
description: "Scaffolds Linear integration for claude-workflow. Creates .claude-workflow/config.yaml with team settings, heartbeat cadence, label configuration, and pipeline flags. Run once per project to enable the heartbeat lifecycle."
user-invocable: true
allowed-tools: Bash, Read, Write, Glob, Grep, AskUserQuestion
effort: low
---

# CW-Linear-Init: Linear Integration Setup

## Context Marker

Always begin your response with: **CW-LINEAR-INIT**

## Overview

You initialize the Linear integration for an existing claude-workflow project. This creates the configuration file and Linear labels needed for the heartbeat lifecycle — the two-tier system where epics decompose into Linear stories (human-reviewable), and stories execute via the cw pipeline (agent-internal).

## Your Role

You are a **setup assistant** who:
- Gathers Linear team and user configuration
- Creates the `.claude-workflow/config.yaml` file
- Verifies Linear MCP tools are available
- Creates required labels in Linear

## Critical Constraints

- **NEVER** overwrite an existing `.claude-workflow/config.yaml` without user consent
- **NEVER** modify any existing cw skills or configuration
- **ALWAYS** verify Linear MCP tools are accessible before proceeding
- **ALWAYS** ask the user for their Linear team key and agent user name

## Process

### Step 1: Preflight Checks

1. Check if `.claude-workflow/config.yaml` already exists:
   ```bash
   test -f .claude-workflow/config.yaml && echo "EXISTS" || echo "MISSING"
   ```
   If it exists, inform the user and ask whether to reconfigure or exit.

2. Verify Linear MCP tools are available by checking for the `mcp__linear__` tool prefix. If unavailable, inform the user:
   ```
   Linear MCP server is not configured. To enable Linear integration:
   1. Add the Linear MCP server to your Claude Code configuration
   2. Ensure the server has read/write access to your team's issues
   3. Re-run /cw-linear-init
   ```

### Step 2: Gather Configuration

Use AskUserQuestion to collect required information:

```
AskUserQuestion({
  questions: [
    {
      question: "What is your Linear team key?",
      header: "Team",
      options: [
        { label: "ENG", description: "Engineering team" },
        { label: "PRODUCT", description: "Product team" },
        { label: "Other", description: "Enter a custom team key" }
      ],
      multiSelect: false
    },
    {
      question: "What name should the agent use when posting to Linear?",
      header: "Agent Name",
      options: [
        { label: "claude-agent", description: "Default agent identity" },
        { label: "Other", description: "Enter a custom name" }
      ],
      multiSelect: false
    }
  ]
})
```

### Step 3: Create Configuration

1. Create the directory:
   ```bash
   mkdir -p .claude-workflow
   ```

2. Read the template from the plugin:
   ```
   Read templates/linear-config.yaml
   ```

3. Replace `{{TEAM}}` and `{{USER_NAME}}` with user-provided values.

4. Write the final config to `.claude-workflow/config.yaml`.

### Step 4: Create Linear Labels

Using the Linear MCP tools, create the label group and all lifecycle labels:

1. Create parent label group: `claude-workflow`

2. Create **state labels** under the group:
   - `agent-working` — Agent is actively processing this issue
   - `agent-blocked` — Agent needs human input before continuing

3. Create **phase transition labels** under the group:
   - `needs-research` — Epic needs codebase research before spec generation
   - `agent-ready-for-spec` — Research done, ready for spec generation
   - `agent-spec-complete` — Spec generated, stories created in Backlog

4. Create **story label** under the group:
   - `agent-story` — This issue is an agent-managed story (child of an epic)

If label creation fails (permissions, duplicates), log a warning but don't fail the init.

### Step 5: Add to .gitignore

Append to `.gitignore` if not already present:

```
# Claude Workflow - Linear integration
.claude-workflow/heartbeat.lock
.claude-workflow/heartbeat-log.jsonl
```

The `config.yaml` itself should be committed (it's team-shared configuration).

### Step 6: Summary

Output a summary:

```
Linear integration initialized:

  Config:  .claude-workflow/config.yaml
  Team:    {TEAM}
  Agent:   {USER_NAME}

  Labels created:
    State:   agent-working, agent-blocked
    Phase:   needs-research, agent-ready-for-spec, agent-spec-complete
    Story:   agent-story

  Lifecycle:
    Epic (Todo) → Research (optional) → Spec + Decompose → Stories (Backlog)
        ─── HUMAN GATE ─── (move stories to Todo to approve)
    Story (Todo) → Plan → Execute → Validate → Review → Test → Done

Next steps:
  1. Create or assign a Linear issue to "{USER_NAME}"
  2. Run /cw-heartbeat to process the issue queue
  3. Or run /cw-heartbeat --dry-run to preview what would be processed
```
