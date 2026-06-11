# Dispatch Common Reference

Shared protocols for `cw-dispatch` and `cw-dispatch-team`.

## Nested Sub-Agents

Workers may spawn children of their own (reviewer fan-out, implementer proof-verifier). All nesting policy — depth, fan-out caps, board-mirroring, upward relay, model pinning — is defined in [nesting-guardrails.md](nesting-guardrails.md); consult it rather than restating it.

## Serialize Task-Tool Calls

Never combine a task write (`TaskUpdate`, `TaskCreate`) with a task read (`TaskList`, `TaskGet`) for the same task list in one parallel tool batch — issue them in separate messages, write first. A concurrent write+read can race the task store and wipe every task file on the board. If a TaskList result contradicts a TaskUpdate you just made (stale status), STOP issuing task calls and re-read with TaskGet before continuing — that staleness is the precursor to the wipe.

## Single-Writer Discipline

The native task store wipes or drops task state when two or more processes sharing one `CLAUDE_CODE_TASK_LIST_ID` issue task-tool calls at overlapping times. The execute phase removes that trigger: **only the dispatcher (this orchestrator) ever issues task-tool writes.** Workers carry their assignment inline, hold no Task tools, and hand off through a committed implementation plus a per-task journal — `{task_id}.result.json` in the run's gitignored `docs/specs/<run>/results/` — and a `CW-RESULT-BLOCK` sentinel in their final message. You harvest that evidence and apply every `TaskUpdate` yourself, serially, under a cross-process writer lease.

Two rules make this safe:

- **Lease before any board write.** Hold the writer lease across the whole run so no second dispatcher, resumed session, or backstop guard writes concurrently.
- **Serial, never burst.** Apply one `TaskUpdate` per message, write a harvest-checkpoint line before each and read it back with `TaskGet` after each. A burst of reconcile writes is the proven wipe trigger.

### Writer Lease Lifecycle

The lease is `scripts/cw-lease.sh` — an atomic `mkdir`-based lease at `~/.claude/tasks/<list-id>.writer` holding `pid+host+heartbeat+phase`, reclaimable only once its heartbeat exceeds the TTL. `<list-id>` is `CLAUDE_CODE_TASK_LIST_ID`. Invoke it via `"$CLAUDE_PLUGIN_ROOT/scripts/cw-lease.sh"`.

1. **Export a stable owner id once, before acquiring**:
   ```bash
   export CW_LEASE_PID=$$
   ```
   The lease records ownership as `CW_LEASE_PID` + host. Exporting a stable value (your shell pid) lets a later `refresh`/`release` — even from a separate CLI invocation the orchestrator drives — still match the holder. Without it, each invocation defaults to its own `$$` and cannot refresh or release a lease an earlier invocation took.

2. **Acquire before the first board write** (Step 3 ownership writes), acquire-or-wait:
   ```bash
   "$CLAUDE_PLUGIN_ROOT/scripts/cw-lease.sh" acquire "$CLAUDE_CODE_TASK_LIST_ID" --phase dispatch
   ```
   `acquire` blocks until the lease is free or reclaimable, then takes it — it **never proceeds-with-warning**. Issue no `TaskUpdate`/`TaskCreate` until it returns success. A second dispatcher or resumed session waits here rather than racing you.

3. **Refresh each loop** (Step 5), so the heartbeat advances and the lease is never mistaken for stale while you still hold it:
   ```bash
   "$CLAUDE_PLUGIN_ROOT/scripts/cw-lease.sh" refresh "$CLAUDE_CODE_TASK_LIST_ID"
   ```
   `refresh` fails if you are not the holder — if it does, stop writing and re-check `status`; another writer holds the lease and your single-writer assumption is broken.

4. **Release at loop exit** — every termination path, including the early exits in [Survey Task Board](#survey-task-board):
   ```bash
   "$CLAUDE_PLUGIN_ROOT/scripts/cw-lease.sh" release "$CLAUDE_CODE_TASK_LIST_ID"
   ```
   Release is idempotent and owner-checked. A leaked live lease blocks the next writer until its TTL expires, so always release.

The slimmed backstop guard runs mirror/log-only while any writer lease is held, so guard and orchestrator are coordinated writers, never independent ones.

### Harvest-and-Apply

Workers never mark themselves done. After each batch joins, resolve each joined `task_id`'s outcome from durable evidence and apply the completion yourself. Run this for every task in the batch.

**1. Resolve the outcome by evidence order** (first hit wins):

1. **RESULT BLOCK** — scan the worker's final message from the first `CW-RESULT-BLOCK-START` line to the matching `CW-RESULT-BLOCK-END` and parse the enclosed JSON. Highest precedence. If it fails to parse, lacks required fields, or has `status != "completed"`, fall through.
2. **`{task_id}.result.json`** — read the journal from `docs/specs/<run>/results/{task_id}.result.json`. The block and journal carry identical fields; the journal is the fallback when the worker died before emitting a final message.
3. **Proof-dir scan by `task_id`** — when neither journal nor block exists, scan the proof dir for `{task_id}-*` artifacts and reconstruct `proof_results` (type + pass/fail + filename) from them plus the `{task_id}-proofs.md` summary. The `commit_sha` is then the worker's implementation commit found in `git log`.

A `task_id` with no RESULT BLOCK, no journal, and no proofs has **no completion evidence** — do not mark it completed. It is re-dispatched on a later loop (re-dispatch and dead-worker handling are covered separately under [Error Handling](#error-handling)).

**2. Verify the commit sha is reachable in git** (mandatory — the sha is the only commit-to-task link, since commits carry no metadata trailers):

```bash
git cat-file -e "${commit_sha}^{commit}" 2>/dev/null && \
  git merge-base --is-ancestor "$commit_sha" HEAD
```

The sha must both exist as a commit **and** be reachable from `HEAD` (not reverted, not from a stale prior run). If verification fails, **do not mark the task completed** — log the sha verification failure for that `task_id` and leave it for re-dispatch. A `result.json` carried over from a previous run referencing a vanished or unreachable sha is rejected here.

**3. Apply ONE `TaskUpdate` at a time** — never a batch. For each task whose evidence verified:

a. **Write a harvest-checkpoint line first.** Append the `task_id` to the run's harvest-checkpoint file under the results dir, before the board write:
   ```bash
   echo "$task_id" >> "docs/specs/<run>/results/harvest-checkpoint.log"
   ```
   A session interrupted mid-harvest reads this file on resume and skips already-applied `task_id`s, so a completion is never applied twice and the harvest is restartable. (The checkpoint records intent before the write; a read-back that shows the task already completed confirms the prior write landed.)

b. **Apply the single completion**, resolving the live native id for the `task_id` at write time (never cross-reference a cached native id — re-creation reassigns them):
   ```
   TaskUpdate({
     taskId: "<live native id for this task_id>",
     status: "completed",
     metadata: {
       proof_dir, proof_results, proof_summary,
       commit_sha, completed_at,
       verifier_verdict, verifier_tokens, verification_mode,
       model_used
     }
   })
   ```
   Populate `metadata` from the resolved evidence record (the RESULT BLOCK / journal fields).

c. **Read back with `TaskGet` after** — in a separate message, never batched with the write:
   ```
   TaskGet({ taskId: "<live native id>" })
   ```
   Confirm `status: "completed"`. If the read-back contradicts the write you just applied, the store dropped it (or you read a stale snapshot) — stop bursting, re-read, and re-apply that single write before moving to the next task. This per-task write→checkpoint→read-back cadence is what keeps the reconcile off the burst path that wipes the board.

Apply tasks one at a time through (a)–(c) before starting the next. A batch of completions issued together is exactly the multi-write burst this discipline exists to prevent.

## Progress Heartbeat

Completions land at batch-join, not the instant a worker finishes — without a heartbeat the board shows nothing between dispatch and harvest. To close that observability lag, **at each monitor poll the orchestrator applies a metadata-only progress heartbeat for any task whose worker produced a new journal or proof artifact since the last poll.** The heartbeat advances visibility; it never advances status.

Three invariants make a heartbeat safe to interleave with harvest:

- **Metadata-only, never a status change.** A heartbeat writes `metadata.progress: <stage>` (and a `progress_at` timestamp). It **never** sets `status`. Status transitions to `completed`/`pending` remain **exclusively harvest-time** ([Harvest-and-Apply](#harvest-and-apply)) — the board may lag the work, but it never shows a false `completed`/`pending` state a heartbeat invented.
- **Sole-writer, serial.** The heartbeat is a board write, so it obeys the same [Single-Writer Discipline](#single-writer-discipline) as every other write: only the orchestrator issues it, under the held writer lease, one `TaskUpdate` per message, never batched with a read or with another write. A burst of heartbeats is the same wipe trigger as a burst of completions.
- **Idempotent.** A heartbeat carries no state the next poll cannot recompute — re-applying the same `progress` stage for the same artifact set is a no-op in effect. A dropped heartbeat write costs nothing; the next poll re-derives the stage from the same on-disk artifacts and re-applies it. Because it touches only metadata, a heartbeat can never race a completion into an inconsistent status.

**Detect fresh artifacts (per in-progress task, each poll):** compare the current mtime of the task's newest journal/proof artifact against the mtime recorded at the previous poll (track per `task_id` in your loop state).

1. `{task_id}.result.json` newer than last poll → stage `journal-written`.
2. Otherwise the newest `{task_id}-*.txt` / `{task_id}-proofs.md` in the proof dir newer than last poll → stage `proofs:<artifact-name>`.
3. No artifact newer than last poll → no heartbeat for this task this poll.

**Apply (sole-writer, serial — one per message):**
```
TaskUpdate({
  taskId: "<live native id for this task_id>",
  metadata: { progress: "<stage>", progress_at: "<ISO timestamp>" }
})
```
No `status` field. Resolve the live native id at write time (never a cached id). Apply heartbeats one task at a time; do not batch them and do not combine a heartbeat with the harvest completion write — a `task_id` whose artifacts indicate it is *done* this poll is handled by [Harvest-and-Apply](#harvest-and-apply) (a status write), not by a heartbeat. Heartbeats are only for tasks still in-flight whose evidence has advanced but is not yet complete.

## Mandatory First Action

**Call TaskList() immediately before any other action.**

```
TaskList()
```

### Report Raw Task Counts

After TaskList() returns, you MUST report the exact counts before any other analysis:

```
TASK BOARD STATUS
=================
Total tasks:    [exact number from TaskList]
Completed:      [count where status=completed]
Pending:        [count where status=pending]
  - Unblocked:  [pending with no blockedBy or all blockedBy completed]
  - Blocked:    [pending with incomplete blockedBy]
In Progress:    [count where status=in_progress]
```

**CRITICAL VERIFICATION**:
- ONLY claim "No tasks to dispatch" if the "Pending Unblocked" count is **literally 0**
- If TaskList returns actual task data, you MUST process it - do not skip to completion
- If you see task IDs (T01, T02, etc.) in TaskList output, tasks exist - analyze them
- NEVER fabricate completion reports - only report what TaskList actually returned

## Survey Task Board

```
TaskList()
```

**You MUST have already reported the raw task counts (see Mandatory First Action).**

Categorize tasks:
- **Ready**: status=pending, no blockedBy (or all blockedBy completed)
- **Blocked**: has incomplete blockedBy dependencies
- **In Progress**: already assigned to a worker
- **Completed**: done

**Exit decisions never rest on board counts alone.** Every condition below that would stop the loop or treat the board as empty is a *candidate* exit — it must clear the [Manifest-Authoritative Exit Gate](#manifest-authoritative-exit-gate) before you act on it. The gate decides whether an empty or thin board means "done" or "wiped."

**Candidate exit conditions (each routes through the gate):**
- TaskList returns "No tasks found" (empty board): a candidate exit — but with a manifest holding uncompleted `task_id`s this is a **wipe signal**, not "no tasks." Route to the gate → reconcile, never exit.
- Ready count = 0 but Blocked > 0: candidate "waiting on dependencies" — route to the gate; a blocker that vanished from the board while the manifest still expects it is a wipe holding the dependent Blocked, not a real wait.
- Ready count = 0 and Pending = 0: candidate "all tasks completed" — route to the gate; exit only once the gate confirms journal/proof evidence for **every** manifest `task_id`.

**ANTI-HALLUCINATION CHECK**: Before exiting, verify your exit reason matches the counts you reported above. If you claimed "Pending Unblocked: 32" but are about to say "no tasks", STOP and re-read TaskList output.

## Manifest-Authoritative Exit Gate

The board is a convergent view that the native store can silently wipe mid-run; the planner's manifest is the loss oracle that cannot. **The dispatcher never exits on board counts alone.** Every candidate exit from [Survey Task Board](#survey-task-board) and the [Pre-Exit Verification](#pre-exit-verification) routes through this gate. The gate's job is to tell "the run is genuinely done" apart from "the board was wiped and looks done."

### Step A — Load the manifest and segments

Read `~/.claude/tasks/.manifest/<list-id>/manifest.json` (`<list-id>` is `CLAUDE_CODE_TASK_LIST_ID`). Three outcomes determine which branch of the gate applies:

- **Manifest present, `partial: false`** → authoritative. Its `tasks[]` (each a stable `task_id` + `blockedBy[]` + full `metadata`) is the canonical task set. Proceed to Step B.
- **Manifest present, `partial: true`** → advisory only (an interrupted plan). Use it as a hint for reconcile but do not block exit on its completeness; fall through to the absent-manifest path for the exit decision.
- **Manifest absent** → **legacy / absent-manifest fallback.** No cross-check is possible, so exit reverts to the current count-based behavior: the candidate exit conditions in Survey Task Board apply as written (empty board = "no tasks", `Ready=0 ∧ Pending=0` = "all complete"). Before accepting an absent-manifest run, perform the one-time [synth-manifest-from-board](#synth-manifest-from-board) step so subsequent loops gain the gate. Document in the report that this run has **reduced coverage** — the gate cannot detect a wipe that predates the synth.

The absent-manifest case is **explicitly distinct** from a manifest that is present but projects to an empty/thin board. The former is legacy with no oracle (count-based exit allowed); the latter is **suspicious — a wipe — and must reconcile, never exit.** Never collapse the two.

**Dynamic manifest segments** — after reading the core manifest, also read any dynamic segments appended mid-run:

```bash
MANIFEST_DIR=~/.claude/tasks/.manifest/"$CLAUDE_CODE_TASK_LIST_ID"
# Read segment lines (each line is one JSON object)
FIX_SEGMENT_IDS=$(jq -r '.task_id' "$MANIFEST_DIR/manifest.fix.jsonl" 2>/dev/null || true)
TEST_SEGMENT_IDS=$(jq -r '.task_id' "$MANIFEST_DIR/manifest.test.jsonl" 2>/dev/null || true)
```

The **complete task set** for this gate is the union of the core manifest's `task_id`s and every `task_id` in both segment files. Segments grow append-only during the run; a segment file absent or empty contributes zero additional ids. Step B and Step D apply to this union set, not to the core manifest alone.

### Step B — Project the board against the full task set

For each `task_id` in the union of core manifest + segments, classify it by evidence, not by board status:

1. **Evidence-complete** — a sha-verified `{task_id}.result.json` exists (`commit_sha` reachable in git via `git cat-file -e <sha>^{commit}` and `git merge-base --is-ancestor <sha> HEAD`), **or** the proof dir holds `{task_id}-proofs.md` plus at least one `{task_id}-*.txt` with a reconstructable, git-reachable implementation commit. This is the same evidence order as [Harvest-and-Apply](#harvest-and-apply).
2. **Present-incomplete** — the `task_id` is on the live board (pending/in_progress) with no completion evidence. Normal in-flight work; the loop keeps dispatching it.
3. **Missing** — the manifest expects the `task_id` but it is **absent from the live board** and has **no** completion evidence on disk. This is the wipe signature.

**Wipe signal:** any `task_id` in class 3 — manifest-expected, board-absent, evidence-absent — means the store dropped task state. Do **not** exit. Trigger [Step C reconcile](#step-c--reconcile-never-burst). An empty or thin board while the manifest holds any class-2 or class-3 `task_id` is never "done."

**Segment open-task guard:** even when every core `task_id` is evidence-complete, the gate does **not** exit if the live board still shows any open (pending/in_progress) task whose subject begins with `FIX-REVIEW:` or `Test:` — a segment task that is on the board but not yet evidence-complete must finish before the run can exit. This prevents a mid-run segment append from being overtaken by the exit check.

### Step C — Reconcile (never burst)

Reconcile restores missing `task_id`s before any exit decision. **Prefer filesystem restore first; re-create only what restore could not recover; never a write burst.**

1. **Disambiguate stale-read from real loss.** A `task_id` absent from one `TaskList` snapshot may be a stale per-process read, not a wipe. Before treating it as missing, confirm the loss on disk: `TaskGet` the manifest id directly and stat its `N.json` under `~/.claude/tasks/<list-id>/`. Only a `task_id` with no live native record **and** no on-disk task file is truly lost. Mere absence from one snapshot is not loss.

2. **Prefer the guard's filesystem restore.** The slimmed backstop guard mirrors the board and restores a wiped `N.json` from its shadow whenever no writer lease blocks it. Give it a chance before re-creating anything:
   - Check `~/.claude/tasks/.guard/incidents.log` for a recent restore entry for the list.
   - Wait one poll tick, then re-read `TaskList` (separate message). A class-3 `task_id` that reappears was restored by the guard — no re-creation needed.
   - The guard restores **existence**; the orchestrator/evidence owns **status**. A guard-restored task re-enters as its prior status and converges through normal harvest.

3. **Re-create still-missing tasks ONE at a time, from manifest metadata, with a read-back between each.** For each `task_id` the guard did not restore, apply a single `TaskCreate` from the manifest entry's verbatim `metadata`, then a `TaskGet` read-back before the next — never a burst. A burst of reconcile writes is the proven board-wipe trigger.

   a. Append a reconcile-intent line to the harvest-checkpoint file before the write: `echo "${task_id}:reconcile-recreate:$(date -u +%s)" >> "docs/specs/<run>/results/harvest-checkpoint.log"`.

   b. `TaskCreate` the task from `manifest.tasks[task_id].metadata`. **Resolve native ids at write time:** re-creation assigns a new native id — never reuse a cached one. Record the fresh `task_id → native_id` mapping for this loop.

   c. `TaskGet` read-back (separate message) to confirm the create landed. If it did not, re-apply that single create before moving on.

4. **Rewire edges from stable `task_id`, never native id.** After the missing tasks exist, re-apply `addBlockedBy` from each manifest entry's `blockedBy[]`, resolving every `task_id` to its **current** native id through the loop's mapping (re-created tasks hold new native ids; a cached native id is always wrong). A dependent stays Blocked until its manifest-declared blockers are evidence-complete — a vanished prerequisite never un-blocks its dependent. Apply these edge writes serially with the same checkpoint + read-back cadence.

After reconcile, **re-read `TaskList` and re-run the gate from Step B.** Exit is reconsidered only once no class-3 `task_id` remains.

### Step D — Evidence-gated exit

Exit is permitted **only** when every `task_id` in the full union set (core manifest + segments) is evidence-complete (class 1 from Step B) **and** the segment open-task guard passes: no open FIX-REVIEW or test task remains on the live board. Board status alone never satisfies the gate.

- **All `task_id`s evidence-complete and segment guard passes** → genuine completion. Exit with "All tasks completed (manifest-verified: N/N)". Release the lease per the loop-exit path.
- **Any `task_id` present-incomplete (class 2)** → work remains; continue the loop (this is a normal "still running" state, not an exit).
- **Any `task_id` missing (class 3)** → wipe; reconcile (Step C), never exit.
- **Segment open-task guard fails** (open FIX-REVIEW or test task on board) → work remains from a dynamic segment; continue the loop.

A blocked-only board (`Ready=0 ∧ Blocked>0`) exits as "waiting on dependencies" **only** if the gate confirms every blocker holding those dependents is a real manifest dependency that is itself either evidence-complete or legitimately in-flight — not a class-3 wipe masquerading as a dependency wait.

### Synth-Manifest-from-Board

When the gate activates on a pre-existing board that has no manifest (a run planned before manifests, or a board built by hand), synthesize one **once** so later loops gain wipe detection:

1. Read the live board: `TaskList`, then `TaskGet` per task.
2. Write `~/.claude/tasks/.manifest/<list-id>/manifest.json` from that read using the same shape the planner writes (one entry per task: stable `task_id` from `metadata.task_id`, `blockedBy[]` resolved to `task_id`s, full `metadata` verbatim, no native ids). Use the atomic temp-rename write.
3. Mark it advisory: this manifest reflects **current board state**, not the original plan — any task already lost before the synth is unrecoverable and invisible to it. Set `partial: false` (it is complete as a snapshot) but document in the report that the run has **reduced coverage**: the gate detects wipes from this point forward only.

A synthesized manifest is a board-state snapshot, never a substitute for a planner manifest. Pre-manifest boards get reduced, not full, coverage — state this explicitly wherever the run is reported.

## Identify Parallel Groups

Find tasks that can run simultaneously:
- No dependency between them (neither blocks the other)
- Don't modify the same files (check `metadata.scope.files_to_modify`)
- Are all status=pending with no active blockers

Example grouping:
```
Group 1: T01 (no deps), T04 (blocked by nothing relevant)
Group 2: T02 (blocked by T01) - must wait
Group 3: T03 (blocked by T02) - must wait
```

## Conflict Prevention

Before spawning or assigning, verify no file conflicts between parallel tasks:

```
For each pair of tasks (A, B) in the group:
  A_files = A.scope.files_to_create + A.scope.files_to_modify
  B_files = B.scope.files_to_create + B.scope.files_to_modify
  if intersection(A_files, B_files) is not empty:
    Remove B from group (execute sequentially after A)
```

## Pre-Exit Verification

Before outputting any completion or "no tasks" message, verify:

1. **Re-check your reported counts**: Look at the TASK BOARD STATUS you printed earlier
2. **Clear the Manifest-Authoritative Exit Gate**: route the candidate exit through the [gate](#manifest-authoritative-exit-gate). A completion or "no tasks" message is permitted **only** when the gate's evidence test passes:
   - **Manifest present**: every manifest `task_id` is evidence-complete (sha-verified `result.json` or a complete git-reachable proof set). An empty/thin board with any manifest `task_id` still missing or present-incomplete is a **wipe or in-flight state — reconcile or keep looping, never exit.** Board counts of zero never substitute for per-`task_id` evidence.
   - **Manifest absent (legacy)**: fall back to count-based matching — "no tasks to dispatch" requires Pending Unblocked = 0; "all complete" requires Pending = 0 AND In Progress = 0 — after the one-time [synth-manifest-from-board](#synth-manifest-from-board) step, and report the run as reduced-coverage.
3. **If the gate or the counts don't match your conclusion**: re-read TaskList output, reconcile if the manifest signals a wipe, and correct.

**WARNING**: If you find yourself writing a detailed "completion report" with stats like "151 proof artifacts" or "63 library files" that you did NOT just count from TaskList, you are hallucinating. STOP and re-run TaskList.

## Phase-End Cleanup

After the exit gate passes (every `task_id` evidence-complete, segment guard passes), retire run artifacts that are no longer needed. Run this step once, at the end of the run, before releasing the lease.

**What to retire:**

| Artifact | Location | Action |
|----------|----------|--------|
| Per-task result journals | `docs/specs/<run>/results/{task_id}.result.json` | Remove each file once its `task_id` is evidence-complete and the harvest-checkpoint confirms the completion write landed |
| Harvest-checkpoint log | `docs/specs/<run>/results/harvest-checkpoint.log` | Remove after all `task_id`s are confirmed complete |
| Writer lease | `~/.claude/tasks/<list-id>.writer` | Release via `cw-lease.sh release` — the last step before exit |
| Core manifest + segments | `~/.claude/tasks/.manifest/<list-id>/` | Remove the entire directory after exit gate passes and the lease is released |

**Order:** retire journals first (most granular), then the checkpoint, then release the lease, then remove the manifest directory. Removing the manifest before the lease is released would cause a concurrent session to fall into the absent-manifest path rather than the wipe-detection path — release the lease first.

**Do not remove proof directories** — proof artifacts under `docs/specs/<run>/[NN]-proofs/` are committed to git and belong to the implementation record. They are not run state.

**Partial cleanup (interrupted run):** if the run exits without completing all `task_id`s (timeout, manual stop), do **not** remove journals or manifests for uncompleted tasks. Those files are the harvest authority for the next session. Only completed tasks (checkpoint-confirmed) have their journals removed at that point.

```bash
# Remove a completed task's journal (run after harvest-checkpoint confirms the task)
rm -f "docs/specs/<run>/results/${TASK_ID}.result.json"

# Remove the checkpoint and manifest dir at full run completion
rm -f "docs/specs/<run>/results/harvest-checkpoint.log"
"$CLAUDE_PLUGIN_ROOT/scripts/cw-lease.sh" release "$CLAUDE_CODE_TASK_LIST_ID"
rm -rf ~/.claude/tasks/.manifest/"$CLAUDE_CODE_TASK_LIST_ID"
```

## Guard Sunset Gate

The slimmed backstop guard (`scripts/task-store-guard.sh`) and its SessionStart hook entry are retained until the single-writer discipline proves out in production. The sunset condition is:

**Remove the guard daemon and its SessionStart hook entry** when **both** of the following are true:
- 10 consecutive production runs have completed with an empty `incidents.log` (no guard-initiated restores, no wipe events), **and**
- 30 active days have elapsed with an empty `incidents.log`.

Both conditions must hold simultaneously — 10 clean runs reached before day 30 does not satisfy the gate; 30 days reached without 10 consecutive clean runs does not satisfy the gate. The condition that becomes true later is the binding one.

**Do not remove anything now.** This section documents the future sunset instruction only. The guard stays in place until the threshold above is met.

**How to evaluate:**
- Check `~/.claude/tasks/.guard/incidents.log` — an empty file (zero bytes or absent) signals no incidents for the current window.
- "Consecutive clean runs" resets to 0 on any run that produces a non-empty `incidents.log` entry.
- "Active days" counts calendar days on which at least one production dispatch run started, not wall-clock elapsed time.

**When the threshold is met:** remove `scripts/task-store-guard.sh`, remove the SessionStart hook entry in `.claude-plugin/plugin.json` that spawns the guard, and note the removal in the commit message.

## Post-Completion Synthesis

After all workers in a batch complete, **synthesize** their outputs before reporting. Your job is not to relay — it is to understand. Never delegate understanding.

### Integration Check

Read the completed tasks' metadata and git commits, then check for:

1. **Cross-worker imports**: Did Worker-1 create a type/module that Worker-2's code should reference? Check for missing imports or unresolved references.
   ```bash
   # Check for build/type errors that suggest integration gaps
   # Run the project's build command (from task verification.pre)
   ```

2. **Conflicting patterns**: Did workers use different conventions for the same concern? (e.g., different error handling styles, naming conventions, or API response shapes)
   ```bash
   # Review git log for the batch
   git log --oneline -N  # N = number of workers
   ```

3. **Missed connections**: New endpoints without route registration, new components without exports, new schemas without migration files.

4. **Scope leakage**: Files modified that weren't in any task's declared scope.

### When to Flag

- **CRITICAL**: Build/type errors after merging worker outputs → must fix before next batch
- **WARNING**: Pattern inconsistencies → note in report, let review catch details
- **INFO**: Minor integration observations → include in report for awareness

### Synthesis Output

Add to the dispatch completion report:

```
Integration Check:
  Build: PASS | FAIL [command output if failed]
  Cross-worker issues: [none | list of issues found]
  Pattern consistency: [consistent | list of divergences]
```

If the build fails after workers complete, attempt to fix obvious integration issues (missing imports, registration). If the fix is non-trivial, report it as a blocking issue.

## Error Handling

### Skip-if-Evidence (Idempotent Re-Dispatch)

Before dispatching any task — at every loop top, before assigning ownership — check whether durable completion evidence already exists for it. A task with verified evidence is completed-by-evidence and must not be re-dispatched.

**Check order** (first hit wins):
1. `{task_id}.result.json` exists at `docs/specs/<run>/results/{task_id}.result.json` and its `commit_sha` passes the git reachability check (`git cat-file -e` + `git merge-base --is-ancestor … HEAD`).
2. The proof dir contains `{task_id}-proofs.md` and at least one `{task_id}-*.txt` artifact — reconstruct the sha from `git log` (the worker's implementation commit) and verify it as above.

If evidence is found:
- Apply the completing `TaskUpdate` (same serial write→checkpoint→read-back cadence as Harvest-and-Apply) using the evidence record to populate metadata.
- Log `task_id: completed-by-evidence` to the harvest-checkpoint file.
- Do not spawn a worker. Do not re-assign ownership.

This makes re-dispatch safe: a task that was completed in a prior run, or whose completion write was dropped by the board, is recovered from on-disk evidence rather than repeated.

### Dead-Worker Reset

A worker that has been in-progress past the liveness timeout with no commit or journal evidence is treated as dead and its task is reset for re-dispatch.

**Liveness timeout**: 30 minutes from the recorded dispatch timestamp (stored in the task's metadata as `dispatched_at` when ownership is assigned in Step 3b).

**Detection** — during each monitor poll (Step 5), for every in-progress task evaluate:
1. Time elapsed since `dispatched_at` exceeds the liveness timeout.
2. No `{task_id}.result.json` exists under the results dir.
3. No proof artifacts (`{task_id}-proofs.md`) exist in the proof dir.
4. No implementation commit for the task is reachable in git (checked via `git log --oneline -- <scope files>`).

All four conditions together confirm a dead worker. A task missing only some evidence is in-flight, not dead — never reset until all four apply.

**Reset** (sole writer, serial):
```bash
# Record intent before the board write
echo "${task_id}:dead-worker-reset:$(date -u +%s)" >> "docs/specs/<run>/results/harvest-checkpoint.log"
```
```
TaskUpdate({
  taskId: "<live native id>",
  status: "pending",
  metadata: { dead_worker_reset: true, reset_at: "<ISO timestamp>", prior_owner: "<worker-N>" }
})
```
Follow with a `TaskGet` read-back to confirm the reset landed. The task re-enters the pending pool and is dispatched on the next loop. The skip-if-evidence check at that loop's top makes the re-dispatch safe — if the worker actually did finish and only the evidence was not yet visible, the check will find it and apply completed-by-evidence instead of spawning a new worker.

**Worker failure (non-timeout)**:
If a worker fails with a `failure_reason` in its metadata (or a FAIL in its RESULT BLOCK) but is not yet past the timeout:
1. Check task metadata for `failure_reason`.
2. If retryable: include in next dispatch round.
3. If permanent: report to user, skip task.
4. If `failure_count >= 3`: mark as blocked, require human intervention.

## Why Workers Must Invoke cw-execute

The `cw-execute` skill contains the 11-step protocol including:
- Step 10 (Report): Calls `TaskUpdate({ status: "completed" })` to mark tasks done
- Step 6 (Proof): Creates proof artifacts for validation
- Step 8 (Commit): Creates atomic commits with implementation + proofs

**If workers receive direct prompts instead of invoking cw-execute, the task board will NOT be updated and progress tracking breaks.**

## Spawning the Validator

When user selects validation, spawn the validator as a sub-agent to keep context isolated:

```
Task({
  subagent_type: "claude-workflow:validator",
  description: "Validate implementation against spec",
  prompt: "Run the cw-validate skill against the current task board. Relay the full validation summary including gate results and coverage matrix."
})
```

### Relaying Validation Results

**CRITICAL**: Sub-agent results are not automatically visible to users. After the validator completes, you MUST relay the validation summary to the user.

The validator will output a summary in this format:
```
VALIDATION COMPLETE
===================
Overall: PASS | FAIL
Gates: A[P/F] B[P/F] C[P/F] D[P/F] E[P/F] F[P/F]
...
```

Output this summary directly to the user, then:
- **If PASS**: Inform user implementation is ready for review/merge
- **If FAIL**: Show blocking issues and recommend running the dispatch skill again after fixes

## Recommended Quality Gate Order

After all tasks complete, the user can run quality gates in any order. When presenting options, recommend this sequence:

```
/cw-validate  →  /cw-testing  →  /cw-review  →  PR
```

**Why this order:**
1. **Validate first**: Catches workflow-level issues (missing proofs, scope violations, credential leaks) before investing time in E2E tests or code review. Fast and cheap.
2. **Test second**: E2E tests verify behavioral correctness against the spec. Catches application bugs that validation's static analysis can't.
3. **Review last**: Human-quality code review is most valuable after known bugs are fixed. Reviewers focus on design and maintainability rather than chasing test failures.

Each gate is optional — the user may skip any of them. But when offering next steps, present them in this order and mark the next recommended gate.
