# Result Journal Schema

Workers write one `{task_id}.result.json` per task into `docs/specs/<run>/results/` (gitignored) immediately after committing. The dispatcher harvests this file and applies every board update itself, serially. The `commit_sha` inside the journal is the sole commit-to-task link; the harvester verifies it against git before accepting the record.

## `{task_id}.result.json`

```json
{
  "task_id": "T02.1",
  "status": "completed",
  "commit_sha": "abc1234",
  "proof_dir": "docs/specs/02-spec-task-store-single-writer/02-proofs",
  "proof_results": [
    { "type": "file", "status": "pass", "output_file": "T02.1-01-file.txt" },
    { "type": "cli",  "status": "pass", "output_file": "T02.1-02-cli.txt"  }
  ],
  "proof_summary": "T02.1-proofs.md",
  "verifier_verdict": "PASS",
  "verifier_tokens": 8420,
  "verification_mode": "spawned",
  "completed_at": "2026-06-11T14:00:00Z"
}
```

### Field Definitions

| Field | Type | Required | Description |
|---|---|---|---|
| `task_id` | string | yes | Stable planner-assigned id (e.g. `T02.1`). Never the native task-store integer. |
| `status` | `"completed"` \| `"failed"` | yes | `"completed"` only when `verifier_verdict` is `PASS`. |
| `commit_sha` | string | yes | The full SHA of the implementation commit. Harvester verifies reachability in git (`git cat-file -e <sha>^{commit}`); an unreachable sha rejects the record. |
| `proof_dir` | string | yes | Repo-root-relative path to the proof artifact directory. |
| `proof_results` | array | yes | One entry per artifact. Each entry: `type` (proof type string), `status` (`"pass"` or `"fail"`), `output_file` (filename only — no path). |
| `proof_summary` | string | yes | Filename of the `{task_id}-proofs.md` summary (no path). |
| `verifier_verdict` | `"PASS"` \| `"FAIL"` | yes | Verbatim overall verdict from the proof-verifier child. When `verification_mode` is `"inline"` or `"inline-degraded"`, record the implementer's own inline check result. |
| `verifier_tokens` | number \| `"n/a"` | yes | Token usage relayed from the verifier child. Literal `"n/a"` when verification ran inline. |
| `verification_mode` | `"spawned"` \| `"inline"` \| `"inline-degraded"` | yes | `"spawned"` when a proof-verifier child ran; `"inline"` when the Task tool was unavailable; `"inline-degraded"` when the child spawned but returned no usable verdict. |
| `deviation_count` | number | no | Count of lines in `{task_id}.deviations.jsonl` at Step 8.5 sealing (`0` when absent or empty). See [deviation-log-schema.md](deviation-log-schema.md). |
| `completed_at` | ISO 8601 string | yes | Timestamp of journal write. |

## Failure Record

When a worker exhausts its retries it emits `status: "failed"` and writes the journal with a failure record instead of completion fields. The failure path writes `{task_id}.result.json` by the same Step 8.5 mechanics so the evidence is durable on disk, not sentinel-only. A failed record carries the diagnostic fields below in place of `commit_sha`, the proof/verifier fields, and `completed_at`.

```json
{
  "task_id": "T02.1",
  "status": "failed",
  "failed_step": "Proof",
  "failure_reason": "proof artifact T02.1-02-cli.txt returned exit 1; expected 0",
  "failure_count": 3,
  "proof_status": "partial",
  "last_failure": "2026-06-11T14:00:00Z"
}
```

### Field Definitions

| Field | Type | Required | Description |
|---|---|---|---|
| `task_id` | string | yes | Stable planner-assigned id, same form as a completed record. |
| `status` | `"failed"` | yes | Marks this a failure record. |
| `failed_step` | string | yes | Protocol step that exhausted retries (`Proof`, `Sanitize`, `Commit`, `Verify Full`, etc.). |
| `failure_reason` | string | yes | Human-readable cause, including the last observed error or verdict. |
| `failure_count` | number | yes | Retry attempts spent before giving up. |
| `proof_status` | `"none"` \| `"partial"` \| `"complete"` | yes | How far proof collection got before the failure. |
| `last_failure` | ISO 8601 string | yes | Timestamp of the final failed attempt. |

A failure record omits `commit_sha`, `proof_dir`, `proof_results`, `proof_summary`, the verifier fields, and `completed_at` — the worker reached no committed, verified state.

### Constraints

- `task_id` always uses the stable planner-assigned form (`T01`, `T02.1`, etc.). Proof files must follow the same convention (`T02.1-01-file.txt`), never the native task-store integer — proof files keyed on a native id cannot be matched across a board wipe.
- The journal is written exactly once by its owning worker and never edited afterward.
- The results directory (`docs/specs/<run>/results/`) is gitignored and local-only. The `commit_sha` in the journal is the only durable commit-to-task link; sha verification at harvest is mandatory.

## CW-RESULT-BLOCK Sentinel

After writing `{task_id}.result.json` and before stopping, the worker emits a fenced result block as the final message. The dispatcher harvests this block first (highest precedence); the on-disk journal is the fallback when the block is absent or unparseable.

### Format

```
CW-RESULT-BLOCK-START
{
  "task_id": "T02.1",
  "status": "completed",
  "commit_sha": "abc1234",
  "proof_dir": "docs/specs/02-spec-task-store-single-writer/02-proofs",
  "proof_results": [
    { "type": "file", "status": "pass", "output_file": "T02.1-01-file.txt" },
    { "type": "cli",  "status": "pass", "output_file": "T02.1-02-cli.txt"  }
  ],
  "proof_summary": "T02.1-proofs.md",
  "verifier_verdict": "PASS",
  "verifier_tokens": 8420,
  "verification_mode": "spawned",
  "completed_at": "2026-06-11T14:00:00Z"
}
CW-RESULT-BLOCK-END
```

### Contract

- The sentinel block contains exactly the same fields as `{task_id}.result.json` — a completion record on success, a failure record on failure. Workers must keep the two in sync; the dispatcher treats them as identical representations.
- The block appears as the last substantive content of the worker's final message.
- The dispatcher extracts the block by scanning from the first `CW-RESULT-BLOCK-START` line to the matching `CW-RESULT-BLOCK-END` line and parsing the enclosed JSON.
- A parseable block with `status: "completed"` and all completion fields applies the board completion. A parseable block with `status: "failed"` and all failure fields is first-class evidence too: the dispatcher records the failure diagnostics and keeps the task dispatchable for re-attempt.
- If the extracted JSON fails to parse or is missing the required fields for its `status`, the dispatcher falls back to the matching on-disk journal — which the failure path also writes.
- A worker that emits no usable block and writes no journal leaves the task without evidence. The dispatcher detects this on the next loop via the manifest and re-dispatches the task.
