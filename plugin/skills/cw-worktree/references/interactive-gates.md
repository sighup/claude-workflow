# Interactive Gates: AskUserQuestion shapes

Full `AskUserQuestion` call shapes for the two interactive gates of
`/cw-worktree create` — **feature discovery** and **drive-mode selection**. The
decision logic (when to fire each gate, how the options collapse, the
label→`DRIVE_MODE` mapping) lives in [SKILL.md](../SKILL.md); this file holds the
verbose JSON examples it points to.

## Feature discovery — single-question shape (≤ 4 candidates)

```
AskUserQuestion({
  questions: [{
    question: "Which features would you like to create worktrees for?",
    header: "Features",
    options: [
      { label: "Team Settings Page", description: "High priority - unlocks integration management" },
      { label: "Export Buttons", description: "Medium effort - completes import/export workflow" }
    ],
    multiSelect: true
  }]
})
```

## Feature discovery — multi-question shape (> 4 candidates)

`AskUserQuestion` enforces `options.maxItems: 4` per question but accepts up to **4 questions per call** (rendered as tabs in the UI). When you have 5–16 candidates, split them across multiple grouped questions instead of dropping any. Group by **semantic affinity** when there is one — e.g., interfaces vs. services — and fall back to arbitrary even chunks only when no natural grouping exists.

Worked example for the fitness-app case ("auth, web, mobile, backend, database"):

```
AskUserQuestion({
  questions: [
    {
      question: "Which interface worktrees?",
      header: "Interfaces",
      options: [
        { label: "Web", description: "Browser-based interface" },
        { label: "Mobile", description: "iOS/Android client" }
      ],
      multiSelect: true
    },
    {
      question: "Which service worktrees?",
      header: "Services",
      options: [
        { label: "Auth", description: "Authentication and session management" },
        { label: "Backend", description: "API and business logic" },
        { label: "Database", description: "Schema and migrations" }
      ],
      multiSelect: true
    }
  ]
})
```

Each question still needs `options.minItems: 2`. If a residual group would end up with a single candidate, either fold it into a sibling group or add a "Skip this one" companion option to keep the array valid.

If candidate count exceeds 16 (4 questions × 4 options), say so plainly and ask the user to either prune the list or group by domain before continuing — don't silently drop candidates.

## Drive-mode selection — question shape (full 4-option variant)

```
AskUserQuestion({
  questions: [{
    question: "How should the {N} worktree(s) be driven after creation?",
    header: "Drive mode",
    options: [
      { label: "Starter prompt (Recommended)",
        description: "Forward the classified /cw-spec or /cw-research kickoff to each tab; you steer from there",
        preview: "<STARTER_PROMPT verbatim for first feature; if N>1 add '\\n\\n…and similar for the other {N-1} worktree(s).'>" },
      { label: "Autonomous (/goal)",
        description: "Drive end-to-end through cw-spec → cw-plan → cw-dispatch → cw-validate → cw-review → cw-testing without further input",
        preview: "<STARTER_PROMPT_GOAL verbatim for first feature; if N>1 add '\\n\\n…and similar for the other {N-1} worktree(s).'>" },
      { label: "Empty session",
        description: "Open the herdr tab(s) with no auto-prompt" },
      { label: "Skip herdr",
        description: "Just create the worktree(s); start sessions manually with cd ... && claude" }
    ],
    multiSelect: false
  }]
})
```
