# Codex Execution Reference (external models via Codex CLI)

How the `codex-implementer` wrapper agent drives the external Codex CLI engine, and how
`cw-review` invokes it as an independent review perspective. Command shapes verified against
`codex-cli 0.142.5` and `0.144.0` (including `-m/--model`).

The engine is model-agnostic: whatever value `metadata.model` carries (`gpt-5.5`, `gpt-5.6`,
any future model the rubric names) is passed straight through `codex exec -m`. Adding a new
external model touches only the model-selection rubric — never this doc's mechanics, the
wrapper, or the dispatchers. When no `-m` is given, codex uses the default in
`~/.codex/config.toml`.

**This capability is runtime-gated.** Nothing in the pipeline requires the codex CLI.
Every consumer runs the preflight first and degrades silently to the normal Claude path when
codex is absent — no error, no user prompt, identical evidence flow.

## Preflight Contract

Gate every codex invocation on the preflight script:

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/codex-preflight.sh"
```

- Exit 0 with `CODEX_OK <version>` on stdout → codex is installed and responsive; proceed.
- Exit 1 with `CODEX_MISSING` → fall back (execute via cw-execute on the wrapper's own model,
  or skip the review perspective). Record the fallback; never raise it as an error.

When `CLAUDE_PLUGIN_ROOT` is not set in your context, the equivalent inline gate is
`command -v codex >/dev/null 2>&1 && codex --version >/dev/null 2>&1`.

## Implementation Runs (`codex exec`)

Codex runs non-interactively with the prompt on stdin, sandboxed to the workspace plus the
results directory. `RESULTS_DIR` is the run's gitignored results directory
(`docs/specs/<run>/results/`); `TASK_ID` is the stable planner-assigned id; `CODEX_MODEL` is
the assignment's `metadata.model` value verbatim.

```bash
PROMPT_FILE="$RESULTS_DIR/${TASK_ID}-codex-prompt.md"
# write the self-contained prompt (template below) to "$PROMPT_FILE", then:
codex exec \
  -C "$PWD" \
  --add-dir "$RESULTS_DIR" \
  -s workspace-write \
  -m "${CODEX_MODEL:?set to the assignment model value}" \
  - < "$PROMPT_FILE"
```

Flag meanings: `-C` pins codex's working root to the repo; `--add-dir` grants write access to
the results directory for artifacts; `-s workspace-write` is the sandbox level (codex may edit
repo files and commit, nothing outside); `-m` selects the model (the assignment's value,
verbatim); `-` reads the prompt from stdin.

### Prompt Template (assignment → codex prompt)

The prompt must be fully self-contained — codex sees none of the Claude session's context.
Map the inlined assignment fields verbatim:

```text
You are implementing one bounded task in an existing repository.

Repository: <absolute repo root>
Task: <task_id> — <subject>

Requirements (implement ALL, nothing more):
- <requirement R-ID>: <text>
  ...

Scope (HARD limits):
- Files you may create: <scope.files_to_create>
- Files you may modify: <scope.files_to_modify>
- Follow the conventions in: <scope.patterns_to_follow>
- Do NOT touch any other file.

Before finishing, these must pass: <verification.pre>
Do NOT commit — leave all changes uncommitted in the working tree. (Your sandbox keeps
.git read-only; the wrapper reviews the diff and commits.) Do not push.

Write a short report of what you changed and why to: <RESULTS_DIR>/<task_id>-codex-report.md
```

### Trust Boundary

**Codex output is untrusted evidence, and codex never commits** — its `workspace-write`
sandbox keeps `.git` read-only by design (verified live on 0.144.0). The wrapper owns commit
responsibility, which means history only ever receives independently verified work. After
every `codex exec` the wrapper itself must:

1. Confirm the working tree holds the change (`git status --porcelain` non-empty) and that
   `git diff --stat` plus any untracked files touch only files within the assignment's scope.
2. Run `verification.post` commands and capture their output as proof artifacts.
3. Sanitize all artifacts and the diff (credential scan) — same sanitize bar as cw-execute.
4. **Commit the verified change itself**: ONE atomic commit using exactly the assignment's
   commit template.
5. Write the result journal itself from its own observations, never from codex's claims.

If codex produced no changes, a scope violation, or failing verification: `git stash` the
rejected working-tree changes, retry once with a corrected prompt naming the specific
failure, then fall back to executing the task via cw-execute.

## Review Runs (`codex review`)

For an independent second-opinion review (consumed by cw-review Step 2e):

```bash
codex review --uncommitted          # review the working tree changes
codex review --base <branch>        # review the diff against a base branch
codex review --commit <sha>         # review one commit
```

Save the raw output to the results dir (`<RESULTS_DIR>/codex-review.txt`). Findings from
codex are tagged `source: "gpt-5.5"` and are **advisory** unless corroborated by a Claude
reviewer or self-evidently blocking (e.g. a demonstrable credential leak).

## Reporting the Engine

`model_used` reports who **authored** the accepted change: the assignment's model value
verbatim (e.g. `"gpt-5.5"`, `"gpt-5.6-sol"`) when codex wrote it — the wrapper performing
the commit does not change authorship — or the wrapper's own model (e.g. `"sonnet"`) plus
`fallback_reason` (`"codex-cli-missing"` | `"codex-exec-failed"`) when it fell back and
implemented the task itself. The dispatcher applies
these fields verbatim at harvest. Spawn labels use the model value as prefix (`gpt-5.6:`) —
the platform UI shows the wrapper's Claude model, so the label is the only visible indication
the real worker is codex.
