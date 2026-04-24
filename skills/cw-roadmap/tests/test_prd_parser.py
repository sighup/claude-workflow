"""
test_prd_parser.py — Unit tests for the PRD parser reference implementation.

Tests cover:
  - Numeric-prefix normalisation (R1.4 / spec §Technical Considerations)
  - H2-section splitting and field extraction
  - Missing-section error (fails fast rather than guessing)
  - Path discovery sort order
  - R1.8 never-modify guarantee: SHA-256 of the exemplar PRD file is the same
    before and after parse_prd() is called.

Run:
    python -m pytest tests/test_prd_parser.py -v
from the claude-workflow/skills/cw-roadmap/ directory.
"""

from __future__ import annotations

import hashlib
import os
import tempfile
from pathlib import Path

import pytest

from prd_parser import (
    MissingSectionError,
    _normalize_heading,
    _split_h2_sections,
    discover_latest_prd,
    parse_prd,
    render_intermediate,
)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

MINIMAL_PRD = """\
---
type: prd
title: "Test Product"
---

## 1. Executive Summary

### 1.1 Vision

A test product vision.

### 1.2 Problem

A test problem statement.

### 1.3 Target Users

| Persona | Primary Need |
|---------|-------------|
| Developer | Speed |

---

## 2. Positioning

Some positioning content that should be ignored.

---

## 3. Core Workflow

1. Frame — User runs the framing command.
2. Specify — User writes a spec.

---

## 4. Primary Capabilities

- Intent capture: structured authoring of briefs.
- Task dispatch: generation of atomic task graphs.

---

## 5. Integrations

GitHub, Linear (should be ignored).

---

## 6. Domain Concepts

- **Product** — the top-level entity representing a product bet.
- **Specification** — a scoped slice of work.

---

## 7. Success Metrics

| Metric | Target |
|--------|--------|
| Clarity score | >= 75 |

---

## 8. Open Questions

1. Pricing model — open source or commercial?
2. Scale ceiling — performance at large repos?

_End of Document_
"""

# PRD without numeric prefixes on headings — template drift
DRIFTED_PRD = MINIMAL_PRD.replace("## 1. Executive Summary", "## Executive Summary") \
                          .replace("## 3. Core Workflow", "## Core Workflow") \
                          .replace("## 4. Primary Capabilities", "## Primary Capabilities") \
                          .replace("## 6. Domain Concepts", "## Domain Concepts") \
                          .replace("## 7. Success Metrics", "## Success Metrics") \
                          .replace("## 8. Open Questions", "## Open Questions")

# PRD with unconventional numeric prefix format
ALT_PREFIX_PRD = MINIMAL_PRD.replace("## 1. Executive Summary", "## 1 Executive Summary") \
                              .replace("## 3. Core Workflow", "## 3 Core Workflow") \
                              .replace("## 4. Primary Capabilities", "## 4 Primary Capabilities") \
                              .replace("## 6. Domain Concepts", "## 6 Domain Concepts") \
                              .replace("## 7. Success Metrics", "## 7 Success Metrics") \
                              .replace("## 8. Open Questions", "## 8 Open Questions")


# ---------------------------------------------------------------------------
# Tests: heading normalisation
# ---------------------------------------------------------------------------

class TestNormalizeHeading:
    def test_strips_dotted_prefix(self):
        assert _normalize_heading("1. Executive Summary") == "executive summary"

    def test_strips_multi_level_prefix(self):
        assert _normalize_heading("1.2. Core Workflow") == "core workflow"

    def test_strips_prefix_without_dot(self):
        assert _normalize_heading("3 Core Workflow") == "core workflow"

    def test_already_bare(self):
        assert _normalize_heading("Primary Capabilities") == "primary capabilities"

    def test_strips_leading_whitespace(self):
        assert _normalize_heading("  2. Positioning") == "positioning"

    def test_preserves_hyphenated_words(self):
        assert _normalize_heading("4. Open-Source Policy") == "open-source policy"


# ---------------------------------------------------------------------------
# Tests: H2 splitting
# ---------------------------------------------------------------------------

class TestSplitH2Sections:
    def test_returns_correct_heading_count(self):
        sections = _split_h2_sections(MINIMAL_PRD)
        headings = [h for h, _ in sections]
        # §2 Positioning and §5 Integrations are also present in MINIMAL_PRD
        assert "executive summary" in headings
        assert "core workflow" in headings
        assert "primary capabilities" in headings
        assert "domain concepts" in headings
        assert "success metrics" in headings
        assert "open questions" in headings

    def test_preamble_discarded(self):
        sections = _split_h2_sections(MINIMAL_PRD)
        headings = [h for h, _ in sections]
        # There should be no empty-string heading from the YAML front matter
        assert "" not in headings

    def test_body_not_empty_for_non_trivial_sections(self):
        sections = dict(_split_h2_sections(MINIMAL_PRD))
        assert len(sections["core workflow"].strip()) > 0
        assert len(sections["primary capabilities"].strip()) > 0


# ---------------------------------------------------------------------------
# Tests: parse_prd full pipeline
# ---------------------------------------------------------------------------

class TestParsePrd:
    def test_returns_all_six_fields(self):
        result = parse_prd(MINIMAL_PRD, prd_path="docs/prds/test.md")
        assert set(result.keys()) == {
            "vision_block",
            "workflow_stages",
            "capabilities",
            "domain_concepts",
            "success_metrics",
            "open_questions",
            "prd_path",
        }

    def test_prd_path_echoed(self):
        result = parse_prd(MINIMAL_PRD, prd_path="docs/prds/test.md")
        assert result["prd_path"] == "docs/prds/test.md"

    def test_vision_extracted(self):
        result = parse_prd(MINIMAL_PRD)
        assert "test product vision" in result["vision_block"]["vision"].lower()

    def test_problem_extracted(self):
        result = parse_prd(MINIMAL_PRD)
        assert "test problem statement" in result["vision_block"]["problem"].lower()

    def test_workflow_stages_count(self):
        result = parse_prd(MINIMAL_PRD)
        assert len(result["workflow_stages"]) == 2

    def test_workflow_stage_names(self):
        result = parse_prd(MINIMAL_PRD)
        assert any("frame" in s.lower() for s in result["workflow_stages"])
        assert any("specify" in s.lower() for s in result["workflow_stages"])

    def test_capabilities_count(self):
        result = parse_prd(MINIMAL_PRD)
        assert len(result["capabilities"]) == 2

    def test_capabilities_content(self):
        result = parse_prd(MINIMAL_PRD)
        joined = " ".join(result["capabilities"]).lower()
        assert "intent capture" in joined
        assert "task dispatch" in joined

    def test_domain_concepts_extracted(self):
        result = parse_prd(MINIMAL_PRD)
        assert len(result["domain_concepts"]) >= 2
        joined = " ".join(result["domain_concepts"])
        assert "Product" in joined
        assert "Specification" in joined

    def test_success_metrics_extracted(self):
        result = parse_prd(MINIMAL_PRD)
        assert len(result["success_metrics"]) >= 1
        assert "Clarity score" in " ".join(result["success_metrics"])

    def test_open_questions_extracted(self):
        result = parse_prd(MINIMAL_PRD)
        assert len(result["open_questions"]) == 2
        joined = " ".join(result["open_questions"])
        assert "Pricing" in joined or "pricing" in joined

    def test_ignored_sections_not_in_result(self):
        # §2 Positioning and §5 Integrations must not appear as top-level keys
        result = parse_prd(MINIMAL_PRD)
        assert "positioning" not in result
        assert "integrations" not in result


# ---------------------------------------------------------------------------
# Tests: template drift (headings without numeric prefixes)
# ---------------------------------------------------------------------------

class TestTemplateDrift:
    def test_drifted_headings_parse_correctly(self):
        result = parse_prd(DRIFTED_PRD)
        assert len(result["workflow_stages"]) == 2
        assert len(result["capabilities"]) == 2

    def test_alt_prefix_format_parses_correctly(self):
        result = parse_prd(ALT_PREFIX_PRD)
        assert len(result["workflow_stages"]) == 2
        assert len(result["open_questions"]) == 2


# ---------------------------------------------------------------------------
# Tests: missing section error
# ---------------------------------------------------------------------------

class TestMissingSectionError:
    def test_raises_on_missing_section(self):
        # Remove the Open Questions section
        truncated = MINIMAL_PRD[: MINIMAL_PRD.index("## 8. Open Questions")]
        with pytest.raises(MissingSectionError) as exc_info:
            parse_prd(truncated)
        assert "open questions" in str(exc_info.value).lower()

    def test_missing_error_lists_all_absent_sections(self):
        # Only keep front matter — all six sections absent
        bare = "---\ntype: prd\ntitle: Empty\n---\n"
        with pytest.raises(MissingSectionError) as exc_info:
            parse_prd(bare)
        assert len(exc_info.value.missing) == 6


# ---------------------------------------------------------------------------
# Tests: render_intermediate output
# ---------------------------------------------------------------------------

class TestRenderIntermediate:
    def test_renders_all_six_sections(self):
        result = parse_prd(MINIMAL_PRD, prd_path="docs/prds/test.md")
        rendered = render_intermediate(result)
        for marker in ["§1", "§3", "§4", "§6", "§7", "§8"]:
            assert marker in rendered

    def test_prd_path_appears_in_output(self):
        result = parse_prd(MINIMAL_PRD, prd_path="docs/prds/test.md")
        rendered = render_intermediate(result)
        assert "docs/prds/test.md" in rendered


# ---------------------------------------------------------------------------
# Tests: path discovery
# ---------------------------------------------------------------------------

class TestDiscoverLatestPrd:
    def test_returns_none_for_empty_dir(self):
        with tempfile.TemporaryDirectory() as d:
            assert discover_latest_prd(d) is None

    def test_returns_none_for_nonexistent_dir(self):
        assert discover_latest_prd("/nonexistent/path/does/not/exist") is None

    def test_returns_highest_prefixed_file(self):
        with tempfile.TemporaryDirectory() as d:
            for name in ["01-alpha.md", "02-beta.md", "03-gamma.md"]:
                Path(d, name).write_text("# test")
            result = discover_latest_prd(d)
            assert result is not None
            assert "03-gamma.md" in result

    def test_single_file_returned(self):
        with tempfile.TemporaryDirectory() as d:
            only = Path(d, "01-only.md")
            only.write_text("# test")
            result = discover_latest_prd(d)
            assert result == str(only)

    def test_non_md_files_ignored(self):
        with tempfile.TemporaryDirectory() as d:
            Path(d, "03-latest.txt").write_text("not markdown")
            Path(d, "01-first.md").write_text("# test")
            result = discover_latest_prd(d)
            assert result is not None
            assert "01-first.md" in result

    def test_files_without_prefix_sorted_lexicographically(self):
        with tempfile.TemporaryDirectory() as d:
            for name in ["alpha.md", "beta.md", "zeta.md"]:
                Path(d, name).write_text("# test")
            result = discover_latest_prd(d)
            assert result is not None
            assert "zeta.md" in result

    def test_prefixed_beats_unprefixed(self):
        with tempfile.TemporaryDirectory() as d:
            for name in ["alpha.md", "01-first.md"]:
                Path(d, name).write_text("# test")
            result = discover_latest_prd(d)
            assert result is not None
            assert "01-first.md" in result


# ---------------------------------------------------------------------------
# Tests: R1.8 never-modify guarantee (checksum test)
# ---------------------------------------------------------------------------

class TestNeverModifyGuarantee:
    """
    R1.8: the source PRD file SHALL NOT be modified under any circumstance.

    This test reads the exemplar PRD from docs/prds/, records its SHA-256
    before calling parse_prd(), re-reads and re-hashes the file after, and
    asserts the checksums are equal.  The test fails if any code path in the
    parser opens the file for writing.
    """

    @staticmethod
    def _sha256(path: str) -> str:
        h = hashlib.sha256()
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(65536), b""):
                h.update(chunk)
        return h.hexdigest()

    def test_exemplar_prd_unchanged_after_parse(self):
        # Locate the exemplar PRD relative to this test file's repo root.
        # The test file lives at:
        #   <repo>/skills/cw-roadmap/tests/test_prd_parser.py
        # Structure: tests/ → cw-roadmap/ → skills/ → <repo_root> (claude-workflow/)
        # The exemplar PRD lives at:
        #   <vault_root>/docs/prds/spec-driven-development-system.md
        # Walk up to the claude-workflow repo root (4 levels), then one more for vault.
        here = Path(__file__).resolve()
        # tests → cw-roadmap → skills → claude-workflow (repo_root) → vault_root
        repo_root = here.parent.parent.parent.parent
        vault_root = repo_root.parent
        prd_path = vault_root / "docs" / "prds" / "spec-driven-development-system.md"

        if not prd_path.exists():
            pytest.skip(f"Exemplar PRD not found at {prd_path}")

        sha_before = self._sha256(str(prd_path))
        text = prd_path.read_text(encoding="utf-8")

        # Run the parser — this must not touch the file
        parse_prd(text, prd_path=str(prd_path.relative_to(vault_root)))

        sha_after = self._sha256(str(prd_path))
        assert sha_before == sha_after, (
            f"PRD file was modified during parse_prd()!\n"
            f"  Before: {sha_before}\n"
            f"  After:  {sha_after}"
        )

    def test_exemplar_prd_parses_all_six_sections(self):
        """Smoke-test the exemplar PRD round-trips through the parser cleanly."""
        here = Path(__file__).resolve()
        # tests → cw-roadmap → skills → claude-workflow (repo_root) → vault_root
        repo_root = here.parent.parent.parent.parent
        vault_root = repo_root.parent
        prd_path = vault_root / "docs" / "prds" / "spec-driven-development-system.md"

        if not prd_path.exists():
            pytest.skip(f"Exemplar PRD not found at {prd_path}")

        text = prd_path.read_text(encoding="utf-8")
        result = parse_prd(text, prd_path=str(prd_path.relative_to(vault_root)))

        assert len(result["workflow_stages"]) >= 1
        assert len(result["capabilities"]) >= 1
        assert len(result["domain_concepts"]) >= 1
        assert len(result["success_metrics"]) >= 1
        assert len(result["open_questions"]) >= 1
        assert result["vision_block"]["vision"] != ""
