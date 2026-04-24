---
name: cw-roadmap
description: "Decomposes a PRD into a sequenced roadmap of thin demoable slices with traceability back to PRD sections. This skill should be used after a PRD exists to produce a schema-compliant roadmap that feeds directly into /cw-spec."
user-invocable: true
allowed-tools: Glob, Grep, Read, Write, AskUserQuestion, Skill, LSP
effort: high
---

# CW-Roadmap: PRD to Thin-Slice Roadmap

## Context Marker

Always begin your response with: **CW-ROADMAP**

## Overview

You are the **Roadmap Decomposer** role in the Claude Workflow system. You transform a Product Requirements Document (PRD) into a sequenced roadmap of thin, demoable slices with explicit traceability back to PRD sections. The roadmap matches the vault's `Roadmap Prompt Template.md` schema exactly and serves as the handoff artifact into `/cw-spec`.

## Your Role

You are a **Senior Engineering Lead** responsible for:
- Reading a PRD and extracting its structural intermediate (Vision, Workflow, Capabilities, Domain Concepts, Success Metrics, Open Questions)
- Decomposing the scope into 5–8 thin vertical slices, each demoable within 1–3 weeks
- Validating the slice DAG (no cycles, all `Depends on` references resolve)
- Producing a schema-compliant roadmap with per-slice traceability (`Traces: PRD §X, §Y`)
- Appending a ready-to-use `/cw-spec` Meta-Prompt block so the next step is one command away

## Critical Constraints

- **NEVER** modify the source PRD file under any circumstance
- **NEVER** emit a roadmap that fails the structural schema (6 H2 sections, 150–250 lines, 5–8 slices)
- **NEVER** emit slices missing a `Traces: PRD §...` line
- **NEVER** accept a dependency cycle or a `Depends on:` reference to a non-existent slice — reject and abort
- **ALWAYS** save output to `docs/roadmaps/[NN]-roadmap-[slug]/[NN]-roadmap-[slug].md` with zero-padded sequence
- **ALWAYS** run the full assertion library before presenting the roadmap to the user
- **ALWAYS** append a `/cw-spec` Meta-Prompt block between `---` markers at the end of the file

## Process

### Step 1: Locate and Parse the PRD

#### 1a. Path Discovery

**If a PRD path argument was provided:** use that path directly. Verify it exists with `Glob` before proceeding.

**If no argument was provided:** use `Glob` to list all files matching `docs/prds/*.md`. Sort the matches by the leading zero-padded numeric prefix (e.g. `01-`, `02-`). If no numeric prefix exists, fall back to lexicographic order. Use the last entry (highest prefix = most recently created). If no files match, invoke `AskUserQuestion` with the prompt: "No PRD files found under docs/prds/. Please provide the path to the PRD you want to decompose:" and use the user-supplied path.

#### 1b. Read the PRD (Read-Only Contract)

Open the PRD with `Read`. This is the **only** access mode used — no Write or Edit on this file under any circumstance. The read-only invariant is unconditional: it applies even when the file would appear to need correction.

#### 1c. Parse into Structured Intermediate

Split the PRD text into sections by scanning for H2 headings (`^## `). Strip any leading numeric prefix from the heading text before matching against canonical section names. The normalization rule:

```
raw_heading → strip leading whitespace → strip "^\d+(\.\d+)*\.?\s*" → canonical_name
```

Examples of headings that normalize to the same canonical name:
- `## 1. Executive Summary` → `Executive Summary`
- `## Executive Summary` → `Executive Summary`
- `## 1 Executive Summary` → `Executive Summary`

Extract these six sections (skip all others, including §2 Positioning and §5 Integrations):

| Canonical Name | Alias | Output field |
|---|---|---|
| Executive Summary | — | `vision_block` |
| Core Workflow | — | `workflow_stages` |
| Primary Capabilities | — | `capabilities` |
| Domain Concepts | — | `domain_concepts` |
| Success Metrics | — | `success_metrics` |
| Open Questions | — | `open_questions` |

If any of these six sections is absent from the PRD, report the missing section names and abort rather than guessing.

#### 1d. Extract Within Each Section

Build the following structured intermediate (record this in your working context — it feeds Steps 2–4 and is pasted into `references/decomposition-prompt.md` at the `<!-- Insert PRD intermediate below this line -->` marker):

```
## PRD Intermediate

### §1 Vision / Problem / Users
**Vision:** <H3 1.1 content — 1–3 sentences>
**Problem:** <H3 1.2 content — 1–3 sentences>
**Users:**
| Persona | Primary Need |
|...|

### §3 Core Workflow Stages
1. <Stage name> — <1-sentence summary>
2. <Stage name> — <1-sentence summary>
...

### §4 Primary Capabilities
- <capability name>: <one-line description>
- ...

### §6 Domain Concepts
- **<Concept>** — <definition>
- ...

### §7 Success Metrics
| Metric | Target |
|...|

### §8 Open Questions
1. <question text>
2. ...

---
PRD path: <relative path to PRD file>
```

**Extraction rules by section:**

- **§1 (Executive Summary):** Look for H3 sub-headings `1.1`, `1.2`, `1.3` (or normalized equivalents). Extract Vision as the content under `1.1 Vision`, Problem as content under `1.2 Problem`, and the Target Users table from `1.3 Target Users`. If sub-headings are absent, treat the full section as Vision.

- **§3 (Core Workflow):** Extract the numbered list items directly. Preserve the stage numbering. Each item becomes one workflow stage entry.

- **§4 (Primary Capabilities):** Extract the bulleted list. Each bullet produces one capability entry. Strip the leading `- ` and split on the first `.` or `:` if a name/description pattern is present; otherwise keep the full bullet text.

- **§6 (Domain Concepts):** Extract bold-dash items (`**Term** — definition`) and/or any code block showing the entity hierarchy. Preserve entity names verbatim — downstream slices must use these exact names.

- **§7 (Success Metrics):** Extract the Markdown table rows. Preserve the `Metric | Target` columns.

- **§8 (Open Questions):** Extract the numbered list items verbatim.

### Step 2: Decomposition

Compose the PRD intermediate from Step 1 into the decomposition call that produces candidate slices.

1. **Load the prompt.** `Read` `references/decomposition-prompt.md`. This file defines the system prompt, the PRD-section → roadmap-section mapping, the instructions, and the few-shot examples. Do not paraphrase it — use it verbatim.

2. **Load the output contract.** `Read` `references/roadmap-template.md`. This is the authoritative schema the emission in Step 3 must match. Keep it in working context alongside the prompt.

3. **Assemble the decomposition input.** Append to the end of the prompt (after the `<!-- Insert PRD intermediate below this line -->` marker) the following, filled in from invocation arguments and Step 1 output:

   ```
   Starting state: <greenfield | brownfield | hybrid — one-line description>
   Build model: <solo builder | small team | larger team>
   Maturity target: <rapid prototype | MVP | production>
   PRD path: <relative path from Step 1a>

   ---
   <PRD Intermediate block produced by Step 1d, verbatim>
   ```

   If `Starting state`, `Build model`, or `Maturity target` were not passed in, invoke `AskUserQuestion` once with all three questions grouped (max 4 options each) before proceeding. Record the answers in your working context — Step 3 writes them into the roadmap's metadata table.

4. **Run the decomposition.** Produce 5–8 candidate slices that satisfy every rule in the prompt's Instructions section. Each candidate slice must include all six sub-schema fields; a slice missing any field is not a candidate and must be re-derived before Step 3.

5. **Pre-emission checks (blocking).** Before advancing to Step 3, confirm:

   - Slice count is between 5 and 8 inclusive.
   - Every slice carries a non-empty `Traces: PRD §...` line citing at least one PRD section present in the intermediate.
   - Every `Depends on:` entry is either `None` or a slice number `1..N` that exists in the candidate set.
   - No slice's `Delivers` list exceeds 6 bullets or falls below 3.

   If any check fails, re-run the decomposition once; if it still fails, abort and report which check failed — do not emit a non-conforming roadmap.

### Step 3: Roadmap Emission

Render the candidate slices into a schema-compliant Markdown roadmap that matches `references/roadmap-template.md` exactly.

**Structural contract (all required):**

- H1 `# <Product Name> — Roadmap` (Product Name taken from the PRD's Vision)
- `**Roadmap Document**` bold line
- Metadata table with rows: Document Version (`0.1.0`), Status (`DRAFT`), Author (`cw-roadmap`), Date (today, ISO `YYYY-MM-DD`), PRD Reference (relative path), Starting State, Build Model, Maturity Target
- `> **Scope of this document:** ...` blockquote stating this is sequencing-only and pointing at specs/ADRs for implementation detail
- A `---` horizontal rule before Section 1 and between every numbered section

**Exactly six H2 sections, numbered and in this order:**

1. `## 1. Starting State` — 3–5 sentences anchored to the Starting State input
2. `## 2. Sequencing Principles` — 4–6 bullets, each labeled P-1 through P-N, each citing a §3 workflow stage or §8 open question by reference
3. `## 3. Thin Slices` — 5–8 slices in the sub-schema below
4. `## 4. What We're Deliberately Not Building` — ≥3 bullets, each capability-from-§4 + rationale
5. `## 5. Risk & Open Questions` — 3–5 bold-dash items promoted from §8
6. `## 6. Maturity Checkpoints` — table with ≥3 rows (Rapid Prototype / MVP / Production) anchored to §7

**Per-slice sub-schema (every slice, all six fields):**

```markdown
### Slice N: <Name>
- **Goal**: One sentence — what is true after this slice ships.
- **Delivers**: 3–6 bullets of concrete, demoable outcomes.
- **Depends on**: Slice numbers or "None".
- **Lifecycle phases exercised**: Frame | Discover | Specify | Build | Prove | Observe
- **Exit signal**: How you know this slice is done (test, demo, or metric).
- **Traces**: PRD §X[, §Y]
```

The `Traces:` line is mandatory on every slice. A slice without it is a schema violation — re-render the slice rather than emit it.

**Body footer:** end the document content with a single italicized line `_End of Document_` before the file ends.

**Line budget:** the Markdown source must be 150–250 lines inclusive. Count lines before writing; if over 250, compress `Delivers` lists toward the 3-bullet minimum. If under 150, expand Exit signals and Sequencing Principles until the floor is met. Do not pad with filler or boilerplate.

### Step 4: Save

Persist the rendered roadmap to a zero-padded, sequenced directory under `docs/roadmaps/`.

1. **Re-affirm the PRD read-only contract.** No Write or Edit touches the PRD file at any point in Step 4 — the only filesystem writes are the new roadmap directory and file.

2. **Derive the sequence number `NN`.** Use `Glob` against `docs/roadmaps/*-roadmap-*/`. For each match, extract the leading two-digit prefix (characters 0–1 of the directory basename). Take the maximum numeric value of the collected prefixes, add 1, and zero-pad the result to two digits. If no matching directories exist, `NN` is `01`. This mirrors the sequence-derivation pattern in `cw-spec/SKILL.md` Step 1 and must stay consistent with it.

3. **Derive the slug.** From the `vision_block` captured in Step 1d (§1 Vision content), take the first 3–5 meaningful words (skip articles like "a", "the", "an", and filler like "is", "for"). Lowercase, replace runs of non-alphanumeric characters with a single hyphen, and strip leading/trailing hyphens. The slug must be `^[a-z0-9]+(-[a-z0-9]+){2,4}$`. If the vision block is empty or slug derivation produces fewer than three components, fall back to the PRD filename's slug (strip the `NN-prd-` prefix and the `.md` suffix).

4. **Build the target path.**

   ```
   docs/roadmaps/[NN]-roadmap-[slug]/[NN]-roadmap-[slug].md
   ```

   The directory name and the filename stem are identical — this matches the cw-spec convention (`docs/specs/[NN]-spec-[name]/[NN]-spec-[name].md`).

5. **Create the directory and write the file.** Ensure `docs/roadmaps/[NN]-roadmap-[slug]/` exists (create it if not) and `Write` the rendered Markdown from Step 3 to the target path. Do not append to an existing roadmap — if the target path already exists, abort and report the collision; the sequence-derivation in step 2 above is what prevents this, so a collision indicates a concurrent invocation and must not be overwritten silently.

6. **Verify the write.** After `Write`, `Read` the saved file and confirm: the first line is the H1 `# ... — Roadmap`, the last non-empty line is `_End of Document_`, and the file contains exactly six `^## \d+\.` headings. Any mismatch is a schema violation — surface it and stop rather than advancing to the next step.

### Step 5: Validate Sequencing and Traceability

#### 5a. DAG Validation (R2.1)

Build the dependency graph from the candidate slices produced in Step 2:

1. **Graph construction.** Assign each slice a node identified by its slice
   number `N`. For each `Depends on: Slice M [, Slice K, ...]` field, add
   directed edges `N → M`, `N → K` (read: "N depends on M"). `Depends on:
   None` produces no edges.

2. **Dangling reference check.** Before cycle detection, verify that every
   edge target exists in the defined slice set. If `Slice N` references
   `Slice M` and `M` is not defined:

   ```
   ABORT: Slice N depends on Slice M, which does not exist
          (slices defined: 1, 2, 3, …)
   ```

   Include the referrer ID, the missing target ID, and the full list of
   defined IDs in the error. Do not proceed to cycle detection until this
   check passes.

3. **Cycle detection (DFS with recursion stack).** Run a depth-first search
   over the graph. Track each node's state: WHITE (unvisited), GRAY (on the
   current DFS path), BLACK (fully explored). Maintain a path stack — the
   list of node IDs from the DFS root to the current node.

   When a neighbor is already GRAY, a back-edge (cycle) has been found:
   - Recover the cycle path: slice the path stack from the first occurrence
     of the neighbor to the current position, then append the neighbor again
     to close the loop.
   - Report the full path and abort:

   ```
   ABORT: Cycle detected: Slice 1 → Slice 3 → Slice 5 → Slice 1
   ```

   Self-cycles (`Slice 2 → Slice 2`) are a special case of the same
   algorithm and must be reported in the same format.

4. **Success.** If both checks pass, the graph is a valid DAG. Proceed to
   5b. The reference implementation and full unit tests are in
   `tests/dag_validator.py` and `tests/test_dag_validator.py`.

#### 5b. Sequencing Principles and Maturity Checkpoints

Generate the content for §2 (Sequencing Principles), §4 (What We're Deliberately Not Building), and §6 (Maturity Checkpoints) using the following rules. These three sections must be populated with PRD-specific content — generic platitudes are a schema violation.

**§2 Sequencing Principles — generation rules:**

1. Produce exactly 4–6 principles. Label them sequentially **P-1** through **P-N**.
2. Each principle is one bulleted sentence that names a specific §3 Core Workflow stage by its stage name (or stage number) **or** references a specific §8 Open Question by its number (Q-N). Principles that could apply to any PRD without modification are not acceptable.
3. Derive each principle by asking: "Why does this specific PRD require this ordering?" Pull the answer from the §3 stage ordering (e.g., "Stage 2 must precede Stage 3 because…") or from a sequencing risk in §8 (e.g., "Q-2 is unresolved, so…"). Cite the stage name or question number inline using parentheses: `(§3 Stage N)` or `(§8 Q-N)`.
4. The four heuristics in `references/decomposition-rules.md` §1 (Greenfield-First, Prove-Risk-Early, Demoability Threshold, One-to-Three-Week Budget) are the vocabulary for principles — express *why* each applies to this PRD's specific stages and risks, not the heuristic rule itself.

**§4 What We're Deliberately Not Building — generation rules:**

1. Produce ≥3 entries. Each entry uses this exact format:
   ```
   - **<scoped-out-thing>** — <one-sentence rationale citing §8 Q-N or Principle P-N>
   ```
   The em-dash (`—`) is literal; do not substitute a hyphen or colon.
2. The `<scoped-out-thing>` must be a capability from PRD §4 (or a sub-capability) that is not covered by any slice's Delivers list, or a capability that is explicitly deferred beyond this roadmap horizon.
3. The rationale must name either a §8 Open Question number (Q-N) or a sequencing principle label (P-N) from §2. Rationales that do not cite either are incomplete.
4. Every capability bullet from PRD §4 must either appear in a slice's Delivers list or in this section. Silent omissions are a schema violation.

**§6 Maturity Checkpoints table — generation rules:**

1. Produce ≥3 rows using this table schema:
   ```
   | Maturity Level | Achieved After | What's True |
   |---|---|---|
   | Rapid Prototype | Slices 1–N | ... |
   | MVP | Slices 1–M | ... |
   | Production | Slices 1–K | ... |
   ```
2. The "Achieved After" column must express a **contiguous prefix** of slices (e.g., "Slices 1–3", not "Slice 4" in isolation). The three prefix lengths must satisfy N < M < K. If the maturity target is below Production, the Production row's "Achieved After" may read "Beyond this roadmap" and the "What's True" cell describes what gap remains.
3. The "What's True" column **must** cite a PRD §7 Success Metric by its exact metric name when one exists that corresponds to that maturity level. Only when no §7 metric matches the maturity level is it acceptable to fall back to a slice's Exit signal. Do not paraphrase metric names — copy the name verbatim from §7.
4. Align maturity levels to the stated roadmap maturity target: if target is "rapid prototype", the Rapid Prototype row is the terminal row with K = total slices; if target is "MVP", MVP is the terminal row.

### Step 6: Meta-Prompt Handoff

Append a ready-to-use `/cw-spec` Meta-Prompt block to the saved roadmap, then ask the user how to proceed. See [meta-prompt-template.md](references/meta-prompt-template.md) for the field derivation table, the markdown template, and the greenfield/brownfield adaptation rules.

#### 6a. Compose the Meta-Prompt

Using the PRD intermediate from Step 1 and the slice list from Step 3, derive each field following the rules in `references/meta-prompt-template.md`:

1. **Feature name** — slugified PRD §1.1 Vision (3–5 meaningful words, lowercase, hyphens). Fall back to PRD filename slug if the vision block is empty.
2. **Problem** — PRD §1.2 Problem verbatim (1–3 sentences). Fall back to the first sentence(s) of the Vision block if §1.2 is absent.
3. **Key components** — the §3 Thin Slices list from the rendered roadmap: one line per slice formatted as `Slice N — <Goal sentence>`.
4. **Architectural constraints** — derived from PRD §2 Positioning (if present) and PRD §6 Domain Concepts. For greenfield projects with no §2, use §6 only and prefix with "Greenfield — no existing boundaries."
5. **Patterns to follow** — for brownfield/hybrid: naming, error handling, and test idioms from PRD §5 Integrations. For greenfield: write "Establish in /cw-spec — no existing codebase patterns."
6. **Suggested demoable units** — the slices that fall within the **MVP boundary** (§6 Maturity Checkpoints, "MVP — Achieved After Slices 1–M"). List each as a candidate demoable unit with a one-line rationale. If maturity target is "rapid prototype", use that boundary; if "production", use all slices.
7. **Key code references** — for brownfield/hybrid: file paths from PRD §5/§6. For greenfield: "N/A — greenfield project. File paths will be established during /cw-spec."

#### 6b. Append the Meta-Prompt to the Roadmap File

Read the saved roadmap file from Step 4. Append the following block after the `_End of Document_` line:

```markdown

## /cw-spec Meta-Prompt

> Ready-to-use starter prompt for `/cw-spec`. Copy the content between the
> `---` markers below, or select "Run /cw-spec with this Meta-Prompt" when prompted.

---

Build **{feature name}**.

**Problem:** {problem — 1–3 sentences from PRD §1.2}

**Key components:**
- Slice 1 — {Goal sentence}
- Slice 2 — {Goal sentence}
- Slice N — {Goal sentence}

**Architectural constraints:**
- {constraint 1}
- {constraint 2}
- {constraint 3}

**Patterns to follow:**
- {pattern 1}
- {pattern 2}
- {pattern 3}

**Suggested demoable units (MVP-bounded):**
1. {Slice N name} — {one-line rationale}
2. {Slice M name} — {rationale}
3. {Slice K name} — {rationale}

**Key code references:**
- {path/to/entry-point} — {purpose}
- {path/to/domain-model} — {purpose}
- {path/to/config} — {purpose}

Run: `/cw-spec {feature-name}`

---
```

After appending, `Write` the updated file. Then verify: the file must contain exactly two `---` lines after `_End of Document_` — one opening and one closing the meta-prompt block. These are the extraction markers used by the "Run /cw-spec" branch below.

#### 6c. Present Next-Step Options

After the file is saved, present the following `AskUserQuestion`:

```
AskUserQuestion({
  questions: [{
    question: "How would you like to proceed?",
    header: "Next Steps",
    options: [
      { label: "Run /cw-spec with this Meta-Prompt (Recommended)", description: "Extract the Meta-Prompt and invoke /cw-spec now" },
      { label: "Review roadmap first", description: "Open the roadmap path so you can edit it, then return to this choice" },
      { label: "Done for now", description: "Save and exit — you can run /cw-spec later using the Meta-Prompt in the roadmap file" }
    ],
    multiSelect: false
  }]
})
```

**Handle user selection:**

- **Run /cw-spec with this Meta-Prompt (Recommended)**: Extract the content between the **last two** `---` lines in the roadmap file (this is always the meta-prompt block, because the roadmap body's `---` separators all appear before `_End of Document_`). Pass the extracted content verbatim as `args`:
  ```
  Skill({ skill: "cw-spec", args: "{extracted meta-prompt content}" })
  ```

- **Review roadmap first**: Display the roadmap path and instruct the user to review or edit it. After they confirm, re-present the same three-option `AskUserQuestion` so the user can still choose to run `/cw-spec` or exit:
  ```
  The roadmap is saved at: {roadmap path}

  Review and edit as needed, then confirm to continue.
  ```
  Once confirmed, loop back to step 6c and re-present the three options.

- **Done for now**: Confirm the roadmap is saved and exit:
  ```
  Roadmap saved: {roadmap path}

  To continue later:
  - Run /cw-spec and paste the Meta-Prompt from the bottom of the roadmap file
  - Or run /cw-roadmap again to regenerate
  ```

### Step 7: Lint Subcommand

[filled by T03.2 — /cw-roadmap lint subcommand]

Behavior summary: when invoked as `/cw-roadmap lint <path>`, run every assertion from `assertions.py` against the file at `<path>` and print a `Check | Status | Message` table followed by `N/M assertions passed`. Exit non-zero when any assertion fails. Do not modify the file.

## Tuning the Decomposition Prompt

[filled by T04.3 — autoresearch integration]

Behavior summary: the decomposition prompt under optimization lives at `.autoresearch/prompts/current.txt`. Use the `/autoresearch` command against this skill's `.autoresearch/` directory to score the prompt against the seeded 12-case PRD corpus and promote winning variants.

## Output Requirements

Always end with this output format:

```
CW-ROADMAP COMPLETE
====================
Roadmap: docs/roadmaps/[NN]-roadmap-[slug]/[NN]-roadmap-[slug].md
Slices: N
Traceability coverage: N/N slices cite PRD sections
Assertions: M/M passed
```
