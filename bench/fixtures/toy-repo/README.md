# toy-repo (eval-harness fixture)

A minimal synthetic git-able repo used to prove `bench/run_instance.sh` end to
end **offline**. It is not a real SWE-bench instance and contains no real
credentials or code under test.

Contents:

- `failing_test.sh` — the designated ground-truth test file. It intentionally
  fails (exit 1), standing in for an unresolved instance a real agent would fix.
  `run_instance.sh` checksum-guards this file: an agent that edits it to force a
  pass is flagged `FAILED: test-tampering`.
- `README.md` — this file; the stub agent makes its harmless (non-test) edit
  here for the happy-path proof.

`run_instance.sh` copies this directory into a throwaway working tree, so
running a proof never mutates the fixture itself.
