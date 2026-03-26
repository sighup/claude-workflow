#!/bin/bash
#
# plugin-data-init.sh - Idempotent initializer for CLAUDE_PLUGIN_DATA directories
#
# Creates ${CLAUDE_PLUGIN_DATA}/logs/ if it does not already exist.
# Exits non-zero with an error message when CLAUDE_PLUGIN_DATA is unset.
#
# Usage:
#   bash scripts/plugin-data-init.sh
#
# Environment variables:
#   CLAUDE_PLUGIN_DATA  (required) Path to the plugin data directory

set -euo pipefail

if [ -z "${CLAUDE_PLUGIN_DATA:-}" ]; then
    echo "Error: CLAUDE_PLUGIN_DATA is required but is not set." >&2
    exit 1
fi

mkdir -p "${CLAUDE_PLUGIN_DATA}/logs"
