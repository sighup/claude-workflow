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
| `/cw-execute` | Execute one task using the 11-step protocol (orient → commit → clean exit) |
| `/cw-dispatch` | Spawn parallel subagent workers for independent tasks (no setup required) |
| `/cw-dispatch-team` | Persistent agent team with lead coordination for parallel task execution |
| `/cw-validate` | Run 7 validation gates and produce a coverage matrix report |
| `/cw-review` | Review implementation for bugs, security issues, and quality; creates fix tasks |
| `/cw-review-team` | Concern-partitioned team review — each reviewer sees all files through a specialized lens (security, correctness, spec compliance) |
| `/cw-testing` | E2E testing with auto-fix — generate tests from specs, execute, and fix failures |
| `cw-gherkin` | Generate Gherkin BDD scenarios from spec acceptance criteria; called automatically by cw-spec |
| `/cw-worktree` | Manage git worktrees for multi-feature parallel development |

## Prerequisites

`jq` is required by the worktree hooks and `cw-status`. The `gh` CLI is needed for PR creation.

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

## Optional integrations

### herdr

[herdr](https://github.com/ogulcancelik/herdr) is a terminal-native agent multiplexer (Linux/macOS). When it is installed and running, `/cw-worktree create` will automatically open a Claude session in the new worktree's herdr pane instead of asking you to open a new terminal. `/cw-worktree open <name>` does the same retrospectively, focusing the existing pane if one already exists.

If herdr is not installed, not running, or you set `CW_DISABLE_HERDR=1`, every worktree command works exactly as before — the integration is silently skipped and the manual `cd ... && claude` instructions are printed instead. Nothing in the plugin requires herdr.

To give the in-pane Claude session full knowledge of herdr's CLI (workspaces, panes, `wait output`, etc.), install herdr's own skill into Claude Code after installing herdr:

```bash
herdr integration install claude
```

That skill is maintained by the herdr project (AGPL-3.0) and self-disables outside a herdr pane via the `HERDR_ENV=1` guard, so it stays out of your way on hosts without herdr.

### Frontier model routing (Claude Fable 5)

claude-workflow can route the thinking-heavy stages — research, spec, plan, and complex implementation tasks — to Claude Fable 5 (`claude-fable-5`) for higher capability on challenging problems. This is entirely optional and does not affect users who choose to stay on the default model ladder (Haiku → Sonnet → Opus).

**Decision protocol:** Frontier mode is decided with zero configuration required. At planning time, the system checks in this order: (1) if `CW_FABLE=on` or `CW_FABLE=off` is set in your environment, that takes precedence; (2) if the current session is already running Fable, frontier mode activates automatically; (3) otherwise, you are asked once ("Use Claude Fable 5 for frontier stages?") and the answer is saved to `.claude/settings.local.json` in your worktree. This decision is made only at plan time — dispatch and execution never prompt.

**Fallback guarantee:** If Fable becomes unavailable for any reason (org policy, credit exhaustion, API error, unknown model error), every affected stage falls back silently to Opus 4.8 and records the substitution (`model_requested` and `fallback_reason` in task metadata). Nothing in the workflow requires Fable — it is always optional, and your work completes uninterrupted.

**Cost:** Fable pricing is approximately 2× Opus; the tokenizer is ~30% heavier, so effective cost per task is roughly 2.6× Opus. Plan-provided Fable credits are available through 2026-06-22; after that, Fable usage is credit-metered. The `complex`-tier tasks and subagent spawns (planner, spec writer, research deep-dive) request Fable when frontier mode is on; trivial and standard tasks, review, validation, and testing remain on the default ladder.

**Advisor alternative:** If you prefer not to route full tasks to Fable, you can use Claude Code's native advisor tool to get Fable guidance at decision points while keeping the main session on a cheaper model. Set `"advisorModel": "fable"` in your `.claude/settings.json` (or use `--advisor fable` / `/advisor fable` in Claude), then frontier mode will use your chosen main model for execution. This requires Claude Code v2.1.170+ and Fable access. Note: `fable` is absent from the `/advisor` dropdown menu — you must pass it explicitly. A Fable main session accepts only a Fable advisor (complementary routing, not a replacement for per-task subagent `model` selection).

Nothing in the plugin requires Fable. The feature is fully backward-compatible: with `CW_FABLE=off` or when Fable is unavailable, behavior is identical to v2.13.0.

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

