#!/bin/bash
#
# tests/helpers.sh - assertion and fixture helpers, sourced by every *.test.sh.
#
# Must stay /bin/bash 3.2 compatible (macOS system bash): no mapfile,
# no associative arrays, no ${var,,}.
#

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/plugin"

_PASS=0
_FAIL=0
_CURRENT=""

CW_TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/cw-tests.XXXXXX") || exit 1
trap 'rm -rf "$CW_TEST_TMP"' EXIT

t() { _CURRENT="$1"; }

pass() { _PASS=$((_PASS + 1)); echo "  ok: $_CURRENT"; }
fail() { _FAIL=$((_FAIL + 1)); echo "  FAIL: $_CURRENT${1:+ — $1}" >&2; }

assert_eq() { # expected actual
    if [ "$1" = "$2" ]; then pass; else fail "expected '$1', got '$2'"; fi
}

assert_empty() { # actual
    if [ -z "$1" ]; then pass; else fail "expected empty, got '$1'"; fi
}

assert_contains() { # haystack needle
    case "$1" in
        (*"$2"*) pass ;;
        (*) fail "output does not contain '$2' (got: '$1')" ;;
    esac
}

assert_success() { # exit-code
    if [ "$1" -eq 0 ]; then pass; else fail "expected exit 0, got $1"; fi
}

assert_failure() { # exit-code
    if [ "$1" -ne 0 ]; then pass; else fail "expected non-zero exit"; fi
}

assert_file() { if [ -f "$1" ]; then pass; else fail "missing file: $1"; fi; }
assert_no_file() { if [ ! -e "$1" ]; then pass; else fail "unexpected file: $1"; fi; }
assert_dir() { if [ -d "$1" ]; then pass; else fail "missing dir: $1"; fi; }

# Create a throwaway git repo (one commit on main) and print its path.
# Usage: repo=$(make_repo [dirname])
# The dirname becomes the {repo} component of derived worktree names.
make_repo() {
    local name="${1:-myrepo}"
    local parent repo
    parent=$(mktemp -d "$CW_TEST_TMP/r.XXXXXX") || return 1
    repo="$parent/$name"
    mkdir -p "$repo"
    git -C "$repo" init -q
    git -C "$repo" symbolic-ref HEAD refs/heads/main
    git -C "$repo" config user.name "CW Tests"
    git -C "$repo" config user.email "tests@example.invalid"
    git -C "$repo" config commit.gpgsign false
    echo "seed" > "$repo/README.md"
    git -C "$repo" add README.md
    git -C "$repo" commit -qm "init"
    # Physical path: macOS TMPDIR lives under the /var -> /private/var symlink
    # and path comparisons must not depend on which alias git reports.
    (cd "$repo" && pwd -P)
}

# Print the per-file summary and exit non-zero if anything failed.
# Every test file must end with: finish
finish() {
    echo "  ($_PASS passed, $_FAIL failed)"
    [ "$_FAIL" -eq 0 ]
}
