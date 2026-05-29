# Quorum Verification Reference

The shared agreement vocabulary for every cw verification stage — `cw-validate`, `cw-review`, `cw-review-team`, `cw-testing`. One vocabulary so a finding is scored the same way no matter which gate raises it.

> **The orchestrator is a control plane; agents are an untrusted data plane. A verifier's vote is a data-plane signal — count votes, never trust a single self-report.**

## The Five Rules

### 1. Abstain ≠ pass

A verifier that did not run, errored, timed out, or returned no opinion **abstains**. An abstention is silence, not approval. Never count an abstention as a PASS or as agreement. A gate with only abstentions is `Unknown`, never `Verified` — the same rule as `cw-validate` GATE B (no `Unknown` entries allowed for functional requirements).

### 2. Majority-refute veto

A finding **survives by default**. It is dismissed only when a **majority of independent verifiers actively refute it** — at least 2 of 3.

| Refuting votes (of 3 present) | Outcome |
|---|---|
| 0–1 refute | Finding **stands** (survives) |
| ≥2 refute | Finding **dismissed** (vetoed) |

Refuting means a verifier supplies counter-evidence (a specific code reference showing the finding is wrong or overstated), not merely declining to corroborate. A non-response is an abstention (rule 1), not a refutation.

> **Direction matters.** The conservative default for a verification pipeline is to *keep* a candidate defect unless the team affirmatively clears it. A lone challenge must not weaken a finding — only a refuting majority can. This is the inverse of "more challenges = weaker finding."

### 3. Multi-gate AND

Independent gates compose with **AND**, never OR. A diff passes only if **every** required gate passes. One gate's PASS does not offset another's FAIL. This mirrors `cw-validate`'s seven mandatory gates: any single FAIL fails the run. Decorrelate the lenses (security, correctness, spec) so a defect one lens misses another can still catch — correlated verifiers collapse the AND into a single point of failure.

### 4. Bounded-abstention escape

Quorum must not deadlock on a flaky verifier. **2 of 3 present is enough** to decide a finding under rules 1–2; the third may abstain.

- **2 present:** decide with the votes in hand (majority-refute needs both to refute to veto).
- **1 present:** the lone vote stands as provisional; flag the gate `partial` (as `cw-review-team` Step 6/7 already does), never silently `Verified`.
- **0 present:** the gate is `Unknown` — escalate, do not pass.

Autonomous `--bg` runs must keep moving: apply the escape, record which verifiers abstained, and let a human or `--force` override a `partial`/`Unknown` gate at an irreversible boundary (PR creation). The override is logged, never implicit.

### 5. Reserve full quorum for high blast radius

Full 3-verifier quorum costs latency and tokens. Spend it where a miss is expensive; degrade to fewer verifiers where it is cheap.

| Diff blast radius | Quorum |
|---|---|
| Auth, payments, data migrations, deletes, shared/core utilities, security-sensitive paths | Full 3-verifier quorum |
| Localized, low-risk, easily reverted changes | Single-verifier or inline check (rules 1–4 still apply to the votes present) |

Blast radius is a property of the diff (reach × reversibility), not its line count.

## Vocabulary Summary

| Term | Meaning |
|---|---|
| **PASS** | Verifier ran and found no blocking issue. |
| **REFUTE** | Verifier supplies counter-evidence against a finding. |
| **ABSTAIN** | Verifier did not run / errored / gave no opinion. Not a PASS, not a vote. |
| **STANDS** | Finding survives (0–1 refutes). |
| **VETOED** | Finding dismissed (≥2 refutes). |
| **partial** | Gate decided with < full quorum present; flagged for escalation. |
| **Unknown** | No present verifier; never treated as PASS. |
