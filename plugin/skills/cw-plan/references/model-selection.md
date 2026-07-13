# Model Selection Rubric

Consulted by `cw-plan` when assigning `metadata.model` to each task. Ships inside the plugin
so model policy loads at plan time everywhere — it never depends on a user-level CLAUDE.md.

## Rankings

Higher = better. **Cost** reflects what is actually paid, **intelligence** how hard a problem
the model takes unsupervised, **taste** UI/UX, code quality, API design, and copy.

| model         | cost | intelligence | taste |
|---------------|------|--------------|-------|
| gpt-5.6-sol   | 9    | 9            | 5     |
| gpt-5.6-terra | 9    | 8            | 4     |
| sonnet        | 5    | 5            | 7     |
| opus          | 4    | 7            | 8     |
| fable         | 2    | 9            | 9     |

`gpt-5.6-sol` is the external default (frontier tier). `gpt-5.6-terra` is the balanced
5.6-generation tier — comparable context, ~half the token cost, lighter on Codex usage
limits, in exchange for some intelligence and noticeably less design sense. Reach for terra
only on the highest-volume, purely-mechanical bulk work where conserving sol's budget matters
and taste is irrelevant.

## How to Apply

- These are defaults, not limits. If a cheaper model's output misses the bar, redo it with a
  smarter one — judge the output, not the price tag. When axes conflict for anything that
  ships: **intelligence > taste > cost** (cost breaks ties only).
- **Bulk/mechanical work** (clear-spec implementation, migrations, data plumbing) → the
  external tier. Eligible only when ALL hold: requirements fully specified (clear R-IDs, no
  design judgment left to the executor); scope exhaustive
  (`files_to_create`/`files_to_modify` complete); and sonnet is an acceptable executor — the
  tier is **runtime-gated**, so a host without the codex CLI silently runs the task on sonnet.
- **Anything user-facing** (UI, copy, API surface) needs taste ≥ 7 → never the external tier.
- **Reviews** → opus (fable when orchestrating), optionally an extra independent Codex
  perspective (cw-review Step 2e).
- **Haiku is plumbing-only** — proof-verifier re-runs, mechanical action batches; never
  authored work products. Trivial *authoring* routes to the external default when eligible,
  else `sonnet`.

## Mechanics

- Non-Claude models run through the Codex CLI wrapper (`codex-implementer`), which passes the
  value to `codex exec -m` and independently verifies the result; reasoning effort scales with
  the task's `complexity`. Mechanics: the [cw-codex skill](../../cw-codex/SKILL.md).
- Claude models pass straight through Task()'s `model` parameter.
- Plan-time `model` is intent; the journal's `model_used` (and `fallback_reason`, if the codex
  path degraded) is fact.

## Adding a New Model

The table is the single point of change — routing is structural, not enumerated: **any
non-Claude `model` dispatches via the wrapper, which passes it verbatim to `codex exec -m`.**
To add one:

1. Add a row with cost/intelligence/taste judged from real output, not marketing. Use the
   exact CLI model id (see the cw-codex skill's model-id guidance).
2. Update the How-to-Apply bullets only if its profile changes which tier owns bulk work.

No dispatcher, wrapper, schema, or hook change is ever needed. If Codex does not recognize the
id, the run fails and the task falls back to sonnet, recorded in `fallback_reason`.
