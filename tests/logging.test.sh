#!/bin/bash
#
# log_warning/log_error must write to stderr so they never pollute $(...)
# command substitutions in callers; log_info/log_success stay on stdout.
# Both library copies (scripts/lib and bin/lib) are checked.
#
source "$(dirname "$0")/helpers.sh"

check_lib() {
    local lib="$1" label="$2"

    t "$label: log_error stdout is empty"
    out=$(bash -c "source '$lib'; log_error boom" 2>/dev/null)
    assert_empty "$out"

    t "$label: log_error message reaches stderr"
    err=$(bash -c "source '$lib'; log_error boom" 2>&1 >/dev/null)
    assert_contains "$err" "boom"

    t "$label: log_warning stdout is empty"
    out=$(bash -c "source '$lib'; log_warning careful" 2>/dev/null)
    assert_empty "$out"

    t "$label: log_warning message reaches stderr"
    err=$(bash -c "source '$lib'; log_warning careful" 2>&1 >/dev/null)
    assert_contains "$err" "careful"

    t "$label: log_info stays on stdout"
    out=$(bash -c "source '$lib'; log_info hello" 2>/dev/null)
    assert_contains "$out" "hello"

    t "$label: log_success stays on stdout"
    out=$(bash -c "source '$lib'; log_success done" 2>/dev/null)
    assert_contains "$out" "done"
}

echo "logging: stream routing in both cw-common.sh copies"
check_lib "$PLUGIN_DIR/scripts/lib/cw-common.sh" "scripts/lib"
check_lib "$PLUGIN_DIR/bin/lib/cw-common.sh" "bin/lib"

finish
