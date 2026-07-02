# Scope-and-Effort Gate

How cw-spec Step 3 decides how much process a piece of work warrants. Three tiers, classified along three axes, **impact-first**.

## The three axes

| Axis | Question | Why it matters |
|------|----------|----------------|
| **Behavioral impact** (primary) | Does this change how the system, its agents, or the workflow *behave* — or is it cosmetic? | A one-line prose edit that changes routing is high-impact; a large doc reformat is not. Impact, not size, decides whether validation is warranted. |
| **Deliverable type** | Authored prose (docs, skills, markdown) or runtime-bearing code with an executable proof surface? | Prose has no runtime to execute — proofs degrade to grepping for strings. Code can be exercised by tests. |
| **Effort** | Trivial one-liner, small/moderate, or substantial? | Modulates: a trivial runtime fix can drop to direct; a large prose effort stays spec-lite but grows more units. |

## The three tiers

| Tier | When | What cw-spec does |
|------|------|-------------------|
| **Direct implementation** | Trivial effort **and** no behavioral impact (typo, CSS color, missing import, cosmetic wording). | Writes **no spec**. Reports that the work is direct-implementation tier and stops; implementation happens directly. |
| **Spec-lite** | Deliverable is authored prose/docs/skills, at small-to-moderate effort — **including** behavior-bearing changes. | Produces the **standard spec template, scaled**: only the sections that apply, 1–2 demoable units, few requirements. When the change is behavior-bearing, generates **BDD scenarios sized to the behavioral impact** (a decision table — not one scenario per requirement). Hands off to **direct implementation** (cw-execute / inline), skipping cw-plan → cw-dispatch. |
| **Full pipeline** | Runtime-bearing feature with an executable proof surface, at moderate-to-substantial effort. | The current default: full spec + full Gherkin + cw-plan + cw-dispatch. |

## Decision rule (impact-first)

1. **No/low behavioral impact + trivial effort** → **Direct implementation**.
2. Otherwise, if the deliverable is **authored prose/docs/skills** → **Spec-lite** (scale BDD to the behavioral impact; behavior-bearing prose still gets scenarios, cosmetic prose does not).
3. Otherwise (deliverable is **runtime-bearing code** with an executable proof surface) → **Full pipeline**.

**Impact is primary.** The trap to avoid: treating "it's just markdown" as "no validation needed." A small skill edit that changes how agents route work is high-impact prose — it belongs in spec-lite *with* scaled BDD, not in direct implementation. Symmetrically, a runtime change with no behavioral surface (e.g., a comment) is direct, not full pipeline.

## Scaling BDD in spec-lite

The proof of a prose/behavioral change is **the decision behavior it induces**, not the presence of strings in a file. Grepping `SKILL.md` for a phrase proves the words are there; it does not prove the skill now routes correctly. So spec-lite BDD scenarios describe observable *decisions* (`Given a prose deliverable that changes behavior / When cw-spec assesses scope / Then it routes to spec-lite`), validated by dogfooding / walking them — not by executing code. Size the set to the impact: a handful of decision scenarios covering the routing matrix, not one scenario per functional requirement.

## Worked example — cw-explain (the case that motivated this gate)

`/cw-spec cw-explain` produced an 18-requirement spec and 26 Gherkin scenarios for a deliverable of ~3 markdown files (a SKILL.md + references). Every proof degraded to grepping prose for strings; the Gherkin described behaviors the pipeline could not execute (running a skill needs a live session). Under this gate: deliverable type = authored prose, effort = small, behavioral impact = moderate (a new skill's behavior) → **spec-lite**. Correct output: a scaled spec (1–2 units, applicable sections only) plus a few BDD decision scenarios — not the full ceremony.

This very spec (`01-spec-spec-scope-effort-gate`) is itself a spec-lite instance: authored prose, behavior-bearing (it changes cw-spec routing), small effort → scaled spec + BDD sized to impact.
