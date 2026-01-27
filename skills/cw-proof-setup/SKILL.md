---
name: cw-proof-setup
description: "Discover and configure proof capture capabilities using skills.sh ecosystem. Analyzes spec/tasks for proof needs and ensures appropriate tools are available."
user-invocable: true
allowed-tools: Glob, Grep, Read, Bash, TaskList, TaskGet, TaskUpdate, AskUserQuestion
---

# CW-Proof-Setup: Proof Capture Capability Discovery

## Context Marker

Always begin your response with: **CW-PROOF-SETUP**

## Overview

You are the **Capability Configurator** in the Claude Workflow system. Your job is to analyze proof artifact requirements from specs or tasks and ensure appropriate capture tools are available. You dynamically discover capabilities using the skills.sh ecosystem and configure tasks with the right tools for proof collection.

## When to Run

- After spec/plan creation, before execution begins
- When visual proof artifacts are detected in a task graph
- On-demand when the user wants to set up proof capture
- When `cw-execute` detects visual proofs but no `proof_capture` config exists

## Critical Constraints

- **DO NOT** install skills without user approval
- **DO NOT** implement any code - this is configuration only
- **Check installed capabilities first** - only prompt for gaps
- **Silent pass-through** when all needs are already covered
- **Graceful fallback** if `npx skills` is not available

## Process

### Phase 1: Locate Proof Sources

Find where proof requirements are defined:

1. **From spec**: Look for `proof artifacts` section in `./docs/specs/*/SPEC.md`
2. **From tasks**: Call `TaskList()` and `TaskGet()` to read `metadata.proof_artifacts`
3. **User-provided**: Accept a spec path or task ID as argument

```bash
# Find recent specs
ls -lt ./docs/specs/*/SPEC.md 2>/dev/null | head -5
```

If no proof sources found, report and exit cleanly.

### Phase 2: Extract Proof Needs

Parse proof artifact descriptions into natural language categories:

| Proof Type | Category | Example Tools |
|------------|----------|---------------|
| `screenshot` | "screenshot capture" | chrome-devtools, screencapture, scrot |
| `browser` | "browser automation" | playwright, puppeteer, chrome-devtools |
| `visual` | "visual verification" | screenshot tools, image comparison |
| `video` | "screen recording" | ffmpeg, screen-capture-recorder |
| `terminal` | "terminal output" | script, asciinema |

Build a list of unique categories needed.

### Phase 3: Check Available Capabilities

Before searching for new tools, check what's already available:

**1. Check installed skills (if skills.sh CLI available)**

```bash
npx skills list 2>/dev/null || echo "skills CLI not available"
```

**2. Check MCP tools**

Look for available MCP tools in the current session:
- `mcp__chrome-devtools__take_screenshot` - web page screenshots
- `mcp__chrome-devtools__navigate_page` - browser automation

**3. Check CLI tools**

```bash
# macOS
which screencapture 2>/dev/null && echo "screencapture available"

# Linux
which scrot 2>/dev/null && echo "scrot available"
which gnome-screenshot 2>/dev/null && echo "gnome-screenshot available"

# Cross-platform
which ffmpeg 2>/dev/null && echo "ffmpeg available (video)"
```

**4. Map capabilities to needs**

For each category from Phase 2, mark as:
- `covered` - a tool/skill is already available
- `uncovered` - no matching capability found

### Phase 4: Discover Missing Capabilities

For each `uncovered` category, search for skills:

```bash
npx skills find "screenshot capture" 2>/dev/null
npx skills find "browser automation" 2>/dev/null
```

If `npx skills` is not available, skip this phase and proceed with MCP/CLI detection only.

Parse results to extract:
- Skill name (e.g., `agent-browser`)
- Repository (e.g., `vercel-labs/agent-browser`)
- Description
- Install count (if available)

### Phase 5: Present Options

**If all needs are covered:** Silent pass-through - report what's available and proceed.

**If gaps exist:** Use AskUserQuestion to let user choose how to fill each gap.

For each uncovered category:

```
AskUserQuestion({
  questions: [{
    question: "For proof type '[category]', how should it be captured?",
    header: "Proof Setup",
    options: [
      { label: "[Skill Name] (Recommended)", description: "[skill description] - [install count] installs" },
      { label: "[Another Skill]", description: "[description]" },
      { label: "Manual verification", description: "I will capture and verify these myself" },
      { label: "Skip", description: "Accept code-level verification only" }
    ],
    multiSelect: false
  }]
})
```

**Option priority:**
1. Skills with highest install counts and best feature match
2. Available MCP tools (if applicable)
3. Manual verification fallback
4. Skip option

### Phase 6: Configure and Store

Based on user selections:

**1. Install chosen skills**

```bash
npx skills add [skill-name]
```

**2. Update task metadata**

For each task with visual proof artifacts, update with `proof_capture` config:

```
TaskUpdate({
  taskId: "<task-id>",
  metadata: {
    proof_capture: {
      visual_method: "auto|manual|skip",
      tool: "chrome-devtools|screencapture|scrot|[skill-name]|null",
      skill: "[skill-name]|null",
      manual_confirmation_required: true|false
    }
  }
})
```

**3. Report configuration**

```
CW-PROOF-SETUP COMPLETE
========================
Proof capture configured for [N] tasks.

Visual Proofs:
  Method: [auto|manual|skip]
  Tool: [tool name]
  Skill: [skill name or "none"]

Next: Run /cw-execute or /cw-dispatch to begin implementation.
```

## Capability Detection Methods

### MCP Tools

Check if MCP tools are available by attempting to use them or checking tool list:

| MCP Tool | Capability |
|----------|------------|
| `mcp__chrome-devtools__take_screenshot` | Web page screenshots |
| `mcp__chrome-devtools__navigate_page` | Browser navigation |
| `mcp__chrome-devtools__evaluate_script` | Page interaction |

### CLI Tools

| Platform | Tool | Command |
|----------|------|---------|
| macOS | screencapture | `screencapture -w output.png` |
| Linux | scrot | `scrot -s output.png` |
| Linux | gnome-screenshot | `gnome-screenshot -a -f output.png` |
| All | ffmpeg | Screen recording |

### Skills.sh Ecosystem

When available, leverage `npx skills` for dynamic discovery:

```bash
# List installed skills
npx skills list

# Search for skills by capability
npx skills find "browser automation"

# Install a skill
npx skills add [skill-name]

# Get skill details
npx skills info [skill-name]
```

## Metadata Schema

The `proof_capture` object stored in task metadata:

```json
{
  "proof_capture": {
    "visual_method": "auto|manual|skip",
    "tool": "chrome-devtools|screencapture|scrot|[skill-name]|null",
    "skill": "[skill-name]|null",
    "skill_repo": "[org/repo]|null",
    "manual_confirmation_required": true,
    "configured_at": "2026-01-26T12:00:00Z",
    "configured_by": "cw-proof-setup"
  }
}
```

## Graceful Fallback

If the skills.sh CLI is not available:

1. Detect MCP tools and CLI tools only
2. Present available options to user
3. Use `manual` as default if no automated tools detected
4. Document in task metadata that skills discovery was unavailable

## What Comes Next

After proof capture is configured:

- **Execute tasks**: Run `/cw-execute` or `/cw-dispatch`
- **Re-configure**: Run `/cw-proof-setup` again to change settings
- **Continue planning**: Return to `/cw-plan` if tasks need adjustment

```
AskUserQuestion({
  questions: [{
    question: "Proof capture is configured. What would you like to do next?",
    header: "Next Step",
    options: [
      { label: "Execute tasks (/cw-dispatch)", description: "Spawn parallel workers for independent tasks" },
      { label: "Execute single task (/cw-execute)", description: "Execute one task with full control" },
      { label: "Done for now", description: "Save configuration and execute later" }
    ],
    multiSelect: false
  }]
})
```

Based on selection, invoke the appropriate skill or confirm completion.
