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

Run these checks and make them pass: <verification.pre>
Do NOT run any git commands — .git is read-only in your sandbox. Leave all changes
uncommitted in the working tree; the invoking agent verifies and commits them.

Write a short report of what you changed and why to: <RESULTS_DIR>/<task_id>-codex-report.md
```

Codex cannot commit: the `workspace-write` sandbox keeps `.git` read-only (verified on
codex-cli 0.144.0 — `index.lock` creation is denied). The wrapper always makes the commit,
after verification. This is the trust boundary working as intended: the external engine
authors content; it never writes history.

### Trust Boundary

**Codex output is untrusted evidence.** The wrapper never relays codex's self-report as
completion proof. After every `codex exec` the wrapper itself must:

1. Inspect the working tree (`git status --porcelain`, `git diff --stat`): changes exist and
   touch only files within the assignment's scope. Codex leaves everything uncommitted.
2. Run `verification.post` commands and capture their output as proof artifacts.
3. Sanitize the diff and all artifacts (credential scan) before committing — same sanitize
   bar as cw-execute.
4. **Commit the changes itself**: one atomic commit using exactly the assignment's commit
   template. The commit is always wrapper-made (see sandbox note above); the *content* is
   what determines `model_used`.
5. Write the result journal from its own observations, never from codex's claims.

If codex produced nothing, a scope violation, or failing verification: `git stash` the
damage, retry once with a corrected prompt naming the specific failure, then fall back to
executing the task via cw-execute.

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

`model_used` records **who authored the accepted implementation**, not who ran `git commit`
(the wrapper always commits): the assignment's model value verbatim (e.g. `"gpt-5.6-sol"`)
when codex authored the changes that passed verification, or the wrapper's own model (e.g.
`"sonnet"`) plus `fallback_reason` (`"codex-cli-missing"` | `"codex-exec-failed"`) when the
wrapper had to implement the task itself. The dispatcher applies these fields verbatim at
harvest. Spawn labels use the model value as prefix (`gpt-5.6-sol:`) — the platform UI shows
the wrapper's Claude model, so the label is the only visible indication the real worker is
codex.
