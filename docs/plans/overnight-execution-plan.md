# Plan: Unified TypeScript CLI for claude-workflow

## Overview

Replace all existing bash scripts (`bin/cw-loop`, `cw-pipeline`, `cw-status`, etc.) with a **single TypeScript CLI** (`cw`) that combines existing functionality with new overnight execution features. Built with Commander.js, bundled with esbuild into a single executable.

## Background

### Night Watch CLI — Key Concepts to Adopt
[night-watch-cli](https://github.com/jonit-dev/night-watch-cli) is an async execution platform that queues scoped engineering work (PRDs or GitHub issues), executes them via AI agents overnight in isolated git worktrees, and opens PRs automatically. Key ideas we're adopting:

1. **Task Queue with Lifecycle States**: pending → running → done/failed
2. **Cron-Based Scheduling**: install crontab entries; run executes one cycle
3. **Worktree Isolation**: each task in its own git worktree
4. **File Locking**: prevents concurrent execution of same work item
5. **Multi-Project Support**: global job queue across repos
6. **Execution Timeouts**: per-task and per-session caps
7. **Dry-Run Mode**: preview without executing
8. **Auto-PR Creation**: opens PRs with generated code
9. **Doctor Command**: validates environment health
10. **GitHub Issue Intake**: auto-queue labeled issues
11. **Execution History**: structured logs with retention

### What Exists Today (Bash)
- `bin/cw-loop` — autonomous sequential/dispatch execution loop
- `bin/cw-init` — spec + plan generation
- `bin/cw-pipeline` — 9-stage end-to-end orchestrator (worktree → spec → plan → execute → validate → review → test → revalidate → PR)
- `bin/cw-status` — task board display
- `bin/cw-test-loop` — test execution with auto-fix cycles
- `bin/cw-test-init` — test scenario generation
- `bin/cw-loop-interactive` — human-in-the-loop execution
- `bin/lib/cw-common.sh` — shared utilities (~1000 lines)

### Why TypeScript

| Concern | Bash (today) | TypeScript (proposed) |
|---------|-------------|----------------------|
| JSON handling | Shell out to `jq` for every operation | Native `JSON.parse/stringify`, typed interfaces |
| Error handling | Exit codes + string matching on stderr | try/catch, typed errors, structured results |
| Concurrency | Background processes + PID files + polling | `Promise.all`, `child_process` with streams |
| Code reuse | `source` scripts, global functions | Imports, classes, dependency injection |
| Testing | None | Vitest with mocks for Claude CLI + filesystem |
| Type safety | None | Full TypeScript interfaces for task schema, queue items, config |
| Single binary | 8 separate scripts + shared lib | One `cw` command with subcommands |
| Maintainability | Complex quoting, indirect expansion | Standard programming patterns |

---

## Architecture

### Single CLI: `cw`

```
cw <command> [subcommand] [options]
```

All existing bash scripts become subcommands of a unified `cw` CLI:

```
cw loop          # was: cw-loop
cw init          # was: cw-init
cw pipeline      # was: cw-pipeline
cw status        # was: cw-status
cw test-loop     # was: cw-test-loop
cw test-init     # was: cw-test-init
cw interactive   # was: cw-loop-interactive

# New overnight commands
cw queue add     # queue work items
cw queue list    # view queue
cw queue cancel  # cancel item
cw queue retry   # retry failed item
cw queue import  # import GitHub issues
cw overnight     # run overnight execution cycle
cw install       # set up cron/systemd
cw doctor        # environment health check
cw history       # execution history viewer
```

### Project Structure

```
cli/
├── package.json
├── tsconfig.json
├── esbuild.config.ts              # Bundle to single file
├── vitest.config.ts
├── src/
│   ├── index.ts                   # Entry point, Commander program setup
│   ├── commands/
│   │   ├── loop.ts                # Port of cw-loop
│   │   ├── init.ts                # Port of cw-init
│   │   ├── pipeline.ts            # Port of cw-pipeline
│   │   ├── status.ts              # Port of cw-status (+ overnight status)
│   │   ├── test-loop.ts           # Port of cw-test-loop
│   │   ├── test-init.ts           # Port of cw-test-init
│   │   ├── interactive.ts         # Port of cw-loop-interactive
│   │   ├── queue.ts               # NEW: queue management
│   │   ├── overnight.ts           # NEW: overnight runner
│   │   ├── install.ts             # NEW: cron/systemd setup
│   │   ├── doctor.ts              # NEW: health checks
│   │   └── history.ts             # NEW: execution history
│   ├── core/
│   │   ├── claude.ts              # Claude CLI invocation (spawn, retry, error detection)
│   │   ├── tasks.ts               # Task file read/write/query (replaces jq operations)
│   │   ├── session.ts             # Session/task-list discovery
│   │   ├── worktree.ts            # Git worktree management
│   │   ├── pipeline-state.ts      # Pipeline checkpoint/resume
│   │   ├── lock.ts                # File locking (flock wrapper)
│   │   ├── timeout.ts             # Timeout enforcement with signal escalation
│   │   ├── rate-limit.ts          # Rate-limit detection & backoff
│   │   ├── queue-store.ts         # Queue item CRUD (JSON files)
│   │   ├── history-store.ts       # Execution history log management
│   │   └── github.ts              # GitHub issue intake (via gh CLI)
│   ├── util/
│   │   ├── logger.ts              # Color logging (chalk)
│   │   ├── config.ts              # Env var loading with defaults
│   │   ├── process.ts             # Child process helpers
│   │   └── fs.ts                  # File system helpers
│   └── types/
│       ├── task.ts                # Task schema interfaces
│       ├── queue.ts               # Queue item interfaces
│       ├── config.ts              # Configuration interfaces
│       └── pipeline.ts            # Pipeline state interfaces
├── tests/
│   ├── commands/                  # Command-level integration tests
│   ├── core/                      # Core module unit tests
│   └── fixtures/                  # Test data (task files, queue items)
└── dist/
    └── cw.js                      # Single bundled output (esbuild)
```

### Tech Stack

| Layer | Choice |
|-------|--------|
| Language | TypeScript (strict mode) |
| CLI Framework | Commander.js |
| Build | esbuild (single-file bundle) |
| Test | Vitest |
| Process spawning | `child_process.spawn` (for `claude` CLI) |
| Terminal colors | chalk |
| Node version | >= 20 |

### How Claude CLI is Invoked

Same pattern as today's bash scripts — spawn the `claude` CLI process:

```typescript
// core/claude.ts
export async function invokeClaude(opts: {
  prompt: string;
  model?: string;
  sessionId?: string;
  verbose?: boolean;
  timeout?: number;
  cwd?: string;
}): Promise<{ exitCode: number; stdout: string; stderr: string }> {
  const args = ['--print', '--model', opts.model ?? 'sonnet',
                '--dangerously-skip-permissions'];
  if (opts.sessionId) args.push('--resume', opts.sessionId);
  if (opts.verbose) args.push('--verbose', '--output-format', 'stream-json');

  // Retry with exponential backoff
  for (let attempt = 1; attempt <= config.invokeRetries; attempt++) {
    const result = await spawnWithTimeout('claude', args, {
      stdin: opts.prompt,
      timeout: opts.timeout,
      cwd: opts.cwd,
    });
    if (result.exitCode === 0) return result;
    if (isRateLimited(result.stderr)) throw new RateLimitError(result.stderr);
    if (attempt < config.invokeRetries) {
      await sleep(config.retryDelay * attempt * 1000);
    }
  }
  throw new MaxRetriesError();
}
```

---

## Command Specifications

### Ported Commands (1:1 behavior parity with bash)

#### `cw loop [project-path]`
Port of `cw-loop`. Reads task board, executes pending tasks in a loop.

```
Options:
  -m, --model <model>      Claude model (default: CW_MODEL or "sonnet")
  -n, --max-iter <n>       Max iterations (default: 50)
  -s, --sleep <n>          Seconds between iterations (default: 5)
  -d, --dispatch           Use parallel dispatch (cw-dispatch skill)
  -v, --verbose            Stream JSON output
```

#### `cw init`
Port of `cw-init`. Two-phase: spec generation → plan generation.

```
Options:
  --prompt <text>          Generate spec from prompt
  --spec <path>            Use existing spec file
  -m, --model <model>      Claude model
  -v, --verbose            Stream JSON output
```

#### `cw pipeline`
Port of `cw-pipeline`. 9-stage orchestrator.

```
Options:
  --prompt <text>          Feature description
  --spec <path>            Use existing spec
  --name <name>            Feature name (for worktree/branch)
  --feature <spec>         Multi-feature mode (repeatable)
  --resume                 Resume from checkpoint
  --from <n>               Force resume from stage N
  --no-worktree            Skip worktree creation
  --no-test                Skip test phases
  --no-review              Skip code review
  --no-pr                  Skip PR creation
  --auto-pr                Create PR without pause
  -m, --model <model>      Claude model
  -v, --verbose            Stream JSON output
```

#### `cw status [project-path]`
Port of `cw-status` plus overnight queue context.

```
Options:
  -l, --list               Show full task list
  -f, --failed             Show only failed tasks
  -p, --pending            Show only pending tasks
  -j, --json               Output JSON
  -q, --queue              Show overnight queue status
```

#### `cw test-loop [project-path]`
Port of `cw-test-loop`. Dual-loop test execution with auto-fix.

```
Options:
  -c, --max-cycles <n>     Max fix cycles (default: 3)
  -n, --max-iter <n>       Max iterations per cycle
  -m, --model <model>      Claude model
  -s, --sleep <n>          Sleep between iterations
  -v, --verbose            Stream JSON output
```

#### `cw test-init`
Port of `cw-test-init`. Generate test scenarios.

```
Options:
  --prompt <text>          Generate from description
  --spec <path>            Generate from spec
  -m, --model <model>      Claude model
  -v, --verbose            Stream JSON output
```

#### `cw interactive [project-path]`
Port of `cw-loop-interactive`. Human-in-the-loop with menu after each task.

```
Options:
  -m, --model <model>      Claude model
```

### New Commands

#### `cw queue add`
Add work items to the overnight queue.

```
Options:
  --prompt <text>          Free-text prompt to spec + implement
  --spec <path>            Pre-existing spec file
  --github-issue <number>  GitHub issue number
  --github-label <label>   Batch-queue all open issues with label
  --name <name>            Feature name (auto-generated if omitted)
  --priority <n>           Priority 1-10 (default: 5, lower = higher priority)
  --project <dir>          Project directory (default: cwd)
```

#### `cw queue list`
```
Options:
  --status <s>             Filter: pending|running|done|failed|rate_limited
  -j, --json               Output JSON
```

#### `cw queue cancel <id>`
Remove item from queue (only if pending).

#### `cw queue retry <id>`
Reset a failed/rate_limited item to pending.

#### `cw queue import`
Import GitHub issues into the queue.

```
Options:
  --label <label>          Required. GitHub label to filter by.
  --repo <owner/repo>      Repository (default: current repo from git remote)
```

**Issue body parsing:**
- `## Spec` section → extract as spec input
- `## Prompt` section → extract as prompt
- Otherwise → full body as prompt

**Post-PR actions (configurable):**
- Comment on issue with PR link
- Remove label (`CW_GITHUB_INTAKE_REMOVE_LABEL_ON_PR`)
- Close issue (`CW_GITHUB_INTAKE_CLOSE_ON_PR`)

#### `cw overnight`
Main overnight execution runner.

```
Options:
  --dry-run                Preview what would execute
  --max-items <n>          Max items per run (default: 5)
  --projects <dirs...>     Multi-project mode (space-separated dirs)
  --strategy <s>           Multi-project strategy: "priority" | "round-robin"
```

**Execution flow:**
1. `cw doctor --quick` pre-flight
2. Import GitHub issues if `CW_GITHUB_INTAKE_LABEL` is set
3. Load queue, sort by priority
4. For each pending item (up to max):
   a. Acquire file lock
   b. Status → `running`
   c. Spawn `cw pipeline` with timeout
   d. Capture result → structured JSON log
   e. Status → `done` or `failed`
   f. Release lock
5. Write execution summary to history
6. Multi-project: iterate `--projects`, run steps 1-5 per project

**Multi-project mode:**
- Reads `--projects` or `CW_OVERNIGHT_PROJECTS` env var
- Global timeout (`CW_OVERNIGHT_GLOBAL_TIMEOUT`, default 8hr) caps total runtime
- `priority`: process all items across projects sorted by priority
- `round-robin`: one item from each project in rotation

#### `cw install`
Set up scheduled execution.

```
Subcommands:
  cw install cron [--schedule "0 2 * * *"]
  cw install systemd
  cw install uninstall
```

- Resolves full PATH for `claude`, `node`, `git` in cron environment
- Multi-project: single cron entry with `--projects`
- Exports required env vars in crontab preamble

#### `cw doctor`
Environment health check.

```
Options:
  --quick                  Essential checks only
  --fix                    Auto-fix what can be fixed (create dirs, etc.)
```

**Checks:**
- `claude` CLI installed and authenticated
- `git` available, repo is clean
- `gh` CLI available (if GitHub intake configured)
- Node.js version >= 20
- Queue directory exists and is writable
- Disk space above threshold
- GitHub API reachable (if intake enabled)

#### `cw history`
Execution history viewer.

```
Subcommands:
  cw history list [--last N]
  cw history show <run-id>
  cw history clean [--older-than 30d]
```

- Structured JSON logs in `logs/overnight/YYYYMMDD-HHMMSS-<name>/`
- Each run: `run.json` (metadata), `stdout.log`, `stderr.log`
- Auto-prune based on `CW_HISTORY_RETENTION_DAYS` (default: 30)

---

## Core Module Details

### `core/tasks.ts` — Task File Operations
Replaces all `jq` operations with native TypeScript:

```typescript
interface Task {
  id: string;
  subject: string;
  status: 'pending' | 'in_progress' | 'completed' | 'failed';
  blocks?: string[];
  metadata?: {
    failure_count?: number;
    fix_task_id?: string;
    test_status?: string;
    test_type?: string;
    test_suite?: boolean;
  };
}

class TaskStore {
  constructor(private tasksDir: string) {}

  getAll(): Task[]
  getPendingUnblocked(): Task[]
  getNextTaskId(): string | null
  isComplete(): boolean
  getCounts(): { total: number; completed: number; pending: number; in_progress: number; failed: number }
  getTestTasks(): Task[]
  getPendingFixTasks(): Task[]
}
```

### `core/queue-store.ts` — Queue Item CRUD

```typescript
interface QueueItem {
  id: string;
  created_at: string;
  status: 'pending' | 'running' | 'done' | 'failed' | 'rate_limited' | 'cancelled';
  priority: number;
  type: 'prompt' | 'spec' | 'github-issue';
  source: string;
  prompt?: string;
  name: string;
  spec_path?: string;
  github_issue?: { number: number; repo: string; title: string; url: string };
  project_dir: string;
  worktree?: string;
  started_at?: string;
  completed_at?: string;
  exit_code?: number;
  pr_url?: string;
  log_dir?: string;
  rate_limit_retries: number;
}

class QueueStore {
  constructor(private queueDir: string) {}

  add(item: Omit<QueueItem, 'id' | 'created_at'>): QueueItem
  list(filter?: { status?: string }): QueueItem[]
  get(id: string): QueueItem | null
  update(id: string, patch: Partial<QueueItem>): void
  cancel(id: string): void
  retry(id: string): void
  getNextPending(): QueueItem | null
}
```

### `core/lock.ts` — File Locking

```typescript
class FileLock {
  acquire(lockPath: string, opts?: { timeout?: number }): Promise<LockHandle>
  release(handle: LockHandle): void
  isStale(lockPath: string): boolean  // Check if holder PID is alive
  cleanup(lockPath: string): void
}
```

### `core/session.ts` — Session Discovery
Port of `discover_session()`:
1. Check `CLAUDE_CODE_TASK_LIST_ID` env → `~/.claude/tasks/$ID/`
2. Fallback: `~/.claude/projects/ENCODED_PATH/sessions-index.json`
3. Returns: `{ sessionId, taskListId, tasksDir }`

### `core/pipeline-state.ts` — Pipeline Checkpoint/Resume
Port of pipeline state management:

```typescript
interface PipelineState {
  feature_name: string;
  mode: 'prompt' | 'spec' | 'auto';
  value: string;
  flags: { noWorktree?: boolean; noTest?: boolean; noReview?: boolean; noPr?: boolean; autoPr?: boolean };
  stages: Record<string, { status: 'pending' | 'completed' | 'skipped' | 'failed'; timestamp?: string }>;
}

class PipelineStateManager {
  init(workDir: string, state: PipelineState): void
  checkpoint(workDir: string, stage: number, status: string): void
  getResumeStage(workDir: string): number | 'done'
  exists(workDir: string): boolean
  readFlags(workDir: string): PipelineState['flags']
}
```

---

## Configuration

All existing env vars remain supported for backward compatibility. New env vars added:

```bash
# Existing (unchanged)
CW_MODEL="sonnet"                             # Claude model
CW_TIMEOUT=0                                  # Claude invocation timeout
CW_SLEEP=5                                    # Sleep between iterations
CW_MAX_ITERATIONS=50                          # Max loop iterations
CW_MAX_FAILURES=3                             # Max consecutive failures
CW_INVOKE_RETRIES=3                           # Retry attempts per invocation
CW_RETRY_DELAY=10                             # Base retry delay (seconds)
CW_VERBOSE=false                              # Stream JSON output
CW_NON_INTERACTIVE=false                      # Skip confirmation prompts

# New: Overnight execution
CW_OVERNIGHT_QUEUE_DIR="docs/queue"           # Queue directory
CW_OVERNIGHT_LOG_DIR="logs/overnight"         # Log output directory
CW_OVERNIGHT_SCHEDULE="0 2 * * *"             # Default cron schedule
CW_OVERNIGHT_MAX_ITEMS=5                      # Max items per run
CW_OVERNIGHT_LOCK_DIR="/tmp/cw-locks"         # Lock file directory

# New: Multi-project
CW_OVERNIGHT_PROJECTS=""                      # Space-separated project dirs
CW_OVERNIGHT_GLOBAL_TIMEOUT=28800             # Global timeout (8hr)
CW_OVERNIGHT_PROJECT_STRATEGY="priority"      # "priority" or "round-robin"

# New: Timeouts
CW_TASK_TIMEOUT=1800                          # Per-task timeout (30min)
CW_SESSION_TIMEOUT=14400                      # Per-session timeout (4hr)

# New: GitHub Issue intake
CW_GITHUB_INTAKE_LABEL=""                     # Label to watch (empty = disabled)
CW_GITHUB_INTAKE_REPO=""                      # owner/repo (empty = current repo)
CW_GITHUB_INTAKE_CLOSE_ON_PR=false            # Close issue when PR created
CW_GITHUB_INTAKE_REMOVE_LABEL_ON_PR=true      # Remove label when PR created

# New: Rate limiting
CW_RATELIMIT_MAX_RETRIES=4                    # Max retries on rate limit
CW_RATELIMIT_BASE_DELAY=30                    # Base backoff (seconds)

# New: History
CW_HISTORY_RETENTION_DAYS=30                  # Auto-prune threshold
```

---

## Migration Strategy

The bash scripts and TypeScript CLI will coexist during migration:

1. **Phase 0**: Scaffold the TS project, set up build pipeline
2. **Phase 1**: Port `core/` modules (tasks, session, claude invocation, worktree, pipeline-state)
3. **Phase 2**: Port existing commands (loop, init, pipeline, status, test-loop, test-init, interactive)
4. **Phase 3**: Add new commands (queue, overnight, doctor, history, install)
5. **Phase 4**: Add GitHub issue intake
6. **Phase 5**: Add multi-project support
7. **Phase 6**: Tests, docs, deprecate bash scripts

The old bash scripts remain functional throughout. The `cw` binary is added alongside them. Once parity is confirmed, a deprecation notice is added to the bash scripts pointing users to `cw`.

---

## Implementation Order

1. **Scaffold**: `package.json`, `tsconfig.json`, esbuild config, Commander entry point
2. **Core utilities**: `logger.ts`, `config.ts`, `process.ts`, `fs.ts`
3. **Core modules**: `claude.ts`, `tasks.ts`, `session.ts`, `worktree.ts`
4. **`cw status`**: Simplest command, validates core modules work
5. **`cw loop`**: Main execution loop
6. **`cw init`**: Spec + plan generation
7. **`cw pipeline`** + `pipeline-state.ts`: Full orchestrator with resume
8. **`cw test-init`** + **`cw test-loop`**: Test commands
9. **`cw interactive`**: Human-in-the-loop
10. **`cw doctor`**: Health checks
11. **`core/lock.ts`** + **`core/timeout.ts`** + **`core/rate-limit.ts`**: Safety primitives
12. **`core/queue-store.ts`** + **`cw queue`**: Queue management
13. **`core/history-store.ts`** + **`cw history`**: Execution history
14. **`cw overnight`**: Overnight runner
15. **`core/github.ts`** + **`cw queue import`**: GitHub issue intake
16. **`cw install`**: Cron/systemd setup
17. **Multi-project support** in `cw overnight`
18. **Tests**: Unit tests for core, integration tests for commands

## Design Principles

1. **Single binary**: One `cw` command replaces 8 scripts
2. **Type-safe**: Full TypeScript interfaces for tasks, queue items, config, pipeline state
3. **Native JSON**: No `jq` dependency — direct `JSON.parse/stringify`
4. **Same invocation model**: Still spawns `claude` CLI (no SDK dependency)
5. **Env var compatible**: All existing `CW_*` env vars work unchanged
6. **Flag compatible**: Same CLI flags as bash scripts for drop-in replacement
7. **Non-destructive**: Dry-run everywhere, worktree isolation, file locking
8. **Testable**: Core modules are pure functions/classes, mockable CLI invocations
9. **Log-based observability**: Structured JSON logs, `cw history` for review
10. **Multi-project from day one**: Cross-repo orchestration via single cron entry
