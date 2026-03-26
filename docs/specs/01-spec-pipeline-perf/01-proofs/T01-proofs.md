# T01 Proof Artifacts - Add --bare flag to invoke_claude

## Summary

Successfully added `--bare` flag to the `invoke_claude` function in `bin/lib/cw-common.sh`, positioned before `--print` on line 109. All syntax checks pass.

## Proof Artifacts

### 1. Grep verification: --bare flag present
- **File**: T01-01-cli.txt
- **Command**: `grep -n 'bare' bin/lib/cw-common.sh`
- **Result**: PASS
- **Evidence**: Line 109 shows `local CMD=(claude --bare --print --model "$MODEL" --dangerously-skip-permissions)`

### 2. Syntax check: cw-common.sh
- **File**: T01-02-cli.txt
- **Command**: `bash -n bin/lib/cw-common.sh`
- **Result**: PASS
- **Exit code**: 0

### 3. Syntax check: bin/cw-pipeline
- **File**: T01-03-cli.txt
- **Command**: `bash -n bin/cw-pipeline`
- **Result**: PASS
- **Exit code**: 0

## Implementation Details

### Change Made
Modified `/bin/lib/cw-common.sh` line 109 in the `invoke_claude()` function:

**Before:**
```bash
local CMD=(claude --print --model "$MODEL" --dangerously-skip-permissions)
```

**After:**
```bash
local CMD=(claude --bare --print --model "$MODEL" --dangerously-skip-permissions)
```

### Impact
- All 7 bin/ scripts that source `bin/lib/cw-common.sh` automatically inherit the `--bare` flag
- Scripted (non-interactive) Claude invocations now skip hooks, LSP, plugin sync, and skill directory walks
- No per-script changes required
- Backward compatible — the flag is standard in the Claude CLI

## Verification Status

All proof artifacts pass. The implementation satisfies all requirements from the spec:
- ✓ `invoke_claude` includes `--bare` in the CMD array
- ✓ `--bare` is positioned before `--print`
- ✓ All modified scripts pass `bash -n` syntax check
- ✓ No changes to interactive invocations (none currently exist in `invoke_claude`)

## Unit Status: COMPLETE

Unit 1 of the pipeline-perf specification is complete and ready for review.
