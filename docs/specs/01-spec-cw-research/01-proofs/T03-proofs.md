# T03 Proof Summary: Meta-Prompt Generation, Agent Definition, and Integration Wiring

## Task
Add meta-prompt generation, agent definition, and integration wiring to complete the cw-research feature.

## Proof Artifacts

| # | File | Type | Status | Description |
|---|------|------|--------|-------------|
| 1 | T03-01-file.txt | file | PASS | SKILL.md contains meta-prompt generation instructions with all required fields (feature name, problem statement, components, architectural constraints, patterns, demoable unit themes, code references) |
| 2 | T03-02-file.txt | file | PASS | SKILL.md contains next-step options with AskUserQuestion including three options (Run cw-spec with context, Review report first, Done for now) and Skill(cw-spec) invocation |
| 3 | T03-03-file.txt | file | PASS | agents/researcher.md exists with correct frontmatter (description, capabilities, color, model, tools, skills: cw-research) and coordination section (Team Lead -> Researcher -> Spec Writer handoff) |
| 4 | T03-04-file.txt | file | PASS | cw-worktree SKILL.md permissions template includes Skill(cw-research) and Task(claude-workflow:researcher) for integration wiring |

## Changes Made

### skills/cw-research/SKILL.md
- Added Step 9: Generate Meta-Prompt -- generates a ready-to-use /cw-spec starter prompt enriched with research findings
- Added Step 10: Present Results and Next-Step Options -- presents completion summary and three next-step options via AskUserQuestion
- Updated "What Comes Next" section to reference meta-prompt acceleration

### agents/researcher.md (new file)
- Created agent definition following spec-writer.md pattern
- Frontmatter: description, capabilities, color (green), model (inherit), tools, skills (cw-research)
- Identity: Role as Researcher
- Coordination: Receives from Team Lead, produces research report, hands off to Spec Writer
- Constraints: Never implements code, only produces research reports, redacts secrets

### skills/cw-worktree/SKILL.md
- Added `Skill(cw-research)` to permissions template
- Added `Task(claude-workflow:researcher)` to permissions template

## Verdict
All 4 proof artifacts PASS. Task T03 requirements are fully satisfied.
