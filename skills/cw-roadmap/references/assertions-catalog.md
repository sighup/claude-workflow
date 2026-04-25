# Assertions Catalog

This document lists every assertion in `assertions.py` with its name, docstring (what it checks), and a minimal markdown fragment that would fail it.

---

### assert_section_order

**Checks:** Roadmap has six H2 sections in canonical order: Starting State, Sequencing Principles, Thin Slices, What We're Deliberately Not Building, Risk & Open Questions, Maturity Checkpoints.

**Failing example:**

```markdown
## 2. Sequencing Principles
Content here

## 1. Starting State
Content here

## 3. Thin Slices
```

(Swapped the order of first two sections)

---

### assert_line_count

**Checks:** Roadmap body line count is between 150 and 250 inclusive.

**Failing example:**

```markdown
# Short Roadmap

## 1. Starting State
Brief intro.

## 2. Sequencing Principles
One principle.

## 3. Thin Slices
### Slice 1: Something
- **Goal**: Goal text.
- **Delivers**: Item 1, Item 2, Item 3.
- **Depends on**: None.
- **Lifecycle phases exercised**: Frame.
- **Exit signal**: Passes tests.
- **Traces**: PRD §1.

## 4. What We're Deliberately Not Building
- Feature X — reason.

## 5. Risk & Open Questions
**Risk** — description.

## 6. Maturity Checkpoints
| Level | Slice | What |
|-------|-------|------|
| MVP | 1 | Done |
```

(Only ~30 lines, well below 150)

---

### assert_slice_cardinality

**Checks:** Section 3 (Thin Slices) contains between 5 and 8 slices inclusive.

**Failing example:**

```markdown
## 3. Thin Slices

### Slice 1: First
- **Goal**: Goal.
- **Delivers**: Item 1, Item 2, Item 3.
- **Depends on**: None.
- **Lifecycle phases exercised**: Frame.
- **Exit signal**: Shows output.
- **Traces**: PRD §1.

### Slice 2: Second
- **Goal**: Goal.
- **Delivers**: Item 1, Item 2, Item 3.
- **Depends on**: Slice 1.
- **Lifecycle phases exercised**: Build.
- **Exit signal**: Displays result.
- **Traces**: PRD §2.
```

(Only 2 slices instead of 5-8)

---

### assert_slice_required_fields

**Checks:** Each slice declares all five required fields: Goal, Delivers, Depends on, Lifecycle phases exercised, Exit signal.

**Failing example:**

```markdown
### Slice 1: Missing Field
- **Goal**: Goal text.
- **Delivers**: Item 1, Item 2, Item 3.
- **Depends on**: None.
- **Exit signal**: Shows result.
```

(Missing "Lifecycle phases exercised" field)

---

### assert_slice_traces_line

**Checks:** Each slice has a Traces: line citing the PRD sections it implements.

**Failing example:**

```markdown
### Slice 1: No Traces
- **Goal**: Goal text.
- **Delivers**: Item 1, Item 2, Item 3.
- **Depends on**: None.
- **Lifecycle phases exercised**: Frame.
- **Exit signal**: Shows output.
```

(Missing "Traces:" line entirely)

---

### assert_exit_signal_verb

**Checks:** Each slice Exit signal contains a concrete observable verb (shows, returns, produces, displays, outputs, logs, renders, passes, etc.).

**Failing example:**

```markdown
### Slice 1: Weak Exit Signal
- **Goal**: Goal text.
- **Delivers**: Item 1, Item 2, Item 3.
- **Depends on**: None.
- **Lifecycle phases exercised**: Frame.
- **Exit signal**: Work is complete.
- **Traces**: PRD §1.
```

("complete" is not an observable verb; should use "shows", "returns", "displays", etc.)

---

### assert_delivers_bullet_count

**Checks:** Each slice Delivers section has between 3 and 6 bullets inclusive.

**Failing example:**

```markdown
### Slice 1: Too Few Deliverables
- **Goal**: Goal text.
- **Delivers**: Item 1, Item 2.
- **Depends on**: None.
- **Lifecycle phases exercised**: Frame.
- **Exit signal**: Shows output.
- **Traces**: PRD §1.
```

(Only 2 deliverables instead of 3-6)

---

### assert_dag_acyclic

**Checks:** The slice dependency graph is acyclic (no circular dependencies between slices).

**Failing example:**

```markdown
### Slice 1: Cycles
- **Depends on**: Slice 2.

### Slice 2: Returns Fire
- **Depends on**: Slice 1.
```

(Slice 1 depends on Slice 2, and Slice 2 depends on Slice 1 — circular)

---

### assert_depends_on_resolve

**Checks:** All Depends on slice references resolve to slices defined in this roadmap (no dangling references).

**Failing example:**

```markdown
### Slice 1: References Non-Existent
- **Goal**: Goal text.
- **Delivers**: Item 1, Item 2, Item 3.
- **Depends on**: Slice 99.
- **Lifecycle phases exercised**: Frame.
- **Exit signal**: Shows output.
- **Traces**: PRD §1.

### Slice 2: Another
- **Goal**: Goal text.
- **Delivers**: Item 1, Item 2, Item 3.
- **Depends on**: None.
- **Lifecycle phases exercised**: Build.
- **Exit signal**: Displays result.
- **Traces**: PRD §2.
```

(Slice 1 depends on Slice 99, which does not exist)

---

### assert_traces_prd_section_format

**Checks:** Each slice Traces line references at least one PRD section in the format 'PRD §<digit>'.

**Failing example:**

```markdown
### Slice 1: Traces Without Section
- **Goal**: Goal text.
- **Delivers**: Item 1, Item 2, Item 3.
- **Depends on**: None.
- **Lifecycle phases exercised**: Frame.
- **Exit signal**: Shows output.
- **Traces**: PRD section 3.
```

("PRD section 3" lacks the § symbol; should be "PRD §3")

---

### assert_maturity_checkpoints_rows

**Checks:** Maturity Checkpoints table has at least 3 data rows.

**Failing example:**

```markdown
## 6. Maturity Checkpoints

| Level | Slice | What |
|-------|-------|------|
| Prototype | 1 | Started |
| MVP | 2 | In flight |
```

(Only 2 data rows instead of 3+)

---

### assert_scope_exclusion_count

**Checks:** What We're Deliberately Not Building section has at least 3 bullet entries.

**Failing example:**

```markdown
## 4. What We're Deliberately Not Building

- Feature A — too early.
- Feature B — not in scope.
```

(Only 2 exclusions instead of 3+)

---

### assert_scope_exclusion_rationale

**Checks:** Each scope-exclusion bullet includes a rationale after the em-dash (—) or en-dash (–) separator.

**Failing example:**

```markdown
## 4. What We're Deliberately Not Building

- Feature A — reason included.
- Feature B
- Feature C — reason included.
```

(Feature B has no em-dash or en-dash with rationale)

---

### assert_no_body_backtick_fences

**Checks:** No triple-backtick fences appear in the roadmap body (between first H2 and the Meta-Prompt --- marker).

**Failing example:**

```markdown
## 3. Thin Slices

### Slice 1: Has Code
- **Goal**: Goal text.
- **Delivers**: 
  - ```python
    some_code()
    ```
- **Depends on**: None.
- **Lifecycle phases exercised**: Build.
- **Exit signal**: Shows output.
- **Traces**: PRD §1.
```

(Code fence in body section)

---

### assert_no_deep_headings_in_slices

**Checks:** No headings deeper than H3 appear inside slice blocks.

**Failing example:**

```markdown
## 3. Thin Slices

### Slice 1: Deep Heading
- **Goal**: Goal text.
- **Delivers**: Item 1, Item 2, Item 3.
- **Depends on**: None.
- **Lifecycle phases exercised**: Frame.
- **Exit signal**: Shows output.
- **Traces**: PRD §1.

#### This is H4, not allowed
More content.
```

(H4 heading in slice block)

---

### assert_sequencing_principles_count

**Checks:** Sequencing Principles section has between 4 and 6 bulleted items inclusive.

**Failing example:**

```markdown
## 2. Sequencing Principles

- Principle 1.
- Principle 2.
- Principle 3.
```

(Only 3 principles instead of 4-6)

---

### assert_meta_prompt_block

**Checks:** Meta-Prompt block exists between two '---' markers at end of file containing Feature name:, Problem:, Key components:, Key code references:.

**Failing example:**

```markdown
## 6. Maturity Checkpoints

| Level | Slice | What |
|-------|-------|------|
| MVP | 5 | Done |

_End of Document_

---
Feature name: Missing problem section
Key components: Something
Key code references: paths
---
```

(Missing "Problem:" field in the Meta-Prompt block)

---
