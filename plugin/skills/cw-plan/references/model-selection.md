# Model Selection Rubric

Consulted by `cw-plan` when assigning `metadata.model` to each task. This rubric ships inside
the plugin so model policy loads at plan time in every environment — it never depends on a
user-level CLAUDE.md.

## Rankings

Higher = better. **Cost** reflects what is actually paid. **Intelligence** is how hard a
problem the model can take unsupervised. **Taste** covers UI/UX, code quality, API design,
and copy.

| model    | cost | intelligence | taste |
|----------|------|--------------|-------|
| gpt-5.5  | 9    | 8            | 5     |
| sonnet   | 5    | 5            | 7     |
| opus     | 4    | 7            | 8     |
| fable    | 2    | 9            | 9     |

## How to Apply

- These are defaults, not limits. If a cheaper model's output doesn't meet the bar, redo the
  work with a smarter model. Judge the output, not the price tag — escalating costs less than
  shipping mediocre work.
- Cost is a tie-breaker only. When axes conflict for anything that ships:
  **intelligence > taste > cost**.
- **Bulk/mechanical work** (clear-spec implementation, migrations, data plumbing) → `gpt-5.5`,
  it's effectively free. Eligibility bar, ALL required:
  - Requirements are fully specified (clear R-IDs, no design judgment left to the executor)
  - Scope is exhaustive (`files_to_create`/`files_to_modify` complete)
  - Silent fallback to sonnet is acceptable — `gpt-5.5` is **runtime-gated**: environments
    without the codex CLI execute the task on sonnet with no warning, so never plan `gpt-5.5`
    for a task that would be mis-sized for sonnet
- **Anything user-facing** (UI, copy, API surface design) needs taste ≥ 7 → never `gpt-5.5`.
- **Reviews** of plans/implementations → opus (or fable when orchestrating), optionally
  gpt-5.5 as an extra independent perspective (see cw-review Step 2e).
- **Haiku is plumbing-only.** Legal for non-authoring mechanics — proof-verifier re-runs,
  mechanical action batches — never for authored work products (code, copy, plans, specs).
  Trivial *authoring* tasks route to `gpt-5.5` when eligible, otherwise `sonnet`.

## Mechanics

- External models (`gpt-5.5` and successors) are reachable only through the Codex CLI. The
  dispatcher spawns the `codex-implementer` wrapper (a sonnet agent that runs
  `codex exec -m "<model>"` and independently verifies the result); see
  [codex-execution.md](../../cw-dispatch/references/codex-execution.md).
- Claude models (`sonnet`, `opus`, `haiku`) pass straight through Task()'s `model` parameter.
- After execution the journal records `model_used` (and `fallback_reason` if the codex path
  degraded) — plan-time `model` is intent; the journal is fact.

## Adding a New Model

This table is the single point of change — the routing rule downstream is structural, not
enumerated: **any `model` value that is not a Claude model (`haiku`/`sonnet`/`opus`) dispatches
via the codex wrapper, which passes the value verbatim to `codex exec -m`.** So when a new
external model ships (e.g. `gpt-5.6`, released 2026-07-09):

1. Add a row above with its cost/intelligence/taste rankings — judge from real output, not
   marketing. Use the **exact CLI model id**, not the marketing name — new models often ship
   as variants (e.g. the gpt-5.6 generation is `gpt-5.6-sol`/`-terra`/`-luna`; bare
   `gpt-5.6` is rejected). Verify with codex's model picker or a one-line
   `codex exec -m <id> -s read-only` probe.
2. Update the "How to Apply" bullets if its profile changes which tier owns bulk/mechanical
   work.
3. Nothing else: no dispatcher, wrapper, schema, or hook changes. Codex must recognize the
   model name (`~/.codex/config.toml` account/provider must support it) — if it doesn't, the
   wrapper's codex run fails and the task silently falls back to sonnet, recorded in
   `fallback_reason`.

New *Claude* models are the platform's concern: once Task()'s `model` parameter accepts a
name, it can be used here directly — extend the Claude-model list in the dispatch skills'
External-engine paragraphs if the haiku/sonnet/opus set ever grows.
