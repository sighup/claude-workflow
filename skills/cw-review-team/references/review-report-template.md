# Review Report Template

## Contents
- Markdown template
- Field guidance

## Markdown template

```markdown
# Code Review Report

**Reviewed**: [ISO timestamp]
**Branch**: [branch name]
**Base**: main
**Commits**: [count] commits, [files changed] files
**Overall**: APPROVED | CHANGES REQUESTED

## Summary

- **Blocking Issues**: X (A: Y correctness, B: Z security, C: W spec compliance)
- **Advisory Notes**: X
- **Files Reviewed**: X / Y changed files
- **FIX Tasks Created**: [list of task IDs]

## Review Methodology

**Approach**: Concern-partitioned team review
**Reviewers**: 3 specialized agents

| Reviewer | Concern | Primary Category | Status |
|----------|---------|------------------|--------|
| security-reviewer | Security | B | Completed / Partial |
| correctness-reviewer | Correctness | A | Completed / Partial |
| spec-reviewer | Spec Compliance | C + D | Completed / Partial |

**Challenge Round**: [Triggered / Not triggered (< 3 blocking findings)]
[If triggered: N findings reviewed, M challenged, K additions]

## Blocking Issues

### [ISSUE-1] [Category A/B/C]: [Title]
- **File**: `path/to/file.ts:42`
- **Severity**: Blocking
- **Concern**: [Primary reviewer who found it]
- **Description**: [What is wrong]
- **Fix**: [What to do]
- **Task**: FIX-REVIEW-[id]
[If challenged: **Challenge Status**: Upheld / Downgraded]

### [ISSUE-2] ...

## Advisory Notes

### [NOTE-1] [Category D]: [Title]
- **File**: `path/to/file.ts:88`
- **Description**: [Observation]
- **Suggestion**: [Optional improvement]

## Files Reviewed

| File | Status | Issues |
|------|--------|--------|
| `src/auth/login.ts` | Modified | 1 blocking |
| `src/utils/hash.ts` | New | Clean |
| `tests/auth.test.ts` | Modified | (not reviewed - test code) |

## Checklist

- [ ] No hardcoded credentials or secrets
- [ ] Error handling at system boundaries
- [ ] Input validation on user-facing endpoints
- [ ] Changes match spec requirements
- [ ] Follows repository patterns and conventions
- [ ] No obvious performance regressions
```

## Field guidance

- **Overall**: `APPROVED` if zero blocking issues this round; `CHANGES REQUESTED` otherwise
- **Files Reviewed**: count only non-test files (tests are the oracle, not under review)
- **FIX Tasks Created**: list every `FIX-REVIEW:` task ID created in Step 10
- **Challenge Round**: only triggers when `blocking >= 3` — see `reviewer-team-protocol.md` for the protocol
