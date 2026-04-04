# claude-workflow

A Claude Code plugin that unifies spec-driven development, autonomous task execution, and parallel agent dispatch into a single workflow. Takes a feature from idea to validated implementation using structured specifications, dependency-aware task graphs, and evidence-based verification. 

## Install

### From Git (recommended)

```bash
# Add the marketplace
claude plugin marketplace add https://github.com/sighup/claude-workflow.git

# Install at project scope (shared with team via .claude/settings.json)
claude plugin install claude-workflow@claude-workflow --scope project

# Or install at user scope (personal, across all projects)
claude plugin install claude-workflow@claude-workflow --scope user
```

### Interactive installation

```bash
/plugin
# Navigate to Marketplaces tab → Add → paste the git URL
# Then go to Discover tab → select claude-workflow → choose scope
```

## Workflow

### Interactive (inside Claude)

```
[/cw-research]  →  /cw-spec  →  [/cw-gherkin]  →  /cw-plan  →  /cw-dispatch  →  /cw-validate
```

Each step can also be run independently. `/cw-execute` handles single-task execution for manual or shell-scripted loops. `/cw-review` adds a code review gate and `/cw-testing` generates and runs E2E tests.

### Worktrees (manual parallel development)

Use `/cw-worktree` to develop multiple features simultaneously. Each worktree gets its own feature branch and **isolated task list** (via `.claude/settings.local.json`). Tasks persist in `~/.claude/tasks/{worktree-name}/`, enabling seamless resume across sessions. See [examples/workflows.md](examples/workflows.md) for the full multi-terminal walkthrough.

## Skills

| Skill | Purpose |
|-------|---------|
| `/cw-research` | Explore codebase across 5 dimensions and produce a structured research report with `/cw-spec` meta-prompt |
| `/cw-spec` | Generate structured specification with demoable units and proof artifacts |
| `/cw-plan` | Transform spec into native task graph with dependencies and metadata |
| `/cw-execute` | Execute one task using the 11-phase protocol (orient → commit → clean exit) |
| `/cw-dispatch` | Spawn parallel subagent workers for independent tasks (no setup required) |
| `/cw-dispatch-team` | Persistent agent team with lead coordination for parallel task execution |
| `/cw-validate` | Run 6 validation gates and produce a coverage matrix report |
| `/cw-review` | Review implementation for bugs, security issues, and quality; creates fix tasks |
| `/cw-review-team` | Concern-partitioned team review — each reviewer sees all files through a specialized lens (security, correctness, spec compliance) |
| `/cw-testing` | E2E testing with auto-fix — generate tests from specs, execute, and fix failures |
| `cw-gherkin` | Generate Gherkin BDD scenarios from spec acceptance criteria; called automatically by cw-spec |
| `/cw-worktree` | Manage git worktrees for multi-feature parallel development |
| `/cw-heartbeat` | Pull issues from Linear and run them through the cw pipeline |
| `/cw-linear-init` | Set up Linear integration (creates `.claude-workflow/config.yaml`) |
| `/cw-linear-status` | Show heartbeat queue, blocked issues, and recent history |

## Prerequisites

Shell scripts require `jq`. The `gh` CLI is needed for PR creation in `cw-pipeline`.

Most skills work out of the box. `/cw-dispatch-team` uses [Claude Code agent teams](https://code.claude.com/docs/en/agent-teams) which requires two env vars:

1. Enable the experimental feature flag (user-level, applies to all projects):

```json
// ~/.claude/settings.json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

2. Set the task list ID (project-level, unique per project):

```json
// .claude/settings.json
{
  "env": {
    "CLAUDE_CODE_TASK_LIST_ID": "your-project-name"
  }
}
```

**Note:** `/cw-worktree create` sets `CLAUDE_CODE_TASK_LIST_ID` automatically in `.claude/settings.local.json` — no manual configuration needed for worktree-based workflows.

`/cw-dispatch` (subagent workers) needs no setup and is the recommended default. `/cw-plan` will offer both options after task graph creation.

`/cw-testing` supports multiple backends. To use the `playwright-bdd` backend (Gherkin → Playwright, CI-friendly):

```bash
npm install --save-dev playwright-bdd @playwright/test
npx playwright install
```

## Task Metadata

Every task on the board carries self-contained metadata enabling autonomous execution:

```json
{
  "task_id": "T01",
  "spec_path": "docs/specs/01-spec-auth/01-spec-auth.md",
  "scope": {
    "files_to_create": ["src/auth/login.ts"],
    "files_to_modify": ["src/routes/index.ts"],
    "patterns_to_follow": ["src/routes/health.ts"]
  },
  "requirements": [
    { "id": "R01.1", "text": "POST /auth/login accepts credentials", "testable": true }
  ],
  "proof_artifacts": [
    { "type": "test", "command": "npm test -- src/auth/login.test.ts", "expected": "All pass" }
  ],
  "commit": { "template": "feat(auth): add login endpoint" },
  "verification": {
    "pre": ["npm run lint"],
    "post": ["npm test"]
  },
  "role": "implementer",
  "complexity": "standard",
  "model": null
}
```

## Linear Integration (Optional)

The heartbeat system connects Linear to the cw pipeline — issues assigned to your agent get automatically specced, planned, executed, and validated.

### Setup

```
# Inside Claude:
/cw-linear-init
```

This creates `.claude-workflow/config.yaml` with your team key, agent name, and pipeline flags. Requires a [Linear MCP server](https://github.com/linear/linear-mcp) configured in Claude Code.

### Usage

```
# Interactive — process the Linear queue
/cw-heartbeat

# Preview what would be processed
/cw-heartbeat --dry-run

# Process a specific issue
/cw-heartbeat --issue ENG-123

# Check queue and history
/cw-linear-status
```

### How It Works

```
Linear Issue (Todo) → /cw-heartbeat picks it up
                       ↓
                    cw-spec (auto-generate spec from issue)
                       ↓
                    cw-plan (decompose into task graph)
                       ↓
                    cw-dispatch (parallel execution)
                       ↓
                    cw-validate (6-gate verification)
                       ↓
                    Report back to Linear (structured comment + state update)
```

The heartbeat is **additive** — all existing `/cw-*` commands work exactly as before without Linear. You can mix heartbeat-driven and manual work in the same project.

### Unattended Execution

```bash
# From the shell (CI, cron, scheduled task)
./bin/cw-heartbeat --model sonnet

# Dry run
./bin/cw-heartbeat --dry-run
```

### Configuration

`.claude-workflow/config.yaml` controls heartbeat behavior:

| Key | Default | Description |
|-----|---------|-------------|
| `heartbeat.max_issues_per_heartbeat` | 2 | Issues to process per cycle |
| `heartbeat.stale_lock_hours` | 1 | Hours before a lock is considered stale |
| `heartbeat.error_cooldown_minutes` | 30 | Wait time after errors |
| `heartbeat.quiet_hours` | disabled | Time window to skip processing |
| `pipeline.auto_spec` | true | Auto-generate specs from issues |
| `pipeline.auto_plan` | true | Auto-decompose into tasks |
| `pipeline.auto_dispatch` | true | Auto-execute tasks in parallel |
| `pipeline.auto_validate` | true | Auto-run validation gates |
| `pipeline.auto_review` | false | Auto-run code review |
| `pipeline.auto_pr` | false | Auto-create pull requests |

## Shell Scripts

Shell scripts in `bin/` are optional and enable autonomous (unattended) execution without an interactive Claude session — useful for CI pipelines or scripted workflows. All core functionality is available through the skills above. See [examples/shell-scripts.md](examples/shell-scripts.md) for usage and environment variable reference.