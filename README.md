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

### Single Feature

```
/cw-spec  →  /cw-plan  →  /cw-dispatch  →  /cw-validate
```

Each step can also be run independently. `/cw-execute` handles single-task execution for manual or shell-scripted loops. Each step provides guidance to the next step.

### Multiple Features (Parallel Development)

Use git worktrees to develop multiple specs simultaneously. Each worktree is self-contained: one worktree = one spec + one implementation = one PR to main.

```
main ──────────────────────●── merge auth PR ──●── merge billing PR
                          /                   /
feature/auth ──●── spec ──●── impl ──────────┘
                                            /
feature/billing ──●── spec ──●── impl ─────┘
```

```bash
# MAIN SESSION (control center - keep running)
/cw-worktree create auth
/cw-worktree create billing
/cw-worktree list              # Check status anytime

# TERMINAL 1: auth feature
cd .worktrees/feature-auth && claude
/cw-spec auth         # Spec committed to feature branch
/cw-plan → /cw-dispatch → /cw-validate
gh pr create          # PR contains spec + implementation
exit

# TERMINAL 2 (concurrent): billing feature
cd .worktrees/feature-billing && claude
/cw-spec billing → /cw-plan → /cw-dispatch → /cw-validate
gh pr create
exit

# MAIN SESSION: cleanup after PRs merged
/cw-worktree cleanup
```

Keep the main session running as a **control center** to create, list, and cleanup worktrees. Open new terminals for each feature's development. Each worktree gets its own feature branch and **isolated task list** (via `.claude/settings.local.json` created automatically). Tasks persist in `~/.claude/tasks/{worktree-name}/`, enabling seamless resume across sessions.

## Skills

| Skill | Purpose |
|-------|---------|
| `/cw-spec` | Generate structured specification with demoable units and proof artifacts |
| `/cw-plan` | Transform spec into native task graph with dependencies and metadata |
| `/cw-execute` | Execute one task using the 11-phase protocol (orient → commit → clean exit) |
| `/cw-dispatch` | Spawn parallel subagent workers for independent tasks (no setup required) |
| `/cw-dispatch-team` | Persistent agent team with lead coordination for parallel task execution |
| `/cw-validate` | Run 6 validation gates and produce a coverage matrix report |
| `/cw-worktree` | Manage git worktrees for multi-feature parallel development |
| `/cw-manifest` | Export task board state to JSON for shell-script orchestration |

## Prerequisites

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

```bash
# Autonomous loop - executes tasks until complete or failure
./scripts/cw-loop                     # Quiet mode (default)
./scripts/cw-loop --verbose           # Stream output for visibility
./scripts/cw-loop --dispatch          # Use parallel task execution
./scripts/cw-loop -m opus -n 100      # Custom model and iterations

# Human-in-the-loop - pauses after each task for review
./scripts/cw-loop-interactive

# Check progress (reads manifest, no Claude needed)
./scripts/cw-status
./scripts/cw-status --list
./scripts/cw-status --pending

# Reset failed/stuck tasks
./scripts/cw-reset --all-failed
./scripts/cw-reset T01 T03
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CW_MODEL` | `sonnet` | Claude model for execution |
| `CW_MAX_ITERATIONS` | `50` | Max loop iterations |
| `CW_SLEEP` | `5` | Seconds between iterations |
| `CW_MAX_FAILURES` | `3` | Consecutive failures before abort |
| `CW_TIMEOUT` | `0` | Claude invocation timeout (0=none) |
| `CW_NON_INTERACTIVE` | `false` | Skip confirmation prompts |
| `CW_VERBOSE` | `false` | Stream JSON output for real-time visibility |