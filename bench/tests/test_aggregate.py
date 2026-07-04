"""Tests for bench/aggregate.py.

Exercises R3.1 (per-run parsing), R3.2 (paired resolve-rate delta + Wilson
score CI, mismatched-arm refusal), and R3.3 (Verified/Failed/Missing report
rows) against bench/fixtures/sample_results/, a hand-built 3-instance x
2-arm fixture tree with known, hand-computed expected stats:

    instance-1: vanilla resolved=False tokens=150 wc=20s reg=0
                treatment resolved=True  tokens=90  wc=12s reg=0
    instance-2: vanilla resolved=True  tokens=200 wc=30s reg=1
                treatment resolved=True  tokens=110 wc=15s reg=0
    instance-3: vanilla resolved=False tokens=180 wc=25s reg=0
                treatment resolved=False tokens=170 wc=22s reg=0

    vanilla:   1/3 resolved (33.33%)
    treatment: 2/3 resolved (66.67%)

The Wilson/Newcombe statistical primitives are additionally checked against
independently-computed reference values (not derived by calling the same
code under test) so a broken formula can't pass by construction.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

BENCH_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BENCH_DIR))

import aggregate  # noqa: E402

FIXTURE_DIR = BENCH_DIR / "fixtures" / "sample_results"


def test_wilson_score_interval_matches_reference_values():
    p, lower, upper = aggregate.wilson_score_interval(1, 3, z=1.96)
    assert p == 1 / 3
    assert round(lower, 9) == round(0.0614903152761605, 9)
    assert round(upper, 9) == round(0.7923450448735121, 9)

    p2, lower2, upper2 = aggregate.wilson_score_interval(2, 3, z=1.96)
    assert p2 == 2 / 3
    assert round(lower2, 9) == round(0.2076549551264879, 9)
    assert round(upper2, 9) == round(0.9385096847238394, 9)


def test_newcombe_diff_interval_matches_reference_values():
    delta, lower, upper = aggregate.newcombe_diff_interval(1, 3, 2, 3, z=1.96)
    assert round(delta, 9) == round(1 / 3, 9)
    assert round(lower, 9) == round(-0.05111074963955464, 9)
    assert round(upper, 9) == round(0.982473921081541, 9)


def test_wilson_score_interval_zero_n_returns_zero():
    assert aggregate.wilson_score_interval(0, 0) == (0.0, 0.0, 0.0)


def test_compute_tokens_prefers_result_event_total():
    events = [
        {"type": "tool_use", "tokens": 5},
        {"type": "result", "total_tokens": 150},
    ]
    assert aggregate.compute_tokens(events) == 150


def test_compute_tokens_falls_back_to_summing_tokens_fields():
    events = [
        {"type": "tool_use", "tokens": 5},
        {"type": "tool_use", "tokens": 7},
    ]
    assert aggregate.compute_tokens(events) == 12


def test_compute_tokens_empty_events_is_zero():
    assert aggregate.compute_tokens([]) == 0


def test_compute_wall_clock_first_to_last_delta():
    events = [
        {"ts": "2026-01-01T00:00:00Z"},
        {"ts": "2026-01-01T00:00:07Z"},
    ]
    assert aggregate.compute_wall_clock(events) == 7.0


def test_compute_wall_clock_no_timestamps_is_none():
    assert aggregate.compute_wall_clock([{"type": "system"}]) is None


def test_build_records_parses_all_known_fixture_values():
    instances, arms, records = aggregate.build_records(FIXTURE_DIR)
    assert instances == ["instance-1", "instance-2", "instance-3"]
    assert arms == ["treatment", "vanilla"]

    expected = {
        ("instance-1", "vanilla"): (False, 150, 20.0, 0),
        ("instance-1", "treatment"): (True, 90, 12.0, 0),
        ("instance-2", "vanilla"): (True, 200, 30.0, 1),
        ("instance-2", "treatment"): (True, 110, 15.0, 0),
        ("instance-3", "vanilla"): (False, 180, 25.0, 0),
        ("instance-3", "treatment"): (False, 170, 22.0, 0),
    }
    for key, (resolved, tokens, wall_clock, regressions) in expected.items():
        record = records[key]
        assert record["status"] in ("Verified", "Failed")
        assert record["resolved"] is resolved
        assert record["tokens"] == tokens
        assert record["wall_clock_seconds"] == wall_clock
        assert record["regression_count"] == regressions


def test_arm_stats_match_hand_computed_resolve_counts():
    instances, arms, records = aggregate.build_records(FIXTURE_DIR)
    assert aggregate.compute_arm_stats(instances, "vanilla", records) == (1, 3)
    assert aggregate.compute_arm_stats(instances, "treatment", records) == (2, 3)


def test_check_matched_instance_sets_passes_on_full_fixture():
    instances, arms, records = aggregate.build_records(FIXTURE_DIR)
    assert aggregate.check_matched_instance_sets(instances, arms, records) == []


def test_check_matched_instance_sets_reports_missing_instance(tmp_path):
    results_dir = _build_gap_tree(tmp_path)
    instances, arms, records = aggregate.build_records(results_dir)
    errors = aggregate.check_matched_instance_sets(instances, arms, records)
    assert len(errors) == 1
    assert "instance-2" in errors[0]
    assert "treatment" in errors[0]


def test_main_exits_nonzero_and_names_instance_on_mismatched_arms(tmp_path):
    results_dir = _build_gap_tree(tmp_path)
    out_path = tmp_path / "report.md"
    result = subprocess.run(
        [
            sys.executable,
            str(BENCH_DIR / "aggregate.py"),
            "--results-dir",
            str(results_dir),
            "--out",
            str(out_path),
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode != 0
    assert "instance-2" in result.stderr
    report = out_path.read_text()
    assert "| instance-2 | treatment | Missing |" in report
    assert "instance-2" in report


def test_report_contains_verified_failed_missing_rows(tmp_path):
    out_path = tmp_path / "report.md"
    rc = aggregate.main(
        ["--results-dir", str(FIXTURE_DIR), "--out", str(out_path)]
    )
    assert rc == 0
    report = out_path.read_text()
    assert "| instance-1 | vanilla | Failed |" in report
    assert "| instance-1 | treatment | Verified |" in report
    assert "| instance-2 | vanilla | Verified |" in report
    assert "| instance-3 | treatment | Failed |" in report


def test_report_contains_numeric_resolve_rate_delta_and_ci(tmp_path):
    out_path = tmp_path / "report.md"
    rc = aggregate.main(
        ["--results-dir", str(FIXTURE_DIR), "--out", str(out_path)]
    )
    assert rc == 0
    report = out_path.read_text()
    assert "Delta (vanilla - treatment):" in report or "Delta (treatment - vanilla):" in report
    assert "Wilson 95% CI:" in report
    assert "+33.3%" in report or "-33.3%" in report


def test_resolved_falls_back_to_metrics_json_when_swebench_result_missing(tmp_path):
    results_dir = tmp_path / "results"
    run_dir = results_dir / "solo-1" / "vanilla" / "1"
    run_dir.mkdir(parents=True)
    (run_dir / "metrics.json").write_text(
        json.dumps({"resolved": True, "regression_count": 0})
    )
    (run_dir / "stream.jsonl").write_text(
        '{"type":"result","total_tokens":10,"ts":"2026-01-01T00:00:00Z"}\n'
    )
    record = aggregate.parse_run_dir(
        "solo-1", "vanilla", "1", run_dir
    )
    assert record["resolved"] is True
    assert "fallback verdict field" in record["evidence"]


def test_cli_produces_report_with_resolve_rate_delta():
    out_path = FIXTURE_DIR.parent.parent / "results" / "report.md"
    result = subprocess.run(
        [
            sys.executable,
            str(BENCH_DIR / "aggregate.py"),
            "--results-dir",
            str(FIXTURE_DIR),
            "--out",
            str(out_path),
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    assert result.returncode == 0
    report = out_path.read_text()
    assert "Wilson 95% CI:" in report


def _build_gap_tree(tmp_path: Path) -> Path:
    """A results tree where instance-2 has a run dir only under 'vanilla',
    not under 'treatment' -- exercises both the mismatched-arm refusal
    (R3.2) and the "Missing" row requirement (R3.3) on the same fixture.
    """
    results_dir = tmp_path / "gap_results"
    for instance_id, arms in {
        "instance-1": ("vanilla", "treatment"),
        "instance-2": ("vanilla",),
    }.items():
        for arm in arms:
            run_dir = results_dir / instance_id / arm / "1"
            run_dir.mkdir(parents=True)
            (run_dir / "metrics.json").write_text(
                json.dumps({"resolved": True, "regression_count": 0})
            )
            (run_dir / "swebench_result.json").write_text(
                json.dumps({"resolved": True})
            )
            (run_dir / "stream.jsonl").write_text(
                '{"type":"result","total_tokens":10,"ts":"2026-01-01T00:00:00Z"}\n'
            )
    return results_dir
