#!/bin/bash
# codex-preflight.sh
# Runtime gate for the optional external (Codex CLI) executor tier.
#
# Part of claude-workflow plugin - invoked by the codex-implementer agent and
# cw-review before any codex invocation. No side effects, no hook wiring.
#
# Prints "CODEX_OK <version>" and exits 0 when the codex CLI is installed and
# responsive. Prints "CODEX_MISSING" and exits 1 otherwise — callers fall back
# to the normal Claude execution path and record the fallback; this exit is
# never an error condition.
#
# Must stay /bin/bash 3.2 compatible (macOS system bash).

set -euo pipefail

if ! command -v codex >/dev/null 2>&1; then
  echo "CODEX_MISSING"
  exit 1
fi

if ! VERSION=$(codex --version 2>/dev/null); then
  echo "CODEX_MISSING"
  exit 1
fi

echo "CODEX_OK ${VERSION}"
exit 0
