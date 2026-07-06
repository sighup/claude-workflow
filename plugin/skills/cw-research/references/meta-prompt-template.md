# Meta-Prompt Template

Template for the `/cw-spec` starter prompt generated at the end of a cw-research report.

## Field Derivation

Derive each field from the research findings:

| Field | Source |
|-------|--------|
| Feature name | Research topic, converted to a spec-friendly name |
| Problem statement | Summary section findings -- what gap or need exists |
| Key components/files | Files and modules identified across all dimensions |
| Architectural constraints | Patterns, conventions, and boundaries discovered in Architecture & Patterns |
| Relevant patterns to follow | Naming conventions, error handling, test patterns from the codebase |
| Suggested demoable unit themes | Logical groupings of work based on module boundaries and data flow |
| Specific code location references | File paths and line references for entry points, models, routes, configs |
| Research directory | `docs/specs/research-{topic_slug}/` — passed to cw-spec so it can co-locate the spec with the research |

## Template

```markdown
## Meta-Prompt

> Ready-to-use starter prompt for `/cw-spec`. Copy the content below or select
> "Run /cw-spec with context" when prompted.

---

**Research:** `docs/specs/research-{topic_slug}/`

Build **{feature name}**.

**Problem:** {problem statement derived from research findings}

**Key Components & Files:**
- `{path/to/file1}` -- {purpose}
- `{path/to/file2}` -- {purpose}
- `{path/to/file3}` -- {purpose}

**Architectural Constraints:**
- {constraint 1, e.g., "All API routes use the middleware pattern in src/middleware/"}
- {constraint 2, e.g., "State management follows the store pattern in src/stores/"}
- {constraint 3}

**Patterns to Follow:**
- {pattern 1, e.g., "Error handling uses Result<T, AppError> pattern (see src/errors.rs)"}
- {pattern 2, e.g., "Tests use describe/it structure with factory helpers (see tests/helpers/)"}
- {pattern 3}

**Suggested Demoable Units:**
1. {unit theme 1, e.g., "Core data model and validation"} -- {brief rationale}
2. {unit theme 2, e.g., "API endpoints and middleware integration"} -- {brief rationale}
3. {unit theme 3, e.g., "UI components and state management"} -- {brief rationale}

**Code References:**
- Entry point: `{path}`
- Configuration: `{path}`
- Related modules: `{path1}`, `{path2}`
- Test examples: `{path}`

Run: `/cw-spec {feature-name}`
```

## Integration

After generating the meta-prompt, append it to the saved research report file. The meta-prompt section should be the last section in the report, enabling the user to copy it directly or select "Run /cw-spec with context" when prompted.
