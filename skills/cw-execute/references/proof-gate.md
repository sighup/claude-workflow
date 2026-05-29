# Input-Keyed Proof Gate Reference

The producer of a task is an untrusted data plane: its self-reported PASS is narration, not evidence. A **separate gate** re-executes the durable `proof_artifacts` in a fresh shell and decides PASS/FAIL itself. Never read the producer's `proof_results[].status` as ground truth — re-run the underlying command.

This gate runs after Step 8 (commit) and before the task is treated as done — by the re-verifying caller (`cw-loop`, `cw-validate`), not by the worker that wrote the proofs.

## Why a separate gate

A worker can mark a proof PASS without running it, run it against stale code, or rationalize a partial result. Re-execution from the committed tree closes all three: it is the only signal that survives a lying or confused producer.

## Input hash (stamp on every proof)

Stamp each proof artifact with a content hash of its **true input set** — everything whose change should invalidate the proof:

- the proof command string (exact text from the artifact's `command`/`url`/`path`+`contains`)
- the git blob SHA of every file in `metadata.scope.files_to_create` + `files_to_modify`

Compute over the committed tree, not the working copy, so the hash is reproducible on re-entry:

```bash
# blob SHAs for scope files (deterministic order), plus the proof command, hashed together
proof_input_hash() {
  local cmd="$1"; shift  # the proof command/url/path string
  { for f in $(printf '%s\n' "$@" | LC_ALL=C sort); do
      git rev-parse "HEAD:$f" 2>/dev/null || echo "MISSING:$f"
    done
    printf '%s\n' "$cmd"
  } | git hash-object --stdin
}
```

Record it in the proof header and in `proof_results`:

```
PROOF ARTIFACT: test
Command: npm test -- src/auth/login.test.ts
Input-Hash: 3f2a9c1...
Timestamp: 2026-01-24T15:30:00Z
```

A scope file with no git blob (uncommitted/deleted) hashes as `MISSING:<path>` — a distinct, intentional hash so the proof is forced to re-run rather than silently matching.

## Re-entry rule

On re-entry (crash-safe resume, re-validation, re-dispatch), for each proof:

| Condition | Action |
|-----------|--------|
| Recomputed input hash == stamped hash | **Skip** — inputs unchanged, prior PASS still valid |
| Hash differs (scope edited or command changed) | **Force re-exec** — stale proof, do not trust it |
| No stamped hash present | **Force re-exec** — treat as unverified |

Skip applies only to a recorded **PASS** at a matching hash. A recorded FAIL/BLOCKED always re-executes regardless of hash. The gate verdict is the re-execution result, never the stored status.

## Attestation escape hatch

Some proofs cannot be re-executed by the gate: `browser`/visual proofs that need a live UI, or any artifact whose `proof_capture.visual_method` is `manual`. For these, the gate accepts a recorded **attestation** in place of re-execution:

```
PROOF ARTIFACT: browser
Attested-By: human | <tool-name>
Input-Hash: 3f2a9c1...
Timestamp: ...
Status: PASS
```

Rules:
- An attestation is valid only while its input hash matches. Hash change invalidates it → re-attest.
- The escape hatch is **only** for genuinely non-automatable proofs. If the gate can run the command, it must — an attestation never substitutes for an automatable `test`/`cli`/`url`/`file` proof.

## Test-rerun cost guard

Re-execution is the cost the gate pays for trust; the input hash is what keeps that cost bounded. Spend it deliberately:

- The hash-match skip already suppresses re-runs when nothing changed — this is the primary guard.
- Re-run only the **task's own** proof artifacts (1–3 commands), never the full suite — the full suite belongs to `verification.post`.
- Wrap re-execution in `timeout` so a hung proof cannot stall the gate.
- When many tasks re-enter at once, the gate may re-run proofs in parallel up to the run's concurrency cap; an unchanged hash short-circuits before any process spawns.
