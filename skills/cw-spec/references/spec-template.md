# Spec Template & Authoring Reference

## Contents
- Markdown template for the spec file
- Demoable units guidelines
- Proof artifact types
- Health checks that are NOT proofs

## Markdown template

Save to `./docs/specs/[NN]-spec-[feature-name]/[NN]-spec-[feature-name].md`:

```markdown
# [NN]-spec-[feature-name]

## Introduction/Overview
[2-3 sentences: what the feature is and what problem it solves]

## Goals
[3-5 specific, measurable objectives]

## User Stories
[Format: "As a [user], I want to [action] so that [benefit]"]

## Demoable Units of Work

### Unit 1: [Title]

**Purpose:** [What this slice accomplishes]

**Functional Requirements:**
- The system shall [requirement: clear, testable, unambiguous]
- The system shall [requirement: clear, testable, unambiguous]

**Proof Artifacts:**
- [Type]: [description] demonstrates [what it proves]

### Unit 2: [Title]
[Same structure as Unit 1]

## Non-Goals (Out of Scope)
[What this feature will NOT include]

## Design Considerations
[UI/UX requirements, or "No specific design requirements identified."]

## Repository Standards
[Existing patterns implementation should follow]

## Technical Considerations
[Implementation constraints, dependencies, architectural decisions]

## Security Considerations
[API keys, tokens, data privacy, auth requirements]

## Success Metrics
[How success is measured, with targets where possible]

## Open Questions
[Remaining questions, or "No open questions at this time."]
```

## Demoable units guidelines

Each demoable unit must be:
- **Thin vertical slice**: end-to-end functionality, not horizontal layers
- **Independently demonstrable**: can show working feature after completion
- **Appropriately sized**: 2–4 units per spec is typical
- **Sequentially buildable**: later units can depend on earlier ones

## Proof artifact types

| Type | Format | Example |
|------|--------|---------|
| Test | `Test: [file] passes` | `Test: auth.test.ts passes demonstrates login works` |
| CLI | `CLI: [command] returns [expected]` | `CLI: curl /health returns {"status":"ok"}` |
| URL | `URL: [url] shows [expected]` | `URL: /dashboard shows welcome message` |
| Screenshot | `Screenshot: [page] showing [state]` | `Screenshot: /login page showing error state` |
| File | `File: [path] contains [pattern]` | `File: config.json contains new field` |

Aim for 1–2 proof artifacts per demoable unit, max 3. Each should demonstrate behavior that *only* exists after this unit is built.

## What is NOT a proof artifact

These are project-wide health checks that already run as part of every task's verification step — never list them as proofs:

- `npm run lint` / `eslint` / `ruff` / `golangci-lint`
- `tsc --noEmit` / `mypy` / `cargo check` (typecheck)
- `npm run build` / `cargo build`
- `npm test` / `pytest` / `go test ./...` with no path filter (full project test suite)

Rule of thumb: if your proof would pass for an empty PR, it's not a proof — it's a health check. Drop it.
