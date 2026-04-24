"""
prd_parser.py — Reference implementation of the PRD parser described in
SKILL.md Step 1c–1d.

This module is the algorithmic specification for the LLM instructions in
SKILL.md. It is used by unit tests and as documentation; the skill itself
executes the equivalent logic via Read/Grep without shelling out.

Public API
----------
parse_prd(text: str) -> dict
    Parse PRD Markdown text into the structured intermediate.
    Returns a dict with keys: vision_block, workflow_stages, capabilities,
    domain_concepts, success_metrics, open_questions, prd_path.
    Raises MissingSectionError if any of the six required sections are absent.

discover_latest_prd(prds_dir: str) -> str | None
    Scan prds_dir for *.md files, sort by leading numeric prefix (NN-),
    return the path of the file with the highest prefix.
    Returns None if no .md files are found.
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Optional


# ---------------------------------------------------------------------------
# Exceptions
# ---------------------------------------------------------------------------

class MissingSectionError(Exception):
    """Raised when a required PRD section is absent."""

    def __init__(self, missing: list[str]) -> None:
        self.missing = missing
        super().__init__(
            f"PRD is missing required sections: {', '.join(missing)}"
        )


# ---------------------------------------------------------------------------
# Section name normalisation
# ---------------------------------------------------------------------------

# Strips leading numeric prefixes such as "1.", "1.2.", "3 ", etc.
_NUMERIC_PREFIX_RE = re.compile(r"^\d+(\.\d+)*\.?\s*")

# Canonical section names → output field names
_CANONICAL_SECTIONS: dict[str, str] = {
    "executive summary": "vision_block",
    "core workflow": "workflow_stages",
    "primary capabilities": "capabilities",
    "domain concepts": "domain_concepts",
    "success metrics": "success_metrics",
    "open questions": "open_questions",
}


def _normalize_heading(raw: str) -> str:
    """Strip leading numeric prefix and lower-case a heading string."""
    stripped = _NUMERIC_PREFIX_RE.sub("", raw.strip())
    return stripped.lower()


# ---------------------------------------------------------------------------
# H2-level section splitter
# ---------------------------------------------------------------------------

def _split_h2_sections(text: str) -> list[tuple[str, str]]:
    """
    Split Markdown text on H2 headings (lines starting with ``## ``).

    Returns a list of (normalized_heading, body_text) pairs.
    The preamble before the first H2 is discarded.
    """
    sections: list[tuple[str, str]] = []
    current_heading: Optional[str] = None
    current_lines: list[str] = []

    for line in text.splitlines(keepends=True):
        if line.startswith("## "):
            if current_heading is not None:
                sections.append((current_heading, "".join(current_lines)))
            raw_heading = line[3:].strip()
            current_heading = _normalize_heading(raw_heading)
            current_lines = []
        else:
            if current_heading is not None:
                current_lines.append(line)

    if current_heading is not None:
        sections.append((current_heading, "".join(current_lines)))

    return sections


# ---------------------------------------------------------------------------
# Per-section extractors
# ---------------------------------------------------------------------------

def _extract_vision_block(body: str) -> dict:
    """Extract Vision, Problem, and Target Users table from §1 body."""
    vision = ""
    problem = ""
    users_table = ""

    # Try H3 sub-sections first
    h3_sections: list[tuple[str, str]] = []
    current: Optional[str] = None
    lines_buf: list[str] = []

    for line in body.splitlines(keepends=True):
        if line.startswith("### "):
            if current is not None:
                h3_sections.append((current, "".join(lines_buf)))
            current = _normalize_heading(line[4:].strip())
            lines_buf = []
        else:
            if current is not None:
                lines_buf.append(line)

    if current is not None:
        h3_sections.append((current, "".join(lines_buf)))

    if h3_sections:
        for heading, content in h3_sections:
            if "vision" in heading:
                vision = content.strip()
            elif "problem" in heading:
                problem = content.strip()
            elif "user" in heading:
                users_table = content.strip()
    else:
        # No sub-sections — treat full body as vision
        vision = body.strip()

    return {"vision": vision, "problem": problem, "users_table": users_table}


def _extract_workflow_stages(body: str) -> list[str]:
    """Extract numbered list items from §3 body."""
    stages: list[str] = []
    for line in body.splitlines():
        m = re.match(r"^\s*(\d+)\.\s+(.+)", line)
        if m:
            stages.append(m.group(2).strip())
    return stages


def _extract_capabilities(body: str) -> list[str]:
    """Extract bulleted list items from §4 body."""
    caps: list[str] = []
    for line in body.splitlines():
        # Match '- ' or '* ' bullets
        m = re.match(r"^\s*[-*]\s+(.+)", line)
        if m:
            caps.append(m.group(1).strip())
    return caps


def _extract_domain_concepts(body: str) -> list[str]:
    """Extract bold-dash items and code-block hierarchy from §6 body."""
    concepts: list[str] = []
    for line in body.splitlines():
        # Bold-dash: **Term** — definition
        m = re.match(r"^\s*[-*]?\s*\*\*(.+?)\*\*\s*[—–-]+\s*(.+)", line)
        if m:
            concepts.append(f"**{m.group(1).strip()}** — {m.group(2).strip()}")
    return concepts


def _extract_table_rows(body: str) -> list[str]:
    """Extract non-header, non-separator Markdown table rows from a body."""
    rows: list[str] = []
    for line in body.splitlines():
        stripped = line.strip()
        if stripped.startswith("|") and stripped.endswith("|"):
            # Skip separator rows (e.g. |---|---|)
            inner = stripped.strip("|").replace(" ", "").replace("-", "")
            if inner:
                rows.append(stripped)
    return rows


def _extract_open_questions(body: str) -> list[str]:
    """Extract numbered list items from §8 body."""
    questions: list[str] = []
    for line in body.splitlines():
        m = re.match(r"^\s*(\d+)\.\s+(.+)", line)
        if m:
            questions.append(m.group(2).strip())
    return questions


# ---------------------------------------------------------------------------
# Main parser
# ---------------------------------------------------------------------------

def parse_prd(text: str, prd_path: str = "") -> dict:
    """
    Parse PRD Markdown text into the structured intermediate.

    Parameters
    ----------
    text:
        Full Markdown content of the PRD file.
    prd_path:
        Relative path of the PRD file (informational, not used for parsing).

    Returns
    -------
    dict with keys:
        vision_block    — dict with 'vision', 'problem', 'users_table'
        workflow_stages — list of stage description strings
        capabilities    — list of capability description strings
        domain_concepts — list of "**Term** — definition" strings
        success_metrics — list of raw Markdown table row strings
        open_questions  — list of question text strings
        prd_path        — the prd_path argument echoed back

    Raises
    ------
    MissingSectionError if any of the six required sections are absent.
    """
    sections = _split_h2_sections(text)
    section_map: dict[str, str] = {}

    for heading, body in sections:
        for canonical in _CANONICAL_SECTIONS:
            if heading == canonical:
                section_map[canonical] = body
                break

    # Check for missing required sections
    missing = [name for name in _CANONICAL_SECTIONS if name not in section_map]
    if missing:
        raise MissingSectionError(missing)

    return {
        "vision_block": _extract_vision_block(section_map["executive summary"]),
        "workflow_stages": _extract_workflow_stages(section_map["core workflow"]),
        "capabilities": _extract_capabilities(section_map["primary capabilities"]),
        "domain_concepts": _extract_domain_concepts(section_map["domain concepts"]),
        "success_metrics": _extract_table_rows(section_map["success metrics"]),
        "open_questions": _extract_open_questions(section_map["open questions"]),
        "prd_path": prd_path,
    }


def render_intermediate(result: dict) -> str:
    """
    Render a parse_prd() result as the Markdown block pasted into
    decomposition-prompt.md below the '<!-- Insert PRD intermediate -->'
    marker.
    """
    vb = result["vision_block"]
    users = vb.get("users_table", "")
    stages = "\n".join(
        f"{i + 1}. {s}" for i, s in enumerate(result["workflow_stages"])
    )
    caps = "\n".join(f"- {c}" for c in result["capabilities"])
    concepts = "\n".join(f"- {c}" for c in result["domain_concepts"])
    metrics_rows = "\n".join(result["success_metrics"])
    questions = "\n".join(
        f"{i + 1}. {q}" for i, q in enumerate(result["open_questions"])
    )

    return f"""\
## PRD Intermediate

### §1 Vision / Problem / Users
**Vision:** {vb.get('vision', '')}

**Problem:** {vb.get('problem', '')}

**Users:**
{users}

### §3 Core Workflow Stages
{stages}

### §4 Primary Capabilities
{caps}

### §6 Domain Concepts
{concepts}

### §7 Success Metrics
| Metric | Target |
|--------|--------|
{metrics_rows}

### §8 Open Questions
{questions}

---
PRD path: {result['prd_path']}
"""


# ---------------------------------------------------------------------------
# Path discovery
# ---------------------------------------------------------------------------

def discover_latest_prd(prds_dir: str) -> Optional[str]:
    """
    Scan prds_dir for *.md files.  Sort by leading NN- numeric prefix
    (lexicographic on the zero-padded digits), falling back to full
    filename sort.  Return the path of the last (highest) entry, or
    None if no .md files are found.
    """
    p = Path(prds_dir)
    if not p.is_dir():
        return None

    candidates = sorted(p.glob("*.md"))
    if not candidates:
        return None

    def _sort_key(path: Path) -> tuple[int, str]:
        m = re.match(r"^(\d+)", path.name)
        return (int(m.group(1)) if m else 0, path.name)

    candidates.sort(key=_sort_key)
    return str(candidates[-1])
