#!/usr/bin/env python3
"""Stratified subset selector for SWE-bench Verified-style metadata.

Turns a local metadata file (JSON array or JSONL, one instance record per
entry) into a deterministic, repo-diverse N-instance subset so a
bounded-cost benchmark run isn't dominated by one easy repo.

Usage:
    python3 bench/select_subset.py --metadata-file bench/fixtures/sample_metadata.json \
        --size 10 --seed 1 [--max-share 0.2]

Prints a JSON list of selected instance_id strings to stdout.
"""

from __future__ import annotations

import argparse
import json
import math
import random
import sys
from collections import defaultdict
from collections.abc import Iterable

DEFAULT_SIZE = 50
DEFAULT_SEED = 0
DEFAULT_MAX_SHARE = 0.2


def load_records(metadata_file: str) -> list[dict]:
    """Load instance records from a JSON array or JSONL metadata file."""
    with open(metadata_file, encoding="utf-8") as f:
        text = f.read()

    stripped = text.strip()
    if not stripped:
        return []

    try:
        data = json.loads(stripped)
    except json.JSONDecodeError:
        data = None

    if isinstance(data, list):
        return data

    records = []
    for line in stripped.splitlines():
        line = line.strip()
        if not line:
            continue
        records.append(json.loads(line))
    return records


def group_by_repo(records: Iterable[dict]) -> dict[str, list[str]]:
    by_repo: dict[str, list[str]] = defaultdict(list)
    for record in records:
        by_repo[record["repo"]].append(record["instance_id"])
    return by_repo


def select_subset(
    records: list[dict],
    size: int,
    seed: int,
    max_share: float,
) -> list[str]:
    """Select `size` unique instance_ids, stratified by repo.

    No repo may contribute more than `floor(size * max_share)` instances
    (minimum 1). Selection round-robins across a seeded-shuffled repo order
    and a seeded-shuffled per-repo instance order, so the result is fully
    deterministic for a given (records, size, seed, max_share) tuple.

    If the available supply cannot fill `size` while respecting the
    per-repo cap, fewer than `size` instances are returned (the cap is a
    hard ceiling, never relaxed) and a warning is printed to stderr.
    """
    by_repo = group_by_repo(records)
    rng = random.Random(seed)

    repos = sorted(by_repo.keys())
    rng.shuffle(repos)
    for repo in repos:
        rng.shuffle(by_repo[repo])

    cap = max(1, math.floor(size * max_share))
    cursor = {repo: 0 for repo in repos}
    counts = {repo: 0 for repo in repos}
    selected: list[str] = []

    progress = True
    while len(selected) < size and progress:
        progress = False
        for repo in repos:
            if len(selected) >= size:
                break
            if counts[repo] >= cap:
                continue
            pool = by_repo[repo]
            if cursor[repo] >= len(pool):
                continue
            selected.append(pool[cursor[repo]])
            cursor[repo] += 1
            counts[repo] += 1
            progress = True

    if len(selected) < size:
        print(
            f"warning: requested size {size} but only {len(selected)} "
            f"instances available under max-share cap of {cap} per repo",
            file=sys.stderr,
        )

    return selected


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--metadata-file",
        required=True,
        help="Path to a local JSON array or JSONL file of instance records",
    )
    parser.add_argument(
        "--size",
        type=int,
        default=DEFAULT_SIZE,
        help=f"Number of instances to select (default: {DEFAULT_SIZE})",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=DEFAULT_SEED,
        help=f"Random seed for deterministic selection (default: {DEFAULT_SEED})",
    )
    parser.add_argument(
        "--max-share",
        type=float,
        default=DEFAULT_MAX_SHARE,
        help=(
            "Max fraction of the subset a single repo may occupy "
            f"(default: {DEFAULT_MAX_SHARE})"
        ),
    )
    args = parser.parse_args(argv)
    if args.size <= 0:
        parser.error("--size must be a positive integer")
    if not (0 < args.max_share <= 1):
        parser.error("--max-share must be in (0, 1]")
    return args


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    records = load_records(args.metadata_file)
    selected = select_subset(records, args.size, args.seed, args.max_share)
    print(json.dumps(selected))
    return 0


if __name__ == "__main__":
    sys.exit(main())
