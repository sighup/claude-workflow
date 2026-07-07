# Tests

Dependency-free bash test suite for the shippable content under `plugin/` —
the shell libraries, hook scripts, and the executable snippets embedded in
the cw-worktree reference docs.

## Running

```bash
tests/run.sh                        # everything
/bin/bash tests/doc-snippets.test.sh   # one file
CW_TEST_BASH=/opt/homebrew/bin/bash tests/run.sh   # alternate interpreter
```

No frameworks or installs required: the runner executes each `tests/*.test.sh`
under `/bin/bash` — deliberately, since macOS ships bash 3.2 and that is the
oldest interpreter the plugin's shell code and documented snippets must parse
under (bash 3.2 rejects `case` patterns inside `$( )` unless they use the
leading-paren form).

## Files

| File | Covers |
|---|---|
| `syntax.test.sh` | `bash -n` over every shell file under `plugin/` |
| `cw-worktree-names.test.sh` | `cw_worktree_names()`: type inference, keyword stripping, slug validation, repo sanitization |
| `provision-worktree.test.sh` | `provision_worktree()` end-to-end in throwaway git repos: branch/dir creation, settings.local.json, gitignore idempotency, existing-branch reuse, minimal mode, base refs, `.worktreeinclude` |
| `logging.test.sh` | `log_warning`/`log_error` route to stderr (both `scripts/lib` and `bin/lib` copies) |
| `doc-snippets.test.sh` | Worktree-lookup snippet extracted from the reference markdown and executed against a fixture repo; regression greps for space-unsafe awk, bash-3.2 case patterns, ORIG_HEAD rollback, namespaced permission rules |

## Conventions

- Test files source `helpers.sh` for `t`/`assert_*`/`make_repo` and must end
  with `finish`.
- Fixtures live in throwaway repos under `mktemp -d`; nothing touches this
  repository's own git state.
- Keep test code bash-3.2 compatible: no `mapfile`, no associative arrays,
  no `${var,,}`.
