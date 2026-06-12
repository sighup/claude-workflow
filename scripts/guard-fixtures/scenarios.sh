#!/bin/bash
#
# scripts/guard-fixtures/scenarios.sh - Deterministic guard decision fixtures.
#
# Each scenario_<id> function exercises one branch (or branch interaction) of
# task-store-guard.sh's per-tick decision logic and SELF-GRADES, emitting a
# single line:
#
#   SCENARIO_RESULT: pass
#   SCENARIO_RESULT: fail — <reason>
#
# The grading lives in the scenario (which knows its own expected outcome), so
# the autoresearch assertion is a trivial "did it say pass?" check that is
# identical for every test case. A guard variant that breaks an invariant flips
# the affected scenario(s) to fail and drops the pass rate.
#
# Determinism: scenarios single-step the guard via guard_tick (one poll tick per
# call) instead of racing the real daemon's sleep loop. The tick-transition
# branches (gradual-delete prune, the deferred WIPE_PENDING latch) are driven
# one controlled tick at a time. No sleeps, no wall-clock dependence (lease
# staleness is faked with explicit heartbeat epochs).
#
# Contract with the harness: before calling a scenario the harness must have
#   1. exported CW_TASKS_DIR to a fresh empty temp dir,
#   2. exported CW_LEASE_SH to a non-existent path (forces the guard's hermetic
#      fallback lock-dir lease inspection — no dependency on cw-lease.sh),
#   3. sourced the guard artifact (so guard_tick/guard_restore/etc. and the
#      TASKS_ROOT/GUARD_ROOT/MIN_TASKS globals are defined),
#   4. sourced this file.
# Run each scenario in its own subshell so global tick-state never leaks.

# --- Per-scenario state + helpers ------------------------------------------

# Reset the working list for a scenario. Sets LIST/LIST_DIR/SHADOW and the
# carried tick state (LAST_COUNT/WIPE_PENDING) the daemon would hold.
gf_init() {
  LIST="fixturelist"
  LIST_DIR="${TASKS_ROOT}/${LIST}"
  SHADOW="${GUARD_ROOT}/${LIST}"
  LAST_COUNT=-1
  WIPE_PENDING=0
  mkdir -p "$LIST_DIR" "$SHADOW"
}

# Write a board task file: gf_task <native-n> <task_id>
gf_task() {
  printf '{"task_id":"%s"}\n' "$2" > "${LIST_DIR}/$1.json"
}

# One guard poll tick against the live list, carrying state forward.
gf_tick() {
  local out
  out="$(guard_tick "$LIST" "$LIST_DIR" "$SHADOW" "$LAST_COUNT" "$WIPE_PENDING")"
  LAST_COUNT="${out%% *}"
  WIPE_PENDING="${out##* }"
}

# Delete every board task file (the wipe).
gf_wipe() { rm -f "${LIST_DIR}"/[0-9]*.json; }

# Counts.
gf_live()   { find "$LIST_DIR" -maxdepth 1 -name '[0-9]*.json' 2>/dev/null | wc -l | tr -d ' '; }
gf_shadow() { find "$SHADOW"   -maxdepth 1 -name '[0-9]*.json' 2>/dev/null | wc -l | tr -d ' '; }

# Does incidents.log contain a line matching the (fixed-string) pattern?
gf_incident() { grep -qF "$1" "${GUARD_ROOT}/incidents.log" 2>/dev/null; }

# Create a fallback-path writer lease. gf_lease <heartbeat-epoch-offset-seconds>
# 0 => live (heartbeat now); a large negative number => stale.
gf_lease() {
  local off="$1" dir="${TASKS_ROOT}/${LIST}.writer" now
  now="$(date +%s)"
  mkdir -p "$dir"
  echo 99999 > "$dir/pid"
  echo "fixture-host" > "$dir/host"
  echo $(( now + off )) > "$dir/heartbeat"
  echo "fixture" > "$dir/phase"
}
gf_lease_release() { rm -rf "${TASKS_ROOT}/${LIST}.writer"; }

# Self-grading. First failure wins; a scenario that never calls gf_fail and
# reaches gf_done passes.
GF_FAILED=""
gf_check() { # condition-desc actual expected
  [ "$2" = "$3" ] && return 0
  [ -n "$GF_FAILED" ] && return 0
  GF_FAILED="$1 (got '$2', want '$3')"
}
gf_assert_incident()  { gf_incident "$1" && return 0; [ -n "$GF_FAILED" ] && return 0; GF_FAILED="missing incident: $1"; }
gf_refute_incident()  { gf_incident "$1" || return 0; [ -n "$GF_FAILED" ] && return 0; GF_FAILED="unexpected incident: $1"; }
gf_done() {
  if [ -n "$GF_FAILED" ]; then
    echo "SCENARIO_RESULT: fail — ${GF_FAILED}"
  else
    echo "SCENARIO_RESULT: pass"
  fi
}

# --- Scenarios --------------------------------------------------------------

# 1. Full wipe of a >=MIN_TASKS board restores every file.
scenario_wipe_restores() {
  gf_init
  gf_task 1 T1; gf_task 2 T2; gf_task 3 T3
  gf_tick                       # mirror; LAST_COUNT=3
  gf_wipe
  gf_tick                       # detect wipe + restore
  gf_check "restored live count" "$(gf_live)" 3
  gf_check "wipe latch cleared" "$WIPE_PENDING" 0
  gf_assert_incident "restored 3 task files"
  gf_done
}

# 2. A 1->0 drop is below the wipe signature: never restored, and with NO
#    manifest there is no incident at all (pure legitimate single deletion).
scenario_below_sig_no_manifest() {
  gf_init
  gf_task 1 T1
  gf_tick                       # LAST_COUNT=1
  gf_wipe
  gf_tick
  gf_check "not restored" "$(gf_live)" 0
  gf_refute_incident "below-signature deletion"
  gf_refute_incident "restored"
  gf_done
}

# 3. The same 1->0 drop WITH a manifest still expecting tasks leaves an audit
#    line — mirrored only, never restored.
scenario_below_sig_logs_with_manifest() {
  gf_init
  mkdir -p "${TASKS_ROOT}/.manifest/${LIST}"
  printf '{"task_ids":["T1"]}\n' > "${TASKS_ROOT}/.manifest/${LIST}/manifest.json"
  gf_task 1 T1
  gf_tick
  gf_wipe
  gf_tick
  gf_check "not restored" "$(gf_live)" 0
  gf_assert_incident "below-signature deletion"
  gf_done
}

# 4 + 5. A live writer lease defers restore (latch set); releasing the lease lets
#        the next tick restore. Tests the cross-tick WIPE_PENDING latch.
scenario_lease_defer_then_restore() {
  gf_init
  gf_task 1 T1; gf_task 2 T2; gf_task 3 T3
  gf_tick
  gf_lease 0                    # live lease
  gf_wipe
  gf_tick                       # deferred
  gf_check "deferred: still empty" "$(gf_live)" 0
  gf_check "wipe latch set" "$WIPE_PENDING" 1
  gf_assert_incident "restore DEFERRED"
  gf_lease_release
  gf_tick                       # latch fires restore
  gf_check "restored after release" "$(gf_live)" 3
  gf_check "latch cleared" "$WIPE_PENDING" 0
  gf_done
}

# 6. A stale lease (heartbeat past TTL) is overridden — restore proceeds and the
#    override is logged.
scenario_stale_lease_overridden() {
  gf_init
  gf_task 1 T1; gf_task 2 T2; gf_task 3 T3
  gf_tick
  gf_lease -100000             # heartbeat far past LEASE_TTL
  gf_wipe
  gf_tick
  gf_check "restored despite lease" "$(gf_live)" 3
  gf_assert_incident "STALE lease overridden"
  gf_done
}

# 7. Newer journal evidence is never clobbered: a task whose result.json is newer
#    than its shadow is skipped; its siblings restore.
scenario_evidence_newer_skip() {
  gf_init
  gf_task 1 T1; gf_task 2 T2; gf_task 3 T3
  gf_tick                       # mirror all three to shadow (~now)
  gf_wipe
  # T1 has fresh journal evidence (future mtime) — must be skipped.
  printf '{"task_id":"T1","status":"completed"}\n' > "${LIST_DIR}/T1.result.json"
  touch -t 203012312359 "${LIST_DIR}/T1.result.json"
  gf_tick
  gf_check "siblings restored, T1 skipped" "$(gf_live)" 2
  gf_check "T1 not restored" "$([ -f "${LIST_DIR}/1.json" ] && echo yes || echo no)" no
  gf_assert_incident "evidence-newer"
  gf_done
}

# 8. Gradual single-file deletion prunes the shadow to match — UNLESS the
#    manifest still expects that task, in which case the shadow is retained.
scenario_manifest_prune_skip() {
  gf_init
  mkdir -p "${TASKS_ROOT}/.manifest/${LIST}"
  printf '{"task_ids":["T2"]}\n' > "${TASKS_ROOT}/.manifest/${LIST}/manifest.json"
  gf_task 1 T1; gf_task 2 T2
  gf_tick                       # LAST_COUNT=2, both mirrored
  rm -f "${LIST_DIR}/2.json"    # gradual: 2 -> 1
  gf_tick
  gf_check "shadow retained (not pruned)" "$(gf_shadow)" 2
  gf_assert_incident "PRUNE skipped for 2.json"
  gf_done
}

# 9. Gradual single-file deletion of a non-manifest task DOES prune the shadow.
scenario_gradual_delete_prunes() {
  gf_init
  gf_task 1 T1; gf_task 2 T2
  gf_tick
  rm -f "${LIST_DIR}/2.json"    # gradual: 2 -> 1, no manifest
  gf_tick
  gf_check "shadow pruned" "$(gf_shadow)" 1
  gf_refute_incident "restored"
  gf_done
}

# 10. Restore never writes through a planted symlink (would escape the list dir);
#     a regular sibling still restores. Calls guard_restore directly — the symlink
#     occupies the target name, which would otherwise foil tick-based wipe detect.
scenario_symlink_not_restored() {
  gf_init
  local evil="${TASKS_ROOT}/evil-target"
  rm -f "$evil"
  # Shadow holds two tasks; list dir is "wiped" but 1.json is a planted symlink.
  gf_task 1 T1; gf_task 2 T2
  cp -p "${LIST_DIR}/1.json" "${SHADOW}/1.json"
  cp -p "${LIST_DIR}/2.json" "${SHADOW}/2.json"
  gf_wipe
  ln -s "$evil" "${LIST_DIR}/1.json"
  guard_restore "$LIST" "$LIST_DIR" "$SHADOW" 2 >/dev/null
  gf_check "symlink not followed (evil unwritten)" "$([ -e "$evil" ] && echo yes || echo no)" no
  gf_check "sibling restored as regular file" "$([ -f "${LIST_DIR}/2.json" ] && [ ! -L "${LIST_DIR}/2.json" ] && echo yes || echo no)" yes
  gf_done
}

# 11. A board that legitimately grows over ticks is mirrored, never restored.
scenario_legit_growth_no_restore() {
  gf_init
  gf_task 1 T1; gf_task 2 T2
  gf_tick
  gf_task 3 T3
  gf_tick
  gf_task 4 T4
  gf_tick
  gf_check "all mirrored" "$(gf_shadow)" 4
  gf_check "live intact" "$(gf_live)" 4
  gf_check "last count tracks growth" "$LAST_COUNT" 4
  gf_refute_incident "restored"
  gf_done
}

# 12. Boundary: a wipe from exactly MIN_TASKS (2) still trips the signature.
scenario_wipe_at_min_boundary() {
  gf_init
  gf_task 1 T1; gf_task 2 T2
  gf_tick
  gf_wipe
  gf_tick
  gf_check "boundary wipe restored" "$(gf_live)" 2
  gf_assert_incident "restored 2 task files"
  gf_done
}

# Registry — the standalone runner iterates this; keep in sync with test_cases.jsonl.
# shellcheck disable=SC2034  # consumed by run.sh after sourcing this file
GF_SCENARIOS="
wipe_restores
below_sig_no_manifest
below_sig_logs_with_manifest
lease_defer_then_restore
stale_lease_overridden
evidence_newer_skip
manifest_prune_skip
gradual_delete_prunes
symlink_not_restored
legit_growth_no_restore
wipe_at_min_boundary
"
