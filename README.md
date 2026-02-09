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
/cw-spec  →  /cw-plan  →  /cw-dispatch  →  /cw-validate
```

Each step can also be run independently. `/cw-execute` handles single-task execution for manual or shell-scripted loops. `/cw-review` adds a code review gate and `/cw-testing` generates and runs E2E tests.

### Full Pipeline (one command, unattended)

```bash
./bin/cw-pipeline --prompt "Build JWT authentication" --name auth
```

Orchestrates the full lifecycle in a git worktree:

```
prompt → worktree → spec → plan → execute → validate → review → test → fix → re-validate → PR
```

Each stage runs non-interactively via `claude --print`. Skip stages with `--no-test`, `--no-review`, or `--no-pr`. See [examples/shell-scripts.md](examples/shell-scripts.md) for more options.

### Worktrees (manual parallel development)

Use `/cw-worktree` to develop multiple features simultaneously. Each worktree gets its own feature branch and **isolated task list** (via `.claude/settings.local.json`). Tasks persist in `~/.claude/tasks/{worktree-name}/`, enabling seamless resume across sessions. See [examples/workflows.md](examples/workflows.md) for the full multi-terminal walkthrough.

## Skills

| Skill | Purpose |
|-------|---------|
| `/cw-spec` | Generate structured specification with demoable units and proof artifacts |
| `/cw-plan` | Transform spec into native task graph with dependencies and metadata |
| `/cw-execute` | Execute one task using the 11-phase protocol (orient → commit → clean exit) |
| `/cw-dispatch` | Spawn parallel subagent workers for independent tasks (no setup required) |
| `/cw-dispatch-team` | Persistent agent team with lead coordination for parallel task execution |
| `/cw-validate` | Run 6 validation gates and produce a coverage matrix report |
| `/cw-review` | Review implementation for bugs, security issues, and quality; creates fix tasks |
| `/cw-testing` | E2E testing with auto-fix — generate tests from specs, execute, and fix failures |
| `/cw-worktree` | Manage git worktrees for multi-feature parallel development |

## Prerequisites

Shell scripts require `jq`. The `gh` CLI is needed for PR creation in `cw-pipeline`.

Most skills work out of the box. `/cw-dispatch-team` uses [Claude Code agent teams](https://code.claude.com/docs/en/agent-teams) which requires two env vars:

```json
// ~/.claude/settings.json (user-level) or .claude/settings.json (project-level)
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1",
    "CLAUDE_CODE_TASK_LIST_ID": "your-project-name"
  }
}
```

`/cw-dispatch` (subagent workers) needs no setup and is the recommended default. `/cw-plan` will offer both options after task graph creation.

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
  "verification": {
    "pre": ["npm run lint"],
    "post": ["npm test"]
  },
  "complexity": "standard"
}
```

## Shell Scripts

For autonomous (unattended) execution without an interactive Claude session:

| Script | Purpose |
|--------|---------|
| `cw-pipeline` | Full end-to-end: prompt → worktree → spec → plan → execute → validate → review → test → PR |
| `cw-init` | Generate spec + plan without executing |
| `cw-loop` | Autonomous task execution loop (sequential or parallel with `--dispatch`) |
| `cw-loop-interactive` | Human-in-the-loop execution with pause after each task |
| `cw-test-init` | Generate E2E test scenarios as `TEST-*` tasks |
| `cw-test-loop` | Execute tests with auto-fix cycles |
| `cw-status` | Check task progress (no Claude needed) |
| `cw-reset` | Reset failed or stuck tasks (no Claude needed) |

See [examples/shell-scripts.md](examples/shell-scripts.md) for detailed usage and flag combinations.

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CW_MODEL` | `sonnet` | Claude model for execution |
| `CW_MAX_ITERATIONS` | `50` | Max loop iterations |
| `CW_SLEEP` | `5` | Seconds between iterations |
| `CW_MAX_FAILURES` | `3` | Consecutive failures before abort |
| `CW_TIMEOUT` | `0` | Claude invocation timeout (0=none) |
| `CW_INVOKE_RETRIES` | `3` | Retries per Claude invocation |
| `CW_RETRY_DELAY` | `10` | Seconds between retries |
| `CW_NON_INTERACTIVE` | `false` | Skip confirmation prompts |
| `CW_VERBOSE` | `false` | Stream JSON output for real-time visibility |