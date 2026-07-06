# Deviation Log Schema

Workers append one JSON line per deviation to `docs/specs/<run>/results/{task_id}.deviations.jsonl` (gitignored) during Step 4, immediately when an ambiguous or under-specified requirement forces a conservative choice — never batched up for later. Most tasks encounter zero deviations, in which case the file is simply never created. At Step 8.5 the log is sealed: `deviation_count` is computed by counting its lines (`0` when absent or empty) and carried into the [result journal](result-journal-schema.md).

## `{task_id}.deviations.jsonl`

Each line is a standalone JSON object:

```json
{"deviation": "Requirement R2.2 did not specify where to document the new field", "conservative_choice": "Added a row to the existing Field Definitions table and a cross-reference link, matching the pattern already used for other optional fields", "requirement_ref": "R2.2", "lesson": ["Spec should name the exact table/section when a requirement asks to 'document' a field in an existing schema doc"], "timestamp": "2026-07-06T13:05:00Z"}
```

### Field Definitions

| Field | Type | Required | Description |
|---|---|---|---|
| `deviation` | string | yes | The ambiguity or under-specified requirement encountered. |
| `conservative_choice` | string | yes | The reasonable interpretation implemented instead. |
| `requirement_ref` | string | no | The requirement id this relates to, if applicable. |
| `lesson` | array of strings (1-3 entries) | yes | Takeaway(s) for whoever refines specs or plans next. |
| `timestamp` | string | yes | ISO 8601 timestamp of the append. |

### Constraints

- The log is **append-only during Step 4**: each deviation is written as its own line the moment it's encountered, never rewritten or truncated, so every line is independently parseable regardless of what comes after it.
- The log is **sealed at Step 8.5**: once `deviation_count` is computed, no further appends are permitted, even if later steps (Verify Local, Proof, Verify Full) surface more ambiguity. Deviations discovered after sealing belong in the task's failure/retry narrative, not this file.
- The file lives in the same gitignored, local-only results directory as `{task_id}.result.json` (`docs/specs/<run>/results/`) and is never committed.
- An absent or empty file is equivalent to zero deviations — workers must not create an empty file just to satisfy a presence check.
