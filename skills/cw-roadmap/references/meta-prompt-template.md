# Meta-Prompt Template

Template for the `/cw-spec` starter prompt appended at the end of every `cw-roadmap`-generated roadmap.

## Field Derivation

Derive each field from the roadmap and the PRD intermediate produced in Step 1:

| Field | Source |
|-------|--------|
| Feature name | PRD §1 Vision (sub-heading 1.1), slugified: take the 3–5 most meaningful words, lowercase, hyphens. Example: `smart-note-tagging-system`. If the vision block is empty, fall back to the PRD filename slug. |
| Problem | PRD §1.2 Problem verbatim (1–3 sentences). If §1.2 is absent, use the first 1–2 sentences of the Vision block as a condensed problem statement. |
| Key components | The roadmap's §3 Thin Slices list: one line per slice using the format `Slice N — <Goal sentence>`. This gives the reader the full decomposition at a glance and lets cw-spec align demoable units to existing slices. |
| Architectural constraints | Distilled from PRD §2 Positioning (if present) and PRD §6 Domain Concepts: list every named entity, integration boundary, or platform constraint that a spec writer must not violate. For greenfield projects with no §2, derive from §6 Domain Concepts only and note "greenfield — no existing boundaries". |
| Patterns to follow | For brownfield and hybrid: naming conventions, error handling idioms, and test patterns discovered in the PRD §5 Integrations section or codebase context. For greenfield: "Establish in /cw-spec — no existing patterns." Include a fallback note so the field is never empty. |
| Suggested demoable units | The subset of slices that fall within the roadmap's **MVP boundary** (as defined by §6 Maturity Checkpoints, "MVP — Achieved After Slices 1–M"). List each slice as a candidate demoable unit with a one-line rationale. If the maturity target is "rapid prototype", use the rapid prototype boundary instead. If the target is "production", use all slices. |
| Key code references | For brownfield and hybrid: file paths and line references for entry points, models, routes, and configs mentioned in PRD §5 Integrations or domain concept definitions in §6. For greenfield: "N/A — greenfield project. File paths will be established during /cw-spec." |

## Template

```markdown
## /cw-spec Meta-Prompt

> Ready-to-use starter prompt for `/cw-spec`. Copy the content between the
> `---` markers below, or select "Run /cw-spec with this Meta-Prompt" when prompted.

---

**Feature name:** {feature name}

**Problem:** {problem — 1–3 sentences from PRD §1.2}

**Key components:**
- Slice 1 — {Goal sentence for Slice 1}
- Slice 2 — {Goal sentence for Slice 2}
- Slice N — {Goal sentence for Slice N}

**Architectural constraints:**
- {constraint 1 — from PRD §2 Positioning or §6 Domain Concepts}
- {constraint 2}
- {constraint 3}

**Patterns to follow:**
- {pattern 1 — naming, error handling, test idioms from codebase or PRD §5}
- {pattern 2}
- {pattern 3}

**Suggested demoable units (MVP-bounded):**
1. {Slice N name} — {one-line rationale for why this maps to a demoable unit}
2. {Slice M name} — {rationale}
3. {Slice K name} — {rationale}

**Key code references:**
- {path/to/entry-point} — {purpose}
- {path/to/domain-model} — {purpose}
- {path/to/config} — {purpose}

Run: `/cw-spec {feature-name}`

---
```

## Greenfield vs Brownfield Adaptations

**Greenfield** (nothing exists yet):

- **Architectural constraints**: Derive from PRD §6 Domain Concepts only. Begin with: "Greenfield — no existing boundaries. The following domain constraints apply:". If §6 is absent, write "Greenfield — no existing constraints. Establish in /cw-spec."
- **Patterns to follow**: Write "Establish in /cw-spec — no existing codebase patterns." Do not fabricate patterns.
- **Key code references**: Write "N/A — greenfield project. File paths will be established during /cw-spec."

**Brownfield** (existing codebase described in PRD §2 / §5):

- **Architectural constraints**: Pull every integration boundary from PRD §2 Positioning and every named integration from §5 Integrations. Each entry should name the system and the boundary rule.
- **Patterns to follow**: Pull from PRD §5 (SDK versions, API contracts, auth patterns) and any codebase conventions mentioned in PRD §2. If none are stated explicitly, note "Derive from codebase audit during /cw-spec Step 2."
- **Key code references**: List any file paths mentioned in PRD §5 or §6. If none are given, note "Identify during /cw-spec Step 2 (Context Assessment)."

**Hybrid** (some components exist, others are new):

- Apply brownfield rules for the existing components and greenfield rules for the new ones. Label each constraint or reference with `[existing]` or `[new]` so the spec writer knows which apply.

## Integration

After generating the meta-prompt, append it to the saved roadmap file after the `_End of Document_` footer. The appended block must be structured as:

1. A blank line after `_End of Document_`.
2. The `## /cw-spec Meta-Prompt` heading.
3. The intro blockquote.
4. A `---` horizontal rule (this is the opening marker).
5. The field content (Feature, Problem, Key components, Architectural constraints, Patterns to follow, Suggested demoable units, Key code references, Run line) — exactly as shown in the Template above.
6. A closing `---` horizontal rule.

The two `---` lines (items 4 and 6) are the extraction markers. When the user selects "Run /cw-spec with this Meta-Prompt", everything between these two `---` lines is extracted verbatim and passed as `args` to `Skill({ skill: "cw-spec", args: <extracted> })`.

**Extraction rule**: take the content between the **last two** `---` lines in the file. This is unambiguous because the roadmap body uses `---` as section separators, but those all appear before `_End of Document_`; the meta-prompt markers are always the final two `---` occurrences.
