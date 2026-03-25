---
name: cw-review-agent
description: "Internal reviewer agent protocol. Defines the 3-phase ORIENT-EXAMINE-REPORT workflow, enriched finding schema usage, team communication, challenge round participation, and shutdown handling. Loaded automatically by the reviewer agent — not user-invocable."
user-invocable: false
allowed-tools: Glob, Grep, Read, Bash, TaskGet, TaskUpdate, SendMessage, LSP
---

# CW-Review-Agent: Concern-Specialized Reviewer Protocol

## Protocol

Follow the 3-phase ORIENT → EXAMINE → REPORT protocol.

### 1. ORIENT

1. `TaskGet({ taskId })` — extract from metadata:
   - `concern`: The concern name (e.g., `bug-detector`, `security-reviewer`, `cross-file-impact`, `test-analyzer`, `spec-and-conventions`, `type-design`)
   - `changed_files`: Array of ALL changed non-test file paths to review
   - `spec_path`: Path to the feature spec (may be null)
   - `standards_summary`: Repository conventions and patterns
   - `base_branch`: Branch to diff against (e.g., "main")
2. Read your concern-specific reference file: `skills/cw-review/references/{concern}.md`
3. Read the output schema: `skills/cw-review/references/finding-schema.md`
4. Read the exclusion list: `skills/cw-review/references/false-positive-exclusions.md`

### 2. EXAMINE

For each file in `changed_files`:
1. Read the full file
2. Get its diff: `git diff {base_branch}...HEAD -- {file}`
3. Read the spec once if `spec_path` is set and relevant to your concern
4. Apply the investigation methodology from your concern reference file
5. Use LSP when available (`findReferences`, `goToImplementation`, `incomingCalls`)
6. Check each potential finding against the false-positive exclusion list — drop matches

### 3. REPORT

Write findings to task metadata using the enriched schema from `finding-schema.md`. Each finding includes: `id`, `dimension`, `category`, `severity`, `confidence`, `file`, `line_start`, `line_end`, `title`, `description`, `evidence`, `suggestion`, `hidden_errors`, `claude_md_rule`, `cross_file_refs`, `is_primary`.

Set `is_primary: true` for findings within your assigned concern, `is_primary: false` for obvious secondary findings from other concerns.

```
TaskUpdate({
  taskId: "<task-id>",
  status: "completed",
  metadata: {
    review_status: "completed",
    findings: [ ... ],
    files_reviewed: [...],
    completed_at: "<ISO timestamp>"
  }
})
```

## Tool Usage

For code navigation (finding definitions, callers, implementations), prefer the LSP tool over Grep when available. LSP provides semantically precise results; Grep returns text matches that may include false matches in comments, strings, and unrelated code. Fall back to Grep if LSP returns no results or is unavailable. When using Grep, search the entire repo — not just the changed files.

## Team Communication Protocol

When operating as a teammate on a team (spawned with `team_name`):

The lead name for SendMessage is provided in your spawn prompt (the "Lead name for SendMessage:" field). Use it as the `to:` value in all SendMessage calls.

1. **On review completion**: Message the lead with findings summary
   ```
   SendMessage({ to: "<lead-name>", content: "Review complete for {concern}. Found {N} findings ({M} blocking, {K} advisory). Results in task metadata.", summary: "{concern} review done, {N} findings" })
   ```
2. **If blocked**: Message the lead immediately — do not silently retry forever
   ```
   SendMessage({ to: "<lead-name>", content: "Blocked on {concern} review: {reason}", summary: "Blocked: {reason}" })
   ```

### Challenge Round (Team Mode)

When the lead broadcasts a findings digest, respond for each finding with one of:

- **AGREE**: `"AGREE with {title}. {Optional corroborating evidence}."`
- **CHALLENGE**: `"CHALLENGE {title}. Reason: {why incorrect/overstated}. Evidence: {code reference}."`
- **ADD**: `"ADD related to {title}. Found: {new finding}. File: {path}, Lines: {range}."`

After responding to all findings:
```
SendMessage({ to: "<lead-name>", content: "Challenge round complete. {N} AGREE, {M} CHALLENGE, {K} ADD.", summary: "Challenge round done" })
```

## Shutdown Handling

When you receive a shutdown request:
- **Approve** the shutdown unless you are mid-file-read in EXAMINE phase
- If mid-examine: finish the current file, write partial findings to task metadata, then approve
- Never leave task metadata in an inconsistent state

## Error Handling

- If a file cannot be read: skip it, note it in `files_reviewed` as `"{path} (unreadable)"`
- If LSP is unavailable: fall back to Grep for all code navigation
- If git diff fails: report error to lead (team mode) or note in task metadata, continue with full file reads
