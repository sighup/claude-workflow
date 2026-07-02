#!/bin/bash
# review-trigger.sh
# Risk-adaptive review-path decision for cw-review / cw-review-team
#
# Given a changed-file list and a total diff line count, decides whether a
# review should run under cw-review-team's concern-partitioned mode ("team")
# or cw-review's default mode ("solo"). Purely mechanical — no judgment call,
# no LLM invocation.
#
# Decision logic:
#   1. Security override: if ANY changed file matches SECURITY_GLOBS, output
#      "team" regardless of size/dir-count. This is a load-bearing safety
#      mechanism (see Security Considerations in the spec) and errs toward
#      over-inclusion. It also covers this script itself, so an edit to the
#      glob list always forces team review of that edit.
#   2. Otherwise: output "team" when the diff touches files across more than
#      MAX_TOP_LEVEL_DIRS top-level directories, OR the diff exceeds
#      MAX_DIFF_LINES total changed lines.
#   3. Otherwise: output "solo".
#
# Usage:
#   scripts/review-trigger.sh [--files <comma-separated-paths>] [--lines <N>] [--base <ref>]
#
#   --files   Comma-separated list of changed file paths. Pass "-" to read a
#             newline-separated list from stdin instead. If omitted, the
#             script computes the list itself via `git diff --name-only`
#             against --base (default: main).
#   --lines   Total changed line count (insertions + deletions). If omitted,
#             the script computes it itself via `git diff --shortstat`
#             against --base (default: main).
#   --base    Base ref for the default git-diff computation (default: main).
#
# Output: a single line, "team" or "solo", to stdout.

set -euo pipefail

# --- Editable constants (thresholds + security glob list) -------------------
# R2.3: these must stay here, at the top, as the single place to tune
# behavior — never hardcode thresholds or globs inline in the logic below.

MAX_TOP_LEVEL_DIRS=2
MAX_DIFF_LINES=400

# R2.2 / R3.3 shared glob list. Bash [[ ]] pattern matching treats "*" as
# matching across "/" (it is not filesystem pathname expansion), so
# "hooks/**" and "hooks/*" behave identically here; "**" is kept for
# readability/parity with the spec's glob notation.
#
# Security note: this list must include the file(s) that define it, so any
# change to the list itself always forces "team" review of that change.
SECURITY_GLOBS=(
  "hooks/**"
  "scripts/*guard*"
  "scripts/*verify*"
  "agents/proof-verifier.md"
  "agents/validator.md"
  "scripts/review-trigger.sh"
)

# --- Arg parsing --------------------------------------------------------

FILES_INPUT=""
LINES_INPUT=""
BASE_REF="main"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --files)
      FILES_INPUT="$2"
      shift 2
      ;;
    --lines)
      LINES_INPUT="$2"
      shift 2
      ;;
    --base)
      BASE_REF="$2"
      shift 2
      ;;
    -h|--help)
      grep '^# ' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "review-trigger.sh: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# --- Gather changed files ------------------------------------------------

CHANGED_FILES=()
if [[ "$FILES_INPUT" == "-" ]]; then
  while IFS= read -r line; do
    [[ -n "$line" ]] && CHANGED_FILES+=("$line")
  done
elif [[ -n "$FILES_INPUT" ]]; then
  IFS=',' read -r -a CHANGED_FILES <<< "$FILES_INPUT"
else
  while IFS= read -r line; do
    [[ -n "$line" ]] && CHANGED_FILES+=("$line")
  done < <(git diff --name-only "${BASE_REF}...HEAD" 2>/dev/null || true)
fi

# --- Gather total diff line count ----------------------------------------

if [[ -n "$LINES_INPUT" ]]; then
  TOTAL_LINES="$LINES_INPUT"
else
  STAT=$(git diff --shortstat "${BASE_REF}...HEAD" 2>/dev/null || echo "")
  INSERTIONS=$(echo "$STAT" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || true)
  DELETIONS=$(echo "$STAT" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+' || true)
  TOTAL_LINES=$(( ${INSERTIONS:-0} + ${DELETIONS:-0} ))
fi

# --- Decision logic --------------------------------------------------------

TEAM=false

# 1. Security override (R2.2): forces team regardless of size/dir-count.
for f in "${CHANGED_FILES[@]:-}"; do
  [[ -z "$f" ]] && continue
  for pattern in "${SECURITY_GLOBS[@]}"; do
    if [[ "$f" == $pattern ]]; then
      TEAM=true
      break 2
    fi
  done
done

# 2. Cross-module / diff-size trigger (R2.1) — only checked if the security
#    override didn't already fire.
# bash 3.2 compat (macOS default /bin/bash lacks associative arrays): collect
# top-level path segments into a newline list and de-dupe with sort -u.
if [[ "$TEAM" == false ]]; then
  TOP_LEVEL_LIST=""
  for f in "${CHANGED_FILES[@]:-}"; do
    [[ -z "$f" ]] && continue
    if [[ "$f" == */* ]]; then
      TOP_LEVEL_LIST="${TOP_LEVEL_LIST}${f%%/*}"$'\n'
    else
      TOP_LEVEL_LIST="${TOP_LEVEL_LIST}${f}"$'\n'
    fi
  done
  DIR_COUNT=$(printf '%s' "$TOP_LEVEL_LIST" | sed '/^$/d' | sort -u | wc -l | tr -d ' ')

  if (( DIR_COUNT > MAX_TOP_LEVEL_DIRS )) || (( TOTAL_LINES > MAX_DIFF_LINES )); then
    TEAM=true
  fi
fi

if [[ "$TEAM" == true ]]; then
  echo "team"
else
  echo "solo"
fi
