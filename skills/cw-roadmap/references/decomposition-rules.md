# Decomposition Rules — Sequencing Heuristics and PRD§→Roadmap§ Mapping

This document is the normative reference for two closely-related concerns:

1. **Sequencing heuristics** — the four rules a decomposer must apply when
   deciding the order of slices.
2. **PRD§→Roadmap§ mapping table** — the explicit field-level contract
   between PRD sections and roadmap sections (formalises the implicit mapping
   from the research report, §3 "Implicit field mapping").

The `cw-roadmap` skill's SKILL.md Step 5 validates the dependency graph
(using the algorithm in `tests/dag_validator.py`). T02.2 extends Step 5 with
the sequencing principles and maturity checkpoints; this file is the
authoritative reference both steps consult.

---

## 1. Sequencing Heuristics

The four heuristics below are listed in priority order. When two heuristics
conflict, the higher-priority one wins; the rationale for any override must
appear in the roadmap's "Sequencing Principles" section.

---

### 1.1 Greenfield-First

**Rule:** In a greenfield project (nothing exists yet), the first slice must
produce a user-visible, demoable artifact — even if the artifact is trivial.
Do not begin with infrastructure, configuration, or "foundation" slices that
deliver no observable behavior.

**Rationale:** A greenfield project has no proven artifact format, no verified
toolchain, and no social proof that the idea is buildable. The first slice
de-risks all of these simultaneously by forcing the team to traverse the
entire path from intent to shipped artifact. Slices that only "set up"
deferred the moment of truth without reducing risk.

**Concrete check:** Ask "Can a non-technical stakeholder see Slice 1 produce
something meaningful in a 5-minute demo?" If no — reframe the slice until
the answer is yes, or merge it with the next slice that would make it
demoable.

**Brownfield adaptation:** In a brownfield project, Slice 1 should stabilize
and audit what exists before adding new capability. The greenfield-first rule
becomes "prove the seam first" — establish the integration contract between
the existing codebase and new additions before building on top.

---

### 1.2 Prove-Risk-Early

**Rule:** Identify the highest-risk capability in the PRD (§4) or the most
uncertain sequencing question in §8 Open Questions. Schedule the slice that
resolves this risk as early as the dependency graph allows — ideally within
the first two slices.

**Rationale:** Deferring risk validation to later slices embeds an assumption
that later work is buildable. If that assumption is wrong, the roadmap
unravels at the worst possible time (after significant preceding investment).
Surfacing the hard part early converts an unknown into a known, allowing the
roadmap to be re-sequenced before dependent slices are committed.

**Concrete check:** After constructing the candidate slice list, rank slices
by technical uncertainty (use §8 Open Questions as a proxy). If any
high-uncertainty slice is numbered 4 or later and has no upstream dependency
preventing it from moving earlier, reorder it.

**Exception:** If proving a risk requires significant scaffolding that is
itself risky, create a "spike" slice that produces a written finding (not a
shippable feature) as its exit signal. The spike is sequenced immediately;
the feature slice that acts on the finding is sequenced after.

---

### 1.3 Demoability Threshold

**Rule:** Every slice must satisfy the demoability threshold before it is
admitted into the roadmap. A slice satisfies the threshold when **all three**
of the following are true:

1. A non-technical stakeholder can observe the slice's outcome without access
   to source code, logs, or developer tooling.
2. The exit signal is a concrete observable event (a test passes, a file
   appears, a UI renders, a CLI prints a specific line) — not a judgment call
   ("it feels ready").
3. The "Delivers" bullets describe outcomes, not activities (✗ "implement the
   parser" → ✓ "running `/cw-roadmap` against any PRD produces a roadmap
   file under `docs/roadmaps/`").

**Rationale:** A roadmap composed of demoable slices functions as a
stakeholder-facing progress tracker. Each slice completion is a demo
opportunity that provides feedback before the next slice is built. Slices
that fail the threshold are planning artifacts — they describe work rather
than outcomes, and they prevent meaningful feedback.

**Concrete check:** Rewrite each proposed slice exit signal in the form
"Demo passes when [concrete event] happens." If you cannot complete that
sentence without using the words "when it's done" or "when development is
complete," the slice fails the threshold. Add specificity until the sentence
is completable.

---

### 1.4 One-to-Three-Week Slice Budget

**Rule:** Every slice must be completable in 1–3 calendar weeks by the stated
build model (solo builder / small team / larger team). Slices shorter than
1 week are probably too granular (merge them); slices longer than 3 weeks
are too thick (split them).

**Rationale:** The 1–3 week budget is the cadence at which feedback is
valuable. Longer slices mean stakeholders wait too long for a demo; shorter
slices produce so many handoffs that coordination cost dominates. The budget
also forces specificity: a slice that cannot be described in terms demoable
within 3 weeks is hiding scope.

**Concrete check:** Count the bullets in the "Delivers" list. A solo-builder
slice with more than 6 bullets almost certainly exceeds 3 weeks — split it.
A team slice with fewer than 3 bullets almost certainly fits in under a week
— consider merging it with an adjacent slice or expanding the exit signal to
require more validation.

**Calibration by build model:**

| Build Model | Slice budget | Max Delivers bullets |
|-------------|-------------|---------------------|
| Solo builder | 1–3 weeks | 6 |
| Small team (2–4) | 1–3 weeks | 8 |
| Larger team (5+) | 1–3 weeks | 10 (but prefer splitting) |

---

## 2. PRD§→Roadmap§ Mapping Table

This table formalises the implicit field mapping identified in the research
report (§3, "Implicit field mapping"). It is the explicit traceability
contract that prevents ad-hoc interpretation during decomposition.

Every row in the table describes:
- Which PRD section is the authoritative source.
- Which roadmap section or per-slice field it populates.
- The transformation rule (how the PRD content is converted).

| PRD field | Roadmap use | Transformation rule |
|-----------|-------------|---------------------|
| §1 Vision + Problem | Slice **goals** and **exit signals** | Each slice's Goal must be a sub-goal traceable to the PRD's stated vision or problem statement. Exit signals reference observable outcomes mentioned in §1. |
| §3 Core Workflow | Slice **grouping** and **Sequencing Principles** (§2) | The workflow stages define the grain of the roadmap. Each workflow stage corresponds to one or a cluster of slices. Sequencing Principles in Section 2 must derive from the stage ordering in §3. |
| §4 Primary Capabilities | Slice **Delivers** bullets | Map each capability bullet to exactly one slice's Delivers list. Capabilities not reachable within this roadmap horizon go into "What We're Deliberately Not Building." |
| §6 Domain Concepts | Slice **scope vocabulary** | Use the domain concept names from §6 verbatim in slice descriptions, goals, and exit signals. Do not invent synonyms or paraphrase; downstream specs must use the same names. |
| §7 Success Metrics | **Maturity Checkpoints** table (§6) | Map each row of the PRD metrics table to a maturity level (Rapid Prototype / MVP / Production). A slice reaches a checkpoint when its exit signal satisfies the metric threshold. |
| §8 Open Questions | **Risk & Open Questions** section (§5) | Promote PRD open questions that affect sequencing or slice ordering into the roadmap's Risk section. Questions affecting implementation (not sequencing) belong in downstream specs — do not carry them forward. |

### Applying the Mapping — Rules

1. **§1 → Goals and exit signals.** Do not invent goals that are absent from
   the PRD vision/problem. If the vision is narrow, the slice goals must be
   narrow too — use the scope exclusions section to document what is out of
   scope rather than broadening goals to fill space.

2. **§3 → Grouping and sequencing.** Respect the stage ordering in §3. If
   Stage 2 logically precedes Stage 3 in the workflow, slices corresponding to
   Stage 2 must appear before Stage 3 slices in the roadmap (barring an
   explicit exception documented in Sequencing Principles with a rationale).

3. **§4 → Delivers.** Every capability bullet from §4 must either appear in
   a slice's Delivers list or in "What We're Deliberately Not Building." No
   capability may be silently dropped. If the capability list is too long for
   the 5–8 slice budget, bundle related capabilities into thematic slices and
   document the bundling decision.

4. **§6 → Vocabulary.** Concept names from §6 are load-bearing identifiers.
   They may appear in downstream specs and code as-is. Paraphrasing creates
   a semantic gap that downstream authors must bridge manually — avoid it.

5. **§7 → Checkpoints.** At least one slice must correspond to each maturity
   level that the roadmap covers (Rapid Prototype and MVP are required; the
   Production row may say "Beyond this roadmap" if the maturity target is
   MVP). The threshold for each level is derived directly from §7 metric
   values, not from judgment.

6. **§8 → Risks.** Filter ruthlessly. Only open questions that could cause a
   slice to be reordered or a dependency to change belong in the roadmap Risk
   section. Implementation questions (e.g., "which database?") belong in the
   spec for the affected slice.

---

## 3. DAG Validation — Algorithm Reference

The dependency graph validator enforces the structural integrity of the
`Depends on:` fields across all slices. The Python reference implementation
is `tests/dag_validator.py`; the algorithm is summarised here for use in
prompt instructions.

### 3.1 Graph Construction

1. Assign each slice a node identified by its slice number `N` (integer).
2. For each slice with `Depends on: Slice M [, Slice K, ...]`, add directed
   edges `N → M`, `N → K`, etc. (read as: "N depends on M").
3. "None" or blank `Depends on:` fields produce no edges.

### 3.2 Dangling Reference Check (pre-DFS)

Before running cycle detection, verify that every edge target exists in the
defined slice set. If `Slice N` references `Slice M` and `M` is not in the
defined set:

```
ABORT: Slice N depends on Slice M, which does not exist
       (slices defined: 1, 2, 3, 4)
```

Include the referrer ID, the missing target ID, and the list of defined IDs in
the error message.

### 3.3 Cycle Detection (DFS with recursion stack)

Run a depth-first search over the graph. Maintain a recursion stack (the
current path from the DFS root to the current node).

- Mark each node WHITE (unvisited), GRAY (on the current path), or BLACK
  (fully explored).
- When visiting a neighbor that is already GRAY, a back-edge (cycle) has been
  detected. Recover the cycle path by slicing the recursion stack from the
  first occurrence of the neighbor to the current position, then appending the
  neighbor again to close the loop.

```
ABORT: Cycle detected: Slice 1 → Slice 3 → Slice 5 → Slice 1
```

The error message must include the full cycle path with `→` arrows and slice
labels. Self-cycles (`Slice 2 → Slice 2`) are a special case of the same
algorithm and must be reported in the same format.

### 3.4 Success

If both checks pass, the graph is a valid DAG. The topological order (for
display or execution) can be derived from the DFS finish order (reversed).

---

## 4. Prompt Design Notes

These four findings emerged from the first `/autoresearch` optimization pass
on `cw-roadmap` (5 cycles, 0% → 92% on the 12-case corpus, 2026-04-25). They
generalize beyond cw-roadmap and apply to any `cw-*` skill whose output is
graded by deterministic assertions.

### 4.1 Directive language beats emphasis

Adding emphasis — uppercase, multiple negative examples, "NEVER do X. NEVER.
NEVER." — does **not** raise compliance and **regresses unrelated checks**.
In v3a/v3b of the optimization run, heavy emphasis on the failing assertion
broke the Traces format check (which was passing) by overshadowing it.

> **Rule:** State each requirement once, declaratively, in the section it
> applies to. Do not stack emphasis. Do not repeat across sections.

### 4.2 Sentence templates beat walls of text

Prose rules ("the exit signal should be a concrete observable outcome
expressed with a verb the reader could verify by inspection") underperform
explicit shape templates.

> **Rule:** When a graded field has a fixed shape, give the model a
> sentence template, not a description. For verbs:
> `<subject> <verb-from-list> <observable artifact>` lifted compliance
> to 92% where the prose rule capped at 75%.

### 4.3 Literal tokens beat guidance

"Cite the PRD section motivating this slice" produced freeform text. The
literal-token requirement `PRD §<digit>` (the word `PRD`, a single space, the
U+00A7 section sign, then a digit) achieved per-line compliance.

> **Rule:** When an assertion greps for an exact string, surface that
> exact string in the prompt. Don't paraphrase it. Show the literal
> bytes the assertion is looking for.

### 4.4 Top-of-prompt contracts must restate, not summarize

Hoisting a "mandatory contract" block to the top of the prompt that
**summarizes** the body rules detaches the rules from the assertion
vocabulary. The model defers to the summary and ignores the body. v3c lifted
the verb check to 83% and the meta-prompt block to 100% but tanked Traces
format to 50% — the contract summarized "cite PRD sections" instead of
restating the literal `PRD §<digit>` token.

> **Rule:** A top-of-prompt contract must restate every rule it enforces
> verbatim. If you can't fit them all verbatim, don't hoist any of them.

### 4.5 Anti-pattern: trying to override model refusal training

The original `edge_overscoped_platform_overhaul` test case forced the model
to decompose a deliberately impossible PRD (13 product domains, 195
countries, 3-month timeline, 4 engineers). Three anti-halt prompt
formulations failed to budge it; Sonnet refused to attempt a roadmap. This
is **correct model behavior**, not a prompt-fixable issue, and the test case
was replaced rather than continuing to optimize against it.

> **Rule:** If three single-variable mutations targeting the same case all
> regress or hold flat, the case is testing model behavior, not prompt
> behavior. Replace it.
