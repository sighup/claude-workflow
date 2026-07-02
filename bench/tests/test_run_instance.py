"""Pytest driver for ``bench/run_instance.sh`` against local fixtures.

Establishes the ``pytest bench/tests/`` invocation convention that spec Unit 1
owns (Units 2 and 3 reuse it) and re-asserts the runner's happy-path capture and
its test-tampering guard. Runs entirely offline: stub agent + toy repo, no real
``claude`` call, no docker, no network.
"""

import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNNER = ROOT / "bench" / "run_instance.sh"
STUB = ROOT / "bench" / "fixtures" / "stub-agent.sh"


def _run(tmp_path, run_n, env_extra=None):
    env = dict(os.environ)
    if env_extra:
        env.update(env_extra)
    results = tmp_path / "results"
    proc = subprocess.run(
        [
            str(RUNNER),
            "--instance-id", "toy-1",
            "--arm", "vanilla",
            "--run-n", str(run_n),
            "--agent-cmd", str(STUB),
            "--results-dir", str(results),
        ],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    out = results / "toy-1" / "vanilla" / str(run_n)
    return proc, out


def _metrics(out):
    return json.loads((out / "metrics.json").read_text())


def test_happy_path_capture(tmp_path):
    proc, out = _run(tmp_path, 1)
    assert proc.returncode == 0, proc.stderr
    for name in ("patch.diff", "stream.jsonl", "metrics.json"):
        assert (out / name).stat().st_size > 0, f"empty {name}"
    metrics = _metrics(out)
    assert metrics["status"] == "completed"
    assert metrics["test_tampering"] is False
    assert metrics["image"] == "bench-fixture:local"
    assert "swebench/" not in metrics["image"]


def test_tampering_guard(tmp_path):
    proc, out = _run(tmp_path, 2, {"BENCH_STUB_TAMPER": "1"})
    assert proc.returncode != 0
    metrics = _metrics(out)
    assert metrics["status"] == "FAILED: test-tampering"
    assert metrics["resolved"] is False


def test_task_list_isolation(tmp_path):
    _, out1 = _run(tmp_path, 1)
    _, out2 = _run(tmp_path, 2)
    assert _metrics(out1)["task_list_id"] != _metrics(out2)["task_list_id"]
