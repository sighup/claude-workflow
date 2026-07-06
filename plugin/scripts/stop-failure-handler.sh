#!/bin/bash
# stop-failure-handler.sh
# StopFailure hook for rate-limit/auth detection
#
# Part of claude-workflow plugin - automatically active when plugin is installed
#
# Reads hook input JSON from stdin, detects rate-limit or auth failure patterns,
# and outputs actionable additionalContext guidance when patterns match.
# Exits silently (exit 0, no output) when no patterns match.

set -euo pipefail

# Read hook input from stdin
INPUT=$(cat)

# Extract stop reason/error text from hook input
# StopFailure hook may provide stop_reason, error, or similar field
STOP_REASON=$(echo "$INPUT" | jq -r '
  .stop_reason //
  .error //
  .reason //
  .message //
  "" | ascii_downcase')

# Detect rate-limit patterns (case-insensitive via ascii_downcase above)
if echo "$STOP_REASON" | grep -qE 'rate.?limit|429|too many requests|quota exceeded'; then
  cat << 'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "StopFailure",
    "additionalContext": "Rate limit hit -- consider pausing /cw-dispatch and retrying in 60s. If running parallel workers, reduce concurrency. Check your provider's usage dashboard for current limits."
  }
}
EOF
  exit 0
fi

# Detect auth failure patterns (case-insensitive via ascii_downcase above)
if echo "$STOP_REASON" | grep -qE 'unauthorized|401|403|authentication.?fail|invalid.?token|expired.?token'; then
  cat << 'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "StopFailure",
    "additionalContext": "Authentication failure detected -- check API keys and token expiration. Verify your provider credentials are set and valid in .claude/settings.json or environment variables."
  }
}
EOF
  exit 0
fi

# No recognized failure pattern - exit silently
exit 0
