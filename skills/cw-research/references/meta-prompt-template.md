# Meta-Prompt Template

Template for the `/cw-spec` starter prompt generated at the end of a cw-research report.

The meta-prompt opens with a **typed handoff block** (YAML frontmatter) that cw-spec validates
on read. The handoff is a contract, not narration: cw-spec parses the block and rejects malformed
input back to cw-research rather than guessing. The prose body below the block stays human-readable;
the frontmatter is the machine-checkable surface.

## Handoff Contract

The frontmatter block carries exactly these fields. All are required; cw-spec rejects the handoff if
any is missing, mistyped, or empty.

| Field | Type | Rule |
|-------|------|------|
| `feature_name` | string | Non-empty, spec-friendly (lowercase, hyphens). Becomes the spec name. |
| `research_dir` | string | Path `docs/specs/research-{topic_slug}/`. Must be the directory the report was saved in. |
| `key_files` | list of strings | Non-empty. Each entry `path -- purpose`. Files/modules identified across dimensions. |
| `demoable_unit_themes` | list of strings | Non-empty. Each entry `theme -- rationale`. Logical work groupings from module boundaries and data flow. |

## Field Derivation

Derive each field from the research findings:

| Field | Source |
|-------|--------|
| `feature_name` | Research topic, converted to a spec-friendly name |
| `research_dir` | The directory the report was saved in (`docs/specs/research-{topic_slug}/`) — passed to cw-spec so it can co-locate the spec with the research |
| `key_files` | Files and modules identified across all dimensions |
| `demoable_unit_themes` | Logical groupings of work based on module boundaries and data flow |
| Problem statement | Summary section findings -- what gap or need exists (prose body only) |
| Architectural constraints | Patterns, conventions, and boundaries discovered in Architecture & Patterns (prose body only) |
| Relevant patterns to follow | Naming conventions, error handling, test patterns from the codebase (prose body only) |
| Specific code location references | File paths and line references for entry points, models, routes, configs (prose body only) |

## Template

````markdown
## Meta-Prompt

> Ready-to-use starter prompt for `/cw-spec`. Copy the content below or select
> "Run /cw-spec with context" when prompted.

```yaml
---
feature_name: {feature-name}
research_dir: docs/specs/research-{topic_slug}/
context_assessment:
  coverage: {returned}/{spawned}
  confidence: {complete | partial}        # partial when returned < spawned
  uncovered: [{dimension}, ...]           # the degraded list; [] when complete
key_files:
  - {path/to/file1} -- {purpose}
  - {path/to/file2} -- {purpose}
demoable_unit_themes:
  - {unit theme 1} -- {brief rationale}
  - {unit theme 2} -- {brief rationale}
---
```

Build **{feature name}**.

**Problem:** {problem statement derived from research findings}

**Architectural Constraints:**
- {constraint 1, e.g., "All API routes use the middleware pattern in src/middleware/"}
- {constraint 2, e.g., "State management follows the store pattern in src/stores/"}

**Patterns to Follow:**
- {pattern 1, e.g., "Error handling uses Result<T, AppError> pattern (see src/errors.rs)"}
- {pattern 2, e.g., "Tests use describe/it structure with factory helpers (see tests/helpers/)"}

**Code References:**
- Entry point: `{path}`
- Configuration: `{path}`
- Related modules: `{path1}`, `{path2}`
- Test examples: `{path}`

Run: `/cw-spec {feature-name}`
````

## Context Assessment

The `context_assessment` block is the funnel-accounting carrier (see [funnel-accounting.md](funnel-accounting.md)).
Set `coverage: {returned}/{spawned}` from Step 2; when `returned < spawned`, set `confidence: partial` and list the
un-covered dimensions in `uncovered`. cw-spec must treat `confidence: partial` as unverified gaps, not confirmed-absent.
The block is never omitted and the coverage stat is computed, not asserted.

## Integration

After generating the meta-prompt, append it to the saved research report file. The meta-prompt section should be the last section in the report, enabling the user to copy it directly or select "Run /cw-spec with context" when prompted.
