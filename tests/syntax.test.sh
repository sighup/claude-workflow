#!/bin/bash
#
# Every shell file shipped under plugin/ must parse under this interpreter
# (the runner invokes tests with /bin/bash — macOS 3.2 — by default).
#
source "$(dirname "$0")/helpers.sh"

echo "syntax: bash -n over all plugin shell files"

count=0
while IFS= read -r f; do
    count=$((count + 1))
    t "parse ${f#"$REPO_ROOT"/}"
    if err=$(bash -n "$f" 2>&1); then pass; else fail "$err"; fi
done < <(find "$PLUGIN_DIR" -type f \( -name '*.sh' -o -path '*/bin/cw-*' \) | sort)

t "found a plausible number of shell files"
if [ "$count" -ge 10 ]; then pass; else fail "only $count files found — find pattern broken?"; fi

finish
