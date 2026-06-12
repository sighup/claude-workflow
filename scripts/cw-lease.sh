#!/bin/bash
#
# scripts/cw-lease.sh - Atomic writer lease for the native task store
#
# Provides cross-process mutual exclusion for processes that write to a task
# list's board, so that only one writer mutates ~/.claude/tasks/<list-id>/ at a
# time. The lease is a directory created with mkdir(2), which is atomic on a
# local filesystem: exactly one concurrent caller wins the create, the rest
# observe EEXIST and wait.
#
# Verbs:
#   acquire <list-id> [--phase LABEL]  acquire-or-wait until the lease is free
#                                      or reclaimable, then take it. Never
#                                      proceeds-with-warning; it blocks.
#   refresh <list-id>                  bump the heartbeat of a lease this
#                                      process owns.
#   release <list-id>                  remove the lease, only if owned.
#   status  <list-id>                  print holder pid/host/heartbeat/phase.
#
# Lease layout (lease dir = $CLAUDE_TASKS_DIR/<list-id>.writer):
#   pid        owning process id
#   host       owning host name
#   heartbeat  epoch seconds of the last acquire/refresh
#   phase      free-form phase label (e.g. execute, dispatch)
#
# Reclaim: a held lease is reclaimable only when its heartbeat is older than the
# TTL (CW_LEASE_TTL, default 600s). A waiting acquirer that observes a stale
# lease removes it and retries the mkdir, so reclaim races stay atomic — only
# the winner of the post-reclaim mkdir proceeds.
#
# Atomicity caveat: mkdir is atomic on a local APFS volume. Over a network
# filesystem (NFS/SMB) mkdir atomicity is NOT guaranteed; this lease is intended
# only for the local ~/.claude/tasks/ tree and must not be relied upon across a
# network mount. flock is deliberately not used — it is absent on Darwin.
#
# Environment knobs (all CW_*):
#   CW_LEASE_TTL          stale threshold in seconds (default 600)
#   CW_LEASE_POLL         poll interval in seconds while waiting (default 2)
#   CW_LEASE_WAIT_MAX     max seconds to wait in acquire before giving up
#                         (default 0 = wait indefinitely)
#   CW_TASKS_DIR          override the tasks root (default ~/.claude/tasks)
#   CW_LEASE_HOST         override the recorded host name (default hostname)
#   CW_LEASE_PID          owner identity recorded/checked for ownership
#                         (default $$). A controlling process that drives the
#                         lease across separate CLI invocations should export
#                         its own stable pid here so that refresh/release from a
#                         later invocation still match the holder. Two distinct
#                         owners (different CW_LEASE_PID + host) remain mutually
#                         exclusive, which is the cross-process guarantee.
#
set -u

# --- Configuration ----------------------------------------------------------

CW_LEASE_TTL="${CW_LEASE_TTL:-600}"
CW_LEASE_POLL="${CW_LEASE_POLL:-2}"
CW_LEASE_WAIT_MAX="${CW_LEASE_WAIT_MAX:-0}"
TASKS_DIR="${CW_TASKS_DIR:-$HOME/.claude/tasks}"

# --- Helpers ----------------------------------------------------------------

err() {
    echo "cw-lease: $*" >&2
}

now_epoch() {
    date +%s
}

this_host() {
    echo "${CW_LEASE_HOST:-$(hostname 2>/dev/null || echo unknown)}"
}

# The owner identity recorded in the lease. Defaults to this process's pid, but
# a controlling process can export CW_LEASE_PID to keep ownership stable across
# separate CLI invocations it drives.
this_owner() {
    echo "${CW_LEASE_PID:-$$}"
}

# Resolve and validate the lease directory path for a list id. Guards against
# path traversal in the list id and refuses to operate through a symlink that
# escapes the tasks root (security requirement: never follow symlinks out of
# the tasks root).
#
# Echoes the absolute lease dir path on success; returns non-zero on rejection.
lease_dir_for() {
    local list_id="$1"

    if [ -z "$list_id" ]; then
        err "list-id is required"
        return 1
    fi

    case "$list_id" in
        .|..)
            err "invalid list-id (reserved name): $list_id"
            return 1
            ;;
        */*|*..*)
            err "invalid list-id (must not contain path separators or '..'): $list_id"
            return 1
            ;;
    esac

    # The tasks root itself must not be a symlink leading outside the home
    # ~/.claude tree. If it is a symlink, resolve it and confirm the real path
    # still lives under $HOME/.claude.
    if [ -L "$TASKS_DIR" ]; then
        local real_root
        real_root="$(cd "$TASKS_DIR" 2>/dev/null && pwd -P)"
        case "$real_root" in
            "$HOME"/.claude|"$HOME"/.claude/*) ;;
            *)
                err "tasks root resolves outside ~/.claude via symlink: $TASKS_DIR -> $real_root"
                return 1
                ;;
        esac
    fi

    local dir="$TASKS_DIR/$list_id.writer"

    # The lease dir must never be a symlink — refuse to write/remove through it.
    if [ -L "$dir" ]; then
        err "lease path is a symlink, refusing to follow: $dir"
        return 1
    fi

    echo "$dir"
}

# Read a single lease field file; echoes empty string if absent.
read_field() {
    local dir="$1" field="$2"
    if [ -f "$dir/$field" ]; then
        cat "$dir/$field" 2>/dev/null
    fi
}

# Write the lease identity files into an already-created lease dir.
write_fields() {
    local dir="$1" phase="$2"
    this_owner > "$dir/pid"
    this_host > "$dir/host"
    now_epoch > "$dir/heartbeat"
    echo "$phase" > "$dir/phase"
}

# Is the lease held by this owner (pid + host match)?
owned_by_me() {
    local dir="$1"
    local pid host
    pid="$(read_field "$dir" pid)"
    host="$(read_field "$dir" host)"
    [ "$pid" = "$(this_owner)" ] && [ "$host" = "$(this_host)" ]
}

# Epoch-seconds mtime of a path, or non-zero if it cannot be read. stat is not
# portable: BSD/Darwin stat uses `-f %m`, GNU coreutils stat uses `-c %Y`, and
# crucially each REJECTS the other's flags by repurposing them (GNU treats `-f`
# as --file-system and emits non-numeric output without failing). So we cannot
# rely on exit status alone — try each form and accept only an all-digits
# result, which uniquely identifies the matching stat implementation.
mtime_epoch() {
    local path="$1" m
    m="$(stat -f %m "$path" 2>/dev/null)"
    case "$m" in
        ''|*[!0-9]*) ;;
        *) echo "$m"; return 0 ;;
    esac
    m="$(stat -c %Y "$path" 2>/dev/null)"
    case "$m" in
        ''|*[!0-9]*) ;;
        *) echo "$m"; return 0 ;;
    esac
    return 1
}

# Is the lease stale (reclaimable)? A live heartbeat older than the TTL is
# stale. A missing/garbage heartbeat is NOT instantly stale: acquire writes the
# lease dir then its fields non-atomically, so a brand-new lease can be observed
# mid-write with no heartbeat yet. Fall back to the lease dir's own mtime and
# only treat a heartbeat-less lease as stale once the dir itself is older than
# the poll interval — long enough that any in-flight field write has completed.
# If the dir mtime cannot be read, fail safe and treat the lease as live (not
# reclaimable) rather than destroy a possibly-fresh lease.
is_stale() {
    local dir="$1"
    local hb age now dirm
    hb="$(read_field "$dir" heartbeat)"
    case "$hb" in
        ''|*[!0-9]*)
            dirm="$(mtime_epoch "$dir")" || return 1
            now="$(now_epoch)"
            age=$(( now - dirm ))
            [ "$age" -ge "$CW_LEASE_POLL" ]
            return
            ;;
    esac
    now="$(now_epoch)"
    age=$(( now - hb ))
    [ "$age" -ge "$CW_LEASE_TTL" ]
}

# --- Verbs ------------------------------------------------------------------

cmd_acquire() {
    local list_id="$1" phase="$2"
    local dir
    dir="$(lease_dir_for "$list_id")" || return 1

    mkdir -p "$TASKS_DIR" 2>/dev/null

    local waited=0
    while true; do
        if mkdir "$dir" 2>/dev/null; then
            write_fields "$dir" "$phase"
            return 0
        fi

        # mkdir failed: lease exists. If we already own it, treat acquire as a
        # refresh (idempotent re-acquire by the same process).
        if owned_by_me "$dir"; then
            now_epoch > "$dir/heartbeat"
            echo "$phase" > "$dir/phase"
            return 0
        fi

        # If the existing lease is stale, reclaim it. A plain `rm -rf "$dir"`
        # here is unsafe: between the is_stale check and the rm, another waiter
        # could reclaim and a fresh holder could mkdir a brand-new LIVE lease at
        # the same path — this rm would then delete that live lease, leaving two
        # holders. Reclaim single-winner via atomic rename instead: mv the stale
        # dir to a unique tombstone. rename(2) is atomic, so exactly one racing
        # reclaimer moves *this* directory; everyone else's mv fails (the source
        # no longer exists or is now a fresh dir) and they loop to re-evaluate.
        # Only the winner removes the tombstone (the snapshot it captured), never
        # the live path, then retries the mkdir.
        if is_stale "$dir"; then
            local tomb
            tomb="$dir.dead.$(this_owner).$(now_epoch).$$"
            if mv "$dir" "$tomb" 2>/dev/null; then
                rm -rf "$tomb" 2>/dev/null
            fi
            continue
        fi

        # Lease is live and not ours: wait. Never proceed-with-warning.
        if [ "$CW_LEASE_WAIT_MAX" -gt 0 ] && [ "$waited" -ge "$CW_LEASE_WAIT_MAX" ]; then
            err "timed out after ${waited}s waiting for lease held by pid $(read_field "$dir" pid) on $(read_field "$dir" host)"
            return 1
        fi
        sleep "$CW_LEASE_POLL"
        waited=$(( waited + CW_LEASE_POLL ))
    done
}

cmd_refresh() {
    local list_id="$1"
    local dir
    dir="$(lease_dir_for "$list_id")" || return 1

    if [ ! -d "$dir" ]; then
        err "no lease to refresh for list: $list_id"
        return 1
    fi
    if ! owned_by_me "$dir"; then
        err "refusing to refresh lease owned by pid $(read_field "$dir" pid) on $(read_field "$dir" host)"
        return 1
    fi
    now_epoch > "$dir/heartbeat"
    return 0
}

cmd_release() {
    local list_id="$1"
    local dir
    dir="$(lease_dir_for "$list_id")" || return 1

    if [ ! -d "$dir" ]; then
        # Nothing to release — idempotent success.
        return 0
    fi
    if ! owned_by_me "$dir"; then
        err "refusing to release lease owned by pid $(read_field "$dir" pid) on $(read_field "$dir" host)"
        return 1
    fi
    rm -rf "$dir" 2>/dev/null
    return 0
}

cmd_status() {
    local list_id="$1"
    local dir
    dir="$(lease_dir_for "$list_id")" || return 1

    if [ ! -d "$dir" ]; then
        echo "lease: free (no holder) for list '$list_id'"
        return 0
    fi

    local pid host hb phase now age state
    pid="$(read_field "$dir" pid)"
    host="$(read_field "$dir" host)"
    hb="$(read_field "$dir" heartbeat)"
    phase="$(read_field "$dir" phase)"

    state="live"
    if is_stale "$dir"; then
        state="stale"
    fi

    age="unknown"
    case "$hb" in
        ''|*[!0-9]*) ;;
        *)
            now="$(now_epoch)"
            age="$(( now - hb ))s"
            ;;
    esac

    echo "lease: held ($state) for list '$list_id'"
    echo "  pid:       ${pid:-unknown}"
    echo "  host:      ${host:-unknown}"
    echo "  heartbeat: ${hb:-unknown} (age ${age})"
    echo "  phase:     ${phase:-unknown}"
    return 0
}

# --- Entry point ------------------------------------------------------------

usage() {
    cat >&2 <<'EOF'
usage: cw-lease.sh <verb> <list-id> [options]

verbs:
  acquire <list-id> [--phase LABEL]   acquire-or-wait, then hold the lease
  refresh <list-id>                   bump heartbeat of an owned lease
  release <list-id>                   remove an owned lease (idempotent)
  status  <list-id>                   print holder pid/host/heartbeat/phase

env: CW_LEASE_TTL (600) CW_LEASE_POLL (2) CW_LEASE_WAIT_MAX (0=infinite)
     CW_TASKS_DIR (~/.claude/tasks) CW_LEASE_HOST (hostname)
EOF
}

main() {
    if [ "$#" -lt 1 ]; then
        usage
        return 2
    fi

    local verb="$1"
    shift

    # Parse a shared positional <list-id> plus optional flags.
    local list_id="" phase="default"
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --phase)
                if [ "$#" -lt 2 ]; then
                    err "--phase requires a value"
                    return 2
                fi
                phase="$2"
                shift 2
                ;;
            --phase=*)
                phase="${1#--phase=}"
                shift
                ;;
            -*)
                err "unknown option: $1"
                return 2
                ;;
            *)
                if [ -z "$list_id" ]; then
                    list_id="$1"
                else
                    err "unexpected argument: $1"
                    return 2
                fi
                shift
                ;;
        esac
    done

    if [ -z "$list_id" ]; then
        err "list-id is required"
        usage
        return 2
    fi

    case "$verb" in
        acquire) cmd_acquire "$list_id" "$phase" ;;
        refresh) cmd_refresh "$list_id" ;;
        release) cmd_release "$list_id" ;;
        status)  cmd_status "$list_id" ;;
        -h|--help|help) usage; return 0 ;;
        *)
            err "unknown verb: $verb"
            usage
            return 2
            ;;
    esac
}

main "$@"
