#!/bin/bash
#
# codex-routing.test.sh - the gpt-5.5 (Codex CLI) executor tier is strictly
# additive and runtime-gated. Guards:
#   - no-codex environments behave identically to 3.7.1 (metadata hook accepts
#     "gpt-5.5" exactly like "sonnet"; preflight degrades cleanly; no new hooks)
#   - routing plumbing exists when codex is present (preflight OK path; the
#     documented `codex exec` command shape parses and passes verified flags)
#
source "$(dirname "$0")/helpers.sh"

VALIDATE="$PLUGIN_DIR/scripts/validate-task-metadata.sh"
PREFLIGHT="$PLUGIN_DIR/scripts/codex-preflight.sh"
CODEX_DOC="$PLUGIN_DIR/skills/cw-dispatch/references/codex-execution.md"
RUBRIC="$PLUGIN_DIR/skills/cw-plan/references/model-selection.md"
WRAPPER_AGENT="$PLUGIN_DIR/agents/codex-implementer.md"

echo "codex routing: runtime gating + no-codex parity"

t "new files exist"
if [ -f "$PREFLIGHT" ] && [ -f "$CODEX_DOC" ] && [ -f "$RUBRIC" ] && [ -f "$WRAPPER_AGENT" ]; then
    pass
else
    fail "missing one of preflight/doc/rubric/wrapper"
fi

# --- (a) metadata hook parity: "gpt-5.5" is treated exactly like "sonnet" ---

make_task_input() { # model
    printf '{"task":{"metadata":{"task_id":"T01","demoable_unit":1,"spec_path":"docs/specs/x.md","scope":{"files_to_modify":["a.ts"]},"requirements":[{"id":"R1.1","text":"x","testable":true}],"model":"%s"}}}' "$1"
}

t "validate hook accepts gpt-5.5 fixture silently (exit 0)"
out_gpt=$(make_task_input "gpt-5.5" | /bin/bash "$VALIDATE"); rc=$?
assert_success $rc

t "gpt-5.5 fixture output identical to sonnet fixture output"
out_sonnet=$(make_task_input "sonnet" | /bin/bash "$VALIDATE")
assert_eq "$out_sonnet" "$out_gpt"

t "gpt-5.5 fixture output is empty (no warning)"
assert_empty "$out_gpt"

t "legacy fixture (missing fields) still warns exactly as before"
out_legacy=$(printf '{"task":{"metadata":{"model":"gpt-5.5"}}}' | /bin/bash "$VALIDATE")
assert_contains "$out_legacy" "missing metadata: task_id, demoable_unit, spec_path, scope, requirements"

# --- (a) preflight degrades cleanly without codex ---

t "preflight without codex on PATH: exit 1"
out=$(PATH="$CW_TEST_TMP/emptybin" /bin/bash "$PREFLIGHT" 2>&1); rc=$?
assert_failure $rc

t "preflight without codex prints CODEX_MISSING"
assert_contains "$out" "CODEX_MISSING"

# --- (a) structural gates: additive change only ---

t "plugin.json wires no codex hook (capability is agent-driven, not hook-driven)"
out=$(grep -c codex "$PLUGIN_DIR/.claude-plugin/plugin.json" 2>/dev/null || true)
assert_eq "0" "$out"

t "codex-implementer wrapper pins model: sonnet"
grep -q '^model: sonnet$' "$WRAPPER_AGENT"
assert_success $?

t "codex-implementer is a leaf agent (no Task tool)"
tools_line=$(grep '^tools:' "$WRAPPER_AGENT")
case "$tools_line" in
    (*Task*) fail "tools line grants Task: $tools_line" ;;
    (*) pass ;;
esac

t "codex-implementer declares the cw-execute fallback skill"
grep -q 'cw-execute' "$WRAPPER_AGENT"
assert_success $?

t "cw-dispatch routes gpt-5.5 to the wrapper"
grep -q 'claude-workflow:codex-implementer' "$PLUGIN_DIR/skills/cw-dispatch/SKILL.md"
assert_success $?

t "cw-dispatch-team routes gpt-5.5 to the wrapper (parity)"
grep -q 'claude-workflow:codex-implementer' "$PLUGIN_DIR/skills/cw-dispatch-team/SKILL.md"
assert_success $?

t "cw-plan consults the model-selection rubric"
grep -q 'references/model-selection.md' "$PLUGIN_DIR/skills/cw-plan/SKILL.md"
assert_success $?

t "cw-review guards the external perspective on codex presence"
grep -q 'command -v codex' "$PLUGIN_DIR/skills/cw-review/SKILL.md"
assert_success $?

t "cw-review skips silently when codex is absent"
grep -q 'never an error' "$PLUGIN_DIR/skills/cw-review/SKILL.md"
assert_success $?

# --- (b) codex present: preflight OK + documented exec shape is sound ---

STUB_BIN="$CW_TEST_TMP/bin"
mkdir -p "$STUB_BIN" "$CW_TEST_TMP/emptybin"
CODEX_ARGV_FILE="$CW_TEST_TMP/codex-argv.txt"
cat > "$STUB_BIN/codex" <<EOF
#!/bin/bash
if [ "\${1:-}" = "--version" ]; then echo "codex-cli 0.0.0-stub"; exit 0; fi
printf '%s\n' "\$@" > "$CODEX_ARGV_FILE"
cat >/dev/null
exit 0
EOF
chmod +x "$STUB_BIN/codex"

t "preflight with codex on PATH: exit 0 and CODEX_OK"
out=$(PATH="$STUB_BIN:/usr/bin:/bin" /bin/bash "$PREFLIGHT" 2>&1); rc=$?
if [ $rc -eq 0 ]; then
    assert_contains "$out" "CODEX_OK"
else
    fail "preflight exit $rc: $out"
fi

# Extract the documented `codex exec` snippet and run it against the stub —
# guards doc drift from the flag shape verified against codex-cli 0.142.5.
SNIP="$CW_TEST_TMP/codex-exec-snippet.sh"
awk '
    /^PROMPT_FILE="\$RESULTS_DIR/ { f = 1 }
    f { print }
    f && /- < "\$PROMPT_FILE"$/ { exit }
' "$CODEX_DOC" > "$SNIP"

t "codex exec snippet extracted from codex-execution.md"
grep -q '^codex exec' "$SNIP"
assert_success $?

t "codex exec snippet parses under this bash"
if err=$(bash -n "$SNIP" 2>&1); then pass; else fail "$err"; fi

t "codex exec snippet passes the verified flag shape to the CLI"
RESULTS_DIR="$CW_TEST_TMP/results"
mkdir -p "$RESULTS_DIR"
WRAP="$CW_TEST_TMP/codex-exec-wrapper.sh"
{
    echo '#!/bin/bash'
    echo "RESULTS_DIR=\"$RESULTS_DIR\""
    echo 'TASK_ID="T01"'
    echo 'echo "stub prompt" > "$RESULTS_DIR/${TASK_ID}-codex-prompt.md"'
    cat "$SNIP"
} > "$WRAP"
PATH="$STUB_BIN:/usr/bin:/bin" /bin/bash "$WRAP" >/dev/null 2>&1
argv=$(cat "$CODEX_ARGV_FILE" 2>/dev/null | tr '\n' ' ')
case "$argv" in
    (exec*-C*--add-dir*-s\ workspace-write*-\ *) pass ;;
    (*) fail "argv was: '$argv'" ;;
esac

finish
