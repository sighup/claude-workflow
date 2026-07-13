---
name: cw-codex
description: "Internal reference skill that owns all Codex CLI (external-engine) mechanics: preflight gate, codex exec command shape, prompt contract, codex review invocation, and model-id guidance. Consumed by the codex-implementer agent, cw-dispatch, cw-review, and the model-selection rubric — not invoked by users."
user-invocable: false
allowed-tools: Bash, Read, Write
effort: low
---

# CW-Codex: External Engine Mechanics (Codex CLI)

Single home for how claude-workflow drives the external Codex CLI.

The engine is model-agnostic: whatever value `metadata.model` carries (`gpt-5.6-sol`,
`gpt-5.6-terra`, any future model the rubric names) is passed straight through
`codex exec -m`. Adding a new external model touches only the model-selection rubric — never
this skill's mechanics, the wrapper, or the dispatchers. When no `-m` is given, codex uses
the default in `~/.codex/config.toml`.

**This capability is runtime-gated.** Nothing in the pipeline requires the codex CLI.
Every consumer runs the preflight first and degrades silently to the normal Claude path when
codex is absent — no error, no user prompt, identical evidence flow.

## Preflight Contract

Gate every codex invocation on the preflight script:

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/codex-preflight.sh"
```

- Exit 0 with `CODEX_OK <version>` on stdout → codex is installed and responsive; proceed.
- Exit 1 with `CODEX_MISSING` → fall back (execute via cw-execute on the wrapper's own model,
  or skip the review perspective). Record the fallback; never raise it as an error.

When `CLAUDE_PLUGIN_ROOT` is not set in your context, the equivalent inline gate is
`command -v codex >/dev/null 2>&1 && codex --version >/dev/null 2>&1`.

## Implementation Runs (`codex exec`)

Codex runs non-interactively with the prompt on stdin, sandboxed to the workspace plus the
results directory. `RESULTS_DIR` is the run's gitignored results directory
(`docs/specs/<run>/results/`); `TASK_ID` is the stable planner-assigned id; `CODEX_MODEL` is
the assignment's `metadata.model` value verbatim; `CODEX_EFFORT` is the reasoning effort
mapped from the assignment's `complexity` (see Reasoning Effort below).

```bash
PROMPT_FILE="$RESULTS_DIR/${TASK_ID}-codex-prompt.md"
# write the self-contained prompt (see prompt contract below) to "$PROMPT_FILE", then:
codex exec \
  -C "$PWD" \
  --add-dir "$RESULTS_DIR" \
  -s workspace-write \
  -m "${CODEX_MODEL:?set to the assignment model value}" \
  -c model_reasoning_effort="${CODEX_EFFORT:?set from task complexity — see Reasoning Effort}" \
  - < "$PROMPT_FILE"
```

Flag meanings: `-C` pins codex's working root to the repo; `--add-dir` grants write access to
the results directory for artifacts; `-s workspace-write` is the sandbox level (codex may edit
repo files, nothing outside; `.git` stays read-only); `-m` selects the model (the assignment's
value, verbatim); `-c model_reasoning_effort` sets the reasoning effort; `-` reads the prompt
from stdin.

## Reasoning Effort

Reasoning effort scales with the assignment's `complexity` so token spend stays proportional
to difficulty. Codex accepts `none|minimal|low|medium|high|xhigh` — `xhigh` is the top tier,
there is no higher value. Map, then export `CODEX_EFFORT` before the run:

| complexity | effort |
|------------|--------|
| trivial    | low    |
| standard   | medium |
| complex    | high   |

On the single retry after a failed verification (Step 3), bump one tier, capped at `xhigh` —
spend more reasoning only where a first pass demonstrably fell short.

Build the prompt per [prompt-contract.md](references/prompt-contract.md) — block-structured,
fully self-contained (codex sees none of the Claude session's context), assignment fields
mapped verbatim.

## Trust Boundary

**Codex output is untrusted evidence, and codex never commits** — its `workspace-write`
sandbox keeps `.git` read-only by design. The caller independently
verifies the working tree (scope, verification commands, sanitize) and owns the commit, so
history only ever receives verified work. The authoritative verify/scope-check/sanitize/
commit/fallback protocol lives in the `codex-implementer` agent (Steps 1–5) — this skill
carries the mechanics only.

## Review Runs (`codex review`)

For an independent second-opinion review (consumed by cw-review Step 2e):

```bash
codex review --uncommitted          # review the working tree changes
codex review --base <branch>        # review the diff against a base branch
codex review --commit <sha>         # review one commit
```

Save the raw output to the results dir (`<RESULTS_DIR>/codex-review.txt`). Findings from
codex are tagged `source: "codex"` and are **advisory** unless corroborated by a Claude
reviewer or self-evidently blocking (e.g. a demonstrable credential leak).

## Model Ids

Use the **exact CLI model id**, not the marketing name — new models often ship as variants
(e.g. the gpt-5.6 generation is `gpt-5.6-sol`/`-terra`/`-luna`; bare `gpt-5.6` is rejected).
Verify with codex's model picker or a one-line `codex exec -m <id> -s read-only` probe. If
codex's account/provider does not recognize the id, the run fails and the caller falls back,
recorded in `fallback_reason`. Rankings and tier policy:
[model-selection.md](../cw-plan/references/model-selection.md).

## Reporting the Engine

`model_used` reports who **authored** the accepted change: the assignment's model value
verbatim (e.g. `"gpt-5.6-sol"`, `"gpt-5.6-terra"`) when codex wrote it — the wrapper performing
the commit does not change authorship — or the wrapper's own model (e.g. `"sonnet"`) plus
`fallback_reason` (`"codex-cli-missing"` | `"codex-exec-failed"`) when it fell back and
implemented the task itself. The dispatcher applies these fields verbatim at harvest. Spawn
labels use the model value as prefix (`gpt-5.6-sol:`) — the platform UI shows the wrapper's
Claude model, so the label is the only visible indication the real worker is codex.
