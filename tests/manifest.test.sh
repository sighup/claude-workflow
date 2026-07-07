#!/bin/bash
#
# Marketplace/plugin manifest layout. Claude Code only recognizes a git
# marketplace via .claude-plugin/marketplace.json at the repository ROOT
# (it does not search subdirectories), while the shippable plugin content
# lives under plugin/ — so the root manifest must point its source there.
#
source "$(dirname "$0")/helpers.sh"

MKT="$REPO_ROOT/.claude-plugin/marketplace.json"
PLG="$PLUGIN_DIR/.claude-plugin/plugin.json"

echo "manifests: marketplace + plugin metadata layout"

t "jq available (documented plugin prerequisite)"
command -v jq >/dev/null 2>&1
assert_success $?

t "marketplace manifest sits at the repository root"
assert_file "$MKT"

t "marketplace manifest is valid JSON"
jq empty "$MKT" >/dev/null 2>&1
assert_success $?

t "plugin source points at ./plugin"
assert_eq "./plugin" "$(jq -r '.plugins[0].source' "$MKT" 2>/dev/null)"

t "no stray marketplace manifest under plugin/"
assert_no_file "$PLUGIN_DIR/.claude-plugin/marketplace.json"

t "plugin.json exists at the plugin root"
assert_file "$PLG"

t "plugin.json name matches the marketplace entry"
assert_eq "$(jq -r '.plugins[0].name' "$MKT" 2>/dev/null)" \
    "$(jq -r '.name' "$PLG" 2>/dev/null)"

t "every hook command in plugin.json resolves under plugin/"
missing=$(jq -r '.. | .command? // empty' "$PLG" 2>/dev/null \
    | sed "s|\${CLAUDE_PLUGIN_ROOT}|$PLUGIN_DIR|" \
    | while IFS= read -r p; do [ -f "$p" ] || printf '%s\n' "$p"; done)
assert_empty "$missing"

finish
