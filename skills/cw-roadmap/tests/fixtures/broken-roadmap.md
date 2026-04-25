# Sample Product — Roadmap

**Roadmap Document**

| Field | Value |
|-------|-------|
| Document Version | 0.1.0 |
| Status | DRAFT |
| Author | test-harness |
| Date | 2026-04-23 |
| PRD Reference | ../prds/sample.md |
| Starting State | greenfield |
| Build Model | small team |
| Maturity Target | MVP |

> **Scope of this document:** Sequencing document describing what ships next and why. Implementation details, architecture decisions, and test plans belong in downstream specs.

---

## 1. Starting State

Nothing exists yet. This is a greenfield project building a new capability described in the PRD. The system will be built by a team of 3 engineers over 8 weeks, targeting an MVP that demonstrates core functionality with manual testing.

---

## 2. Sequencing Principles

- Deliver demoable behavior in the first slice.
- Build the artifact format before the UI.
- Defer persistence until workflow is proven.
- Validate dependencies early, stabilize late.

---

## 3. Thin Slices

### Slice 1: Core Parser
- **Goal**: Basic markdown parsing works end-to-end.
- **Delivers**:
  - Parse markdown file and extract sections.
  - Return structured representation of headings and content.
  - Handle simple error cases.
  - Produce parseable output artifact.
  - Write integration test demonstrating parse → structure flow.
- **Depends on**: None.
- **Lifecycle phases exercised**: Build, Prove.
- **Exit signal**: Shows parsed structure for sample input.
- **Traces**: PRD §1.

### Slice 2: Validation Engine
- **Goal**: Validate parsed structure against schema rules.
- **Delivers**:
  - Implement assertion library for roadmap rules.
  - Check section ordering and slice structure.
  - Verify all required fields are present.
  - Return validation result (pass/fail per rule).
  - Unit tests for each assertion rule.
- **Depends on**: Slice 1.
- **Lifecycle phases exercised**: Build, Prove.
- **Exit signal**: Displays validation results in table format.
- **Traces**: PRD §2.

### Slice 3: Dependency Graph
- **Goal**: Slice dependencies are validated for cycles and resolution.
- **Delivers**:
  - Build slice dependency DAG from parsed roadmap.
  - Check for circular dependencies using DFS algorithm.
  - Verify all referenced slices exist in roadmap.
  - Return dependency validation errors if any detected.
  - Add integration test covering cyclic dependency case.
- **Depends on**: Slice 2.
- **Lifecycle phases exercised**: Build, Prove.
- **Exit signal**: Logs validation results for complex DAG.

### Slice 4: Lint CLI
- **Goal**: Standalone lint command reports all assertion results.
- **Delivers**:
  - Create `/cw-roadmap lint` command dispatcher.
  - Run all assertions on input roadmap in sequence.
  - Print results in fixed-width table format (PASS/FAIL).
  - Exit with code 0 if all pass, 1 if any fail.
  - Support verbose output showing failed assertions.
- **Depends on**: Slice 99.
- **Lifecycle phases exercised**: Build, Prove.
- **Exit signal**: Displays lint report table for input file.
- **Traces**: PRD §3.

### Slice 5: Reporting and Metrics
- **Goal**: Lint output includes pass-rate metrics for visibility.
- **Delivers**:
  - Add pass count and total assertion count to summary line.
  - Show pass rate as percentage (K/M).
  - Highlight failed assertions prominently in output.
  - Generate pass-rate trend log appended to CSV file.
  - Document pass rate interpretation in README.
- **Depends on**: Slice 4.
- **Lifecycle phases exercised**: Observe.
- **Exit signal**: Outputs pass-rate summary line after table.
- **Traces**: PRD §4.

### Slice 6: Documentation
- **Goal**: Users can understand all assertions and extend the system.
- **Delivers**:
  - Write assertions catalog listing every assertion by name.
  - Include docstring and failing example for each assertion.
  - Create fixture gallery with broken roadmaps for testing.
  - Document how to add new assertions to the library.
  - Write quick-start guide for running lint command.
- **Depends on**: Slice 5.
- **Lifecycle phases exercised**: Observe.
- **Exit signal**: Renders complete assertions documentation.
- **Traces**: PRD §5.

---

## 4. What We're Deliberately Not Building

- **Full PRD validation** — The lint system validates roadmap structure only, not PRD conformance. PRD validation is a separate skill.
- **Automated repair** — This roadmap identifies problems but does not attempt to fix them. Repair is manual or scripted downstream.
- **Real-time linting** — No IDE integration or file-watch mode in this roadmap.

---

## 5. Risk & Open Questions

**Maturity of dependency resolver** — Building a DAG validator is straightforward for acyclic graphs. A real roadmap might have implicit dependencies we miss.

**Assertion extensibility** — If the assertion library grows beyond 20 checks, maintainability becomes harder. Plan for a plugin registry if this becomes a bottleneck.

**Performance at scale** — Parsing and validating a 500-line roadmap is fast on any machine. If roadmaps grow dramatically larger, revisit performance assumptions.

---

## 6. Maturity Checkpoints

| Maturity Level | Achieved After | What's True |
|---|---|---|
| Rapid Prototype | Slice 2 | Parser and validator work end-to-end. |

---

_End of Document_

---

Feature name: Roadmap Lint System

Problem: Teams need a way to validate that roadmap documents conform to a schema and best practices, catching errors early before decomposition.

Key components:
- Markdown parser (extract sections and slices)
- Assertion library (15+ binary checks)
- Dependency graph validator (detect cycles, resolve references)
- Lint CLI (run all assertions, print results)

Key code references:
- skills/cw-roadmap/assertions.py
- skills/cw-roadmap/cli/lint.py
- tests/test_assertions.py

---
