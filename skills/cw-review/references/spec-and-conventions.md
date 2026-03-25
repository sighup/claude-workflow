# Spec & Conventions Reference

Expertise for verifying that code changes follow the project's documented rules, match the planned intent from specs, and keep code comments truthful. Three investigation passes, each independent.

## Quick Reference — Three Passes

1. **Convention compliance** — Check changed code against CLAUDE.md, REVIEW.md, AGENTS.md, QODO.md rules, and code comment contracts. Every finding MUST cite a specific rule.
2. **Intent alignment** — Check changed code against spec requirements, decision records, and documented constraints. Only run if docs/specs context exists.
3. **Comment accuracy** — Verify that code comments are factually correct. Only run if the diff contains significant comment changes.

## Pass 1: Convention Compliance

### How to Review

1. **Read ALL convention files first.** Check for and read each if they exist:
   - `CLAUDE.md` (root and subdirectory-level) — primary project conventions
   - `REVIEW.md` — custom review rules and checklists
   - `AGENTS.md` — agent-specific instructions with code quality rules
   - `QODO.md` — additional review configuration

   Understand every rule before looking at code. Not all rules are relevant during code review — some are about how Claude should write code, not about what the code should look like. Focus on rules that describe the desired state of the code.

2. **Check each changed file against applicable rules.** For each rule:
   - Does the change comply?
   - If not, is the violation in new code or pre-existing?
   - Only report violations in code the author changed or added.

3. **Check directory-level CLAUDE.md files.** Subdirectory rules take precedence over root where they conflict.

4. **Check REVIEW.md custom rules explicitly.** Treat each rule as a required check. Walk through the checklist item by item. REVIEW.md rules carry the same weight as CLAUDE.md rules.

5. **Check code comment compliance.** Read comments in modified files (not just the diff, but surrounding context):
   - TODO comments specifying how something should be done
   - Invariant notes ("this must always be called after X")
   - API contracts in comments (parameter constraints, return value guarantees, thread-safety notes)
   - Warning comments ("do not change this without also changing Z")

   If the author's changes violate a documented invariant or ignore a warning comment in the same file, that is a finding.

### What Counts as a Convention Violation

- Import ordering/grouping that doesn't match documented pattern
- Naming conventions not followed (casing, prefixes, suffixes)
- File structure deviating from documented patterns
- Framework/library usage contradicting documented conventions
- Error handling not matching the project's chosen pattern
- Testing conventions not followed in new test files
- Code contradicting an invariant, contract, or warning in a code comment

### What Does NOT Count

- CLAUDE.md rules about Claude's behavior, not code quality
- Rules explicitly silenced in code (lint-ignore, suppression attributes)
- Pre-existing violations on untouched lines
- Generic best practices not mentioned in any convention file
- Style issues a formatter/linter would catch (unless explicitly called out)

### Convention Output Requirements

**Every convention finding MUST include a non-null `claude_md_rule` field** — quote the specific rule being violated and cite its source file (CLAUDE.md, REVIEW.md, AGENTS.md, QODO.md, or the specific code comment). A compliance finding without a cited rule is useless and must not be reported. If you cannot point to a specific documented rule or code comment, do not report the finding.

If no convention files exist and no relevant code comments contain rules, skip this entire pass and report: "No project conventions found — convention compliance check skipped." Return an empty findings array for this pass.

## Pass 2: Intent Alignment

Only run if specification documents, decision records, or planning documents are available. If none found: "No specification documents found — intent alignment check skipped."

### How to Review

1. Read spec documents referenced in PR description or found in `docs/specs/`.
2. Read decision records (ADRs), design docs, or planning documents.
3. For each requirement or decision, trace to the implementing code and verify match.

### What to Look For

**Spec contradictions** — Code does the opposite of what spec says. Edge case handling contradicting documented behavior. Default values differing from spec. Error handling not matching documented strategy.

**Missing requirements** — Acceptance criteria with no implementation. Required validations absent from code. Documented error cases not handled. Required integrations missing.

**Decision record violations** — Using an explicitly rejected approach. Implementing a discarded alternative without documenting why the decision changed. Ignoring documented constraints.

**Scope drift** — Implementation beyond spec without documentation. Partial implementation not noting what's deferred. Changed scope without updated docs.

### Intent Output Requirements

**Quote the specific spec text** and show the corresponding code. A misalignment claim without a cited spec is not useful — the author needs to see both sides to evaluate whether the spec or the code should change.

### What You Do NOT Report for Intent

- Implementation details not specified in docs
- Stylistic choices that don't affect requirements
- Legitimate evolution beyond specs used as starting points
- Minor wording differences without correctness impact

## Pass 3: Comment Accuracy

Only run if the diff contains significant comment additions or modifications. Minor or no comment changes → skip.

### How to Review

For each changed file, read code and comments together. Treat comments as claims and verify each.

**Factual accuracy** — Do documented parameters match actual parameters? Does the comment say "this does X" when it does Y? Do references (@see, @link) point to things that exist? Do exception lists match what's thrown?

**Misleading elements** — Ambiguous language around nullability, ownership, or threading safety. Outdated references to old class names, removed features, or deprecated APIs. Stale TODOs that reference completed work, closed issues, or shipped features. Two comments in the same scope that make incompatible claims.

**Staleness** — Comments describing behavior changed by this PR but not updated. Referenced types or functions that were renamed or removed. Fragile comments that reference specific line numbers, hardcoded values, or implementation details likely to change.

### Comment Output Requirements

Quote the specific comment text and explain what's wrong. For accuracy issues, show both the comment's claim and the code's actual behavior.

### What You Do NOT Report for Comments

- Missing comments on self-documenting code
- Comment formatting preferences
- Missing comments in unchanged code (unless a change makes an existing comment inaccurate)
- Suggestions to add comments restating clear code
- Spelling/grammar unless it changes meaning

## Calibration

WARNING: LLMs are systematically overconfident, clustering scores in the 80-100 range. Calibrate carefully: 90-100 = exact trigger identifiable, 70-89 = likely real but needs more context, 50-69 = suspicious but uncertain. Use the full range.

Report findings with confidence >= 60. The validation pipeline will apply stricter dimension-specific thresholds (80 for conventions/intent).

### Confidence

- **90-100**: Rule/spec is explicit and code clearly violates it. You can quote rule and show violation side by side. Or comment makes a demonstrably false factual claim.
- **80-89**: Rule is clear but violation is in a gray area. Or comment is misleading enough to confuse a reader.
- **70-79**: Rule is vaguely worded and code might or might not violate the spirit. Or comment is stale but a careful reader could figure out the truth.
- **60-69**: Plausible issue but significant uncertainty remains.
