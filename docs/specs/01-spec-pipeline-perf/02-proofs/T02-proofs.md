# T02 Proof Summary: Adopt CLAUDE_PLUGIN_DATA for execution logs

**Task**: T02 — Move pipeline execution logs from /tmp/ to ${CLAUDE_PLUGIN_DATA}/logs/

## Artifacts

| File | Type | Status |
|------|------|--------|
| T02-01-cli.txt | cli | PASS |
| T02-02-cli.txt | cli | PASS |
| T02-03-cli.txt | cli | PASS |

## Changes Implemented

1. **`scripts/plugin-data-init.sh`** (new) — idempotent helper: creates `${CLAUDE_PLUGIN_DATA}/logs/`, exits non-zero if `CLAUDE_PLUGIN_DATA` is unset.

2. **`bin/lib/cw-common.sh`** (line 65-66) — added `CW_LOG_DIR` variable:
   - Resolves to `${CLAUDE_PLUGIN_DATA}/logs` when `CLAUDE_PLUGIN_DATA` is set
   - Falls back to `/tmp` when unset

3. **`bin/cw-pipeline`** (lines 699, 721) — replaced two hardcoded `/tmp/cw-pipeline-*.log` references with `${CW_LOG_DIR}/cw-pipeline-*.log`.

## Proof Results

- **T02-01**: `plugin-data-init.sh` creates `logs/` on first run (exit 0), is idempotent on second run (exit 0), and exits 1 with a helpful stderr message when `CLAUDE_PLUGIN_DATA` is unset.
- **T02-02**: Sourcing `cw-common.sh` with `CLAUDE_PLUGIN_DATA=/tmp/test-pd` yields `CW_LOG_DIR=/tmp/test-pd/logs`; without it, `CW_LOG_DIR=/tmp`.
- **T02-03**: `bin/cw-pipeline` contains exactly two `CW_LOG_DIR` references (log file path + summary line) and zero hardcoded `/tmp/cw-pipeline-` literals.

## Scope Note

Per-worktree pipeline state (`.claude/pipeline-state.json`) was not modified and remains in its original location.
