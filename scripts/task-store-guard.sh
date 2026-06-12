#!/bin/bash
#
# scripts/task-store-guard.sh - Slimmed, lease-coordinated task-store backstop
#
# Defends the native task store (~/.claude/tasks/<list-id>/) against the
# concurrent-write wipe, in which parallel task-tool calls across processes
# sharing one CLAUDE_CODE_TASK_LIST_ID can delete every N.json in the directory
# (.highwatermark survives). Task tools bypass PreToolUse/PostToolUse hooks, so
# the guard works at the filesystem level: a per-list daemon mirrors task files
# to a shadow journal and restores the board when the wipe signature appears.
#
# This is the slimmed successor to the original guard (PR #35). It defaults to
# mirror/log-only and is coordinated by the writer lease (scripts/cw-lease.sh):
#
#   - It restores a wiped board only when NO writer lease is held for the list.
#     While a lease is held the restore is deferred and logged to incidents.log
#     with the holder as the reason; it restores only after the lease releases.
#   - It never clobbers newer journal evidence: a shadowed task is restored only
#     when its shadow copy is newer than any co-located {task_id}.result.json.
#     A stale shadow is skipped and logged with the evidence-newer reason.
#   - It is manifest-aware: it never prunes a shadowed task the manifest still
#     expects, so a task the planner declared cannot be dropped from the shadow.
#
# Retained from PR #35: pidfile idempotence (one daemon per list), poll/TTL
# knobs (all CW_* env-overridable), incident logging, and symlink safety — the
# guard never follows a symlink out of the tasks root when restoring or pruning.
#
# Modes:
#   (no args)            hook mode — reads SessionStart JSON on stdin, derives
#                        the task list id, spawns the daemon detached, exits
#   --watch <list-id>    daemon mode — poll loop (runs until --stop or TTL)
#   --stop <list-id>     stop a running daemon
#   --status <list-id>   print daemon + shadow state
#
# Wipe signature: task count drops to 0 in one poll tick from >= MIN_TASKS while
# the list directory itself still exists. Gradual single-file deletions
# (legitimate TaskUpdate status:deleted) are mirrored, never restored.
#
# Environment knobs (all CW_*):
#   CW_TASKS_DIR / CW_TASKS_ROOT   tasks root (default ~/.claude/tasks).
#                                  CW_TASKS_DIR is preferred and matches
#                                  cw-lease.sh; CW_TASKS_ROOT is accepted for
#                                  back-compat with the original guard.
#   CW_GUARD_POLL_SECONDS          poll interval in seconds (default 1)
#   CW_GUARD_MIN_TASKS             restore only if at least this many tasks
#                                  existed before the wipe (default 2)
#   CW_GUARD_TTL_SECONDS           daemon self-terminates after this many
#                                  seconds (default 43200 = 12h)
#   CW_LEASE_SH                    path to cw-lease.sh (default: sibling of this
#                                  script). Used to read lease status; if absent
#                                  the guard falls back to a direct lock-dir
#                                  check at <tasks-root>/<list-id>.writer.
#   CW_LEASE_TTL                   seconds before a held lease is considered
#                                  stale (default 600, matching cw-lease.sh).
#                                  Used in the fallback lock-dir path to skip
#                                  stale leases and allow restore to proceed.
#
# Network-FS caveat: like the lease, this guard assumes the local APFS tasks
# tree. mkdir/rename atomicity is not guaranteed over NFS/SMB.
#
# Part of claude-workflow plugin - automatically active when plugin is installed

set -u

# --- Configuration ----------------------------------------------------------

TASKS_ROOT="${CW_TASKS_DIR:-${CW_TASKS_ROOT:-$HOME/.claude/tasks}}"
GUARD_ROOT="${TASKS_ROOT}/.guard"
POLL_SECONDS="${CW_GUARD_POLL_SECONDS:-1}"
MIN_TASKS="${CW_GUARD_MIN_TASKS:-2}"
TTL_SECONDS="${CW_GUARD_TTL_SECONDS:-43200}"
LEASE_TTL="${CW_LEASE_TTL:-600}"

# Resolve cw-lease.sh: explicit override, else the sibling of this script.
_self_dir() {
  local src="${BASH_SOURCE[0]}"
  cd "$(dirname "$src")" 2>/dev/null && pwd -P
}
LEASE_SH="${CW_LEASE_SH:-$(_self_dir)/cw-lease.sh}"

# --- Helpers ----------------------------------------------------------------

log_incident() { # list_id message
  mkdir -p "$GUARD_ROOT"
  echo "$(date -u +%FT%TZ) [$1] $2" >> "${GUARD_ROOT}/incidents.log"
}

count_tasks() { # dir -> count of [0-9]*.json
  find "$1" -maxdepth 1 -name '[0-9]*.json' 2>/dev/null | wc -l | tr -d ' '
}

# Is a writer lease currently held for this list? Prefers cw-lease.sh status;
# falls back to a direct check of the lease directory. Echoes the holder
# description (pid/host) on its own line when held, nothing when free; returns 0
# when held, 1 when free.
lease_holder() { # list_id -> echoes holder; rc 0 held / 1 free
  local list_id="$1" dir
  if [ -x "$LEASE_SH" ]; then
    local out
    out="$("$LEASE_SH" status "$list_id" 2>/dev/null)"
    # Only a live lease blocks restore. A stale lease means the writer crashed;
    # treat it as free so the restore backstop can fire.
    if printf '%s' "$out" | grep -q '^lease: held (live)'; then
      local pid host
      pid="$(printf '%s\n' "$out" | awk '/^  pid:/ {print $2; exit}')"
      host="$(printf '%s\n' "$out" | awk '/^  host:/ {print $2; exit}')"
      echo "pid ${pid:-unknown} on ${host:-unknown}"
      return 0
    fi
    if printf '%s' "$out" | grep -q '^lease: held (stale)'; then
      local pid host
      pid="$(printf '%s\n' "$out" | awk '/^  pid:/ {print $2; exit}')"
      host="$(printf '%s\n' "$out" | awk '/^  host:/ {print $2; exit}')"
      log_incident "$list_id" "STALE lease overridden — treating as free (crashed writer pid ${pid:-unknown} on ${host:-unknown}); restore will proceed"
      return 1
    fi
    return 1
  fi
  # Fallback: direct lock-dir inspection (no symlink following).
  dir="${TASKS_ROOT}/${list_id}.writer"
  if [ -L "$dir" ]; then
    # Refuse to trust a symlinked lease path; treat as held to stay safe.
    echo "symlinked lease path (refusing to follow)"
    return 0
  fi
  if [ -d "$dir" ]; then
    local pid host hb now age
    pid="$(cat "$dir/pid" 2>/dev/null)"
    host="$(cat "$dir/host" 2>/dev/null)"
    hb="$(cat "$dir/heartbeat" 2>/dev/null)"
    # Apply TTL check: a missing or non-numeric heartbeat is treated as stale.
    case "$hb" in
      ''|*[!0-9]*)
        log_incident "$list_id" "STALE lease overridden (fallback path — missing/corrupt heartbeat) — treating as free (pid ${pid:-unknown} on ${host:-unknown}); restore will proceed"
        return 1
        ;;
    esac
    now="$(date +%s)"
    age=$(( now - hb ))
    if [ "$age" -ge "$LEASE_TTL" ]; then
      log_incident "$list_id" "STALE lease overridden (fallback path — heartbeat age ${age}s >= TTL ${LEASE_TTL}s) — treating as free (pid ${pid:-unknown} on ${host:-unknown}); restore will proceed"
      return 1
    fi
    echo "pid ${pid:-unknown} on ${host:-unknown}"
    return 0
  fi
  return 1
}

# Does the manifest for this list still expect the given task base file?
# The manifest keys on stable task_id; native board files are <native-id>.json
# carrying a "task_id" field. We treat a shadow file as manifest-expected when
# its task_id appears in the manifest's task_ids. Absent manifest or jq => not
# expected (advisory: we only use this to AVOID pruning, never to force one).
manifest_expects() { # list_id shadow_file -> rc 0 expected / 1 not
  local list_id="$1" shadow_file="$2"
  local manifest="${TASKS_ROOT}/.manifest/${list_id}/manifest.json"
  [ -f "$manifest" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  local tid
  tid="$(jq -r '.task_id // empty' "$shadow_file" 2>/dev/null)"
  [ -n "$tid" ] || return 1
  jq -e --arg t "$tid" '
    [ (.tasks // [])[]?.task_id, (.task_ids // [])[]? ] | index($t) != null
  ' "$manifest" >/dev/null 2>&1
}

# Is the shadow copy newer than co-located result.json journal evidence for the
# same task? Returns 0 (restore OK) when the shadow is strictly newer than, or
# when there is no, journal evidence; returns 1 (skip) when a journal exists
# that is at least as new as the shadow. The journal is looked up by the shadow
# file's task_id as <list-dir>/<task_id>.result.json and, as a fallback, beside
# the shadow itself — co-located evidence per the spec.
shadow_newer_than_evidence() { # list_dir shadow_file -> rc 0 restore / 1 skip
  local list_dir="$1" shadow_file="$2"
  local tid="" journal=""
  if command -v jq >/dev/null 2>&1; then
    tid="$(jq -r '.task_id // empty' "$shadow_file" 2>/dev/null)"
  fi
  local base candidate
  base="$(basename "$shadow_file" .json)"
  for candidate in \
    ${tid:+"${list_dir}/${tid}.result.json"} \
    ${tid:+"$(dirname "$shadow_file")/${tid}.result.json"} \
    "${list_dir}/${base}.result.json" \
    "$(dirname "$shadow_file")/${base}.result.json"; do
    if [ -e "$candidate" ] && [ ! -L "$candidate" ]; then
      journal="$candidate"
      break
    fi
  done
  [ -n "$journal" ] || return 0
  # Journal exists: restore only if the shadow is strictly newer than it.
  if [ "$shadow_file" -nt "$journal" ]; then
    return 0
  fi
  return 1
}

# --- Daemon -----------------------------------------------------------------

daemon() { # list_id
  local LIST_ID="$1"
  local LIST_DIR="${TASKS_ROOT}/${LIST_ID}"
  local SHADOW="${GUARD_ROOT}/${LIST_ID}"
  local PIDFILE="${GUARD_ROOT}/${LIST_ID}.pid"

  mkdir -p "$SHADOW"

  # Idempotence: one daemon per list.
  if [ -f "$PIDFILE" ]; then
    local OLD_PID
    OLD_PID=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
      exit 0
    fi
  fi
  echo $$ > "$PIDFILE"
  trap 'rm -f "$PIDFILE"; exit 0' TERM INT

  local LAST_COUNT=-1
  local ELAPSED=0
  local WIPE_PENDING=0   # a wipe was seen but restore is deferred by the lease

  while [ "$ELAPSED" -lt "$TTL_SECONDS" ]; do
    if [ -d "$LIST_DIR" ] && [ ! -L "$LIST_DIR" ]; then
      local COUNT
      COUNT=$(count_tasks "$LIST_DIR")

      if [ "$COUNT" -gt 0 ]; then
        guard_mirror "$LIST_ID" "$LIST_DIR" "$SHADOW" "$COUNT" "$LAST_COUNT"
        LAST_COUNT="$COUNT"
        WIPE_PENDING=0
      elif { [ "$COUNT" -eq 0 ] && [ "$LAST_COUNT" -ge "$MIN_TASKS" ]; } || [ "$WIPE_PENDING" -eq 1 ]; then
        # Wipe signature (or a previously deferred wipe still un-restored).
        if guard_restore "$LIST_ID" "$LIST_DIR" "$SHADOW" "$LAST_COUNT"; then
          LAST_COUNT="$(count_tasks "$LIST_DIR")"
          WIPE_PENDING=0
        else
          WIPE_PENDING=1
        fi
      elif [ "$COUNT" -eq 0 ] && [ "$LAST_COUNT" -gt 0 ]; then
        # Below the wipe signature (e.g. a 1-task list went 1 -> 0). Treated as
        # a legitimate deletion — mirrored, never restored — but logged when a
        # manifest still expects tasks for this list, so single-task boards
        # losing their record at end-of-run leave an audit trail.
        if [ -f "${TASKS_ROOT}/.manifest/${LIST_ID}/manifest.json" ]; then
          log_incident "$LIST_ID" "below-signature deletion (${LAST_COUNT} -> 0, MIN_TASKS=${MIN_TASKS}) with manifest present; mirrored only, shadow retained"
        fi
        LAST_COUNT=0
      fi
    fi
    sleep "$POLL_SECONDS"
    ELAPSED=$((ELAPSED + POLL_SECONDS))
  done
  rm -f "$PIDFILE"
}

# Mirror new/changed task files into the shadow, and mirror a single gradual
# deletion (status:deleted) without restoring. Never prunes a task the manifest
# still expects.
guard_mirror() { # list_id list_dir shadow count last_count
  local LIST_ID="$1" LIST_DIR="$2" SHADOW="$3" COUNT="$4" LAST_COUNT="$5"
  local f base
  for f in "$LIST_DIR"/[0-9]*.json; do
    [ -f "$f" ] || continue
    [ -L "$f" ] && continue
    base=$(basename "$f")
    if [ ! -f "$SHADOW/$base" ] || [ "$f" -nt "$SHADOW/$base" ]; then
      cp -p "$f" "$SHADOW/$base" 2>/dev/null
    fi
  done
  # Gradual deletion (exactly one file gone this tick): prune the shadow to
  # match — but never prune a task the manifest still expects.
  if [ "$LAST_COUNT" -ge 0 ] && [ "$COUNT" -eq $((LAST_COUNT - 1)) ]; then
    for f in "$SHADOW"/[0-9]*.json; do
      [ -f "$f" ] || continue
      base=$(basename "$f")
      [ -f "$LIST_DIR/$base" ] && continue
      if manifest_expects "$LIST_ID" "$f"; then
        log_incident "$LIST_ID" "PRUNE skipped for ${base}: manifest still expects this task"
        continue
      fi
      rm -f "$SHADOW/$base"
    done
  fi
}

# Attempt a lease-coordinated, evidence-aware restore of a wiped board.
# Returns 0 when the restore was performed (or there was nothing to restore),
# 1 when it was deferred because a writer lease is held.
guard_restore() { # list_id list_dir shadow last_count -> rc 0 done / 1 deferred
  local LIST_ID="$1" LIST_DIR="$2" SHADOW="$3" LAST_COUNT="$4"

  # Defer while a writer lease is held — the holder is mid-write, not wiped.
  local holder
  if holder="$(lease_holder "$LIST_ID")"; then
    log_incident "$LIST_ID" "WIPE detected (>=${MIN_TASKS} tasks -> 0); restore DEFERRED — writer lease held by ${holder}"
    return 1
  fi

  local RESTORED=0 SKIPPED=0 f base
  for f in "$SHADOW"/[0-9]*.json; do
    [ -f "$f" ] || continue
    [ -L "$f" ] && continue
    base=$(basename "$f")
    # Never clobber newer journal evidence with an older shadow.
    if ! shadow_newer_than_evidence "$LIST_DIR" "$f"; then
      log_incident "$LIST_ID" "RESTORE skipped for ${base}: co-located result.json journal is newer than shadow (evidence-newer)"
      SKIPPED=$((SKIPPED + 1))
      continue
    fi
    # Never restore through a symlink out of the list dir.
    [ -L "$LIST_DIR/$base" ] && continue
    if cp -p "$f" "$LIST_DIR/$base" 2>/dev/null; then
      RESTORED=$((RESTORED + 1))
    fi
  done
  log_incident "$LIST_ID" "WIPE detected (${LAST_COUNT} tasks -> 0); restored ${RESTORED} task files from shadow (skipped ${SKIPPED} for newer evidence)"
  return 0
}

# --- Entry point ------------------------------------------------------------

case "${1:-hook}" in
  --watch)
    daemon "${2:?--watch requires a list-id}"
    ;;
  --stop)
    PIDFILE="${GUARD_ROOT}/${2:?--stop requires a list-id}.pid"
    if [ -f "$PIDFILE" ]; then
      kill "$(cat "$PIDFILE")" 2>/dev/null
      rm -f "$PIDFILE"
      echo "stopped guard for $2"
    else
      echo "no guard running for $2"
    fi
    ;;
  --status)
    PIDFILE="${GUARD_ROOT}/${2:?--status requires a list-id}.pid"
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
      echo "guard running (pid $(cat "$PIDFILE")) for $2; shadow: $(count_tasks "${GUARD_ROOT}/$2") task files"
    else
      echo "guard not running for $2"
    fi
    ;;
  hook|*)
    # SessionStart hook mode. Derive the task list id:
    #   1. CLAUDE_CODE_TASK_LIST_ID from worktree settings (matches session-init)
    #   2. session_id from the hook's stdin JSON (session-based lists)
    INPUT=$(cat 2>/dev/null || true)
    CURRENT_DIR="${CW_OVERRIDE_CWD:-$(pwd)}"
    LIST_ID=""

    for marker in "/.claude/worktrees/" "/.worktrees/"; do
      if [[ "$CURRENT_DIR" == *"${marker}"* ]]; then
        WT_NAME="${CURRENT_DIR#*"${marker}"}"; WT_NAME="${WT_NAME%%/*}"
        SETTINGS="${CURRENT_DIR%%"${marker}"*}${marker}${WT_NAME}/.claude/settings.local.json"
        if [ -f "$SETTINGS" ]; then
          LIST_ID=$(jq -r '.env.CLAUDE_CODE_TASK_LIST_ID // empty' "$SETTINGS" 2>/dev/null)
        fi
        [ -n "$LIST_ID" ] || LIST_ID="$WT_NAME"
        break
      fi
    done

    if [ -z "$LIST_ID" ] && [ -n "$INPUT" ]; then
      LIST_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
    fi

    if [ -n "$LIST_ID" ]; then
      SCRIPT_PATH="${BASH_SOURCE[0]}"
      nohup "$SCRIPT_PATH" --watch "$LIST_ID" >/dev/null 2>&1 &
      disown 2>/dev/null || true
    fi
    exit 0
    ;;
esac
