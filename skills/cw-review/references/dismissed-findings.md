# Dismissed Findings Flow

After review delivery, offer to suppress findings in REVIEW.md so they won't be flagged in future reviews. This only fires if there are findings the user might want to dismiss.

## Step 1: Offer Dismissal

```
AskUserQuestion(
  question: "Should any of these findings be ignored in future reviews? This adds them to REVIEW.md so they won't be flagged again.",
  options: [
    "Yes — let me pick which ones to dismiss",
    "No — all findings are valid"
  ]
)
```

If "No", skip the rest of this flow.

## Step 2: Selection

Show a numbered list of all findings (blocking + advisory) and let the user pick:

```
Findings available for dismissal:

  #1  [medium]  err-1: Silent failure in webhook retry (bug-detector)
  #2  [low]     conv-1: Naming inconsistency in DTOs (spec-and-conventions)
  #3  [low]     test-1: Missing edge case test for empty input (test-analyzer)

Which findings should be dismissed?
Examples: "1,3", "all low", "2", "none"
```

Support natural patterns: `1,3`, `all low`, `all advisory`, `all except 1`, `none`.

For each selected finding, ask for a brief reason (one line).

## Step 3: Show Proposed Entries

Show what will be written to REVIEW.md before modifying:

```
These entries would be added to REVIEW.md under ## Ignore:

- bug:"silent failure in webhook retry" (not exploitable in current architecture, 2026-03-25)
- conventions:"naming inconsistency" (tracked in ROADMAP.md, 2026-03-25)
```

Each entry: `dimension:"pattern matching finding title"` with parenthesized reason and date.

## Step 4: Confirm Before Writing

```
AskUserQuestion(
  question: "Add these to REVIEW.md?",
  options: [
    "Yes — add to REVIEW.md",
    "No — skip"
  ]
)
```

## Step 5: Write to REVIEW.md

If confirmed:
- If no REVIEW.md exists → offer to create using scaffolding template from `review-config-spec.md`
- If REVIEW.md exists without `## Ignore` section → append the section
- If `## Ignore` section exists → append new entries

After writing: "Added N dismissed findings to REVIEW.md. These won't be flagged in future reviews."

If declined, skip without modifying files.
