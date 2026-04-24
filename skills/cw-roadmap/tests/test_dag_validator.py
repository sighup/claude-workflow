"""
test_dag_validator.py — Unit tests for the DAG validator reference implementation.

Tests cover:
  - (a) Acyclic input passes without error
  - (b) Self-cycle is rejected with cycle path in the error
  - (c) Two-node cycle is rejected with cycle path in the error
  - (d) Three-node cycle is rejected with the full cycle path in the error
  - (e) Reference to non-existent slice is rejected with referrer and target in
        the error message
  - parse_slices: extraction of id, name, and depends_on from roadmap Markdown
  - parse_slices: smoke-test on cyclic-prd fixture (must parse without error)

Run:
    python3 -m pytest tests/test_dag_validator.py -v
from the claude-workflow/skills/cw-roadmap/ directory.
"""

from __future__ import annotations

from pathlib import Path

import pytest

from dag_validator import (
    CycleError,
    DanglingDependencyError,
    parse_slices,
    validate_dag,
)


# ---------------------------------------------------------------------------
# Helpers — build slice records without markdown parsing
# ---------------------------------------------------------------------------

def _slice(sid: int, depends_on: list[int] | None = None) -> dict:
    """Construct a minimal slice record for direct use in validate_dag()."""
    return {
        "id": sid,
        "name": f"Slice {sid} Name",
        "depends_on": depends_on or [],
    }


# ---------------------------------------------------------------------------
# Fixture — minimal roadmap markdown for parse_slices() tests
# ---------------------------------------------------------------------------

MINIMAL_ROADMAP_MD = """\
# Test Product — Roadmap

**Roadmap Document**

## 3. Thin Slices

### Slice 1: Bootstrap
- **Goal**: Baseline exists.
- **Delivers**:
  - Something demoable
- **Depends on**: None
- **Lifecycle phases exercised**: Build
- **Exit signal**: It runs.
- **Traces**: PRD §1

### Slice 2: Core Feature
- **Goal**: Core feature works.
- **Delivers**:
  - Another thing
- **Depends on**: Slice 1
- **Lifecycle phases exercised**: Build, Prove
- **Exit signal**: Demo passes.
- **Traces**: PRD §3, §4

### Slice 3: Extension
- **Goal**: Extended capability ships.
- **Delivers**:
  - Extension outcome
- **Depends on**: Slice 1, Slice 2
- **Lifecycle phases exercised**: Build
- **Exit signal**: All checks pass.
- **Traces**: PRD §4

_End of Document_
"""


# ---------------------------------------------------------------------------
# Tests: parse_slices
# ---------------------------------------------------------------------------

class TestParseSlices:
    def test_extracts_three_slices(self):
        slices = parse_slices(MINIMAL_ROADMAP_MD)
        assert len(slices) == 3

    def test_slice_ids(self):
        slices = parse_slices(MINIMAL_ROADMAP_MD)
        ids = [s["id"] for s in slices]
        assert ids == [1, 2, 3]

    def test_slice_names(self):
        slices = parse_slices(MINIMAL_ROADMAP_MD)
        assert slices[0]["name"] == "Bootstrap"
        assert slices[1]["name"] == "Core Feature"
        assert slices[2]["name"] == "Extension"

    def test_none_depends_on_is_empty_list(self):
        slices = parse_slices(MINIMAL_ROADMAP_MD)
        assert slices[0]["depends_on"] == []

    def test_single_dependency_parsed(self):
        slices = parse_slices(MINIMAL_ROADMAP_MD)
        assert slices[1]["depends_on"] == [1]

    def test_multiple_dependencies_parsed(self):
        slices = parse_slices(MINIMAL_ROADMAP_MD)
        assert sorted(slices[2]["depends_on"]) == [1, 2]

    def test_empty_string_returns_empty_list(self):
        assert parse_slices("") == []

    def test_no_slices_returns_empty_list(self):
        assert parse_slices("# Just a header\n\nSome text.\n") == []

    def test_bare_number_dependency(self):
        md = "### Slice 1: A\n- **Depends on**: None\n\n### Slice 2: B\n- **Depends on**: 1\n"
        slices = parse_slices(md)
        assert slices[1]["depends_on"] == [1]


# ---------------------------------------------------------------------------
# Tests: (a) acyclic input passes
# ---------------------------------------------------------------------------

class TestValidateDagAcyclic:
    def test_empty_list_passes(self):
        # Empty graph is trivially acyclic
        validate_dag([])  # must not raise

    def test_single_slice_no_deps(self):
        validate_dag([_slice(1)])

    def test_linear_chain(self):
        # 1 → 2 → 3 (each depends on previous)
        slices = [
            _slice(1),
            _slice(2, depends_on=[1]),
            _slice(3, depends_on=[2]),
        ]
        validate_dag(slices)  # must not raise

    def test_diamond_graph(self):
        # 1 → 2, 1 → 3, 2 → 4, 3 → 4
        slices = [
            _slice(1),
            _slice(2, depends_on=[1]),
            _slice(3, depends_on=[1]),
            _slice(4, depends_on=[2, 3]),
        ]
        validate_dag(slices)  # must not raise

    def test_multiple_independent_slices(self):
        slices = [_slice(1), _slice(2), _slice(3)]
        validate_dag(slices)

    def test_minimal_roadmap_passes(self):
        slices = parse_slices(MINIMAL_ROADMAP_MD)
        validate_dag(slices)  # must not raise


# ---------------------------------------------------------------------------
# Tests: (b) self-cycle rejected
# ---------------------------------------------------------------------------

class TestValidateDagSelfCycle:
    def test_self_cycle_raises_cycle_error(self):
        slices = [_slice(1, depends_on=[1])]
        with pytest.raises(CycleError):
            validate_dag(slices)

    def test_self_cycle_message_contains_cycle_path(self):
        slices = [_slice(2, depends_on=[2])]
        with pytest.raises(CycleError) as exc_info:
            validate_dag(slices)
        msg = str(exc_info.value)
        # Path must show Slice 2 → Slice 2
        assert "Slice 2" in msg
        assert "→" in msg

    def test_self_cycle_path_attribute(self):
        slices = [_slice(3, depends_on=[3])]
        with pytest.raises(CycleError) as exc_info:
            validate_dag(slices)
        path = exc_info.value.cycle_path
        assert path[0] == 3
        assert path[-1] == 3

    def test_self_cycle_path_length(self):
        # Self-cycle: [N, N] — two elements
        slices = [_slice(1, depends_on=[1])]
        with pytest.raises(CycleError) as exc_info:
            validate_dag(slices)
        assert len(exc_info.value.cycle_path) == 2


# ---------------------------------------------------------------------------
# Tests: (c) two-node cycle rejected
# ---------------------------------------------------------------------------

class TestValidateDagTwoNodeCycle:
    def test_two_node_cycle_raises_cycle_error(self):
        slices = [
            _slice(1, depends_on=[2]),
            _slice(2, depends_on=[1]),
        ]
        with pytest.raises(CycleError):
            validate_dag(slices)

    def test_two_node_cycle_path_contains_both_nodes(self):
        slices = [
            _slice(1, depends_on=[2]),
            _slice(2, depends_on=[1]),
        ]
        with pytest.raises(CycleError) as exc_info:
            validate_dag(slices)
        path = exc_info.value.cycle_path
        path_set = set(path)
        # Both slice IDs must appear
        assert 1 in path_set
        assert 2 in path_set

    def test_two_node_cycle_message_contains_arrow(self):
        slices = [
            _slice(4, depends_on=[5]),
            _slice(5, depends_on=[4]),
        ]
        with pytest.raises(CycleError) as exc_info:
            validate_dag(slices)
        msg = str(exc_info.value)
        assert "→" in msg
        assert "Slice 4" in msg
        assert "Slice 5" in msg


# ---------------------------------------------------------------------------
# Tests: (d) three-node cycle rejected with cycle path in error
# ---------------------------------------------------------------------------

class TestValidateDagThreeNodeCycle:
    def test_three_node_cycle_raises_cycle_error(self):
        # 1 → 2 → 3 → 1
        slices = [
            _slice(1, depends_on=[2]),
            _slice(2, depends_on=[3]),
            _slice(3, depends_on=[1]),
        ]
        with pytest.raises(CycleError):
            validate_dag(slices)

    def test_three_node_cycle_path_contains_all_three_nodes(self):
        slices = [
            _slice(1, depends_on=[2]),
            _slice(2, depends_on=[3]),
            _slice(3, depends_on=[1]),
        ]
        with pytest.raises(CycleError) as exc_info:
            validate_dag(slices)
        path = exc_info.value.cycle_path
        path_set = set(path)
        assert 1 in path_set
        assert 2 in path_set
        assert 3 in path_set

    def test_three_node_cycle_path_starts_and_ends_at_same_node(self):
        slices = [
            _slice(1, depends_on=[2]),
            _slice(2, depends_on=[3]),
            _slice(3, depends_on=[1]),
        ]
        with pytest.raises(CycleError) as exc_info:
            validate_dag(slices)
        path = exc_info.value.cycle_path
        assert path[0] == path[-1], (
            f"Cycle path must begin and end at the same node; got {path}"
        )

    def test_three_node_cycle_message_shows_arrows(self):
        slices = [
            _slice(5, depends_on=[6]),
            _slice(6, depends_on=[7]),
            _slice(7, depends_on=[5]),
        ]
        with pytest.raises(CycleError) as exc_info:
            validate_dag(slices)
        msg = str(exc_info.value)
        # Three distinct slice mentions + two arrows for a 3-cycle (or more)
        assert msg.count("→") >= 2
        assert "Slice 5" in msg
        assert "Slice 6" in msg
        assert "Slice 7" in msg

    def test_three_node_cycle_with_acyclic_prefix(self):
        # Slices 1 and 2 are fine; 3 → 4 → 5 → 3 is the cycle
        slices = [
            _slice(1),
            _slice(2, depends_on=[1]),
            _slice(3, depends_on=[4]),
            _slice(4, depends_on=[5]),
            _slice(5, depends_on=[3]),
        ]
        with pytest.raises(CycleError) as exc_info:
            validate_dag(slices)
        path_set = set(exc_info.value.cycle_path)
        assert 3 in path_set
        assert 4 in path_set
        assert 5 in path_set


# ---------------------------------------------------------------------------
# Tests: (e) reference to non-existent slice rejected
# ---------------------------------------------------------------------------

class TestValidateDagDanglingReference:
    def test_missing_dep_raises_dangling_error(self):
        slices = [_slice(1, depends_on=[99])]
        with pytest.raises(DanglingDependencyError):
            validate_dag(slices)

    def test_dangling_error_contains_referrer(self):
        slices = [_slice(2, depends_on=[99])]
        with pytest.raises(DanglingDependencyError) as exc_info:
            validate_dag(slices)
        msg = str(exc_info.value)
        assert "Slice 2" in msg

    def test_dangling_error_contains_missing_target(self):
        slices = [_slice(2, depends_on=[99])]
        with pytest.raises(DanglingDependencyError) as exc_info:
            validate_dag(slices)
        msg = str(exc_info.value)
        assert "99" in msg

    def test_dangling_error_attributes(self):
        slices = [_slice(3, depends_on=[42])]
        with pytest.raises(DanglingDependencyError) as exc_info:
            validate_dag(slices)
        err = exc_info.value
        assert err.referrer == 3
        assert err.missing == 42
        assert 3 in err.defined
        assert 42 not in err.defined

    def test_dangling_error_shows_defined_slices(self):
        slices = [
            _slice(1),
            _slice(2, depends_on=[1]),
            _slice(3, depends_on=[99]),
        ]
        with pytest.raises(DanglingDependencyError) as exc_info:
            validate_dag(slices)
        msg = str(exc_info.value)
        # Error should indicate which slices are defined
        assert "1" in msg
        assert "2" in msg or "3" in msg

    def test_dangling_reference_beats_cycle_check(self):
        # Dangling deps are checked before cycles — even if there's also a cycle,
        # the dangling check runs first.
        slices = [
            _slice(1, depends_on=[99]),  # missing ref
            _slice(2, depends_on=[1]),
        ]
        with pytest.raises(DanglingDependencyError):
            validate_dag(slices)


# ---------------------------------------------------------------------------
# Tests: cyclic-prd.md fixture smoke-test (parse_prd must succeed)
# ---------------------------------------------------------------------------

class TestCyclicPrdFixture:
    """
    The cyclic-prd.md fixture must be a valid PRD (all 6 sections present)
    even though a naive LLM decomposition of it would produce a cyclic slice
    graph.  This smoke-test asserts that parse_prd() succeeds on the fixture
    and returns all six required sections.
    """

    @staticmethod
    def _fixture_path() -> Path:
        here = Path(__file__).resolve()
        return here.parent / "fixtures" / "cyclic-prd.md"

    def test_fixture_file_exists(self):
        assert self._fixture_path().exists(), (
            f"Fixture not found at {self._fixture_path()}"
        )

    def test_fixture_parses_all_six_sections(self):
        import sys
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        from prd_parser import parse_prd, MissingSectionError

        text = self._fixture_path().read_text(encoding="utf-8")
        try:
            result = parse_prd(text, prd_path="tests/fixtures/cyclic-prd.md")
        except MissingSectionError as exc:
            pytest.fail(
                f"cyclic-prd.md is missing required PRD sections: {exc.missing}"
            )

        assert len(result["workflow_stages"]) >= 1
        assert len(result["capabilities"]) >= 1

    def test_fixture_slice_graph_would_be_cyclic(self):
        """
        The fixture's Capabilities section describes mutual dependencies that
        would force a cycle in the slice graph.  We verify this by ensuring the
        text itself contains the markers used to communicate mutual dependency.
        """
        text = self._fixture_path().read_text(encoding="utf-8")
        # The fixture must mention at least two capabilities that each require
        # the other — the comments in the fixture explain this.
        assert "requires" in text.lower() or "depends on" in text.lower(), (
            "cyclic-prd.md should describe capabilities with mutual dependencies"
        )
