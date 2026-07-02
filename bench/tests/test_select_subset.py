"""Tests for bench/select_subset.py.

Exercises stratification (no repo exceeds the configured max share) and
determinism (same seed -> identical ordered output) against both the
shared fixture (bench/fixtures/sample_metadata.json) and small inline
fixtures built to probe edge cases (uneven supply, backfill shortfall).
"""

from __future__ import annotations

import json
import math
import subprocess
import sys
from pathlib import Path

BENCH_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BENCH_DIR))

import select_subset  # noqa: E402

FIXTURE_FILE = BENCH_DIR / "fixtures" / "sample_metadata.json"


def load_fixture_records() -> list[dict]:
    return select_subset.load_records(str(FIXTURE_FILE))


def test_fixture_has_multiple_uneven_repos():
    records = load_fixture_records()
    by_repo = select_subset.group_by_repo(records)
    assert len(by_repo) >= 4
    counts = sorted((len(v) for v in by_repo.values()), reverse=True)
    assert counts[0] > counts[-1]


def test_select_subset_returns_requested_size_and_unique_ids():
    records = load_fixture_records()
    selected = select_subset.select_subset(records, size=10, seed=1, max_share=0.2)
    assert len(selected) == 10
    assert len(set(selected)) == 10


def test_select_subset_default_size_is_50():
    args = select_subset.parse_args(
        ["--metadata-file", str(FIXTURE_FILE), "--seed", "1"]
    )
    assert args.size == select_subset.DEFAULT_SIZE
    assert select_subset.DEFAULT_SIZE == 50


def test_stratification_respects_max_share():
    records = load_fixture_records()
    size = 10
    max_share = 0.2
    selected = select_subset.select_subset(
        records, size=size, seed=1, max_share=max_share
    )
    by_repo = select_subset.group_by_repo(records)
    id_to_repo = {}
    for repo, ids in by_repo.items():
        for instance_id in ids:
            id_to_repo[instance_id] = repo

    cap = max(1, math.floor(size * max_share))
    selected_counts: dict[str, int] = {}
    for instance_id in selected:
        repo = id_to_repo[instance_id]
        selected_counts[repo] = selected_counts.get(repo, 0) + 1

    for repo, count in selected_counts.items():
        assert count <= cap, f"{repo} exceeded cap {cap} with {count}"

    assert len(selected_counts) > 1, "selection should span more than one repo"


def test_dominant_repo_does_not_dominate_selection():
    records = load_fixture_records()
    by_repo = select_subset.group_by_repo(records)
    dominant_repo = max(by_repo, key=lambda r: len(by_repo[r]))
    selected = select_subset.select_subset(records, size=10, seed=1, max_share=0.2)
    dominant_selected = sum(1 for i in selected if i in set(by_repo[dominant_repo]))
    assert dominant_selected <= 2


def test_determinism_same_seed_identical_ordered_list():
    records = load_fixture_records()
    first = select_subset.select_subset(records, size=10, seed=1, max_share=0.2)
    second = select_subset.select_subset(records, size=10, seed=1, max_share=0.2)
    assert first == second


def test_different_seed_can_change_selection():
    records = load_fixture_records()
    with_seed_1 = select_subset.select_subset(records, size=10, seed=1, max_share=0.2)
    with_seed_2 = select_subset.select_subset(records, size=10, seed=2, max_share=0.2)
    assert with_seed_1 != with_seed_2


def test_cap_is_hard_ceiling_even_when_supply_insufficient():
    records = [
        {"instance_id": "a1", "repo": "big/repo", "base_commit": "c1"},
        {"instance_id": "a2", "repo": "big/repo", "base_commit": "c2"},
        {"instance_id": "a3", "repo": "big/repo", "base_commit": "c3"},
        {"instance_id": "a4", "repo": "big/repo", "base_commit": "c4"},
        {"instance_id": "a5", "repo": "big/repo", "base_commit": "c5"},
        {"instance_id": "b1", "repo": "small/repo", "base_commit": "d1"},
    ]
    selected = select_subset.select_subset(records, size=10, seed=1, max_share=0.2)
    assert len(selected) < 10
    big_count = sum(1 for i in selected if i.startswith("a"))
    assert big_count <= 2


def test_load_records_supports_jsonl(tmp_path):
    jsonl_path = tmp_path / "metadata.jsonl"
    jsonl_path.write_text(
        '{"instance_id": "x1", "repo": "r/one", "base_commit": "c1"}\n'
        '{"instance_id": "x2", "repo": "r/two", "base_commit": "c2"}\n'
    )
    records = select_subset.load_records(str(jsonl_path))
    assert len(records) == 2
    assert records[0]["instance_id"] == "x1"


def test_cli_prints_requested_unique_ids():
    result = subprocess.run(
        [
            sys.executable,
            str(BENCH_DIR / "select_subset.py"),
            "--metadata-file",
            str(FIXTURE_FILE),
            "--size",
            "10",
            "--seed",
            "1",
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    ids = json.loads(result.stdout)
    assert len(ids) == 10
    assert len(set(ids)) == 10


def test_cli_is_deterministic_across_invocations():
    def run():
        result = subprocess.run(
            [
                sys.executable,
                str(BENCH_DIR / "select_subset.py"),
                "--metadata-file",
                str(FIXTURE_FILE),
                "--size",
                "10",
                "--seed",
                "1",
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        return json.loads(result.stdout)

    assert run() == run()
