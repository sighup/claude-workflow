#!/usr/bin/env python3
"""Metrics aggregator for the SWE-bench eval harness.

Parses a populated bench/results/{instance_id}/{arm}/{run_n}/ tree (the
layout bench/run_instance.sh produces) into per-run records, computes a
paired resolve-rate delta between two arms (matched by instance_id) with a
Wilson score confidence interval, and emits a coverage-matrix-style markdown
report.

Usage:
    python3 bench/aggregate.py --results-dir bench/results --out bench/results/report.md

Documented parsing rules (spec R3.1):
  - resolved: read from swebench_result.json's "resolved" field if that file
    is present in the run directory; otherwise fall back to metrics.json's
    own "resolved" field (the verdict bench/run_instance.sh itself records).
  - tokens: if stream.jsonl contains a "result"-type event with a
    "total_tokens" field, that is treated as the authoritative cumulative
    token count for the run (the convention bench/fixtures/stub-agent.sh and
    real `claude` stream-json output both follow). Otherwise every "tokens"
    field across all events is summed.
  - wall_clock_seconds: the delta between the first and last event's "ts"
    timestamp in stream.jsonl.
  - regression_count: read directly from metrics.json's "regression_count"
    field (already computed by run_instance.sh's checksum guard).

Paired comparison rule (spec R3.2): the two arms must report evidence (a
non-"Missing" record) for the exact same instance_id set, or the aggregator
refuses to compute a delta -- it still writes the full per-instance matrix
(including "Missing" rows) so nothing is silently dropped from the report,
but exits non-zero and names the offending instance_id(s) on stderr.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

Z_95 = 1.96

# Same redaction intent as cw-validate Gate F: never let a captured
# stream.jsonl/metrics.json event leak a real credential into report.md.
REDACT_PATTERNS = [
    re.compile(r"sk-[A-Za-z0-9_-]{10,}"),
    re.compile(r"pk_[A-Za-z0-9_-]{10,}"),
    re.compile(r"(?i)api[_-]?key\S*"),
    re.compile(r"Bearer\s+\S+"),
    re.compile(r"eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"),
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
]


def redact(text: str) -> str:
    for pattern in REDACT_PATTERNS:
        text = pattern.sub("[REDACTED]", text)
    return text


def read_json(path: Path) -> dict | None:
    if not path.exists():
        return None
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def read_jsonl(path: Path) -> list[dict]:
    events = []
    if not path.exists():
        return events
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            events.append(json.loads(line))
    return events


def parse_ts(ts: str) -> datetime:
    return datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)


def compute_tokens(events: list[dict]) -> int:
    """Sum token usage from stream.jsonl events (see module docstring)."""
    result_total = None
    summed = 0.0
    has_any = False
    for event in events:
        if event.get("type") == "result" and isinstance(
            event.get("total_tokens"), (int, float)
        ):
            result_total = event["total_tokens"]
        tokens = event.get("tokens")
        if isinstance(tokens, (int, float)):
            summed += tokens
            has_any = True
    if result_total is not None:
        return int(result_total)
    return int(summed) if has_any else 0


def compute_wall_clock(events: list[dict]) -> float | None:
    """First-to-last event "ts" delta in seconds, or None if no timestamps."""
    timestamps = []
    for event in events:
        ts = event.get("ts")
        if not ts:
            continue
        try:
            timestamps.append(parse_ts(ts))
        except ValueError:
            continue
    if not timestamps:
        return None
    if len(timestamps) == 1:
        return 0.0
    return (max(timestamps) - min(timestamps)).total_seconds()


def missing_record(instance_id: str, arm: str) -> dict:
    return {
        "instance_id": instance_id,
        "arm": arm,
        "run_n": None,
        "status": "Missing",
        "resolved": None,
        "tokens": None,
        "wall_clock_seconds": None,
        "regression_count": None,
        "evidence": "no run directory found",
    }


def parse_run_dir(instance_id: str, arm: str, run_n: str, run_dir: Path) -> dict:
    metrics = read_json(run_dir / "metrics.json")
    if metrics is None:
        return missing_record(instance_id, arm)

    swebench_result = read_json(run_dir / "swebench_result.json")
    if swebench_result is not None and "resolved" in swebench_result:
        resolved = bool(swebench_result["resolved"])
        evidence = str(run_dir / "swebench_result.json")
    else:
        resolved = bool(metrics.get("resolved", False))
        evidence = str(run_dir / "metrics.json") + " (fallback verdict field)"

    events = read_jsonl(run_dir / "stream.jsonl")
    tokens = compute_tokens(events)
    wall_clock_seconds = compute_wall_clock(events)
    regression_count = int(metrics.get("regression_count", 0))

    return {
        "instance_id": instance_id,
        "arm": arm,
        "run_n": run_n,
        "status": "Verified" if resolved else "Failed",
        "resolved": resolved,
        "tokens": tokens,
        "wall_clock_seconds": wall_clock_seconds,
        "regression_count": regression_count,
        "evidence": redact(evidence),
    }


def discover_runs(
    results_dir: Path,
) -> tuple[list[str], list[str], dict[tuple[str, str], list[str]]]:
    instances = sorted(p.name for p in results_dir.iterdir() if p.is_dir())
    arms_seen: set[str] = set()
    run_index: dict[tuple[str, str], list[str]] = {}
    for instance_id in instances:
        instance_dir = results_dir / instance_id
        for arm_dir in sorted(p for p in instance_dir.iterdir() if p.is_dir()):
            arm = arm_dir.name
            arms_seen.add(arm)
            runs = sorted(p.name for p in arm_dir.iterdir() if p.is_dir())
            run_index[(instance_id, arm)] = runs
    return instances, sorted(arms_seen), run_index


def build_records(
    results_dir: Path,
) -> tuple[list[str], list[str], dict[tuple[str, str], dict]]:
    """Parse every discovered {instance_id}/{arm}/ into one record.

    When multiple run_n directories exist for an (instance_id, arm) pair,
    the lexicographically-first run_n is the canonical record driving the
    resolve-rate statistics -- raw per-run evidence under every run_n is
    left untouched on disk either way.
    """
    instances, arms, run_index = discover_runs(results_dir)
    records: dict[tuple[str, str], dict] = {}
    for instance_id in instances:
        for arm in arms:
            runs = run_index.get((instance_id, arm), [])
            if not runs:
                records[(instance_id, arm)] = missing_record(instance_id, arm)
                continue
            run_n = runs[0]
            run_dir = results_dir / instance_id / arm / run_n
            records[(instance_id, arm)] = parse_run_dir(
                instance_id, arm, run_n, run_dir
            )
    return instances, arms, records


def wilson_score_interval(k: int, n: int, z: float = Z_95) -> tuple[float, float, float]:
    """Return (point_estimate, lower, upper) via the Wilson score interval."""
    if n == 0:
        return (0.0, 0.0, 0.0)
    p = k / n
    denom = 1 + z * z / n
    center = (p + z * z / (2 * n)) / denom
    margin = (z * ((p * (1 - p) / n + z * z / (4 * n * n)) ** 0.5)) / denom
    return (p, max(0.0, center - margin), min(1.0, center + margin))


def newcombe_diff_interval(
    k1: int, n1: int, k2: int, n2: int, z: float = Z_95
) -> tuple[float, float, float]:
    """CI for the difference of two proportions (arm2 - arm1), built from
    each arm's independent Wilson score interval per Newcombe (1998) method
    10 -- a documented, stdlib-only approximation used here as the paired
    resolve-rate delta's confidence interval (spec R3.2).
    """
    p1, l1, u1 = wilson_score_interval(k1, n1, z)
    p2, l2, u2 = wilson_score_interval(k2, n2, z)
    delta = p2 - p1
    lower = delta - ((p1 - l1) ** 2 + (u2 - p2) ** 2) ** 0.5
    upper = delta + ((u1 - p1) ** 2 + (p2 - l2) ** 2) ** 0.5
    return (delta, lower, upper)


def compute_arm_stats(
    instances: list[str], arm: str, records: dict[tuple[str, str], dict]
) -> tuple[int, int]:
    """Return (resolved_count, total_with_evidence) for one arm."""
    k = 0
    n = 0
    for instance_id in instances:
        record = records[(instance_id, arm)]
        if record["status"] == "Missing":
            continue
        n += 1
        if record["resolved"]:
            k += 1
    return k, n


def check_matched_instance_sets(
    instances: list[str], arms: list[str], records: dict[tuple[str, str], dict]
) -> list[str]:
    """Return loud-failure messages if the two arms disagree on which
    instance_ids have any evidence at all (R3.2's mismatched-sample guard).
    Empty list means the arms are comparable.
    """
    if len(arms) != 2:
        return []
    arm_a, arm_b = arms
    present_a = {i for i in instances if records[(i, arm_a)]["status"] != "Missing"}
    present_b = {i for i in instances if records[(i, arm_b)]["status"] != "Missing"}
    errors = []
    for instance_id in sorted(present_a - present_b):
        errors.append(
            f"instance_id '{instance_id}' present in arm '{arm_a}' "
            f"but missing from arm '{arm_b}'"
        )
    for instance_id in sorted(present_b - present_a):
        errors.append(
            f"instance_id '{instance_id}' present in arm '{arm_b}' "
            f"but missing from arm '{arm_a}'"
        )
    return errors


def render_report(
    instances: list[str],
    arms: list[str],
    records: dict[tuple[str, str], dict],
    arm_stats: dict[str, tuple[int, int]],
    delta_info: tuple[float, float, float] | None,
    errors: list[str],
) -> str:
    lines = ["# Metrics Aggregation & Comparison Report", ""]
    lines.append(f"**Generated**: {datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}")
    lines.append(f"**Arms**: {', '.join(arms)}")
    lines.append("")
    lines.append("## Coverage Matrix: Per-Instance Results")
    lines.append("")
    lines.append(
        "| Instance | Arm | Status | Resolved | Tokens | Wall-Clock (s) | Regressions | Evidence |"
    )
    lines.append(
        "|----------|-----|--------|----------|--------|-----------------|--------------|----------|"
    )
    for instance_id in instances:
        for arm in arms:
            record = records[(instance_id, arm)]
            resolved_str = "-" if record["resolved"] is None else str(record["resolved"])
            tokens_str = "-" if record["tokens"] is None else str(record["tokens"])
            wc = record["wall_clock_seconds"]
            wc_str = "-" if wc is None else f"{wc:.1f}"
            reg = record["regression_count"]
            reg_str = "-" if reg is None else str(reg)
            lines.append(
                f"| {instance_id} | {arm} | {record['status']} | {resolved_str} | "
                f"{tokens_str} | {wc_str} | {reg_str} | {record['evidence']} |"
            )
    lines.append("")
    lines.append("## Summary Metrics")
    lines.append("")
    lines.append("| Arm | Resolve Rate | Resolved/N |")
    lines.append("|-----|--------------|------------|")
    for arm in arms:
        k, n = arm_stats[arm]
        rate = (k / n * 100) if n else 0.0
        lines.append(f"| {arm} | {rate:.1f}% | {k}/{n} |")
    lines.append("")
    lines.append("## Paired Resolve-Rate Delta")
    lines.append("")
    if errors:
        lines.append(
            "**Delta**: NOT COMPUTED - arms do not share the same instance-id set:"
        )
        lines.append("")
        for error in errors:
            lines.append(f"- {error}")
    elif delta_info is not None and len(arms) == 2:
        arm_a, arm_b = arms
        delta, lower, upper = delta_info
        lines.append(
            f"Delta ({arm_b} - {arm_a}): {delta * 100:+.1f}% "
            f"(Wilson 95% CI: [{lower * 100:.1f}%, {upper * 100:.1f}%])"
        )
    else:
        lines.append("**Delta**: NOT COMPUTED - need exactly two arms to compare.")
    lines.append("")
    return "\n".join(lines)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--results-dir",
        required=True,
        help="Root of the {instance_id}/{arm}/{run_n}/ results tree",
    )
    parser.add_argument(
        "--out",
        required=True,
        help="Path to write the markdown report to",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    results_dir = Path(args.results_dir)
    if not results_dir.is_dir():
        print(f"error: results-dir not found: {results_dir}", file=sys.stderr)
        return 64

    instances, arms, records = build_records(results_dir)
    if not instances:
        print(f"error: no instance directories found under {results_dir}", file=sys.stderr)
        return 64

    errors = check_matched_instance_sets(instances, arms, records)
    arm_stats = {arm: compute_arm_stats(instances, arm, records) for arm in arms}

    delta_info = None
    if not errors and len(arms) == 2:
        arm_a, arm_b = arms
        k1, n1 = arm_stats[arm_a]
        k2, n2 = arm_stats[arm_b]
        delta_info = newcombe_diff_interval(k1, n1, k2, n2)

    report = render_report(instances, arms, records, arm_stats, delta_info, errors)
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(report, encoding="utf-8")

    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        print(
            "error: refusing to compute paired resolve-rate delta for mismatched arms",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
