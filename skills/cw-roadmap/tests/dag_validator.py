"""
dag_validator.py — Reference implementation of the dependency-graph (DAG)
validator described in SKILL.md Step 5 (DAG validation paragraph).

This module is the algorithmic specification for the LLM instructions in
SKILL.md. It is used by unit tests and as documentation; the skill itself
executes the equivalent logic without shelling out.

Public API
----------
parse_slices(roadmap_md: str) -> list[dict]
    Parse a roadmap Markdown text and extract slice records.
    Returns a list of dicts, each with keys:
        id          — int slice number
        name        — str slice display name
        depends_on  — list[int] dependency slice numbers (empty if None)
    Raises SliceParseError if a 'Depends on:' value cannot be interpreted.

validate_dag(slices: list[dict]) -> None
    Build the dependency graph from the slice list and reject any input
    containing a cycle or a reference to a non-existent slice.
    Raises CycleError if a cycle is detected (including self-cycles).
    Raises DanglingDependencyError if a slice references a non-existent
    slice.
    Returns None on success (graph is a valid DAG).
"""

from __future__ import annotations

import re
from typing import Optional


# ---------------------------------------------------------------------------
# Exceptions
# ---------------------------------------------------------------------------

class DAGValidationError(Exception):
    """Base class for DAG validation errors."""


class CycleError(DAGValidationError):
    """
    Raised when a cycle is detected in the dependency graph.

    Attributes
    ----------
    cycle_path : list[int]
        The slice IDs forming the cycle, ordered from the first node
        back to itself, e.g. [1, 3, 5, 1].
    """

    def __init__(self, cycle_path: list[int]) -> None:
        self.cycle_path = cycle_path
        path_str = " → ".join(f"Slice {sid}" for sid in cycle_path)
        super().__init__(f"Cycle detected: {path_str}")


class DanglingDependencyError(DAGValidationError):
    """
    Raised when a slice references a non-existent slice in 'Depends on:'.

    Attributes
    ----------
    referrer : int
        The slice ID that has the bad dependency.
    missing  : int
        The slice ID that was referenced but does not exist.
    defined  : list[int]
        The slice IDs that are actually defined (sorted).
    """

    def __init__(self, referrer: int, missing: int, defined: list[int]) -> None:
        self.referrer = referrer
        self.missing = missing
        self.defined = sorted(defined)
        ids_str = ", ".join(str(s) for s in self.defined)
        super().__init__(
            f"Slice {referrer} depends on Slice {missing}, which does not exist "
            f"(slices defined: {ids_str})"
        )


class SliceParseError(Exception):
    """Raised when a 'Depends on:' field value cannot be interpreted."""


# ---------------------------------------------------------------------------
# Slice record helpers
# ---------------------------------------------------------------------------

# Matches "### Slice N: Name" where N is one or more digits.
_SLICE_HEADER_RE = re.compile(r"^###\s+Slice\s+(\d+):\s*(.+)", re.IGNORECASE)

# Matches "- **Depends on**: <value>" or "- **Depends on:** <value>"
_DEPENDS_ON_RE = re.compile(
    r"^\s*-\s+\*\*Depends\s+on\*\*:?\s*(.+)", re.IGNORECASE
)

# Matches a slice reference like "Slice 3" or just "3" inside a depends list
_SLICE_REF_RE = re.compile(r"\bslice\s*(\d+)\b", re.IGNORECASE)
_BARE_NUMBER_RE = re.compile(r"\b(\d+)\b")


def _parse_depends_on_value(raw: str) -> list[int]:
    """
    Parse the raw text after 'Depends on:'.

    Accepts:
    - "None"  — no dependencies
    - "Slice 1", "Slice 1, Slice 3", "1", "1, 3"
    - Mixed: "Slice 1, 3, Slice 5"

    Returns a (possibly empty) list of integer slice IDs.
    Raises SliceParseError if the value is non-empty and non-'None' but
    contains no parseable numbers.
    """
    stripped = raw.strip().rstrip(".")

    # Explicit "None"
    if stripped.lower() in ("none", "n/a", "-"):
        return []

    # Extract all slice IDs from named references first
    ids = [int(m.group(1)) for m in _SLICE_REF_RE.finditer(stripped)]

    if not ids:
        # Fall back to bare numbers (e.g. "1, 3")
        ids = [int(m.group(1)) for m in _BARE_NUMBER_RE.finditer(stripped)]

    if not ids:
        raise SliceParseError(
            f"Cannot parse 'Depends on' value: {raw!r}"
        )

    return ids


def parse_slices(roadmap_md: str) -> list[dict]:
    """
    Parse roadmap Markdown text and extract slice dependency records.

    Only parses '### Slice N: Name' blocks and their 'Depends on:' lines.
    Other roadmap content is ignored.

    Parameters
    ----------
    roadmap_md:
        Full Markdown content of the roadmap file.

    Returns
    -------
    list of dicts, each with:
        id          — int slice number
        name        — str slice display name
        depends_on  — list[int] dependency slice numbers (empty if None)

    Raises
    ------
    SliceParseError if a 'Depends on:' value cannot be parsed.
    """
    slices: list[dict] = []
    current: Optional[dict] = None

    for line in roadmap_md.splitlines():
        header_match = _SLICE_HEADER_RE.match(line)
        if header_match:
            # Save previous slice if any
            if current is not None:
                slices.append(current)
            current = {
                "id": int(header_match.group(1)),
                "name": header_match.group(2).strip(),
                "depends_on": [],
            }
            continue

        if current is not None:
            dep_match = _DEPENDS_ON_RE.match(line)
            if dep_match:
                raw_value = dep_match.group(1)
                current["depends_on"] = _parse_depends_on_value(raw_value)

    if current is not None:
        slices.append(current)

    return slices


# ---------------------------------------------------------------------------
# DAG validation — DFS with recursion stack
# ---------------------------------------------------------------------------

def validate_dag(slices: list[dict]) -> None:
    """
    Validate that the slice dependency graph is a directed acyclic graph (DAG).

    Algorithm:
    1. Build adjacency map {slice_id: [dependency_slice_id, ...]}.
    2. For every Depends on: reference, check it names an existing slice ID.
       Raise DanglingDependencyError on the first bad reference.
    3. Run DFS over all nodes, maintaining a recursion stack (path from root
       to the current node). On a back-edge (target already in recursion
       stack), recover the cycle path from the stack and raise CycleError.

    Parameters
    ----------
    slices:
        List of dicts as returned by parse_slices().

    Returns
    -------
    None — the graph is a valid DAG.

    Raises
    ------
    DanglingDependencyError if any 'Depends on:' references a non-existent
    slice ID.
    CycleError if a cycle exists, with the full cycle path in the exception.
    """
    if not slices:
        return

    defined_ids: set[int] = {s["id"] for s in slices}

    # Step 1: check dangling references
    for s in slices:
        for dep_id in s["depends_on"]:
            if dep_id not in defined_ids:
                raise DanglingDependencyError(
                    referrer=s["id"],
                    missing=dep_id,
                    defined=list(defined_ids),
                )

    # Build adjacency map: edges go FROM a slice TO its dependencies
    # (i.e. "A depends on B" → edge A → B)
    adj: dict[int, list[int]] = {s["id"]: list(s["depends_on"]) for s in slices}

    # Step 2: DFS cycle detection
    # States: WHITE = unvisited, GRAY = on current path, BLACK = fully done
    WHITE, GRAY, BLACK = 0, 1, 2
    color: dict[int, int] = {sid: WHITE for sid in defined_ids}
    # Stack tracks the current DFS path for cycle recovery
    path: list[int] = []

    def _dfs(node: int) -> None:
        color[node] = GRAY
        path.append(node)

        for neighbor in adj[node]:
            if color[neighbor] == GRAY:
                # Back-edge: recover cycle path
                cycle_start = path.index(neighbor)
                cycle = path[cycle_start:] + [neighbor]
                raise CycleError(cycle)
            if color[neighbor] == WHITE:
                _dfs(neighbor)

        path.pop()
        color[node] = BLACK

    for sid in defined_ids:
        if color[sid] == WHITE:
            _dfs(sid)
