# Roadmap Template

A reusable schema that defines the exact format every `cw-roadmap`-generated roadmap must match. This file is the authoritative reference for the six required sections, the per-slice sub-schema, formatting conventions, and hard constraints. Feed it to the decomposition prompt as the output contract.

This document sits in the decomposition chain:

```
prd.md           — Vision brief (2 pages)           — PRD Prompt Template
roadmap.md       — Thin slices + sequencing          — this schema
/cw-spec output  — SDD spec (demoable units, ACs)   — cw-spec skill
/cw-plan output  — Executable tasks                 — cw-plan skill
```

The roadmap answers: **what do we build, in what order, and why that order** — without prescribing implementation details.

---

## Hard Constraints

- **Length: 150–250 lines of Markdown source.** This is a sequencing document, not a spec. Over-running means implementation detail is leaking.
- **Audience: product owner, tech lead, and any contributor** who needs to understand what ships next and why.
- **Job: answer "what do we build first, and what can wait"** — nothing more. Acceptance criteria, architecture decisions, task breakdowns, and technical design belong in downstream documents.
- **Thin slices, not phases.** Each slice must be demoable or testable independently. Avoid "foundational infrastructure" slices that deliver no visible behavior.
- **No overbuilding.** Every slice should justify its existence with a user-visible outcome. If a slice only exists to support a future slice, merge them or defer the dependent work.
- **Traceability required.** Every slice must carry a `Traces:` line citing the PRD sections it implements (e.g., `Traces: PRD §3, §4`).

---

## Context Inputs

The roadmap prompt must be given:

1. **The PRD** it decomposes (or a path to it)
2. **Starting state** — one of:
   - `greenfield` — nothing exists yet
   - `brownfield` — existing codebase described in a brief context paragraph
   - `hybrid` — some components exist, others are new (describe what exists)
3. **Build model** — who is building (solo builder, small team, etc.)
4. **Maturity target** — what level the roadmap aims for (rapid prototype, MVP, production)

These inputs shape sequencing. A greenfield solo-builder roadmap sequences differently than a brownfield team roadmap.

---

## Required Structure

### Front Matter (before Section 1)

1. `# <Product Name> — Roadmap` as H1
2. Bold line: `**Roadmap Document**`
3. A metadata table with columns "Field | Value":
   - Document Version (semver)
   - Status (`DRAFT`, `REVIEW`, `APPROVED`)
   - Author
   - Date
   - PRD Reference (relative path to the PRD)
   - Starting State (`greenfield`, `brownfield`, or `hybrid` + brief)
   - Build Model
   - Maturity Target
4. A `> **Scope of this document:** ...` blockquote callout stating this is a sequencing document and pointing at where implementation detail lives (specs, ADRs).
5. A horizontal rule `---` separating front matter from Section 1.

### Numbered Sections

Use top-level H2 headings numbered `## 1.` through `## 6.`. Separate every section with a horizontal rule `---`.

---

## 1. Starting State

3–5 sentences describing what exists today.

- **Greenfield:** "Nothing exists." followed by what the PRD envisions. Keep this brief — focus on the vision.
- **Brownfield:** what's built, what's proven, what needs rework. Reference the PRD and any audit documents.
- **Hybrid:** identify kept vs restarted components; note the integration contract between old and new.

---

## 2. Sequencing Principles

4–6 bulleted principles that explain *how* slices were ordered. These are the rules the roadmap follows.

Examples:
- "Demo something in the first slice."
- "Defer persistence until the workflow is proven."
- "Build the contract (artifact format) before the surfaces."
- "Don't break what's working."

These principles make the roadmap defensible — anyone reading can check whether a slice violates them.

---

## 3. Thin Slices

The core of the document. An ordered list of slices. **Aim for 5–8 slices for an MVP roadmap.**

Each slice must follow this exact sub-schema:

```markdown
### Slice N: <Name>
- **Goal**: One sentence — what is true after this slice ships.
- **Delivers**: 3–6 bullets of concrete, demoable outcomes.
- **Depends on**: Slice numbers or "None".
- **Lifecycle phases exercised**: Which of the six phases this slice touches.
- **Exit signal**: How you know this slice is done (a test, a demo, a metric).
- **Traces**: PRD §X, §Y  ← required; cite the PRD sections that motivate this slice.
```

Each slice must be completable in 1–3 weeks by the stated build model. If a slice would take longer, it is too thick — split it.

### Thin Slice Rules

A well-formed thin slice:

- **Is demoable.** Someone can see it work. "Set up the database" is not a thin slice. "Create a PRD and see it saved to the repo" is.
- **Has a clear exit signal.** Not "done when it feels ready" but "done when `cw-frame` produces a valid PRD that passes `cw-score` with clarity > 60."
- **Exercises at least one lifecycle phase.** Map every slice to Frame / Discover / Specify / Build / Prove / Observe so coverage is visible.
- **Stands alone or depends on completed slices only.** No circular dependencies. No "Slice 3 and Slice 4 must ship together."
- **Takes 1–3 weeks** for the stated build model. If longer, split it.

---

## 4. What We're Deliberately Not Building

3–6 bullets of things that are in-scope for the vision (per the PRD) but excluded from this roadmap. For each, a one-sentence rationale.

This prevents scope creep and makes trade-offs visible.

---

## 5. Risk & Open Questions

3–5 items. Each as `**Risk/Question** — one sentence.`

These are sequencing risks, not product risks (those are in the PRD).

Examples:
- **Artifact format stability** — If artifact format changes mid-roadmap, slices 3–5 need rework.
- **Parallel execution readiness** — Unclear whether cw-dispatch should support parallel execution in Slice 4 or defer to Slice 6.

---

## 6. Maturity Checkpoints

A table mapping maturity levels to slice completion:

| Maturity Level | Achieved After | What's True |
|---|---|---|
| Rapid Prototype | Slice N | One sentence |
| MVP | Slice N | One sentence |
| Production | Beyond this roadmap | One sentence |

Rows must be anchored to PRD §7 Success Metrics where possible.

End the document body with a single italicized footer: `_End of Document_`

---

## Formatting Conventions

### Tables

Use tables sparingly — **2–3 total**:

- The metadata table in the front matter (required)
- The maturity checkpoints table (required)
- Optionally: a slice dependency summary if the graph is complex

### Lists

- Sequencing Principles: bulleted list, one sentence each
- Slice Delivers: bulleted list, one sentence each
- Not Building: bulleted list with rationale
- Risks: bold-dash list (`**Topic** — sentence`)

### Cross-references

Use relative paths when referencing other documents:

- `See [PRD](../prds/spec-driven-development-system.md)` for the vision
- `See [Artifact Format Spec](../model/artifact-format-spec.md)` for format details
- `Detailed in [ADR-001](../decisions/ADR-001-whatever.md)` for architecture decisions

---

## Tone and Voice

- Third-person, declarative, present tense for goals and outcomes. "This slice delivers X." not "We will build X."
- Future tense only for deferred items in "Not Building" section.
- Sequencing rationale should be explicit — every ordering choice must be traceable to a principle in Section 2.
- Confident but honest about uncertainty. Use the Risks section rather than hedging throughout.
- No marketing language, no aspirational filler.

---

## What MUST NOT Appear

The following content belongs in specs, ADRs, or task plans — not the roadmap:

- Architecture decisions, stack choices, deployment topology
- Database schemas, API designs, code snippets
- Acceptance criteria or test scenarios
- Effort estimates in hours/points (use slice duration as a rough proxy)
- Sprint numbers, specific calendar dates
- Task breakdowns or subtasks within a slice
- Technical dependency graphs (use plain "Depends on: Slice N" instead)
- Wireframes, mockups, or design artifacts

---

## Greenfield vs Brownfield Adaptations

**Greenfield:**
- Slice 1 should produce a visible artifact (even if trivial) to prove the toolchain works end-to-end.
- Sequencing Principles should include "prove the artifact format early" since there's no existing contract.
- The Starting State section is brief — focus on what the PRD envisions.

**Brownfield:**
- Slice 1 should stabilize or audit what exists before adding new capability.
- Sequencing Principles should include "don't break what's working" and "extract before rewrite."
- The Starting State section describes what's built, what's tested, and what's fragile.

**Hybrid:**
- Identify which components are kept vs restarted in Starting State.
- Early slices should establish the integration contract between kept and new components.
- Sequencing Principles should address the seam between old and new.
