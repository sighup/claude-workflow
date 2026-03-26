# Review Report Format

Shared template for review reports. Used by both `cw-review` and `cw-review-team` orchestrators. Adapt section headers based on what was actually found — don't include empty sections.

**Emoji format:** Always use Unicode emoji characters (🔴 🟠 🟡 💡), never GitHub shortcodes (`:red_circle:`, `:orange_circle:`). Shortcodes don't render in terminal/chat output.

---

## Full Report Template

```markdown
# Code Review Report

**Reviewed**: [ISO timestamp]
**Branch**: [branch name]
**Base**: [base branch]
**Commits**: [count] commits, [files changed] files, +[additions] / -[deletions]
**Overall**: [APPROVED | APPROVED WITH SUGGESTIONS | CHANGES REQUESTED]

---

## Change Summary

- **What changed:** [1-2 sentences describing the functional change]
- **Key files:** [list the 3-5 most important files changed, with one-line descriptions]
- **Patterns observed:** [e.g., "New API endpoints added", "Refactor of auth module"]

---

## Executive Summary

[2-3 sentences: what was reviewed, key finding themes, overall assessment.]

### Verdict

[One of: APPROVE | APPROVE WITH SUGGESTIONS | REQUEST CHANGES]

**Blocking issues:** [N] (critical + high-security — these trigger REQUEST CHANGES)
**Action items:** [N] (high + medium — should be addressed but not merge-blocking)
**Suggestions:** [N] (low)

---

## 🔴 Critical Issues

[Only findings with severity=critical and confidence>=80]

### [finding.id]: [finding.title]

**File:** `[file]:[line_start]`
**Dimension:** [dimension] | **Confidence:** [confidence]%
**Classification:** [New / Surfaced]
**Validation:** [Verified / Skipped]
**Challenge:** [Upheld / Contested / N/A]
**Flagged by:** [list of agents]

[description]

**Evidence:**
[evidence — the actual code snippet or behavior demonstrating the issue]

**Suggested fix:**
[suggestion]

**Task:** FIX-REVIEW-[id]

---

## 🟠 High-Priority Issues

[Same format as Critical, but with severity=high]

---

## 🟡 Medium Issues

| # | File | Issue | Dimension | Confidence |
|---|------|-------|-----------|------------|
| [id] | `[file]:[line]` | [title] | [dimension] | [confidence]% |

[For each, a brief 1-2 sentence description below the table]

---

## 💡 Low-Priority Suggestions

- **[id]**: `[file]:[line]` — [title] ([dimension], [confidence]%)

---

## Surfaced Findings

Pre-existing issues surfaced by this PR's changes. These were not introduced by this PR
but interact with it. Severity has been downgraded one level from the original classification.

| # | File | Issue | Dimension | Confidence | Originally from |
|---|------|-------|-----------|------------|-----------------|
| [id] | `[file]:[line]` | [title] | [dimension] | [confidence]% | [blame author, date] |

---

## Advisory Notes

[Category D findings: test-coverage, type-design, comments]

### [NOTE-1] [Category D]: [Title]
- **File**: `[file]:[line]`
- **Dimension**: [dimension]
- **Confidence**: [0-100]
- **Description**: [Observation]
- **Suggestion**: [Optional improvement]

---

## Files Reviewed

| File | Status | Risk | Issues |
|------|--------|------|--------|
| `src/auth/login.ts` | Modified | High | 1 blocking |
| `src/utils/hash.ts` | New | Medium | Clean |
| `tests/auth.test.ts` | Modified | — | (not reviewed - test code) |

---

## Review Methodology

**Approach**: [Light review (2 agents) | Inline review | Concern-partitioned (sub-agents, N agents) | Concern-partitioned (team, N members)]
**Model Tier**: [optimized | frontier]
**Config**: [REVIEW.md path | none]

| Concern | Model | Status | Findings | Blocking |
|---------|-------|--------|----------|----------|
| bug-detector | opus/sonnet | Completed / Failed / Skipped | N | M |
| security-reviewer | opus | Completed | N | M |
| cross-file-impact | sonnet | Completed | N | M |
| test-analyzer | sonnet | Completed | N | M |
| spec-and-conventions | sonnet | Completed | N | M |
| type-design | sonnet | Skipped (no new types) | — | — |

**Validation Pipeline**:
- Blame classification: [N new, M surfaced (severity downgraded)]
- Deterministic verification: [N verified, M failed, K skipped]
- Confidence filtering: [N below threshold]
- Disagreements: [N consensus, M contradictions]
- Blind challenge: [N challenged, M upheld, K downgraded, L contested, J removed]

**FIX Tasks Created**: [task IDs or "none"]
```

---

## Verdict Logic (Advisory-First)

Advisory-first tools sustain adoption; overly blocking tools get disabled within a month. AI approval should never count toward required review thresholds — the verdict signals priority to human reviewers, not a gate.

- **REQUEST CHANGES**: Any critical findings, OR high-severity security findings (category B). These represent bugs or vulnerabilities that would cause real harm in production.
- **APPROVE WITH SUGGESTIONS**: High or medium findings exist, but none are critical or security-blocking. The code is functional but has significant improvement opportunities.
- **APPROVE**: Only low-severity findings or no findings. The code is ready to merge.
