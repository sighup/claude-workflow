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

[filled by T01.2 — PRD parser + path discovery + never-modify guarantee]

Behavior summary: accept either an explicit PRD path argument or, with no argument, discover the most recent file under `docs/prds/*.md`. Parse the PRD into a structured intermediate covering §1 Vision/Problem/Users, §3 Core Workflow stages, §4 Primary Capabilities, §6 Domain Concepts, §7 Success Metrics, and §8 Open Questions. Treat the source PRD as read-only.

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
