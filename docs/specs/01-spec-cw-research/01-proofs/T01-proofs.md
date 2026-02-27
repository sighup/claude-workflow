# T01 Proof Summary: Core cw-research skill with auto-explore and basic report

## Task
Create the foundational `skills/cw-research/SKILL.md` skill file implementing the auto-explore phase with parallel subagent orchestration and structured markdown report output.

## Results

| # | Type | Description | Status |
|---|------|-------------|--------|
| 1 | file | SKILL.md contains frontmatter with `name: cw-research` and `user-invocable: true` | PASS |
| 2 | file | SKILL.md contains all five research dimension definitions | PASS |
| 3 | file | SKILL.md contains `Task(Explore)` subagent usage instructions for parallel exploration | PASS |

## Artifact Files

- `T01-01-file.txt` - Frontmatter verification (name, user-invocable, allowed-tools)
- `T01-02-file.txt` - Five research dimensions verification (15 occurrences across the file)
- `T01-03-file.txt` - Task(Explore) subagent verification (5 parallel calls)

## Implementation Notes

The skill file follows existing conventions observed in `cw-spec/SKILL.md` and `cw-worktree/SKILL.md`:
- YAML frontmatter with name, description, user-invocable, and allowed-tools
- Context marker section
- Overview and role description
- Critical constraints
- Step-by-step process protocol
- Report template with structured sections
- "What Comes Next" section linking to downstream skills

Key design decisions:
- Five parallel `Task(Explore)` subagents launched in a single message for maximum concurrency
- Topic filtering passed to each subagent prompt to scope exploration
- Report size management guidelines (under 500 lines, top 5-10 items per subsection)
- Topic slug normalization for output filename
- Summary section at report top with 3-5 key findings
