# Model Selection Rubric

Consulted by `cw-plan` when assigning `metadata.model` to each task. Ships inside the plugin
so model policy loads at plan time everywhere — it never depends on a user-level CLAUDE.md.

## Model Profiles

Each model is judged on three axes, relative to this roster rather than in absolute terms:
**cost** — what you actually pay, in tokens and (for Claude models) usage-limit pressure;
**intelligence** — how hard a problem it handles unsupervised; **taste** — UI/UX, code
quality, API design, and copy.

**gpt-5.6-sol** — the external default, frontier tier.
- Cost: among the most expensive options; reserve it for work that genuinely needs the intelligence.
- Intelligence: the strongest in the roster — takes on the hardest problems with no supervision.
- Taste: middling — competent structure and code, but no distinctive design sense. Keep it off anything user-facing.

**gpt-5.6-terra** — the balanced 5.6 tier.
- Cost: roughly half sol's token cost and noticeably lighter on Codex usage limits — the whole reason to reach for it.
- Intelligence: a notch below sol, still comfortably ahead of the Claude models on hard unsupervised work.
- Taste: the weakest here — trust its design sense even less than sol's. Highest-volume, purely-mechanical bulk work only, where conserving sol's budget matters and taste is irrelevant.

**sonnet** — the default Claude executor.
- Cost: cheap — the economical default, and the tier a codex task silently falls back to.
- Intelligence: solid on well-specified work; not the model for open-ended or research-heavy problems.
- Taste: good — the reliable choice for most user-facing implementation.

**opus** — the design-strong Claude model.
- Cost: a premium Claude model, pricier than sonnet.
- Intelligence: strong — below the frontier external tier but well above sonnet.
- Taste: excellent; the default for reviews and design-sensitive work.

**fable** — the taste-and-intelligence ceiling.
- Cost: premium — the priciest Claude option.
- Intelligence: frontier-class, on par with sol.
- Taste: the best in the roster; the ceiling for design and copy, and the reviewer to orchestrate with.

## How to Apply

- These are defaults, not limits. If a cheaper model's output misses the bar, redo it with a
  smarter one — judge the output, not the price tag. When axes conflict for anything that
  ships: **intelligence > taste > cost** (cost breaks ties only).
- **Bulk/mechanical work** (clear-spec implementation, migrations, data plumbing) → the
  external tier. Eligible only when ALL hold: requirements fully specified (clear R-IDs, no
  design judgment left to the executor); scope exhaustive
  (`files_to_create`/`files_to_modify` complete); and sonnet is an acceptable executor — the
  tier is **runtime-gated**, so a host without the codex CLI silently runs the task on sonnet.
- **Anything user-facing** (UI, copy, API surface) needs a model with real design sense
  (sonnet, opus, or fable) → never the external tier.
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

The profile list is the single point of change — routing is structural, not enumerated: **any
non-Claude `model` dispatches via the wrapper, which passes it verbatim to `codex exec -m`.**
To add one:

1. Add a profile with a sentence per axis (cost/intelligence/taste), judged from real output,
   not marketing. Use the exact CLI model id (see the cw-codex skill's model-id guidance).
2. Update the How-to-Apply bullets only if its profile changes which tier owns bulk work.

No dispatcher, wrapper, schema, or hook change is ever needed. If Codex does not recognize the
id, the run fails and the task falls back to sonnet, recorded in `fallback_reason`.
