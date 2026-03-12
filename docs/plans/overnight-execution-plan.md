# Plan: Incorporate Overnight Execution into claude-workflow

## Background

### Night Watch CLI — Key Concepts to Adopt
[night-watch-cli](https://github.com/jonit-dev/night-watch-cli) is an async execution platform that queues scoped engineering work (PRDs or GitHub issues), executes them via AI agents overnight in isolated git worktrees, and opens PRs automatically. Key architectural ideas:

1. **Task Queue with Lifecycle States**: Draft → Ready → In Progress → Review → Done
2. **Cron-Based Scheduling**: `night-watch install` writes crontab entries; `night-watch run` executes one cycle
3. **Worktree Isolation**: Each task runs in its own git worktree to prevent conflicts
4. **Claim Files / Locking**: Prevents concurrent execution of the same PRD
5. **Provider Abstraction**: Supports Claude CLI and Codex with configurable env vars and fallback on rate limits
6. **Multi-Project Support**: Global job queue balances work across repos
7. **Notification System**: Webhooks (Telegram, etc.) for completion/failure events
8. **Execution Timeouts**: `NW_MAX_RUNTIME` / `NW_SESSION_MAX_RUNTIME` caps
9. **Dry-Run Mode**: Preview what would execute without doing it
10. **Auto-PR Creation**: Opens pull requests with generated code
11. **Doctor Command**: Validates provider detection and environment health
12. **Log Rotation & History**: Archived logs, execution history tracking

### claude-workflow — Current State
claude-workflow already has strong foundations that overlap with night-watch:
- **Worktree management** (`cw-worktree` skill, `bin/` scripts)
- **Task board** (native Claude Code task system with JSON persistence)
- **Autonomous execution loop** (`cw-loop`, `cw-pipeline`)
- **Parallel dispatch** (`cw-dispatch`, `cw-dispatch-team`)
- **Spec-driven workflow** (research → spec → plan → execute → validate → review → test)
- **Agent roles** (implementer, reviewer, bug-fixer, etc.)
- **Resumable pipeline** (checkpoint state in `.claude/pipeline-state.json`)

### What's Missing
claude-workflow currently requires a human to **start** execution (interactive or shell). It lacks:
1. **Scheduled/unattended triggering** (cron, systemd timer, or similar)
2. **Task queue intake** from external sources (GitHub issues, file drops)
3. **Execution locking** to prevent concurrent runs on the same feature
4. **Timeout enforcement** at the session/task level
5. **Health checks / doctor command** to verify environment readiness
6. **Execution history & log management**
7. **Rate-limit detection and provider fallback**
8. **Multi-project orchestration**

---

## Implementation Plan

### Phase 1: Queue System & Overnight Core

#### `bin/cw-queue` — Queue Management CLI
Manages a file-based queue supporting both prompt and spec intake.

```bash
# Add work items (both intake methods)
cw-queue add --prompt "Add JWT authentication" --name jwt-auth --priority 1
cw-queue add --spec docs/specs/03-spec-billing/03-spec-billing.md --priority 2
cw-queue add --github-issue 42                    # GitHub Issue intake
cw-queue add --github-label "overnight"           # Batch-queue all issues with label

# Manage queue
cw-queue list [--status pending|running|done|failed]
cw-queue cancel <id>
cw-queue retry <id>
cw-queue import-issues [--label overnight] [--repo owner/repo]  # Poll & queue labeled issues
```

- Queue items stored as individual JSON files in `docs/queue/` (configurable via `CW_OVERNIGHT_QUEUE_DIR`)
- Each item has: id, status, priority, type (prompt|spec|github-issue), source metadata
- GitHub Issue intake fetches issue title + body as the prompt, links back to issue number
- `import-issues` can be called standalone or as part of `cw-overnight` pre-flight

#### `bin/cw-overnight` — Main Overnight Runner
Wraps `cw-pipeline` with overnight-specific orchestration.

```bash
cw-overnight                        # Process queue for current project
cw-overnight --dry-run              # Preview what would execute
cw-overnight --projects ~/proj1 ~/proj2 ~/proj3   # Multi-project mode
cw-overnight --max-items 3          # Limit items per run
```

**Execution flow:**
1. Run `cw-doctor` pre-flight check (fail fast if environment is broken)
2. Import GitHub issues if `CW_GITHUB_INTAKE_LABEL` is set
3. Read queue directory, sort by priority
4. For each pending item (up to `CW_OVERNIGHT_MAX_ITEMS`):
   a. Acquire file lock (flock) for the item
   b. Update item status → `running`, record `started_at`
   c. Wrap execution in `timeout` (per `CW_SESSION_TIMEOUT`)
   d. Invoke `cw-pipeline --prompt "..." --name "..."` or `cw-pipeline --spec "..."`
   e. Capture exit code, stdout/stderr → structured JSON log
   f. Update item status → `done` or `failed`, record `completed_at`, `exit_code`, `pr_url`
   g. Release lock
5. Write summary to execution history log
6. In multi-project mode: iterate through `--projects` list, running steps 1-5 for each

**Multi-project mode:**
- Accepts `--projects <dir1> <dir2> ...` or reads from `CW_OVERNIGHT_PROJECTS` env var
- Changes working directory to each project, loads its queue, runs items
- Global execution timeout (`CW_OVERNIGHT_GLOBAL_TIMEOUT`) caps total runtime across all projects
- Round-robin or priority-based cross-project scheduling (configurable)

#### `bin/cw-install` — Cron/systemd Setup
```bash
cw-install cron [--schedule "0 2 * * *"]   # Install crontab entry
cw-install systemd                          # Generate systemd timer unit
cw-install uninstall                        # Remove scheduled entries
```

- Resolves full PATH for `claude`, `node`, `git`, `jq` in cron environment
- For multi-project: single cron entry with `--projects` flag
- Exports necessary env vars (`ANTHROPIC_API_KEY`, etc.) in crontab preamble

### Phase 2: Execution Safety & Reliability

#### `bin/lib/cw-lock.sh` — Locking Primitives
- File-based locking per queue item and per worktree
- Uses `flock` for atomic lock acquisition
- Stale lock detection: if lock holder PID is dead, auto-cleanup
- Prevents concurrent overnight + interactive conflicts on same feature

#### `bin/lib/cw-timeout.sh` — Timeout Enforcement
- Per-task timeout (default: 30min, configurable via `CW_TASK_TIMEOUT`)
- Per-session timeout (default: 4hr, configurable via `CW_SESSION_TIMEOUT`)
- Global overnight timeout (default: 8hr, configurable via `CW_OVERNIGHT_GLOBAL_TIMEOUT`)
- Graceful SIGTERM → 30s grace → SIGKILL escalation
- Timeout events logged with partial progress captured

#### `bin/lib/cw-ratelimit.sh` — Rate-Limit Detection
- Parse Claude CLI stderr for HTTP 429 / rate-limit patterns
- On detection: exponential backoff (30s, 60s, 120s, 240s)
- After max retries: mark item as `rate_limited`, move to next item
- Log rate-limit events for capacity planning

### Phase 3: Observability & Health

#### `bin/cw-doctor` — Environment Health Check
```bash
cw-doctor              # Full check
cw-doctor --quick      # Essential checks only
```

Checks:
- Claude CLI installed and authenticated (`claude --version`, test API call)
- Required tools present (`git`, `jq`, `flock`, `timeout`)
- Git repo is clean (no uncommitted changes that would block worktree creation)
- Disk space adequate (configurable threshold)
- Queue directory exists and is writable
- GitHub CLI (`gh`) available if GitHub intake is configured
- Network connectivity to GitHub API (if issue intake is enabled)

#### `bin/cw-history` — Execution History
```bash
cw-history list [--last N]              # Recent runs
cw-history show <run-id>                # Detailed run report
cw-history clean [--older-than 30d]     # Prune old logs
```

- Structured JSON log entries per execution run in `logs/overnight/`
- Each run gets a directory: `logs/overnight/YYYYMMDD-HHMMSS-<name>/`
  - `run.json` — metadata (items processed, timing, exit codes, PR URLs)
  - `stdout.log` — captured output
  - `stderr.log` — captured errors
- Log rotation: archive runs older than `CW_HISTORY_RETENTION_DAYS` (default: 30)
- Summary view shows: date, items processed, success/fail count, total duration, PR links

#### `bin/cw-status` Enhancement
Add overnight context to the existing status command:
- Show pending queue items count and next scheduled run
- Show active locks and running overnight sessions
- Show last execution result summary (pass/fail, duration, PRs created)

### Phase 4: GitHub Issue Intake

#### Issue Polling & Auto-Queue
```bash
# One-shot import
cw-queue import-issues --label overnight --repo owner/repo

# Auto-import as part of overnight run (configured via env)
CW_GITHUB_INTAKE_LABEL="overnight"
CW_GITHUB_INTAKE_REPO="owner/repo"    # defaults to current repo
```

**Flow:**
1. `gh issue list --label overnight --state open --json number,title,body`
2. For each issue not already in queue:
   - Create queue item with `type: "github-issue"`, `source: "github#42"`
   - Use issue title as `name`, issue body as `prompt`
3. On successful PR creation:
   - Comment on the issue with link to PR
   - Optionally close the issue or remove the label (configurable)

**Issue body conventions:**
- If issue body contains `## Spec` section → extract and use as spec input
- If issue body contains `## Prompt` section → extract and use as prompt
- Otherwise → use full body as prompt

---

## File Structure (New/Modified)

```
bin/
├── cw-overnight          # NEW — Main overnight execution runner
├── cw-queue              # NEW — Queue management CLI
├── cw-install            # NEW — Cron/systemd installer
├── cw-doctor             # NEW — Environment health checker
├── cw-history            # NEW — Execution history viewer
├── cw-status             # MODIFY — Add queue/overnight status
├── lib/
│   ├── cw-common.sh      # MODIFY — Add shared queue/lock helpers
│   ├── cw-lock.sh        # NEW — Locking primitives
│   ├── cw-timeout.sh     # NEW — Timeout enforcement
│   └── cw-ratelimit.sh   # NEW — Rate-limit detection & backoff
docs/
├── queue/                # NEW — Queue directory for pending work items
│   └── .gitkeep
logs/
├── overnight/            # NEW — Overnight execution logs
│   └── .gitkeep
```

## Configuration (Environment Variables)

```bash
# Overnight execution
CW_OVERNIGHT_QUEUE_DIR="docs/queue"           # Queue directory path
CW_OVERNIGHT_LOG_DIR="logs/overnight"         # Log output directory
CW_OVERNIGHT_SCHEDULE="0 2 * * *"             # Default cron schedule (2 AM daily)
CW_OVERNIGHT_DRY_RUN=false                    # Preview mode
CW_OVERNIGHT_MAX_ITEMS=5                      # Max queue items per run
CW_OVERNIGHT_LOCK_DIR="/tmp/cw-locks"         # Lock file directory

# Multi-project
CW_OVERNIGHT_PROJECTS=""                      # Space-separated project dirs
CW_OVERNIGHT_GLOBAL_TIMEOUT=28800             # Global timeout (seconds, default 8hr)
CW_OVERNIGHT_PROJECT_STRATEGY="priority"      # "priority" or "round-robin"

# Timeouts
CW_TASK_TIMEOUT=1800                          # Per-task timeout (seconds, default 30min)
CW_SESSION_TIMEOUT=14400                      # Per-session timeout (seconds, default 4hr)

# GitHub Issue intake
CW_GITHUB_INTAKE_LABEL="overnight"            # Label to watch (empty = disabled)
CW_GITHUB_INTAKE_REPO=""                      # owner/repo (empty = current repo)
CW_GITHUB_INTAKE_CLOSE_ON_PR=false            # Close issue when PR is created
CW_GITHUB_INTAKE_REMOVE_LABEL_ON_PR=true      # Remove label when PR is created

# History
CW_HISTORY_RETENTION_DAYS=30                  # Auto-prune logs older than this

# Execution
CW_OVERNIGHT_RATELIMIT_MAX_RETRIES=4          # Max retries on rate limit
CW_OVERNIGHT_RATELIMIT_BASE_DELAY=30          # Base backoff delay (seconds)
```

## Queue Item Format

```json
{
  "id": "20260312-001",
  "created_at": "2026-03-12T22:00:00Z",
  "status": "pending",
  "priority": 5,
  "type": "prompt",
  "source": "manual",
  "prompt": "Add JWT authentication with refresh tokens",
  "name": "jwt-auth",
  "spec_path": null,
  "github_issue": null,
  "project_dir": "/home/user/my-project",
  "worktree": null,
  "started_at": null,
  "completed_at": null,
  "exit_code": null,
  "pr_url": null,
  "log_dir": null,
  "rate_limit_retries": 0
}
```

For GitHub Issue intake:
```json
{
  "id": "20260312-002",
  "type": "github-issue",
  "source": "github#42",
  "prompt": "Full issue body extracted here...",
  "name": "issue-42-add-dark-mode",
  "github_issue": {
    "number": 42,
    "repo": "owner/repo",
    "title": "Add dark mode toggle",
    "url": "https://github.com/owner/repo/issues/42"
  }
}
```

## Typical Workflows

### Basic Overnight Run
```bash
# During the day — queue work
cw-queue add --prompt "Add JWT authentication" --name jwt-auth --priority 1
cw-queue add --spec docs/specs/03-spec-billing/03-spec-billing.md --priority 2

# Install cron (one-time)
cw-install cron --schedule "0 2 * * *"

# At 2 AM — cw-overnight runs automatically
# Next morning — review results
cw-history list --last 3
cw-queue list --status done
```

### GitHub Issue-Driven
```bash
# Label issues "overnight" in your GitHub repo
# Configure intake
export CW_GITHUB_INTAKE_LABEL="overnight"

# cw-overnight auto-imports labeled issues, processes them, opens PRs,
# and comments on the original issues with PR links
```

### Multi-Project Overnight
```bash
# Single cron entry covers all projects
cw-install cron --schedule "0 1 * * *" \
  --projects ~/work/api ~/work/frontend ~/work/infra

# Or via env var
export CW_OVERNIGHT_PROJECTS="~/work/api ~/work/frontend ~/work/infra"
cw-overnight  # processes queues across all three repos
```

### Manual Test Run
```bash
cw-doctor                    # Verify environment
cw-overnight --dry-run       # Preview what would run
cw-overnight --max-items 1   # Run just one item to test
```

---

## Design Principles

1. **Bash-native**: Consistent with existing claude-workflow architecture (pure shell scripts)
2. **Composable**: Each script is independently useful; `cw-overnight` composes them
3. **Non-destructive**: Dry-run support everywhere; worktree isolation prevents main branch conflicts
4. **Minimal dependencies**: Only requires what claude-workflow already needs (bash, jq, git, claude) plus `gh` for GitHub intake
5. **Backward-compatible**: All existing workflows continue to work unchanged
6. **Night-watch-inspired, not copied**: Adapts the best ideas (queue, cron, locking, multi-project, issue intake) to claude-workflow's existing architecture rather than porting TypeScript code
7. **Log-based observability**: Structured JSON logs and `cw-history` for reviewing results — no external notification dependencies
8. **Multi-project from day one**: Global orchestration across repos via a single cron entry

## Implementation Order

1. `bin/lib/cw-lock.sh` + `bin/lib/cw-timeout.sh` — Foundation primitives
2. `bin/cw-queue` — Queue management (add, list, cancel, retry)
3. `bin/cw-overnight` — Core overnight runner (single-project first)
4. `bin/cw-doctor` — Health checks
5. `bin/cw-history` + logging infrastructure — Observability
6. `bin/cw-install` — Cron/systemd setup
7. Multi-project support in `cw-overnight`
8. `bin/lib/cw-ratelimit.sh` — Rate-limit detection
9. GitHub Issue intake (`cw-queue import-issues`, auto-import in `cw-overnight`)
10. `bin/cw-status` enhancement — Unified status view
