#!/bin/bash
#
# bench/run_instance.sh - per-(instance, arm, run) execution unit for the
# SWE-bench eval harness.
#
# For one benchmark instance it: derives an isolated CLAUDE_CODE_TASK_LIST_ID,
# copies the target repo into a throwaway working tree, invokes a configurable
# --agent-cmd (default `claude`, overridable to a stub for fixture proofs),
# captures patch.diff (git diff of the agent's edits) and stream.jsonl (the
# agent's stdout), and checksum-guards the benchmark's designated test files so
# an agent cannot silently pass by editing the ground-truth tests.
#
# It is proven end-to-end against local fixtures only (bench/fixtures/toy-repo,
# bench/fixtures/Dockerfile.fixture, bench/fixtures/stub-agent.sh): no real
# `claude` billing and no external SWE-bench image pull are required. Pointing
# it at a real instance is a documented, argument-only change (--agent-cmd,
# --repo-dir, --image, --use-docker).
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=bench/lib/task_list_id.sh disable=SC1091
. "$SCRIPT_DIR/lib/task_list_id.sh"
# shellcheck source=bench/lib/checksum_guard.sh disable=SC1091
. "$SCRIPT_DIR/lib/checksum_guard.sh"

usage() {
  cat <<'EOF'
Usage: run_instance.sh --instance-id ID --arm ARM --run-n N [options]

Required:
  --instance-id ID    benchmark instance id (e.g. toy-1)
  --arm ARM           arm label (e.g. vanilla | plugin)
  --run-n N           run index (e.g. 1)

Options:
  --agent-cmd CMD     agent executable (default: claude). Override to a stub for
                      fixture testing so no real billed claude call happens.
  --repo-dir DIR      source repo to copy (default: bench/fixtures/toy-repo)
  --test-files LIST   comma-separated designated test files, relative to the
                      repo, that are checksum-guarded (default: failing_test.sh)
  --results-dir DIR   results root (default: bench/results)
  --image TAG         fixture image tag recorded in metrics.json
                      (default: bench-fixture:local; never an external swebench/*)
  --dockerfile PATH   fixture Dockerfile (default: bench/fixtures/Dockerfile.fixture)
  --use-docker        actually build the local fixture image (off by default;
                      proofs run the agent against the local repo copy, no pull)
  -h, --help          show this help

Exit codes: 0 = run completed; 3 = test-tampering detected (also recorded as
status "FAILED: test-tampering" in metrics.json); 64 = usage error.
EOF
}

INSTANCE_ID=""
ARM=""
RUN_N=""
AGENT_CMD="claude"
REPO_DIR="$SCRIPT_DIR/fixtures/toy-repo"
TEST_FILES="failing_test.sh"
RESULTS_DIR="$SCRIPT_DIR/results"
IMAGE="bench-fixture:local"
DOCKERFILE="$SCRIPT_DIR/fixtures/Dockerfile.fixture"
USE_DOCKER=0

while [ $# -gt 0 ]; do
  case "$1" in
    --instance-id) INSTANCE_ID="$2"; shift 2 ;;
    --arm) ARM="$2"; shift 2 ;;
    --run-n) RUN_N="$2"; shift 2 ;;
    --agent-cmd) AGENT_CMD="$2"; shift 2 ;;
    --repo-dir) REPO_DIR="$2"; shift 2 ;;
    --test-files) TEST_FILES="$2"; shift 2 ;;
    --results-dir) RESULTS_DIR="$2"; shift 2 ;;
    --image) IMAGE="$2"; shift 2 ;;
    --dockerfile) DOCKERFILE="$2"; shift 2 ;;
    --use-docker) USE_DOCKER=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage >&2; exit 64 ;;
  esac
done

[ -n "$INSTANCE_ID" ] || { echo "error: missing --instance-id" >&2; exit 64; }
[ -n "$ARM" ] || { echo "error: missing --arm" >&2; exit 64; }
[ -n "$RUN_N" ] || { echo "error: missing --run-n" >&2; exit 64; }
[ -d "$REPO_DIR" ] || { echo "error: repo-dir not found: $REPO_DIR" >&2; exit 64; }

# Resolve a path-based agent command to absolute BEFORE we cd into the working
# copy; a bare command name (e.g. "claude") is left to PATH resolution.
if [ -e "$AGENT_CMD" ]; then
  AGENT_CMD="$(cd "$(dirname "$AGENT_CMD")" && pwd -P)/$(basename "$AGENT_CMD")"
fi

OUT_DIR="$RESULTS_DIR/$INSTANCE_ID/$ARM/$RUN_N"
mkdir -p "$OUT_DIR"
PATCH_FILE="$OUT_DIR/patch.diff"
STREAM_FILE="$OUT_DIR/stream.jsonl"
METRICS_FILE="$OUT_DIR/metrics.json"

TASK_LIST_ID="$(derive_task_list_id "$INSTANCE_ID" "$ARM" "$RUN_N")"
STARTED_AT="$(date -u +%FT%TZ)"

# split the comma-separated designated test list into an array
IFS=',' read -r -a TEST_FILE_ARR <<< "$TEST_FILES" || true

# Throwaway working copy: copy the repo contents and init a fresh git repo so we
# can diff the agent's edits without touching the fixture or nesting a .git in
# the plugin repo.
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/bench-run.XXXXXX")"
# Baseline checksums live OUTSIDE the working copy so they never leak into the
# captured patch.diff.
BASELINE="$(mktemp "${TMPDIR:-/tmp}/bench-before.XXXXXX")"
trap 'rm -rf "$WORKDIR" "$BASELINE"' EXIT

cp -R "$REPO_DIR/." "$WORKDIR/"
rm -rf "$WORKDIR/.git"
git -C "$WORKDIR" init -q
git -C "$WORKDIR" add -A
git -C "$WORKDIR" -c user.email=bench@fixture -c user.name=bench-fixture \
  commit -q -m baseline

# "${arr[@]+"${arr[@]}"}" is the bash-3.2-safe empty-array idiom: macOS's
# default /bin/bash (3.2.57) trips `set -u` on "${arr[@]}" when arr has zero
# elements (an empty --test-files is a legitimate case); fixed only in
# bash 4.4+. See bench/tests/test_run_instance.sh for the regression case.
record_checksums "$WORKDIR" "$BASELINE" "${TEST_FILE_ARR[@]+"${TEST_FILE_ARR[@]}"}"

# Optional real-run on-ramp: build the LOCAL fixture image. Never pulls an
# external swebench/* image. Off by default so proofs need no docker/network.
CONTAINER_MODE="local"
if [ "$USE_DOCKER" -eq 1 ]; then
  CONTAINER_MODE="docker"
  docker build -q -t "$IMAGE" -f "$DOCKERFILE" "$SCRIPT_DIR/fixtures" >/dev/null
fi

# Invoke the agent inside the working copy with the isolated task-list id
# exported ONLY into the child environment. Its stdout is the captured event
# stream; a failure is recorded, not fatal.
AGENT_RC=0
(
  cd "$WORKDIR"
  CLAUDE_CODE_TASK_LIST_ID="$TASK_LIST_ID" \
  BENCH_INSTANCE_ID="$INSTANCE_ID" \
  BENCH_ARM="$ARM" \
  BENCH_RUN_N="$RUN_N" \
  "$AGENT_CMD"
) > "$STREAM_FILE" 2> "$OUT_DIR/agent.log" || AGENT_RC=$?

# Capture the agent's edits as a patch (staged so new files are included).
git -C "$WORKDIR" add -A
git -C "$WORKDIR" diff --cached > "$PATCH_FILE" || true

# Post-run checksum comparison of the designated test files.
CHANGED="$(compare_checksums "$WORKDIR" "$BASELINE" "${TEST_FILE_ARR[@]+"${TEST_FILE_ARR[@]}"}")"
FINISHED_AT="$(date -u +%FT%TZ)"

if [ "$CHANGED" -gt 0 ]; then
  STATUS="FAILED: test-tampering"
  TEST_TAMPERING="true"
else
  STATUS="completed"
  TEST_TAMPERING="false"
fi

# designated test files as a JSON array. Guarded on length rather than the
# empty-array idiom here: printf still runs its format once with an empty %s
# when given zero arguments, which would otherwise render an empty
# --test-files as the JSON array ["" ] instead of the accurate [].
if [ "${#TEST_FILE_ARR[@]}" -gt 0 ]; then
  TEST_FILES_JSON="$(printf '%s\n' "${TEST_FILE_ARR[@]}" \
    | awk 'BEGIN{printf "["} {printf "%s\"%s\"", (NR>1?",":""), $0} END{printf "]"}')"
else
  TEST_FILES_JSON="[]"
fi

cat > "$METRICS_FILE" <<EOF
{
  "instance_id": "$INSTANCE_ID",
  "arm": "$ARM",
  "run_n": "$RUN_N",
  "agent_cmd": "$AGENT_CMD",
  "task_list_id": "$TASK_LIST_ID",
  "image": "$IMAGE",
  "container_mode": "$CONTAINER_MODE",
  "status": "$STATUS",
  "test_tampering": $TEST_TAMPERING,
  "regression_count": $CHANGED,
  "designated_test_files": $TEST_FILES_JSON,
  "resolved": false,
  "agent_exit_code": $AGENT_RC,
  "started_at": "$STARTED_AT",
  "finished_at": "$FINISHED_AT",
  "patch_file": "patch.diff",
  "stream_file": "stream.jsonl"
}
EOF

echo "run_instance: $INSTANCE_ID/$ARM/$RUN_N -> $STATUS (artifacts in $OUT_DIR)"

# Never silently pass a tampered run: loud nonzero exit in addition to the
# FAILED status recorded above.
if [ "$CHANGED" -gt 0 ]; then
  echo "run_instance: designated test file(s) modified during run" >&2
  exit 3
fi
exit 0
