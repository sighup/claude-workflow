"""
test_assertions.py — Unit tests for the cw-roadmap binary assertion library.

Each assertion gets >=1 passing case (using GOOD_ROADMAP) and >=1 failing case
(using a targeted single-mutation of GOOD_ROADMAP).

Run from the skills/cw-roadmap/ directory:
    python3 -m pytest tests/test_assertions.py -v

Import strategy:
    assertions.py lives at skills/cw-roadmap/assertions.py (not in a package).
    We load it via importlib.util so it exercises the same import path used by
    cw-roadmap lint and the .autoresearch/ harness.
"""

from __future__ import annotations

import importlib.util
import inspect
import sys
from pathlib import Path

import pytest

# ---------------------------------------------------------------------------
# Load assertions module via importlib (mirrors production import path)
# ---------------------------------------------------------------------------

_ASSERTIONS_PATH = Path(__file__).resolve().parent.parent / "assertions.py"


def _load_assertions():
    spec = importlib.util.spec_from_file_location("assertions", _ASSERTIONS_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


_mod = _load_assertions()
ASSERTIONS = _mod.ASSERTIONS

# Pull individual functions for explicit tests
assert_section_order = _mod.assert_section_order
assert_line_count = _mod.assert_line_count
assert_slice_cardinality = _mod.assert_slice_cardinality
assert_slice_required_fields = _mod.assert_slice_required_fields
assert_slice_traces_line = _mod.assert_slice_traces_line
assert_exit_signal_verb = _mod.assert_exit_signal_verb
assert_delivers_bullet_count = _mod.assert_delivers_bullet_count
assert_dag_acyclic = _mod.assert_dag_acyclic
assert_depends_on_resolve = _mod.assert_depends_on_resolve
assert_traces_prd_section_format = _mod.assert_traces_prd_section_format
assert_maturity_checkpoints_rows = _mod.assert_maturity_checkpoints_rows
assert_scope_exclusion_count = _mod.assert_scope_exclusion_count
assert_scope_exclusion_rationale = _mod.assert_scope_exclusion_rationale
assert_no_body_backtick_fences = _mod.assert_no_body_backtick_fences
assert_no_deep_headings_in_slices = _mod.assert_no_deep_headings_in_slices
assert_sequencing_principles_count = _mod.assert_sequencing_principles_count
assert_meta_prompt_block = _mod.assert_meta_prompt_block

# ---------------------------------------------------------------------------
# Canonical good-roadmap fixture (~180 lines, all checks pass)
# ---------------------------------------------------------------------------

GOOD_ROADMAP = """\
# MyProduct — Roadmap

**Roadmap Document**

| Field | Value |
|---|---|
| Document Version | 0.1.0 |
| Status | DRAFT |
| Author | Team |
| Date | 2026-04-23 |
| PRD Reference | ../prds/01-product.md |
| Starting State | greenfield |
| Build Model | solo builder |
| Maturity Target | MVP |

> **Scope of this document:** Sequencing document only. See specs and ADRs for implementation detail.
> Architecture decisions, task breakdowns, and acceptance criteria belong in downstream documents.

---

## 1. Starting State

Nothing exists today. The PRD describes a web application that lets users manage projects and
track task completion across their teams. The codebase is empty; this roadmap sequences from
zero to MVP. We have a clear understanding of the target user and their core workflow.
The tech stack is undecided; that decision belongs in a downstream ADR, not in this document.
No CI/CD pipeline or deployment infrastructure exists at this point in the project.
Target users have been interviewed and their workflow is documented in the PRD.
The primary user goal is reducing time spent tracking project status manually.
The secondary goal is improving visibility into cross-team dependencies.
The product vision is to deliver a lightweight alternative to heavyweight project tools.

---

## 2. Sequencing Principles

- Demo something visible in the first slice so the toolchain is proven end-to-end.
- Defer persistence until the core workflow is proven to reduce early rework.
- Build the contract (data model) before the surfaces that consume it.
- Keep slices independent so any single slice can be deferred without blocking others.
- Prefer user-visible outcomes over internal infrastructure.

---

## 3. Thin Slices

### Slice 1: Hello World Shell
- **Goal**: A runnable shell exists that displays a welcome screen to the user.
- **Delivers**:
  - Application boots without errors on a clean install
  - Welcome screen renders with product name and version
  - Navigation skeleton shows top-level sections
  - Dependency versions are pinned and reproducible
- **Depends on**: None
- **Lifecycle phases exercised**: Build
- **Exit signal**: Running the app shows a welcome screen in the browser.
- **Traces**: PRD §1, §2

### Slice 2: User Authentication
- **Goal**: A user can register and log in with email and password.
- **Delivers**:
  - Registration form validates and creates an account
  - Login form authenticates and returns a session token
  - Protected routes redirect unauthenticated users to login
  - Logout invalidates the session and redirects to login
- **Depends on**: Slice 1
- **Lifecycle phases exercised**: Build, Prove
- **Exit signal**: A new user registers and logs in; the dashboard renders correctly.
- **Traces**: PRD §3

### Slice 3: Project CRUD
- **Goal**: A logged-in user can create, view, update, and delete projects.
- **Delivers**:
  - Project list page displays all user projects
  - Create-project form produces a new project with a unique ID
  - Edit-project form updates the project name and description
  - Delete confirmation removes the project from the list
  - Empty state renders when no projects exist
- **Depends on**: Slice 2
- **Lifecycle phases exercised**: Build, Prove
- **Exit signal**: A user creates a project and it shows in the project list.
- **Traces**: PRD §4

### Slice 4: Task Management
- **Goal**: A user can add, complete, and remove tasks within a project.
- **Delivers**:
  - Task list renders inside a project detail page
  - Add-task form produces a new task under the current project
  - Completing a task logs a completion timestamp
  - Removing a task outputs a confirmation and deletes the record
- **Depends on**: Slice 3
- **Lifecycle phases exercised**: Build, Prove
- **Exit signal**: A user adds a task and marks it complete; the task shows as done.
- **Traces**: PRD §5, §6

### Slice 5: Reporting Dashboard
- **Goal**: A user can view a summary of project progress on a dashboard.
- **Delivers**:
  - Dashboard renders task completion metrics per project
  - Progress chart displays percentage of completed tasks
  - Date-range filter returns filtered results
  - Export button produces a CSV download of the current view
- **Depends on**: Slice 4
- **Lifecycle phases exercised**: Build, Observe
- **Exit signal**: The dashboard renders project stats after the user completes tasks.
- **Traces**: PRD §7

---

## 4. What We're Deliberately Not Building

- Real-time collaboration — the PRD envisions multi-user editing, but this adds significant complexity that is out of scope for the MVP.
- Mobile native apps — the PRD mentions iOS and Android clients, but we defer these until the web app is validated with users.
- Third-party integrations — Slack and GitHub integrations are in the PRD but out of scope until core workflow is proven.
- Advanced analytics — ML-powered insights are listed in the PRD vision but require a data corpus we do not yet have.

---

## 5. Risk & Open Questions

**Session token lifetime** — We have not decided on session expiry policy; this affects user experience in Slice 2.
**Database choice** — The persistence layer is not yet chosen; Slice 3 assumes a relational DB but this is open.
**CSV export format** — The exact column schema for the Slice 5 export is not specified in the PRD.
**Test environment** — No staging environment exists; this may complicate Slice 2 verification.
**Accessibility requirements** — The PRD does not specify WCAG level; this affects implementation in early slices.
**Browser support matrix** — No browser targets are specified; this affects CSS decisions in Slice 1.
**Performance budgets** — Load-time targets are not in the PRD; this may affect Slice 5 dashboard design.
**Legal/privacy compliance** — GDPR handling for user data is unspecified and may affect Slice 2 scope.
**Hosting platform** — Cloud provider and deployment model are undecided; affects Slice 1 toolchain choices.
**QA strategy** — No automated testing approach is documented; this risk spans all five slices.

---

## 6. Maturity Checkpoints

| Maturity Level | Achieved After | What's True |
|---|---|---|
| Rapid Prototype | Slice 1 | Application boots and displays a welcome screen to any user. |
| Basic Auth MVP | Slice 2 | Users can register, log in, and access protected content. |
| Core MVP | Slice 3 | Users can create and manage projects end-to-end. |
| Full MVP | Slice 5 | Users can track tasks and view progress reports. |

_End of Document_

---
Feature name: MyProduct
Problem: Users need a way to manage projects and tasks.
Key components: auth, project CRUD, task management, reporting
Key code references: src/auth.py, src/projects.py, src/tasks.py
---
"""

# ---------------------------------------------------------------------------
# Contract test: ASSERTIONS list and callable signatures
# ---------------------------------------------------------------------------

class TestAssertionsContract:
    def test_assertions_list_exists(self):
        assert hasattr(_mod, "ASSERTIONS"), "Module must export ASSERTIONS"

    def test_assertions_count_at_least_15(self):
        assert len(ASSERTIONS) >= 15, (
            f"ASSERTIONS must have >=15 entries, got {len(ASSERTIONS)}"
        )

    def test_all_assertions_callable(self):
        for fn in ASSERTIONS:
            assert callable(fn), f"{fn} must be callable"

    def test_all_assertions_have_docstring(self):
        for fn in ASSERTIONS:
            assert fn.__doc__ and fn.__doc__.strip(), (
                f"{fn.__name__} must have a non-empty docstring"
            )

    def test_all_assertions_accept_one_str_param(self):
        for fn in ASSERTIONS:
            sig = inspect.signature(fn)
            params = list(sig.parameters.values())
            assert len(params) == 1, (
                f"{fn.__name__} must accept exactly one parameter, got {len(params)}"
            )

    def test_all_assertions_return_bool_on_good_roadmap(self):
        for fn in ASSERTIONS:
            result = fn(GOOD_ROADMAP)
            assert isinstance(result, bool), (
                f"{fn.__name__}(GOOD_ROADMAP) must return bool, got {type(result)}"
            )

    def test_good_roadmap_passes_all_assertions(self):
        failures = [fn.__name__ for fn in ASSERTIONS if not fn(GOOD_ROADMAP)]
        assert not failures, (
            f"GOOD_ROADMAP should pass all assertions, failed: {failures}"
        )


# ---------------------------------------------------------------------------
# A1: assert_section_order
# ---------------------------------------------------------------------------

class TestAssertSectionOrder:
    def test_good_roadmap_passes(self):
        assert assert_section_order(GOOD_ROADMAP) is True

    def test_wrong_order_fails(self):
        # Swap sections 1 and 2 — order becomes wrong
        bad = GOOD_ROADMAP.replace(
            "## 1. Starting State",
            "## 1. ZZZ Starting State TEMP",
        ).replace(
            "## 2. Sequencing Principles",
            "## 1. Starting State",
        ).replace(
            "## 1. ZZZ Starting State TEMP",
            "## 2. Sequencing Principles",
        )
        assert assert_section_order(bad) is False

    def test_missing_section_fails(self):
        # Remove Maturity Checkpoints heading
        bad = GOOD_ROADMAP.replace("## 6. Maturity Checkpoints", "## 6. Something Else")
        assert assert_section_order(bad) is False

    def test_empty_string_fails(self):
        assert assert_section_order("") is False


# ---------------------------------------------------------------------------
# A2: assert_line_count
# ---------------------------------------------------------------------------

class TestAssertLineCount:
    def test_good_roadmap_passes(self):
        assert assert_line_count(GOOD_ROADMAP) is True

    def test_too_few_lines_fails(self):
        short = "\n".join(["line"] * 100)
        assert assert_line_count(short) is False

    def test_too_many_lines_fails(self):
        long_doc = "\n".join(["line"] * 300)
        assert assert_line_count(long_doc) is False

    def test_exactly_150_passes(self):
        doc = "\n".join(["line"] * 150)
        assert assert_line_count(doc) is True

    def test_exactly_250_passes(self):
        doc = "\n".join(["line"] * 250)
        assert assert_line_count(doc) is True

    def test_149_fails(self):
        doc = "\n".join(["line"] * 149)
        assert assert_line_count(doc) is False

    def test_251_fails(self):
        doc = "\n".join(["line"] * 251)
        assert assert_line_count(doc) is False


# ---------------------------------------------------------------------------
# A3: assert_slice_cardinality
# ---------------------------------------------------------------------------

class TestAssertSliceCardinality:
    def test_good_roadmap_passes(self):
        assert assert_slice_cardinality(GOOD_ROADMAP) is True

    def test_too_few_slices_fails(self):
        # Remove all slices and add only 3
        thin_section = """\
## 3. Thin Slices

### Slice 1: A
- **Goal**: Goal A.
- **Delivers**:
  - Thing one
  - Thing two
  - Thing three
- **Depends on**: None
- **Lifecycle phases exercised**: Build
- **Exit signal**: Shows result.
- **Traces**: PRD §1

### Slice 2: B
- **Goal**: Goal B.
- **Delivers**:
  - Thing one
  - Thing two
  - Thing three
- **Depends on**: Slice 1
- **Lifecycle phases exercised**: Build
- **Exit signal**: Returns output.
- **Traces**: PRD §2

### Slice 3: C
- **Goal**: Goal C.
- **Delivers**:
  - Thing one
  - Thing two
  - Thing three
- **Depends on**: Slice 2
- **Lifecycle phases exercised**: Build
- **Exit signal**: Passes test.
- **Traces**: PRD §3
"""
        bad = _replace_section(GOOD_ROADMAP, "## 3. Thin Slices", thin_section)
        assert assert_slice_cardinality(bad) is False

    def test_too_many_slices_fails(self):
        # Inject 4 extra slices to push from 5 to 9 (above the 5-8 limit)
        extra = (
            "\n### Slice 6: Extra One\n- **Goal**: Extra one.\n"
            "\n### Slice 7: Extra Two\n- **Goal**: Extra two.\n"
            "\n### Slice 8: Extra Three\n- **Goal**: Extra three.\n"
            "\n### Slice 9: Extra Four\n- **Goal**: Extra four.\n"
        )
        bad = GOOD_ROADMAP.replace(
            "---\n\n## 4. What We're Deliberately Not Building",
            extra + "\n---\n\n## 4. What We're Deliberately Not Building",
        )
        assert assert_slice_cardinality(bad) is False

    def test_no_thin_slices_section_fails(self):
        bad = GOOD_ROADMAP.replace("## 3. Thin Slices", "## 3. Something Else")
        assert assert_slice_cardinality(bad) is False


# ---------------------------------------------------------------------------
# A4: assert_slice_required_fields
# ---------------------------------------------------------------------------

class TestAssertSliceRequiredFields:
    def test_good_roadmap_passes(self):
        assert assert_slice_required_fields(GOOD_ROADMAP) is True

    def test_missing_goal_fails(self):
        bad = GOOD_ROADMAP.replace("- **Goal**: A runnable shell exists that displays a welcome screen to the user.", "")
        assert assert_slice_required_fields(bad) is False

    def test_missing_delivers_fails(self):
        bad = GOOD_ROADMAP.replace("- **Delivers**:\n  - Application boots without errors on a clean install", "- **Deliverables**:\n  - Application boots without errors on a clean install")
        assert assert_slice_required_fields(bad) is False

    def test_missing_depends_on_fails(self):
        bad = GOOD_ROADMAP.replace("- **Depends on**: None\n- **Lifecycle phases exercised**: Build\n- **Exit signal**: Running the app shows a welcome screen in the browser.", "- **Lifecycle phases exercised**: Build\n- **Exit signal**: Running the app shows a welcome screen in the browser.")
        assert assert_slice_required_fields(bad) is False

    def test_missing_lifecycle_fails(self):
        bad = GOOD_ROADMAP.replace(
            "- **Lifecycle phases exercised**: Build\n- **Exit signal**: Running the app shows a welcome screen in the browser.",
            "- **Exit signal**: Running the app shows a welcome screen in the browser."
        )
        assert assert_slice_required_fields(bad) is False


# ---------------------------------------------------------------------------
# A5: assert_slice_traces_line
# ---------------------------------------------------------------------------

class TestAssertSliceTracesLine:
    def test_good_roadmap_passes(self):
        assert assert_slice_traces_line(GOOD_ROADMAP) is True

    def test_missing_traces_fails(self):
        bad = GOOD_ROADMAP.replace("- **Traces**: PRD §1, §2\n", "")
        assert assert_slice_traces_line(bad) is False

    def test_empty_roadmap_fails(self):
        assert assert_slice_traces_line("## 3. Thin Slices\n") is False


# ---------------------------------------------------------------------------
# A6: assert_exit_signal_verb
# ---------------------------------------------------------------------------

class TestAssertExitSignalVerb:
    def test_good_roadmap_passes(self):
        assert assert_exit_signal_verb(GOOD_ROADMAP) is True

    def test_no_verb_fails(self):
        bad = GOOD_ROADMAP.replace(
            "- **Exit signal**: Running the app shows a welcome screen in the browser.",
            "- **Exit signal**: The welcome screen is visible when done.",
        )
        assert assert_exit_signal_verb(bad) is False

    def test_returns_verb_passes(self):
        snippet = """\
## 3. Thin Slices

### Slice 1: Test
- **Goal**: Something works.
- **Delivers**:
  - Outcome one
  - Outcome two
  - Outcome three
- **Depends on**: None
- **Lifecycle phases exercised**: Build
- **Exit signal**: The API returns a 200 response.
- **Traces**: PRD §1
"""
        assert assert_exit_signal_verb(snippet) is True

    def test_passes_verb_works(self):
        snippet = """\
## 3. Thin Slices

### Slice 1: Test
- **Goal**: Something works.
- **Delivers**:
  - Outcome one
  - Outcome two
  - Outcome three
- **Depends on**: None
- **Lifecycle phases exercised**: Build
- **Exit signal**: The integration test suite passes.
- **Traces**: PRD §1
"""
        assert assert_exit_signal_verb(snippet) is True


# ---------------------------------------------------------------------------
# A7: assert_delivers_bullet_count
# ---------------------------------------------------------------------------

class TestAssertDeliversBulletCount:
    def test_good_roadmap_passes(self):
        assert assert_delivers_bullet_count(GOOD_ROADMAP) is True

    def test_too_few_bullets_fails(self):
        # Slice 1 has 4 bullets; remove two to drop below minimum
        bad = GOOD_ROADMAP.replace(
            """\
- **Delivers**:
  - Application boots without errors on a clean install
  - Welcome screen renders with product name and version
  - Navigation skeleton shows top-level sections
  - Dependency versions are pinned and reproducible""",
            """\
- **Delivers**:
  - Application boots without errors on a clean install
  - Welcome screen renders with product name and version""",
        )
        assert assert_delivers_bullet_count(bad) is False

    def test_too_many_bullets_fails(self):
        bad = GOOD_ROADMAP.replace(
            """\
- **Delivers**:
  - Application boots without errors on a clean install
  - Welcome screen renders with product name and version
  - Navigation skeleton shows top-level sections
  - Dependency versions are pinned and reproducible""",
            """\
- **Delivers**:
  - Application boots without errors on a clean install
  - Welcome screen renders with product name and version
  - Navigation skeleton shows top-level sections
  - Dependency versions are pinned and reproducible
  - Extra bullet five
  - Extra bullet six
  - Extra bullet seven""",
        )
        assert assert_delivers_bullet_count(bad) is False

    def test_exactly_3_passes(self):
        snippet = """\
## 3. Thin Slices

### Slice 1: Test
- **Goal**: Something.
- **Delivers**:
  - Outcome one
  - Outcome two
  - Outcome three
- **Depends on**: None
- **Lifecycle phases exercised**: Build
- **Exit signal**: Shows result.
- **Traces**: PRD §1
"""
        assert assert_delivers_bullet_count(snippet) is True

    def test_exactly_6_passes(self):
        snippet = """\
## 3. Thin Slices

### Slice 1: Test
- **Goal**: Something.
- **Delivers**:
  - Outcome one
  - Outcome two
  - Outcome three
  - Outcome four
  - Outcome five
  - Outcome six
- **Depends on**: None
- **Lifecycle phases exercised**: Build
- **Exit signal**: Renders output.
- **Traces**: PRD §1
"""
        assert assert_delivers_bullet_count(snippet) is True


# ---------------------------------------------------------------------------
# A8: assert_dag_acyclic
# ---------------------------------------------------------------------------

class TestAssertDagAcyclic:
    def test_good_roadmap_passes(self):
        assert assert_dag_acyclic(GOOD_ROADMAP) is True

    def test_self_cycle_fails(self):
        bad = GOOD_ROADMAP.replace(
            "- **Depends on**: None\n- **Lifecycle phases exercised**: Build\n- **Exit signal**: Running the app shows a welcome screen in the browser.",
            "- **Depends on**: Slice 1\n- **Lifecycle phases exercised**: Build\n- **Exit signal**: Running the app shows a welcome screen in the browser.",
        )
        assert assert_dag_acyclic(bad) is False

    def test_two_node_cycle_fails(self):
        snippet = """\
## 3. Thin Slices

### Slice 1: A
- **Goal**: A works.
- **Delivers**:
  - Outcome one
  - Outcome two
  - Outcome three
- **Depends on**: Slice 2
- **Lifecycle phases exercised**: Build
- **Exit signal**: Shows A.
- **Traces**: PRD §1

### Slice 2: B
- **Goal**: B works.
- **Delivers**:
  - Outcome one
  - Outcome two
  - Outcome three
- **Depends on**: Slice 1
- **Lifecycle phases exercised**: Build
- **Exit signal**: Returns B.
- **Traces**: PRD §2
"""
        assert assert_dag_acyclic(snippet) is False

    def test_empty_slices_passes(self):
        assert assert_dag_acyclic("## 3. Thin Slices\n") is True

    def test_no_thin_slices_passes(self):
        assert assert_dag_acyclic("No slices here.") is True


# ---------------------------------------------------------------------------
# A9: assert_depends_on_resolve
# ---------------------------------------------------------------------------

class TestAssertDependsOnResolve:
    def test_good_roadmap_passes(self):
        assert assert_depends_on_resolve(GOOD_ROADMAP) is True

    def test_dangling_reference_fails(self):
        bad = GOOD_ROADMAP.replace(
            "- **Depends on**: Slice 2\n- **Lifecycle phases exercised**: Build, Prove\n- **Exit signal**: A user creates a project and it shows in the project list.",
            "- **Depends on**: Slice 99\n- **Lifecycle phases exercised**: Build, Prove\n- **Exit signal**: A user creates a project and it shows in the project list.",
        )
        assert assert_depends_on_resolve(bad) is False

    def test_none_dependency_passes(self):
        snippet = """\
## 3. Thin Slices

### Slice 1: A
- **Goal**: A works.
- **Delivers**:
  - Outcome one
  - Outcome two
  - Outcome three
- **Depends on**: None
- **Lifecycle phases exercised**: Build
- **Exit signal**: Shows A.
- **Traces**: PRD §1
"""
        assert assert_depends_on_resolve(snippet) is True


# ---------------------------------------------------------------------------
# A10: assert_traces_prd_section_format
# ---------------------------------------------------------------------------

class TestAssertTracesPrdSectionFormat:
    def test_good_roadmap_passes(self):
        assert assert_traces_prd_section_format(GOOD_ROADMAP) is True

    def test_traces_without_section_number_fails(self):
        bad = GOOD_ROADMAP.replace("- **Traces**: PRD §1, §2\n", "- **Traces**: PRD section 1\n")
        assert assert_traces_prd_section_format(bad) is False

    def test_traces_with_section_number_passes(self):
        snippet = """\
## 3. Thin Slices

### Slice 1: Test
- **Goal**: Something.
- **Delivers**:
  - Outcome one
  - Outcome two
  - Outcome three
- **Depends on**: None
- **Lifecycle phases exercised**: Build
- **Exit signal**: Returns result.
- **Traces**: PRD §3, §4
"""
        assert assert_traces_prd_section_format(snippet) is True

    def test_missing_traces_fails(self):
        snippet = """\
## 3. Thin Slices

### Slice 1: Test
- **Goal**: Something.
- **Delivers**:
  - Outcome one
  - Outcome two
  - Outcome three
- **Depends on**: None
- **Lifecycle phases exercised**: Build
- **Exit signal**: Displays result.
"""
        assert assert_traces_prd_section_format(snippet) is False


# ---------------------------------------------------------------------------
# A11: assert_maturity_checkpoints_rows
# ---------------------------------------------------------------------------

class TestAssertMaturityCheckpointsRows:
    def test_good_roadmap_passes(self):
        assert assert_maturity_checkpoints_rows(GOOD_ROADMAP) is True

    def test_only_two_data_rows_fails(self):
        bad = GOOD_ROADMAP.replace(
            """\
| Maturity Level | Achieved After | What's True |
|---|---|---|
| Rapid Prototype | Slice 1 | Application boots and displays a welcome screen to any user. |
| Basic Auth MVP | Slice 2 | Users can register, log in, and access protected content. |
| Core MVP | Slice 3 | Users can create and manage projects end-to-end. |
| Full MVP | Slice 5 | Users can track tasks and view progress reports. |""",
            """\
| Maturity Level | Achieved After | What's True |
|---|---|---|
| Rapid Prototype | Slice 1 | Application boots. |
| Full MVP | Slice 5 | Users can track tasks. |""",
        )
        assert assert_maturity_checkpoints_rows(bad) is False

    def test_no_maturity_section_fails(self):
        bad = GOOD_ROADMAP.replace("## 6. Maturity Checkpoints", "## 6. Something Else")
        assert assert_maturity_checkpoints_rows(bad) is False

    def test_exactly_3_rows_passes(self):
        snippet = """\
## 6. Maturity Checkpoints

| Maturity Level | Achieved After | What's True |
|---|---|---|
| Prototype | Slice 1 | App boots. |
| MVP | Slice 3 | Core workflow works. |
| Production | Beyond roadmap | Full feature set deployed. |
"""
        assert assert_maturity_checkpoints_rows(snippet) is True


# ---------------------------------------------------------------------------
# A12: assert_scope_exclusion_count
# ---------------------------------------------------------------------------

class TestAssertScopeExclusionCount:
    def test_good_roadmap_passes(self):
        assert assert_scope_exclusion_count(GOOD_ROADMAP) is True

    def test_only_two_bullets_fails(self):
        bad = GOOD_ROADMAP.replace(
            """\
- Real-time collaboration — the PRD envisions multi-user editing, but this adds significant complexity that is out of scope for the MVP.
- Mobile native apps — the PRD mentions iOS and Android clients, but we defer these until the web app is validated with users.
- Third-party integrations — Slack and GitHub integrations are in the PRD but out of scope until core workflow is proven.
- Advanced analytics — ML-powered insights are listed in the PRD vision but require a data corpus we do not yet have.""",
            """\
- Real-time collaboration — the PRD envisions multi-user editing, deferred for MVP.
- Mobile native apps — deferred until the web app is validated.""",
        )
        assert assert_scope_exclusion_count(bad) is False

    def test_no_section_fails(self):
        bad = GOOD_ROADMAP.replace("## 4. What We're Deliberately Not Building", "## 4. Exclusions")
        assert assert_scope_exclusion_count(bad) is False


# ---------------------------------------------------------------------------
# A13: assert_scope_exclusion_rationale
# ---------------------------------------------------------------------------

class TestAssertScopeExclusionRationale:
    def test_good_roadmap_passes(self):
        assert assert_scope_exclusion_rationale(GOOD_ROADMAP) is True

    def test_missing_em_dash_fails(self):
        bad = GOOD_ROADMAP.replace(
            "- Real-time collaboration — the PRD envisions multi-user editing, but this adds significant complexity that is out of scope for the MVP.",
            "- Real-time collaboration (out of scope for MVP)",
        )
        assert assert_scope_exclusion_rationale(bad) is False

    def test_with_en_dash_passes(self):
        # en-dash (–) should also work as a separator
        snippet = """\
## 4. What We're Deliberately Not Building

- Feature A – rationale for excluding this feature from the roadmap.
- Feature B – another rationale that explains the decision.
- Feature C – final rationale for exclusion.
"""
        assert assert_scope_exclusion_rationale(snippet) is True

    def test_no_section_fails(self):
        bad = GOOD_ROADMAP.replace("## 4. What We're Deliberately Not Building", "## 4. Exclusions")
        assert assert_scope_exclusion_rationale(bad) is False


# ---------------------------------------------------------------------------
# A14: assert_no_body_backtick_fences
# ---------------------------------------------------------------------------

class TestAssertNoBodyBacktickFences:
    def test_good_roadmap_passes(self):
        assert assert_no_body_backtick_fences(GOOD_ROADMAP) is True

    def test_backtick_fence_in_body_fails(self):
        bad = GOOD_ROADMAP.replace(
            "- **Goal**: A runnable shell exists that displays a welcome screen to the user.",
            "- **Goal**: See the example below:\n```python\nprint('hello')\n```",
        )
        assert assert_no_body_backtick_fences(bad) is False

    def test_backtick_fence_only_in_meta_prompt_passes(self):
        # Backtick fence ONLY in the meta-prompt block (after last ---) does not fail
        # Our GOOD_ROADMAP already has the Meta-Prompt after ---, and the roadmap-template
        # itself has ``` in the front matter description (before first H2).
        # Verify the good roadmap passes as-is.
        assert assert_no_body_backtick_fences(GOOD_ROADMAP) is True

    def test_inline_backtick_ok(self):
        # Single backtick (inline code) is fine — only triple-backtick fences fail
        good = GOOD_ROADMAP.replace(
            "- **Goal**: A runnable shell exists that displays a welcome screen to the user.",
            "- **Goal**: A runnable `shell` exists that displays a welcome screen.",
        )
        assert assert_no_body_backtick_fences(good) is True


# ---------------------------------------------------------------------------
# A15: assert_no_deep_headings_in_slices
# ---------------------------------------------------------------------------

class TestAssertNoDeepHeadingsInSlices:
    def test_good_roadmap_passes(self):
        assert assert_no_deep_headings_in_slices(GOOD_ROADMAP) is True

    def test_h4_in_slice_fails(self):
        bad = GOOD_ROADMAP.replace(
            "- **Goal**: A runnable shell exists that displays a welcome screen to the user.",
            "#### Sub-heading\n- **Goal**: A runnable shell exists.",
        )
        assert assert_no_deep_headings_in_slices(bad) is False

    def test_h3_is_acceptable(self):
        # H3 is used for slice headers themselves, so they are allowed
        assert assert_no_deep_headings_in_slices(GOOD_ROADMAP) is True

    def test_no_thin_slices_passes(self):
        assert assert_no_deep_headings_in_slices("No slices here.") is True


# ---------------------------------------------------------------------------
# A16: assert_sequencing_principles_count
# ---------------------------------------------------------------------------

class TestAssertSequencingPrinciplesCount:
    def test_good_roadmap_passes(self):
        assert assert_sequencing_principles_count(GOOD_ROADMAP) is True

    def test_too_few_principles_fails(self):
        bad = GOOD_ROADMAP.replace(
            """\
- Demo something visible in the first slice so the toolchain is proven end-to-end.
- Defer persistence until the core workflow is proven to reduce early rework.
- Build the contract (data model) before the surfaces that consume it.
- Keep slices independent so any single slice can be deferred without blocking others.
- Prefer user-visible outcomes over internal infrastructure.""",
            """\
- Demo something visible in the first slice.
- Defer persistence until proven.""",
        )
        assert assert_sequencing_principles_count(bad) is False

    def test_too_many_principles_fails(self):
        bad = GOOD_ROADMAP.replace(
            """\
- Demo something visible in the first slice so the toolchain is proven end-to-end.
- Defer persistence until the core workflow is proven to reduce early rework.
- Build the contract (data model) before the surfaces that consume it.
- Keep slices independent so any single slice can be deferred without blocking others.
- Prefer user-visible outcomes over internal infrastructure.""",
            """\
- Principle one.
- Principle two.
- Principle three.
- Principle four.
- Principle five.
- Principle six.
- Principle seven.""",
        )
        assert assert_sequencing_principles_count(bad) is False

    def test_exactly_4_passes(self):
        snippet = """\
## 2. Sequencing Principles

- Principle A.
- Principle B.
- Principle C.
- Principle D.
"""
        assert assert_sequencing_principles_count(snippet) is True

    def test_exactly_6_passes(self):
        snippet = """\
## 2. Sequencing Principles

- Principle A.
- Principle B.
- Principle C.
- Principle D.
- Principle E.
- Principle F.
"""
        assert assert_sequencing_principles_count(snippet) is True

    def test_no_section_fails(self):
        bad = GOOD_ROADMAP.replace("## 2. Sequencing Principles", "## 2. Ordering")
        assert assert_sequencing_principles_count(bad) is False


# ---------------------------------------------------------------------------
# A17: assert_meta_prompt_block
# ---------------------------------------------------------------------------

class TestAssertMetaPromptBlock:
    def test_good_roadmap_passes(self):
        assert assert_meta_prompt_block(GOOD_ROADMAP) is True

    def test_missing_meta_prompt_fails(self):
        # Remove the trailing --- block entirely
        bad = GOOD_ROADMAP.replace(
            "\n---\nFeature name: MyProduct\nProblem: Users need a way to manage projects and tasks.\nKey components: auth, project CRUD, task management, reporting\nKey code references: src/auth.py, src/projects.py, src/tasks.py\n---\n",
            "\n",
        )
        assert assert_meta_prompt_block(bad) is False

    def test_missing_field_fails(self):
        bad = GOOD_ROADMAP.replace("Feature name: MyProduct\n", "")
        assert assert_meta_prompt_block(bad) is False

    def test_missing_key_components_fails(self):
        bad = GOOD_ROADMAP.replace(
            "Key components: auth, project CRUD, task management, reporting\n",
            "",
        )
        assert assert_meta_prompt_block(bad) is False

    def test_only_one_separator_fails(self):
        # Only one --- marker means no enclosed block
        bad = "## 1. Starting State\n\nSome content.\n\n---\nFeature name: X\n"
        assert assert_meta_prompt_block(bad) is False


# ---------------------------------------------------------------------------
# Helpers for test fixtures
# ---------------------------------------------------------------------------

def _replace_section(roadmap: str, section_heading: str, new_section: str) -> str:
    """
    Replace from section_heading to the next '---' separator with new_section.
    Used to swap out entire sections in the good roadmap for testing.
    """
    lines = roadmap.splitlines(keepends=True)
    start_idx = None
    end_idx = None
    for i, line in enumerate(lines):
        if line.strip() == section_heading.strip():
            start_idx = i
        if start_idx is not None and i > start_idx and line.strip() == "---":
            end_idx = i
            break
    if start_idx is None:
        return roadmap
    before = "".join(lines[:start_idx])
    after = "".join(lines[end_idx:]) if end_idx else ""
    return before + new_section + after
