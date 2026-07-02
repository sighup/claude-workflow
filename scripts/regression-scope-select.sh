#!/bin/bash
# regression-scope-select.sh
# Impact-based regression-scenario selection for cw-testing.
#
# Given the files a bug-fix changed and a scenario-scope manifest, outputs the
# subset of scenario IDs whose recorded file scope overlaps the fix's changed
# files. cw-testing's regression-check step re-runs only these scenarios instead
# of every previously-passed scenario, so fix iterations don't get slower as the
# scenario count grows. Purely mechanical — no judgment call, no LLM invocation.
#
# Scenario-scope manifest format (JSONL — one JSON object per line):
#   {"scenario_id": "S1", "scope": ["src/auth/*"]}
#   {"scenario_id": "S2", "scope": ["src/billing/*", "lib/pay.ts"]}
# The `scope` array reuses the scenario task's declared
# scope.files_to_create + scope.files_to_modify (already present on the task
# board) — no new schema is invented. Entries may be exact paths or globs;
# a changed file "overlaps" a scope entry when it matches that entry under
# bash [[ ]] pattern matching (where "*" spans "/", so "src/auth/*" matches
# "src/auth/login.ts").
#
# Overlap logic:
#   For each manifest scenario, if ANY of the fix's changed files matches ANY
#   of that scenario's scope patterns, the scenario ID is selected. When
#   --passed is supplied, only scenario IDs in that set are considered
#   (the caller restricts selection to previously-passed scenarios, per R4.2).
#
# Output: selected scenario IDs, one per line, to stdout (in manifest order).
#   Empty output = empty overlap set. cw-testing treats empty output as
#   "skip the regression check for this fix attempt, recorded explicitly"
#   (R4.4) — never as "all passed". Exit status is 0 on a successful
#   selection regardless of whether the set is empty.
#
# Usage:
#   scripts/regression-scope-select.sh --manifest <path> \
#     [--changed <comma-separated-paths>] [--passed <comma-separated-ids>] \
#     [--base <ref>]
#
#   --manifest  Path to the scenario-scope manifest (JSONL). Required.
#   --changed   Comma-separated list of the fix's changed file paths. Pass "-"
#               to read a newline-separated list from stdin instead. If omitted,
#               the script computes the list itself via `git diff --name-only`
#               against --base (default: main).
#   --passed    Comma-separated list of previously-passed scenario IDs. When
#               given, the output is restricted to the intersection of the
#               overlap set with this set. When omitted, every overlapping
#               manifest scenario is emitted.
#   --base      Base ref for the default git-diff computation (default: main).

set -euo pipefail

# --- Editable constants -----------------------------------------------------

DEFAULT_BASE_REF="main"

# --- Arg parsing ------------------------------------------------------------

MANIFEST=""
CHANGED_INPUT=""
PASSED_INPUT=""
BASE_REF="$DEFAULT_BASE_REF"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest)
      MANIFEST="$2"
      shift 2
      ;;
    --changed)
      CHANGED_INPUT="$2"
      shift 2
      ;;
    --passed)
      PASSED_INPUT="$2"
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
      echo "regression-scope-select.sh: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$MANIFEST" ]]; then
  echo "regression-scope-select.sh: --manifest is required" >&2
  exit 1
fi
if [[ ! -f "$MANIFEST" ]]; then
  echo "regression-scope-select.sh: manifest not found: $MANIFEST" >&2
  exit 1
fi

# --- Gather the fix's changed files -----------------------------------------

CHANGED_FILES=()
if [[ "$CHANGED_INPUT" == "-" ]]; then
  while IFS= read -r line; do
    [[ -n "$line" ]] && CHANGED_FILES+=("$line")
  done
elif [[ -n "$CHANGED_INPUT" ]]; then
  IFS=',' read -r -a CHANGED_FILES <<< "$CHANGED_INPUT"
else
  while IFS= read -r line; do
    [[ -n "$line" ]] && CHANGED_FILES+=("$line")
  done < <(git diff --name-only "${BASE_REF}...HEAD" 2>/dev/null || true)
fi

# --- Gather the previously-passed scenario filter (optional) ----------------

PASSED_IDS=()
if [[ -n "$PASSED_INPUT" ]]; then
  IFS=',' read -r -a PASSED_IDS <<< "$PASSED_INPUT"
fi

# is_passed <scenario_id> — true when no --passed filter was given, or when the
# id is present in the supplied passed set.
is_passed() {
  local sid="$1"
  [[ -z "$PASSED_INPUT" ]] && return 0
  local p
  for p in "${PASSED_IDS[@]:-}"; do
    [[ "$sid" == "$p" ]] && return 0
  done
  return 1
}

# --- Selection: emit scenarios whose scope overlaps a changed file ----------

# No changed files means nothing can overlap — emit an empty set and exit clean.
if [[ ${#CHANGED_FILES[@]} -eq 0 ]]; then
  exit 0
fi

while IFS= read -r entry; do
  [[ -z "$entry" ]] && continue

  SID=$(printf '%s' "$entry" | jq -r '.scenario_id // empty' 2>/dev/null || true)
  [[ -z "$SID" ]] && continue

  is_passed "$SID" || continue

  # Read this scenario's scope patterns into an array (bash 3.2 safe).
  SCOPE_PATTERNS=()
  while IFS= read -r pat; do
    [[ -n "$pat" ]] && SCOPE_PATTERNS+=("$pat")
  done < <(printf '%s' "$entry" | jq -r '.scope[]? // empty' 2>/dev/null || true)

  OVERLAP=false
  for f in "${CHANGED_FILES[@]}"; do
    [[ -z "$f" ]] && continue
    for pattern in "${SCOPE_PATTERNS[@]:-}"; do
      [[ -z "$pattern" ]] && continue
      # shellcheck disable=SC2053  # intentional glob match: RHS is a pattern.
      if [[ "$f" == $pattern ]]; then
        OVERLAP=true
        break 2
      fi
    done
  done

  if [[ "$OVERLAP" == true ]]; then
    echo "$SID"
  fi
done < "$MANIFEST"
