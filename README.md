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

Each step can also be run independently. `/cw-execute` handles single-task execution for manual or shell-scripted loops.

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
| `/cw-dispatch` | Find independent tasks and spawn parallel agent workers |
| `/cw-validate` | Run 6 validation gates and produce a coverage matrix report |
| `/cw-worktree` | Manage git worktrees for multi-feature parallel development |
| `/cw-manifest` | Export task board state to JSON for shell-script orchestration |

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

## Execution Protocol (11 Phases)

The `/cw-execute` skill follows this protocol for each task:

| Phase | Name | Purpose |
|-------|------|---------|
| 1 | ORIENT | Read task board, identify assigned task |
| 2 | BASELINE | Verify codebase health before changes |
| 3 | CONTEXT | Read pattern files, understand conventions |
| 4 | IMPLEMENT | Create/modify files, write tests |
| 5 | VERIFY-LOCAL | Run lint and build |
| 6 | PROOF | Execute proof artifacts, capture evidence |
| 7 | SANITIZE | Remove credentials from proofs (blocking) |
| 8 | COMMIT | Atomic commit with implementation + proofs |
| 9 | VERIFY-FULL | Run full test suite |
| 10 | REPORT | Update task board with results |
| 11 | CLEAN EXIT | Verify git clean, output summary |

## Validation Gates

`/cw-validate` applies 6 mandatory gates:

| Gate | Rule |
|------|------|
| A | No CRITICAL or HIGH severity issues |
| B | No Unknown entries in coverage matrix |
| C | All proof artifacts accessible and functional |
| D | Changed files in declared scope or justified |
| E | Implementation follows repository standards |
| F | No real credentials in proof artifacts |

## Directory Structure

```
claude-workflow/
├── .claude-plugin/plugin.json        # Plugin registration
├── skills/
│   ├── cw-spec/SKILL.md             # Spec Writer
│   ├── cw-plan/                      # Architect
│   │   ├── SKILL.md
│   │   └── references/task-metadata-schema.md
│   ├── cw-execute/                   # Implementer
│   │   ├── SKILL.md
│   │   └── references/
│   │       ├── execution-protocol.md
│   │       └── proof-artifact-types.md
│   ├── cw-validate/                  # Validator
│   │   ├── SKILL.md
│   │   └── references/validation-gates.md
│   ├── cw-dispatch/SKILL.md         # Dispatcher
│   ├── cw-worktree/                  # Worktree Manager
│   │   ├── SKILL.md
│   │   └── references/worktree-lifecycle.md
│   └── cw-manifest/SKILL.md         # Manifest bridge
├── scripts/
│   ├── lib/cw-common.sh             # Shared shell utilities
│   ├── cw-loop                       # Autonomous execution
│   ├── cw-loop-interactive           # Human-in-the-loop
│   ├── cw-status                     # Progress display
│   └── cw-reset                      # Reset failed tasks
├── agents/                           # Swarms-ready agent definitions
│   ├── spec-writer.md
│   ├── architect.md
│   ├── implementer.md
│   └── validator.md
└── README.md
```
