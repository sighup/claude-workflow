#!/bin/bash
#
# bench/lib/checksum_guard.sh - checksum the benchmark's designated ground-truth
# test files before and after the agent runs, so run_instance.sh can detect an
# agent that "resolves" an instance by editing the test itself.
#
# Sourced by bench/run_instance.sh. Uses a portable hash (shasum -> sha256sum ->
# cksum fallback) so it works on stock macOS and Linux without extra deps.
#
set -euo pipefail

# _hash_file <path> -> prints a hex/opaque digest of the file's contents.
_hash_file() {
  local f="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$f" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$f" | awk '{print $1}'
  else
    cksum "$f" | awk '{print $1"-"$2}'
  fi
}

# record_checksums <repo_dir> <out_file> <relfile>...
# writes "<digest>  <relfile>" lines (digest MISSING when the file is absent).
record_checksums() {
  local repo="$1" out="$2"
  shift 2
  : > "$out"
  local rel
  for rel in "$@"; do
    if [ -f "$repo/$rel" ]; then
      printf '%s  %s\n' "$(_hash_file "$repo/$rel")" "$rel" >> "$out"
    else
      printf '%s  %s\n' "MISSING" "$rel" >> "$out"
    fi
  done
}

# compare_checksums <repo_dir> <baseline_file> <relfile>...
# prints the count of files whose current digest differs from the baseline.
compare_checksums() {
  local repo="$1" baseline="$2"
  shift 2
  local changed=0 rel before after
  for rel in "$@"; do
    before="$(awk -v r="$rel" '$2 == r {print $1; exit}' "$baseline")"
    if [ -f "$repo/$rel" ]; then
      after="$(_hash_file "$repo/$rel")"
    else
      after="MISSING"
    fi
    if [ "$before" != "$after" ]; then
      changed=$((changed + 1))
    fi
  done
  printf '%s' "$changed"
}
