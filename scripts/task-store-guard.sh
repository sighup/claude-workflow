#!/bin/bash
# task-store-guard.sh
# Defends the native task store (~/.claude/tasks/<list-id>/) against the
# concurrent-write wipe: multiple processes sharing one task list can race the
# store and delete every N.json in the directory (.highwatermark survives).
# Task tools bypass PreToolUse/PostToolUse hooks, so the guard works at the
# filesystem level instead: a per-list daemon continuously mirrors task files
# to a shadow journal and restores the board when the wipe signature appears.
#
# Modes:
#   (no args)            hook mode — reads SessionStart JSON on stdin, derives
#                        the task list id, spawns the daemon detached, exits
#   --watch <list-id>    daemon mode — poll loop (runs until --stop or TTL)
#   --stop <list-id>     stop a running daemon
#   --status <list-id>   print daemon + shadow state
#
# Wipe signature: task count drops to 0 in one poll tick from >= MIN_TASKS,
# while the list directory itself still exists. Gradual single-file deletions
# (legitimate TaskUpdate status:deleted) are mirrored, never restored.
#
# Part of claude-workflow plugin - automatically active when plugin is installed

set -u

TASKS_ROOT="${CW_TASKS_ROOT:-$HOME/.claude/tasks}"
GUARD_ROOT="${TASKS_ROOT}/.guard"
POLL_SECONDS="${CW_GUARD_POLL_SECONDS:-1}"
MIN_TASKS="${CW_GUARD_MIN_TASKS:-2}"     # restore only if this many tasks existed
TTL_SECONDS="${CW_GUARD_TTL_SECONDS:-43200}"  # daemon self-terminates after 12h

log_incident() { # list_id message
  mkdir -p "$GUARD_ROOT"
  echo "$(date -u +%FT%TZ) [$1] $2" >> "${GUARD_ROOT}/incidents.log"
}

count_tasks() { # dir -> count of [0-9]*.json
  find "$1" -maxdepth 1 -name '[0-9]*.json' 2>/dev/null | wc -l | tr -d ' '
}

daemon() { # list_id
  local LIST_ID="$1"
  local LIST_DIR="${TASKS_ROOT}/${LIST_ID}"
  local SHADOW="${GUARD_ROOT}/${LIST_ID}"
  local PIDFILE="${GUARD_ROOT}/${LIST_ID}.pid"

  mkdir -p "$SHADOW"

  # Idempotence: one daemon per list
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

  while [ "$ELAPSED" -lt "$TTL_SECONDS" ]; do
    if [ -d "$LIST_DIR" ]; then
      local COUNT
      COUNT=$(count_tasks "$LIST_DIR")

      if [ "$COUNT" -gt 0 ]; then
        # Mirror: copy new/changed task files into the shadow
        local f base
        for f in "$LIST_DIR"/[0-9]*.json; do
          [ -f "$f" ] || continue
          base=$(basename "$f")
          if [ ! -f "$SHADOW/$base" ] || [ "$f" -nt "$SHADOW/$base" ]; then
            cp -p "$f" "$SHADOW/$base" 2>/dev/null
          fi
        done
        # Gradual deletion (single file per tick): mirror it, don't fight it
        if [ "$LAST_COUNT" -ge 0 ] && [ "$COUNT" -eq $((LAST_COUNT - 1)) ]; then
          for f in "$SHADOW"/[0-9]*.json; do
            [ -f "$f" ] || continue
            base=$(basename "$f")
            [ -f "$LIST_DIR/$base" ] || rm -f "$SHADOW/$base"
          done
        fi
        LAST_COUNT="$COUNT"
      elif [ "$COUNT" -eq 0 ] && [ "$LAST_COUNT" -ge "$MIN_TASKS" ]; then
        # Wipe signature: >= MIN_TASKS tasks vanished within one poll tick.
        # Restore the full board from the shadow.
        local RESTORED=0
        local f
        for f in "$SHADOW"/[0-9]*.json; do
          [ -f "$f" ] || continue
          cp -p "$f" "$LIST_DIR/$(basename "$f")" 2>/dev/null && RESTORED=$((RESTORED + 1))
        done
        log_incident "$LIST_ID" "WIPE detected (${LAST_COUNT} tasks -> 0); restored ${RESTORED} task files from shadow"
        LAST_COUNT="$RESTORED"
      fi
    fi
    sleep "$POLL_SECONDS"
    ELAPSED=$((ELAPSED + POLL_SECONDS))
  done
  rm -f "$PIDFILE"
}

case "${1:-hook}" in
  --watch)
    daemon "$2"
    ;;
  --stop)
    PIDFILE="${GUARD_ROOT}/$2.pid"
    if [ -f "$PIDFILE" ]; then
      kill "$(cat "$PIDFILE")" 2>/dev/null
      rm -f "$PIDFILE"
      echo "stopped guard for $2"
    else
      echo "no guard running for $2"
    fi
    ;;
  --status)
    PIDFILE="${GUARD_ROOT}/$2.pid"
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
        WT_NAME="${CURRENT_DIR#*${marker}}"; WT_NAME="${WT_NAME%%/*}"
        SETTINGS="${CURRENT_DIR%%${marker}*}${marker}${WT_NAME}/.claude/settings.local.json"
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
