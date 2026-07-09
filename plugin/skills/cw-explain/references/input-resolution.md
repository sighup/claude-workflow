# Input Resolution

How `/cw-explain` arguments map to a diff source. Evaluate the rules top-down; first match wins.

## Resolution Rules

| Priority | Argument shape | Mode | Commands |
|----------|---------------|------|----------|
| 1 | Natural language mentioning uncommitted / working-tree / unstaged changes | **Uncommitted** | `git diff HEAD` (staged + unstaged) |
| 2 | Pure number (`42`, `#42`) | **Pull request** | `gh pr diff 42` for the diff, `gh pr view 42 --json title,body,baseRefName` for context |
| 3 | Contains `..` or `...` (`abc123..def456`, `main...feature-x`) | **Range** | `git diff <range>` verbatim (`..` and `...` semantics preserved as given) |
| 4 | A ref that resolves via `git rev-parse --verify <ref>` | **Ref** | Current branch → `git diff main...HEAD`; any other ref → `git diff main...<ref>` |
| 5 | No argument (or only a topic phrase / "no quiz") | **Branch (default)** | `git diff main...HEAD` |

Notes:

- Detect the base branch rather than hardcoding `main`: use `git symbolic-ref refs/remotes/origin/HEAD` when available, falling back to `main`.
- A topic phrase that isn't a ref (e.g. `/cw-explain the auth changes`) is not an input selector — it's guidance for emphasis within the default branch mode.
- "no quiz" / "skip the quiz" composes with any mode; it never affects resolution.

## Per-Mode Details

### Pull request

- Requires `gh`. If `gh` is missing or unauthenticated, report exactly what's missing and suggest the range form as a fallback — do not crash, do not guess.
- If the PR doesn't exist, report the `gh` error verbatim.
- Use the PR title/body as seed context for the header and Background; the base branch from `baseRefName` replaces `main` in any supplementary local diff commands.

### Uncommitted

- `git diff HEAD` covers staged and unstaged. If the working tree is clean, exit early: "Working tree is clean — nothing to explain."
- Untracked files aren't in the diff; list them in the header as "new untracked files (not diffed)" when present.

### Range / Ref

- Validate before use: `git rev-parse --verify` each endpoint; on failure report which ref is invalid.
- For a non-HEAD ref, the comparison is `main...<ref>` (what that branch adds relative to base), not `<ref>...HEAD`.

### Branch (default)

- `git diff main...HEAD` with the cw-review idiom: `--stat` for size, `--name-only` for the file list, per-file diffs for the walkthrough.
- Empty diff (fresh branch, or already merged): exit early, stating the branch and base compared.

## Error-Handling Principles

- Every failure path produces a one-line diagnosis plus the suggested next invocation — never a stack trace, never a silent fallback to a different mode.
- Mode is always reported in the completion block so the reader knows exactly what was explained.
