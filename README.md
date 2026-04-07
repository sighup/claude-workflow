# claude-workflow

A Claude Code plugin that unifies spec-driven development, autonomous task execution, and parallel agent dispatch into a single workflow. Takes a feature from idea to validated implementation using structured specifications, dependency-aware task graphs, and evidence-based verification. 

## Install

### From Git (recommended)

```bash
# Add the marketplace
claude plugin marketplace add https://github.com/sighup/claude-workflow.git

# Install the plugin
claude plugin install claude-workflow@claude-workflow
```

## Workflow

```
[/cw-research]  →  /cw-spec  →  [+/cw-gherkin]  →  /cw-plan  →  /cw-dispatch  →  /cw-validate
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
| `cw-gherkin` | Generate Gherkin BDD scenarios from spec acceptance criteria; opt-in via `--gherkin` on cw-spec, cw-init, or cw-pipeline |
| `/cw-worktree` | Manage git worktrees for multi-feature parallel development |

## Prerequisites

Shell scripts require `jq`. The `gh` CLI is needed for PR creation in `cw-pipeline`.

Most skills work out of the box. `/cw-dispatch-team` uses [Claude Code agent teams](https://code.claude.com/docs/en/agent-teams), which requires the experimental feature flag (user-level, applies to all projects):

```json
// ~/.claude/settings.json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

Team skills also require `CLAUDE_CODE_TASK_LIST_ID` so all teammates share one task list. `/cw-worktree create` sets this automatically in `.claude/settings.local.json`, and a PreToolUse hook will prompt you with setup instructions if you invoke a team skill without it.

`/cw-dispatch` (subagent workers) needs no setup and is the recommended default. `/cw-plan` will offer both options after task graph creation.

`/cw-testing` supports multiple backends. To use the `playwright-bdd` backend (Gherkin → Playwright, CI-friendly):

```bash
npm install --save-dev playwright-bdd @playwright/test
npx playwright install
```

## Task Metadata

Every task on the board carries self-contained metadata enabling autonomous execution. The following is an example of a typical task — a `standard`-complexity implementer task adding a login session endpoint:

```json
{
  "id": "412",
  "subject": "T03.1: Implement POST /api/sessions login handler",
  "description": "Add a POST /api/sessions route that accepts {email, password}, validates credentials against the users table via bcrypt.compare, and returns a signed JWT on success or 401 on failure.\n\nFollow the existing route handler pattern in src/routes/health.ts. Use the shared db client from src/lib/db.ts and the JWT_SECRET env var. Rate limiting is handled upstream by middleware and is out of scope.",
  "activeForm": "Implementing login session handler",
  "status": "pending",
  "blocks": ["415", "418"],
  "blockedBy": ["408"],
  "metadata": {
    "task_id": "T03.1",
    "parent_task": "T03",
    "demoable_unit": 3,
    "demoable_unit_title": "User authentication",
    "spec_path": "docs/specs/07-spec-auth-sessions/07-spec-auth-sessions.md",
    "scope": {
      "files_to_create": [
        "src/routes/sessions.ts",
        "src/routes/sessions.test.ts"
      ],
      "files_to_modify": [
        "src/routes/index.ts (register sessions router)"
      ],
      "patterns_to_follow": [
        "src/routes/health.ts",
        "src/lib/db.ts"
      ]
    },
    "requirements": [
      {
        "id": "R03.1.1",
        "text": "POST /api/sessions accepts JSON body {email, password}",
        "testable": true
      },
      {
        "id": "R03.1.2",
        "text": "Returns 200 + {token} on valid credentials, 401 on invalid",
        "testable": true
      },
      {
        "id": "R03.1.3",
        "text": "Token is a JWT signed with JWT_SECRET, expires in 24h",
        "testable": true
      }
    ],
    "proof_artifacts": [
      {
        "type": "test",
        "command": "npm test -- src/routes/sessions.test.ts",
        "expected": "All tests pass (valid login, invalid password, missing fields)",
        "capture_method": "auto"
      },
      {
        "type": "cli",
        "command": "curl -sX POST http://localhost:3000/api/sessions -H 'Content-Type: application/json' -d '{\"email\":\"demo@example.com\",\"password\":\"correcthorse\"}'",
        "expected": "200 response with {\"token\":\"<jwt>\"}",
        "capture_method": "auto"
      }
    ],
    "proof_capture": {
      "visual_method": "skip",
      "tool": null
    },
    "commit": {
      "template": "feat(auth): add POST /api/sessions login handler (T03.1)"
    },
    "verification": {
      "pre": ["npm run lint", "npm run typecheck"],
      "post": ["npm test", "npm run build"]
    },
    "role": "implementer",
    "complexity": "standard",
    "model": "sonnet",
    "proof_results": null,
    "completed_at": null
  }
}
```

See [skills/cw-plan/references/task-metadata-schema.md](skills/cw-plan/references/task-metadata-schema.md) for the full schema.

## Shell Scripts

Shell scripts in `bin/` are optional and enable autonomous (unattended) execution without an interactive Claude session — useful for CI pipelines or scripted workflows. All core functionality is available through the skills above. See [examples/shell-scripts.md](examples/shell-scripts.md) for usage and environment variable reference.