# claude-workflow

A Claude Code plugin that unifies spec-driven development, autonomous task execution, and parallel agent dispatch into a single workflow. Takes a feature from idea to validated implementation using structured specifications, dependency-aware task graphs, and evidence-based verification.

## Install

Add the plugin to your Claude Code project:

```bash
claude plugins add /path/to/claude-workflow
```

Or add it globally in `~/.claude/plugins.json`.

## Workflow

```
/cw-spec  →  /cw-plan  →  /cw-dispatch  →  /cw-validate
  idea        task graph    parallel exec     verification
```

1. **`/cw-spec`** - Define what to build (spec with demoable units + proof artifacts)
2. **`/cw-plan`** - Break spec into a dependency-aware task graph on the native task board
3. **`/cw-dispatch`** - Spawn parallel agents to execute independent tasks concurrently
4. **`/cw-validate`** - Verify implementation against spec using 6 gates + coverage matrix

Each step can also be run independently. `/cw-execute` handles single-task execution for manual or shell-scripted loops.

## Skills

| Skill | Purpose |
|-------|---------|
| `/cw-spec` | Generate structured specification with demoable units and proof artifacts |
| `/cw-plan` | Transform spec into native task graph with dependencies and metadata |
| `/cw-execute` | Execute one task using the 11-phase protocol (orient → commit → clean exit) |
| `/cw-dispatch` | Find independent tasks and spawn parallel agent workers |
| `/cw-validate` | Run 6 validation gates and produce a coverage matrix report |
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

## Parallel Dispatch

`/cw-dispatch` identifies independent tasks (no mutual dependencies, no file conflicts) and spawns workers concurrently:

- Model selected by complexity: `trivial` → haiku, `standard` → sonnet, `complex` → opus
- Max 3 parallel workers per batch
- File conflict detection prevents parallel tasks from touching the same files

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

## Swarms Readiness

The plugin is designed to map directly to Claude Code's upcoming Swarms feature. The `agents/` directory defines worker roles that a team lead agent can spawn. The native task board (TaskCreate/TaskUpdate/TaskList) serves as the shared coordination layer in both modes:

| Today | Swarms |
|-------|--------|
| User invokes `/cw-dispatch` | Lead agent delegates autonomously |
| Task tool spawns subagents | Workers spawned natively |
| Dependencies via addBlockedBy | Same mechanism |
| Shell scripts orchestrate loops | Lead handles iteration |
