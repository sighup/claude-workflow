#!/bin/bash
#
# The cw-worktree reference docs contain shell snippets that agents execute
# verbatim. These tests extract the worktree-lookup snippet from the markdown
# and run it under this interpreter (/bin/bash 3.2 via the runner), guarding:
#   - the case-pattern-inside-$() parse error (needs the leading-paren form)
#   - space-unsafe `awk '{print $2}'` worktree parsing
#   - lookup behavior: resolve, not-found, and ambiguous-match error
#
source "$(dirname "$0")/helpers.sh"

REFS="$PLUGIN_DIR/skills/cw-worktree/references"
CMD="$REFS/worktree-commands.md"
LIFE="$REFS/worktree-lifecycle.md"

echo "doc snippets: lookup snippet extraction + shell-safety regressions"

t "reference docs exist"
if [ -f "$CMD" ] && [ -f "$LIFE" ]; then pass; else fail "missing $CMD or $LIFE"; fi

# --- Extract the first lookup snippet occurrence from worktree-commands.md ---
SNIP="$CW_TEST_TMP/lookup-snippet.sh"
awk '
    /_MATCHES=\$\(git worktree list/ { f = 1 }
    f { sub(/^[[:space:]]*/, ""); print }
    f && /^WORKTREE_DIR="\$_MATCHES"/ { exit }
' "$CMD" > "$SNIP"

t "lookup snippet extracted from worktree-commands.md"
grep -q '^WORKTREE_DIR="\$_MATCHES"$' "$SNIP"
assert_success $?

t "lookup snippet parses under this bash (case-in-\$() regression)"
if err=$(bash -n "$SNIP" 2>&1); then pass; else fail "$err"; fi

# --- Extract the WT= lookup variant from worktree-lifecycle.md ---
LSNIP="$CW_TEST_TMP/lifecycle-snippet.sh"
awk '
    /^WT=\$\(git worktree list/ { f = 1 }
    f { print }
    f && /done\)$/ { exit }
' "$LIFE" > "$LSNIP"

t "lifecycle WT snippet extracted and parses"
if [ -s "$LSNIP" ] && err=$(bash -n "$LSNIP" 2>&1); then pass; else fail "${err:-empty extraction}"; fi

# --- Run the commands.md snippet against a fixture repo ---
WRAP="$CW_TEST_TMP/lookup-wrapper.sh"
{
    echo '#!/bin/bash'
    echo 'FEATURE="$1"'
    cat "$SNIP"
    echo 'printf "%s\n" "$WORKTREE_DIR"'
} > "$WRAP"

repo=$(make_repo myrepo)
git -C "$repo" worktree add -q -b fix/login "$repo/.claude/worktrees/fix-myrepo-login" >/dev/null 2>&1
git -C "$repo" worktree add -q -b feature/auth "$repo/.claude/worktrees/feature-myrepo-auth" >/dev/null 2>&1

t "short name resolves via suffix match"
out=$(cd "$repo" && bash "$WRAP" login)
assert_eq "fix-myrepo-login" "$(basename "${out:-none}")"

t "resolved path is a real directory"
if [ -n "$out" ] && [ -d "$out" ]; then pass; else fail "not a directory: '$out'"; fi

t "full basename resolves via exact match"
out=$(cd "$repo" && bash "$WRAP" fix-myrepo-login)
assert_eq "fix-myrepo-login" "$(basename "${out:-none}")"

t "unknown feature resolves to empty (caller handles not-found)"
out=$(cd "$repo" && bash "$WRAP" bogus)
assert_empty "$out"

git -C "$repo" worktree add -q -b fix/dup "$repo/.claude/worktrees/fix-myrepo-dup" >/dev/null 2>&1
git -C "$repo" worktree add -q -b feature/dup "$repo/.claude/worktrees/feature-myrepo-dup" >/dev/null 2>&1

t "ambiguous feature name errors instead of picking one"
out=$(cd "$repo" && bash "$WRAP" dup 2>&1)
rc=$?
assert_failure $rc
t "ambiguous error lists the candidates"
assert_contains "$out" "matches multiple"

# --- Whole-tree regression greps ---

t "no space-unsafe awk worktree parsing anywhere in plugin/"
out=$(grep -rn -- "/^worktree /{print" "$PLUGIN_DIR" 2>/dev/null)
assert_empty "$out"

t "every lookup case pattern uses the bash-3.2-safe leading paren"
out=$(grep -rn 'case "\$_b" in' "$REFS" | grep -v 'in ("')
assert_empty "$out"

t "lookup snippet occurrences are structurally consistent"
starts=$(grep -cF '_MATCHES=$(git worktree list' "$CMD")
ends=$(grep -c '^ *WORKTREE_DIR="\$_MATCHES"$' "$CMD")
assert_eq "$starts" "$ends"

t "merge flow rolls back with ORIG_HEAD (not merge --abort)"
grep -q 'git reset --hard ORIG_HEAD' "$CMD"
assert_success $?

t "permission allowlist includes namespaced skill rules"
grep -q 'Skill(claude-workflow:cw-' "$CMD"
assert_success $?

finish
