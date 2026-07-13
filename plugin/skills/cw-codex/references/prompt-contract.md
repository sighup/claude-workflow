# Codex Prompt Contract (assignment → codex prompt)

The prompt is codex's entire world — it sees none of the Claude session's context, the task
board, or the spec directory. Map the inlined assignment fields **verbatim**: every
requirement, every scope path, every verification command. Prompt like an operator, not a
collaborator: compact, block-structured with XML tags, one bounded task per run, done-state
stated explicitly. Prefer a tighter contract over more prose — do not pad with reasoning
nudges or restated context.

## Template

```text
You are implementing one bounded task in an existing repository.

Repository: <absolute repo root>
Task: <task_id> — <subject>

<task>
Requirements (implement ALL, nothing more):
- <requirement R-ID>: <text>
  ...
Done means: every requirement above is implemented and the verification commands pass.
</task>

<scope>
HARD limits:
- Files you may create: <scope.files_to_create>
- Files you may modify: <scope.files_to_modify>
- Follow the conventions in: <scope.patterns_to_follow>
- Do NOT touch any other file.
</scope>

<action_safety>
Keep changes tightly scoped to the requirements. No unrelated refactors, renames, or cleanup.
Do NOT commit — leave all changes uncommitted in the working tree. (Your sandbox keeps
.git read-only; the caller reviews the diff and commits.) Do not push.
</action_safety>

<completeness_contract>
Resolve the task fully before stopping. Do not stop at the first plausible implementation —
check edge cases and follow-on fixes needed for a correct result.
</completeness_contract>

<verification_loop>
Before finishing, these must pass: <verification.pre>
If a check fails, revise the change instead of reporting the first draft.
</verification_loop>

<grounding_rules>
Do not guess repository facts — read the files. If required context is genuinely absent,
state exactly what remains unknown in your report rather than inventing it.
</grounding_rules>

<compact_output_contract>
Write a short report of what you changed and why to: <RESULTS_DIR>/<task_id>-codex-report.md
Keep it compact: files touched, requirement → change mapping, verification results.
</compact_output_contract>
```

On a retry after a failed verification pass, keep the same template and add one line at the
top of `<task>` naming the specific failure (the failing command output or the scope
violation) — the delta, not a rewritten prompt.

## Assembly Checklist

1. `<task>` holds every requirement with its R-ID, verbatim, plus an explicit done-state.
2. `<scope>` lists the exact `files_to_create`/`files_to_modify`/`patterns_to_follow` paths.
3. `<action_safety>` carries the no-commit/no-push rule — never omit it.
4. `<verification_loop>` inlines the literal `verification.pre` commands.
5. All placeholder `<...>` fields are substituted — grep the prompt file for `<` leftovers.
6. Remove any block that restates another; redundancy dilutes the contract.

## Antipatterns

- **Vague framing** ("implement the task as discussed") — codex has no "discussed"; inline
  the requirements.
- **Missing output contract** — without the report path, codex's account of its work is
  lost and the caller verifies blind.
- **Asking for more effort instead of a better contract** ("be very thorough") — tighten
  `<verification_loop>` instead.
- **Mixing unrelated jobs** — one task per run; a second concern is a second dispatch.
- **Referencing session context** (task ids on the board, spec files not in scope, prior
  worker output) — codex cannot see any of it; either inline the content or drop the
  reference.
