# Starter Prompt Generation

Templates and delivery mechanics for the prompt that seeds a new worktree's first
claude session. Referenced from [SKILL.md](../SKILL.md) ("Starter Prompt
Generation") and [worktree-commands.md](worktree-commands.md) (`create` step 9).

When prior discussion gives you enough signal, **construct a starter prompt** to seed the new worktree's first claude session. After every feature has its `STARTER_PROMPT` (and, where applicable, `STARTER_PROMPT_GOAL`), the **Drive-Mode Selection** gate decides — once for the whole batch — what gets forwarded to each tab. When herdr is available the chosen prompt is forwarded via `cw-herdr-open --prompt`; when herdr is unavailable, step 11 prints it as a copy-paste block.

Classify the user's intent into one of three shapes:

**Research-mode** — the user said things like "look into X", "I want to understand Y", "let's research how Z works", or otherwise signaled they need to investigate before scoping. Construct:

```
/cw-research {topic derived from the discussion}
```

**Spec/build-mode** — the user identified concrete components, routes, APIs, or requirements. Construct:

```
Build {feature-name}.

{Brief description of what the feature does}

Components/files to create:
- {Component1}: {purpose}
- {Component2}: {purpose}

{Any routes, APIs, or patterns to follow}

Run: /cw-spec {feature-name}
```

**No starter prompt** — `STARTER_PROMPT=""`. Use this when:
- Bare `/cw-worktree create <name>` was issued without prior context.
- The user said they want to drive the new session themselves.
- Intent is ambiguous and a wrong guess would be worse than no guess.

The Drive-Mode Selection gate always offers an "Other" escape hatch so the user can edit a misclassified preset before it is forwarded.

## Autonomous variant (`STARTER_PROMPT_GOAL`)

Whenever `STARTER_PROMPT` is non-empty, **also** construct an autonomous variant `STARTER_PROMPT_GOAL`. This wraps the same intent in a `/goal`-prefixed directive that drives the full pipeline end-to-end (cw-research → cw-spec → cw-plan → cw-dispatch → cw-validate → cw-review → cw-testing). The Drive-Mode Selection gate surfaces this as the autonomous option so the user can promote the whole batch to hands-off execution without restating the request. `/goal` is a semantic marker, not a registered slash command — the spawned claude session reads it as plain text and follows the structured steps.

**Template — when base mode is Research-mode** (no spec exists, greenfield or large-unknown task):

```
/goal Pipeline complete for `{feature-name}`: research done, spec committed, plan executed, all non-test tasks have status `completed` (verified via TaskList), `cw-validate` passes, `cw-review` has no blocking issues, and `cw-testing` is green.

Workflow (research → spec → plan → dispatch → validate → review → testing):
1. Invoke `cw-research` with the topic below. It saves a report under `docs/specs/research-*/` and appends a Meta-Prompt section ready for `cw-spec`.
2. Without pausing for review, extract the meta-prompt from the research report and invoke `cw-spec` with it.
3. Commit the spec and research artifacts (`git add docs/specs && git commit -m "spec: {feature-name}"`).
4. Invoke `cw-plan` against the spec to populate this worktree's task list.
5. Use `cw-dispatch` to advance ready tasks until non-test tasks are complete.
6. Invoke `cw-validate`, then `cw-review`, then `cw-testing`. Treat their findings as new FIX tasks on the board and keep dispatching until the goal condition holds.

Topic: {topic derived from the discussion — same text as Research-mode STARTER_PROMPT, minus the `/cw-research` prefix}

Stop and report if three consecutive turns make no progress on task transitions.
```

**Template — when base mode is Spec/build-mode** (concrete build directive, no research needed):

```
/goal Pipeline complete for `{feature-name}`: spec committed, plan executed, all non-test tasks have status `completed` (verified via TaskList), `cw-validate` passes, `cw-review` has no blocking issues, and `cw-testing` is green.

Workflow (spec → plan → dispatch → validate → review → testing):
1. Invoke `cw-spec` with the build directive below as input.
2. Commit the spec (`git add docs/specs && git commit -m "spec: {feature-name}"`).
3. Invoke `cw-plan` against the spec to populate this worktree's task list.
4. Use `cw-dispatch` to advance ready tasks until non-test tasks are complete.
5. Invoke `cw-validate`, then `cw-review`, then `cw-testing`. Treat their findings as new FIX tasks on the board and keep dispatching until the goal condition holds.

Build directive:
{STARTER_PROMPT body without the trailing `Run: /cw-spec` line}

Stop and report if three consecutive turns make no progress on task transitions.
```

When `STARTER_PROMPT=""`, leave `STARTER_PROMPT_GOAL=""` too — without a topic or build directive there is nothing concrete to drive the goal toward.

## Delivery: committed goal file + inline forward

`STARTER_PROMPT_GOAL` is large (≈1.5–3 kB once filled in). Do **not** type it onto a command line — backticks, `$`, and quotes in the body would be interpreted, and a long single line is what truncated under herdr (the `quote>`-stuck pane bug). For `DRIVE_MODE=autonomous`, persist the goal to a committed file and forward it inline **from that file**, so the text is authored exactly once and never re-quoted:

1. Write the full `STARTER_PROMPT_GOAL` (the entire `/goal …` directive, placeholders already resolved) to `docs/specs/goal-${WORKTREE_DIR}.md` inside the worktree, using a **quoted** heredoc (`<<'CW_GOAL_EOF'`) so nothing in the body is expanded.
2. Forward it with `--prompt "$(cat <that file>)"` — double-quoted command substitution passes the exact bytes as a single argv. `cw-herdr-open` then routes it through its own temp file, keeping the typed pane command short regardless of length.

The file is a committed artifact (it lands in `docs/specs/`, which the autonomous pipeline already commits) and doubles as the human copy-paste source when herdr is unavailable (step 11). Name it after the worktree directory (`goal-${WORKTREE_DIR}.md`, e.g. `goal-feature-myrepo-auth.md`) so it never collides with spec files or other worktrees.

**Author the goal within its 4000-character budget — do not rely on truncation.** 4000 characters is the limit for a `/goal` directive, so *produce* the goal to fit: write `goal-${WORKTREE_DIR}.md` so its content is ≤ 4000 characters. The templates above land well under that once filled in; if a goal would run over, **condense it** (tighten steps, drop redundant prose) and rewrite — never let it overflow. After writing the file, verify with `wc -m "$GOAL_FILE"` and rewrite more tightly if it exceeds 4000. Nothing truncates the goal: the transport forwards it intact at any length, and the `--max-prompt-chars 4000` guard on the forward (step 9) only *rejects* a runaway (exit 2) — it never cuts the prompt — so the budget is enforced by how you write the goal, not by the tooling clipping it.

> **Why not `@docs/specs/goal-…md`?** Claude Code's `@`-file import only expands when typed **interactively** — not when the prompt is passed as claude's launch argument (which is how herdr injects it). So the goal is inlined in full rather than referenced by `@`. (`@` *does* expand on interactive paste, so the step-11 fallback can offer the short `@` form.)
