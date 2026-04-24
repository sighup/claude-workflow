"""
assertions.py — Binary assertion library for cw-roadmap lint validation.

Each function has signature (response: str) -> bool and returns True when the
roadmap markdown string satisfies that check. The one-line docstring on each
function is the failure message shown in the lint table.

Exported via the module-level ASSERTIONS list.

Import via importlib.util (no package init required):
    import importlib.util
    spec = importlib.util.spec_from_file_location("assertions", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    ASSERTIONS = mod.ASSERTIONS

No eval, no shell-out, no file writes inside assertion functions.
"""

from __future__ import annotations

import re
from typing import Optional

# ---------------------------------------------------------------------------
# Canonical constants
# ---------------------------------------------------------------------------

_CANONICAL_SECTIONS = [
    "Starting State",
    "Sequencing Principles",
    "Thin Slices",
    "What We're Deliberately Not Building",
    "Risk & Open Questions",
    "Maturity Checkpoints",
]

# Field name as it appears between ** markers in the slice template.
# "Lifecycle phases exercised" matches the roadmap template exactly.
_REQUIRED_SLICE_FIELDS = [
    "Goal",
    "Delivers",
    "Depends on",
    "Lifecycle phases exercised",
    "Exit signal",
]

_EXIT_SIGNAL_VERBS = [
    "shows",
    "returns",
    "produces",
    "displays",
    "outputs",
    "logs",
    "renders",
    "passes",
    "emits",
    "prints",
    "writes",
    "generates",
    "exports",
    "reports",
]

_META_PROMPT_FIELDS = [
    "Feature name:",
    "Problem:",
    "Key components:",
    "Key code references:",
]

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

_SLICE_HEADER_RE = re.compile(r"^###\s+Slice\s+(\d+):", re.IGNORECASE | re.MULTILINE)
_H2_RE = re.compile(r"^##\s+(?:\d+\.\s+)?(.+)", re.MULTILINE)
_NUMERIC_PREFIX_RE = re.compile(r"^\d+(\.\d+)*\.?\s*")
# Matches "- **Depends on**: ..." or "- **Depends on:** ..."
_DEPENDS_ON_RE = re.compile(r"^\s*-\s+\*\*Depends\s+on\*\*:?\s*(.+)", re.IGNORECASE | re.MULTILINE)
_SLICE_REF_RE = re.compile(r"\bslice\s*(\d+)\b", re.IGNORECASE)
_BARE_NUMBER_RE = re.compile(r"\b(\d+)\b")


def _normalize_heading(raw: str) -> str:
    """Strip leading numeric prefix from a heading."""
    return _NUMERIC_PREFIX_RE.sub("", raw.strip()).strip()


def _extract_h2_headings(response: str) -> list[str]:
    """Return normalized H2 heading names, in order."""
    return [_normalize_heading(m.group(1)) for m in _H2_RE.finditer(response)]


def _get_section_body(response: str, section_name: str) -> Optional[str]:
    """
    Return the body text of the H2 section matching section_name (normalized),
    from after its heading to just before the next H2 or end-of-string.
    """
    lines = response.splitlines(keepends=True)
    in_section = False
    body_lines: list[str] = []
    for line in lines:
        if line.startswith("## "):
            heading = _normalize_heading(line[3:].strip())
            if heading == section_name:
                in_section = True
                body_lines = []
                continue
            elif in_section:
                break
        elif in_section:
            body_lines.append(line)
    if not in_section:
        return None
    return "".join(body_lines)


def _extract_slice_blocks(thin_slices_body: str) -> list[str]:
    """
    Given the body of '## 3. Thin Slices', return a list of strings,
    each being the content of one ### Slice N: block (up to the next
    ### Slice or end of body).
    """
    blocks: list[str] = []
    current: list[str] = []
    in_slice = False
    for line in thin_slices_body.splitlines(keepends=True):
        if re.match(r"^###\s+Slice\s+\d+:", line, re.IGNORECASE):
            if in_slice and current:
                blocks.append("".join(current))
            current = [line]
            in_slice = True
        elif in_slice:
            current.append(line)
    if in_slice and current:
        blocks.append("".join(current))
    return blocks


def _parse_depends_on(raw: str) -> list[int]:
    """Parse the text after 'Depends on:' into a list of slice IDs."""
    stripped = raw.strip().rstrip(".")
    if stripped.lower() in ("none", "n/a", "-"):
        return []
    ids = [int(m.group(1)) for m in _SLICE_REF_RE.finditer(stripped)]
    if not ids:
        ids = [int(m.group(1)) for m in _BARE_NUMBER_RE.finditer(stripped)]
    return ids


def _get_meta_prompt_region(response: str) -> Optional[str]:
    """
    Extract the text between the last two '---' separators at the end of file.
    Returns None if the file does not end with two '---' markers.
    """
    lines = response.splitlines()
    separator_indices = [i for i, ln in enumerate(lines) if ln.strip() == "---"]
    if len(separator_indices) < 2:
        return None
    start_idx = separator_indices[-2]
    end_idx = separator_indices[-1]
    region_lines = lines[start_idx + 1:end_idx]
    return "\n".join(region_lines)


def _get_body_region(response: str) -> str:
    """
    Return the 'body' region: from the first H2 to the Meta-Prompt opening '---'.
    Checks for fences/heading depth violations only in this region.
    """
    lines = response.splitlines()
    body_start = None
    for i, ln in enumerate(lines):
        if ln.startswith("## "):
            body_start = i
            break
    if body_start is None:
        return response

    separator_indices = [i for i, ln in enumerate(lines) if ln.strip() == "---"]
    if len(separator_indices) >= 2:
        body_end = separator_indices[-2]
    else:
        body_end = len(lines)

    return "\n".join(lines[body_start:body_end])


def _check_dag_acyclic(slices: list[dict]) -> bool:
    """
    Return True if the slice dependency graph is acyclic.
    Uses recursive DFS with visited/in-stack color tracking.
    Neighbors that are not in the defined set are skipped (dangling refs
    are handled separately by assert_depends_on_resolve).
    """
    if not slices:
        return True
    defined_ids: set[int] = {s["id"] for s in slices}
    # Build adjacency map; filter out any dangling refs (not our job here)
    adj: dict[int, list[int]] = {
        s["id"]: [d for d in s["depends_on"] if d in defined_ids]
        for s in slices
    }
    # WHITE=0 unvisited, GRAY=1 on current path, BLACK=2 fully processed
    WHITE, GRAY, BLACK = 0, 1, 2
    color: dict[int, int] = {sid: WHITE for sid in defined_ids}

    def _dfs(node: int) -> bool:
        """Return True if no cycle found from node."""
        color[node] = GRAY
        for neighbor in adj.get(node, []):
            if color[neighbor] == GRAY:
                return False  # back edge = cycle
            if color[neighbor] == WHITE:
                if not _dfs(neighbor):
                    return False
        color[node] = BLACK
        return True

    for sid in list(defined_ids):
        if color[sid] == WHITE:
            if not _dfs(sid):
                return False
    return True


def _build_slices_from_roadmap(response: str) -> list[dict]:
    """Parse Thin Slices section into a list of {id, depends_on} dicts."""
    body = _get_section_body(response, "Thin Slices")
    if body is None:
        return []
    blocks = _extract_slice_blocks(body)
    slices: list[dict] = []
    for block in blocks:
        header_m = re.match(r"###\s+Slice\s+(\d+):", block.strip(), re.IGNORECASE)
        if not header_m:
            continue
        sid = int(header_m.group(1))
        dep_match = _DEPENDS_ON_RE.search(block)
        deps: list[int] = []
        if dep_match:
            deps = _parse_depends_on(dep_match.group(1))
        slices.append({"id": sid, "depends_on": deps})
    return slices


# ---------------------------------------------------------------------------
# Assertion functions — R3.1 checks
# ---------------------------------------------------------------------------

def assert_section_order(response: str) -> bool:
    """Roadmap has six H2 sections in canonical order: Starting State, Sequencing Principles, Thin Slices, What We're Deliberately Not Building, Risk & Open Questions, Maturity Checkpoints."""
    headings = _extract_h2_headings(response)
    canonical_positions = []
    for section in _CANONICAL_SECTIONS:
        try:
            pos = headings.index(section)
            canonical_positions.append(pos)
        except ValueError:
            return False
    return canonical_positions == sorted(canonical_positions)


def assert_line_count(response: str) -> bool:
    """Roadmap body line count is between 150 and 250 inclusive."""
    count = len(response.splitlines())
    return 150 <= count <= 250


def assert_slice_cardinality(response: str) -> bool:
    """Section 3 (Thin Slices) contains between 5 and 8 slices inclusive."""
    body = _get_section_body(response, "Thin Slices")
    if body is None:
        return False
    count = len(_SLICE_HEADER_RE.findall(body))
    return 5 <= count <= 8


def assert_slice_required_fields(response: str) -> bool:
    """Each slice declares all five required fields: Goal, Delivers, Depends on, Lifecycle phases exercised, Exit signal."""
    body = _get_section_body(response, "Thin Slices")
    if body is None:
        return False
    blocks = _extract_slice_blocks(body)
    if not blocks:
        return False
    for block in blocks:
        for field in _REQUIRED_SLICE_FIELDS:
            # Match "- **<field>**: ..." — field name may be followed immediately by **
            # e.g. "- **Goal**: text" or "- **Lifecycle phases exercised**: ..."
            pattern = re.compile(
                r"^\s*-\s+\*\*" + re.escape(field) + r"\*\*:?",
                re.IGNORECASE | re.MULTILINE,
            )
            if not pattern.search(block):
                return False
    return True


def assert_slice_traces_line(response: str) -> bool:
    """Each slice has a Traces: line citing the PRD sections it implements."""
    body = _get_section_body(response, "Thin Slices")
    if body is None:
        return False
    blocks = _extract_slice_blocks(body)
    if not blocks:
        return False
    # Match "Traces" followed by optional bold/colon formatting
    _traces_re = re.compile(r"\bTraces\b", re.IGNORECASE)
    for block in blocks:
        if not _traces_re.search(block):
            return False
    return True


def assert_exit_signal_verb(response: str) -> bool:
    """Each slice Exit signal contains a concrete observable verb (shows, returns, produces, displays, outputs, logs, renders, passes, etc.)."""
    body = _get_section_body(response, "Thin Slices")
    if body is None:
        return False
    blocks = _extract_slice_blocks(body)
    if not blocks:
        return False
    # Match "Exit signal" with optional markdown bold markers
    exit_re = re.compile(
        r"^\s*-\s+\*\*Exit\s+signal\*\*:?\s*(.+)",
        re.IGNORECASE | re.MULTILINE,
    )
    verb_pattern = re.compile(
        r"\b(" + "|".join(re.escape(v) for v in _EXIT_SIGNAL_VERBS) + r")\b",
        re.IGNORECASE,
    )
    for block in blocks:
        m = exit_re.search(block)
        if not m:
            return False
        exit_text = m.group(1).strip()
        if not verb_pattern.search(exit_text):
            return False
    return True


def assert_delivers_bullet_count(response: str) -> bool:
    """Each slice Delivers section has between 3 and 6 bullets inclusive."""
    body = _get_section_body(response, "Thin Slices")
    if body is None:
        return False
    blocks = _extract_slice_blocks(body)
    if not blocks:
        return False
    delivers_header_re = re.compile(
        r"^\s*-\s+\*\*Delivers\*\*:?",
        re.IGNORECASE | re.MULTILINE,
    )
    # Any of the other field names at the same indent level signals end of Delivers
    next_field_re = re.compile(
        r"^\s*-\s+\*\*(?:Depends\s+on|Lifecycle\s+phases|Exit\s+signal|Goal|Traces)\*\*",
        re.IGNORECASE,
    )
    for block in blocks:
        lines = block.splitlines()
        delivers_start = None
        for i, ln in enumerate(lines):
            if delivers_header_re.match(ln):
                delivers_start = i
                break
        if delivers_start is None:
            return False
        bullet_count = 0
        for ln in lines[delivers_start + 1:]:
            if next_field_re.match(ln):
                break
            # Sub-bullets are indented (2+ spaces or a tab) and start with - or *
            if re.match(r"^[ \t]{1,}-\s+\S", ln) or re.match(r"^[ \t]{2,}\*\s+\S", ln):
                bullet_count += 1
        if not (3 <= bullet_count <= 6):
            return False
    return True


def assert_dag_acyclic(response: str) -> bool:
    """The slice dependency graph is acyclic (no circular dependencies between slices)."""
    slices = _build_slices_from_roadmap(response)
    if not slices:
        return True
    return _check_dag_acyclic(slices)


def assert_depends_on_resolve(response: str) -> bool:
    """All Depends on slice references resolve to slices defined in this roadmap (no dangling references)."""
    slices = _build_slices_from_roadmap(response)
    if not slices:
        return True
    defined_ids = {s["id"] for s in slices}
    for s in slices:
        for dep in s["depends_on"]:
            if dep not in defined_ids:
                return False
    return True


def assert_traces_prd_section_format(response: str) -> bool:
    """Each slice Traces line references at least one PRD section in the format 'PRD §<digit>'."""
    body = _get_section_body(response, "Thin Slices")
    if body is None:
        return False
    blocks = _extract_slice_blocks(body)
    if not blocks:
        return False
    # Match any line containing "Traces" (accounting for **Traces** bold) then PRD §N
    # The § char is U+00A7; use a simple string search for robustness
    for block in blocks:
        found = False
        for line in block.splitlines():
            if "Traces" in line and "PRD" in line and "§" in line:
                # Verify at least one §<digit>
                if re.search(r"§\d+", line):
                    found = True
                    break
        if not found:
            return False
    return True


def assert_maturity_checkpoints_rows(response: str) -> bool:
    """Maturity Checkpoints table has at least 3 data rows."""
    body = _get_section_body(response, "Maturity Checkpoints")
    if body is None:
        return False
    data_rows = 0
    header_seen = False
    for line in body.splitlines():
        stripped = line.strip()
        if not (stripped.startswith("|") and stripped.endswith("|")):
            continue
        # Separator row: all non-empty cells are only dashes
        inner = stripped.strip("|")
        cells = [c.strip() for c in inner.split("|")]
        if all(re.match(r"^-+$", c) for c in cells if c):
            continue
        if not header_seen:
            header_seen = True
            continue
        data_rows += 1
    return data_rows >= 3


def assert_scope_exclusion_count(response: str) -> bool:
    """What We're Deliberately Not Building section has at least 3 bullet entries."""
    body = _get_section_body(response, "What We're Deliberately Not Building")
    if body is None:
        return False
    bullets = [ln for ln in body.splitlines() if re.match(r"^\s*[-*]\s+", ln)]
    return len(bullets) >= 3


def assert_scope_exclusion_rationale(response: str) -> bool:
    """Each scope-exclusion bullet includes a rationale after the em-dash (—) or en-dash (–) separator."""
    body = _get_section_body(response, "What We're Deliberately Not Building")
    if body is None:
        return False
    bullets = [ln for ln in body.splitlines() if re.match(r"^\s*[-*]\s+", ln)]
    if not bullets:
        return False
    # Each bullet must contain an em-dash (—) or en-dash (–) followed by at least one word
    rationale_re = re.compile(r"[—–]\s+\S")
    for bullet in bullets:
        if not rationale_re.search(bullet):
            return False
    return True


def assert_no_body_backtick_fences(response: str) -> bool:
    """No triple-backtick fences appear in the roadmap body (between first H2 and the Meta-Prompt --- marker)."""
    body = _get_body_region(response)
    return "```" not in body


def assert_no_deep_headings_in_slices(response: str) -> bool:
    """No headings deeper than H3 appear inside slice blocks."""
    body = _get_section_body(response, "Thin Slices")
    if body is None:
        return True
    blocks = _extract_slice_blocks(body)
    for block in blocks:
        for line in block.splitlines():
            if re.match(r"^####", line):
                return False
    return True


def assert_sequencing_principles_count(response: str) -> bool:
    """Sequencing Principles section has between 4 and 6 bulleted items inclusive."""
    body = _get_section_body(response, "Sequencing Principles")
    if body is None:
        return False
    bullets = [ln for ln in body.splitlines() if re.match(r"^\s*[-*]\s+", ln)]
    return 4 <= len(bullets) <= 6


def assert_meta_prompt_block(response: str) -> bool:
    """Meta-Prompt block exists between two '---' markers at end of file containing Feature name:, Problem:, Key components:, Key code references:."""
    region = _get_meta_prompt_region(response)
    if region is None:
        return False
    for field in _META_PROMPT_FIELDS:
        if field not in region:
            return False
    return True


# ---------------------------------------------------------------------------
# ASSERTIONS registry
# ---------------------------------------------------------------------------

ASSERTIONS = [
    assert_section_order,
    assert_line_count,
    assert_slice_cardinality,
    assert_slice_required_fields,
    assert_slice_traces_line,
    assert_exit_signal_verb,
    assert_delivers_bullet_count,
    assert_dag_acyclic,
    assert_depends_on_resolve,
    assert_traces_prd_section_format,
    assert_maturity_checkpoints_rows,
    assert_scope_exclusion_count,
    assert_scope_exclusion_rationale,
    assert_no_body_backtick_fences,
    assert_no_deep_headings_in_slices,
    assert_sequencing_principles_count,
    assert_meta_prompt_block,
]
