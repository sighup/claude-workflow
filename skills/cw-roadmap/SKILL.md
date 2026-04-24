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

### Step 2: Build the Slice Decomposition

[filled by T01.3 — roadmap template + decomposition-prompt baseline]

Behavior summary: apply the decomposition prompt from `references/decomposition-prompt.md` against the parsed PRD to produce 5–8 thin slices, each with Goal / Delivers (3–6 bullets) / Depends on / Lifecycle phases / Exit signal / Traces fields, following `references/roadmap-template.md`.

### Step 3: Validate Sequencing and Traceability

[filled by T02.1–T02.3 — DAG validation, sequencing principles, maturity checkpoints]

Behavior summary: build the dependency graph from each slice's `Depends on:` field and abort on any cycle or dangling reference. Generate 4–6 Sequencing Principles, populate the Maturity Checkpoints table (≥3 rows tied to Success Metrics), and fill "What We're Deliberately Not Building" with ≥3 entries each carrying a rationale.

### Step 4: Emit the Roadmap and Handoff

[filled by T01.4 — end-to-end pipeline; T02.3 — Meta-Prompt appender]

Behavior summary: write the six-H2-section roadmap to the target path, append a `/cw-spec` Meta-Prompt block between `---` markers, and present a next-step `AskUserQuestion` offering "Run /cw-spec with this Meta-Prompt (Recommended) / Review roadmap first / Done for now".

### Step 5: Lint Subcommand

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
