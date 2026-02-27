# 01-spec-cw-research

## Introduction/Overview

cw-research is a new Claude Workflow skill that performs preliminary codebase fact-finding and external context aggregation to produce a structured research report. This report feeds into `/cw-spec` as enriched context, enabling better specification generation for unfamiliar or complex codebases. It fills the gap between "I have an idea" and "I can articulate a clear spec prompt" by automating deep exploration and surfacing what matters.

## Goals

1. Produce a structured research report (`docs/specs/research-{topic}.md`) covering architecture, patterns, dependencies, tests, data models, and user-directed external context
2. Follow a hybrid workflow: auto-explore first, then ask user to refine focus areas and provide external context sources before deep-diving
3. Generate a pre-filled `/cw-spec` meta-prompt enriched with codebase knowledge so users start spec writing with full context
4. Support team-based workflows via a corresponding `agents/researcher.md` agent definition
5. Integrate seamlessly into the existing Claude Workflow pipeline (`/cw-research` → `/cw-spec` → `/cw-plan` → `/cw-dispatch`)

## User Stories

- As a developer working on an unfamiliar codebase, I want to run `/cw-research` so that I understand the architecture, patterns, and conventions before writing a spec.
- As a developer with external context (Jira tickets, architecture decision records, design docs), I want cw-research to incorporate those sources so the research report is comprehensive.
- As a developer starting a new feature, I want cw-research to generate a `/cw-spec` starter prompt so I don't have to manually summarize codebase knowledge.
- As a team lead using cw-dispatch-team, I want to assign research tasks to a researcher agent so exploration can happen in parallel with other work.

## Demoable Units of Work

### Unit 1: Core Skill with Auto-Explore and Basic Report

**Purpose:** Create the foundational skill file and auto-explore phase that detects the tech stack, maps project structure, identifies patterns, and saves a structured research report — end-to-end from invocation to file output.

**Functional Requirements:**
- The system shall create `skills/cw-research/SKILL.md` with frontmatter (name: cw-research, description, user-invocable: true, allowed-tools: Glob, Grep, Read, Write, Bash, WebFetch, WebSearch, AskUserQuestion, Task) and a markdown protocol
- The system shall use the context marker **CW-RESEARCH** at the start of every response
- The system shall accept an optional topic argument (e.g., `/cw-research authentication`) to scope the exploration
- The system shall perform an auto-explore phase covering five research dimensions:
  1. **Tech Stack & Project Structure** — languages, frameworks, build tools, directory layout, entry points
  2. **Architecture & Patterns** — design patterns, module boundaries, abstractions, state management
  3. **Dependencies & Integrations** — external deps, APIs, integration points, data flow between services
  4. **Test & Quality Patterns** — test frameworks, coverage approach, CI/CD config, linting, type checking
  5. **Data Models & API Surface** — database schemas, API endpoints, request/response shapes, key data structures
- The system shall use `Task(Explore)` subagents for parallel deep codebase exploration across multiple dimensions simultaneously
- The system shall save the research report to `docs/specs/research-{topic}.md` using a structured markdown template with sections for each dimension
- The system shall include a summary section at the top of the report with key findings and notable patterns

**Proof Artifacts:**
- File: `skills/cw-research/SKILL.md` contains frontmatter with `name: cw-research` and `user-invocable: true`
- File: `skills/cw-research/SKILL.md` contains all five research dimension definitions
- File: `skills/cw-research/SKILL.md` contains `Task(Explore)` subagent usage instructions for parallel exploration

### Unit 2: Interactive Refinement with External Context Sources

**Purpose:** After auto-explore produces initial findings, present them to the user and enable refinement — allowing users to redirect focus areas and provide external context sources (URLs, file paths, screenshots, documentation) that get incorporated into a deep-dive phase.

**Functional Requirements:**
- The system shall present auto-explore findings as a summary and ask the user to confirm, refine, or redirect focus areas using `AskUserQuestion`
- The system shall ask the user if they have external context sources to include, with examples: GitHub issues/PRs, Jira tickets, Confluence pages, Google Docs, filesystem paths, pasted images, web URLs, documentation links, knowledgebase articles, architecture decision records
- The system shall accept multiple external context sources in a single interaction (user can provide a list of URLs, paths, etc.)
- The system shall fetch and incorporate external web sources using `WebFetch` and `WebSearch` tools
- The system shall read local file/directory sources using `Read`, `Glob`, and `Grep` tools
- The system shall handle images provided by the user (screenshots, diagrams) by reading them via `Read` tool and describing their content in the report
- The system shall launch targeted `Task(Explore)` subagents for deep-dive exploration of user-selected focus areas
- The system shall update the research report with deep-dive findings and external context, clearly attributing which information came from which source
- The system shall gracefully handle inaccessible external sources (auth-required pages, broken links) by noting them as "inaccessible" in the report rather than failing

**Proof Artifacts:**
- File: `skills/cw-research/SKILL.md` contains interactive refinement phase with `AskUserQuestion` usage
- File: `skills/cw-research/SKILL.md` contains external context source handling instructions covering web, filesystem, and image sources
- File: `skills/cw-research/SKILL.md` contains graceful error handling for inaccessible sources

### Unit 3: Meta-Prompt Generation, Agent Definition, and cw-spec Integration

**Purpose:** Generate a pre-filled `/cw-spec` starter prompt enriched with research findings, create the corresponding agent definition for team workflows, and wire up the integration point where cw-research hands off to cw-spec.

**Functional Requirements:**
- The system shall generate a "Meta-Prompt" section at the end of the research report containing a ready-to-use `/cw-spec` starter prompt
- The meta-prompt shall include: feature name, problem statement derived from research, key components/files identified, architectural constraints discovered, relevant patterns to follow, suggested demoable unit themes, and references to specific code locations
- The system shall present the user with next-step options after report completion:
  1. "Run /cw-spec with context (Recommended)" — invoke cw-spec with the research report as enriched context
  2. "Review report first" — let user review and edit the report before proceeding
  3. "Done for now" — save the report and exit
- If the user selects "Run /cw-spec with context", the system shall invoke `/cw-spec` with the meta-prompt content as the argument
- The system shall create `agents/researcher.md` with frontmatter (description, capabilities, tools, skills: cw-research) following the same pattern as `agents/spec-writer.md`
- The agent definition shall specify: role as Researcher, coordination notes (receives work from Team Lead, produces research report, hands off to Spec Writer), and constraints (never implements code, only produces research reports)
- The system shall register the skill in the plugin's skill listing so it appears alongside cw-spec, cw-plan, etc.

**Proof Artifacts:**
- File: `skills/cw-research/SKILL.md` contains meta-prompt generation instructions with specific fields (feature name, problem statement, components, constraints, patterns)
- File: `skills/cw-research/SKILL.md` contains next-step options with `AskUserQuestion` including cw-spec integration
- File: `agents/researcher.md` exists with frontmatter matching agent convention (description, capabilities, tools, skills)
- File: `agents/researcher.md` contains coordination section referencing Team Lead → Researcher → Spec Writer handoff

## Non-Goals (Out of Scope)

- **Code generation or implementation** — cw-research only produces research reports, never modifies source code
- **Automated refactoring recommendations** — findings describe what exists, not prescriptive changes
- **Performance profiling or benchmarking** — research covers architecture and patterns, not runtime performance
- **Security auditing** — security considerations may be noted but no formal security audit is performed
- **Persistent caching of research results** — each invocation produces a fresh report (no incremental updates)
- **Authentication to external services** — cw-research uses available tools (WebFetch, gh CLI) but does not manage OAuth/API keys for Jira, Confluence, etc.

## Design Considerations

No specific UI/UX design requirements. The skill operates in the CLI via markdown output and `AskUserQuestion` interactive prompts. The research report uses structured markdown with clear section headers for readability.

## Repository Standards

- **Skill file convention**: `skills/{name}/SKILL.md` with YAML frontmatter (name, description, user-invocable, allowed-tools) followed by markdown protocol
- **Agent file convention**: `agents/{role}.md` with YAML frontmatter (description, capabilities, color, model, tools, skills) followed by markdown identity and coordination sections
- **Context marker convention**: `**CW-{NAME}**` at the start of every response (e.g., **CW-RESEARCH**)
- **Output path convention**: Research reports go to `docs/specs/research-{topic}.md` alongside spec directories
- **Subagent convention**: Use `Task(Explore)` for codebase exploration, `Task(general-purpose)` for broader tasks
- **Existing skills to reference**: cw-spec (output consumer), cw-worktree (structural pattern), cw-plan (downstream step)

## Technical Considerations

- **Parallel exploration**: The auto-explore phase should launch multiple `Task(Explore)` subagents concurrently (one per research dimension) to maximize throughput
- **Report size management**: Research reports for large codebases could become unwieldy. The protocol should instruct the agent to keep each dimension section focused (key findings, not exhaustive listings) with links to specific files rather than inline code dumps
- **External context flexibility**: The external context phase must be tool-agnostic — users might provide a GitHub URL (use `gh` CLI or `WebFetch`), a local file path (use `Read`), a web URL (use `WebFetch`), or paste content directly. The protocol should handle each gracefully
- **Meta-prompt quality**: The generated `/cw-spec` starter prompt should be opinionated enough to be useful but flexible enough that the user can modify it. It should reference specific file paths and patterns discovered during research
- **Integration with cw-spec**: The meta-prompt is passed as the argument to `/cw-spec`. cw-spec's Step 2 (Context Assessment) will be significantly accelerated because the research report already covers that ground in depth

## Security Considerations

- Research reports may reference file paths, API endpoints, or configuration values from the codebase. The report itself is saved locally and not transmitted externally
- External context fetching via `WebFetch` should respect the tool's built-in limitations (no authenticated pages). The protocol should warn users that auth-required sources cannot be automatically fetched
- No credentials, API keys, or secrets should be included in research reports. The protocol should instruct the agent to redact sensitive values discovered during exploration

## Success Metrics

- A user can run `/cw-research {topic}` on an unfamiliar codebase and receive a comprehensive research report within a single session
- The generated meta-prompt, when passed to `/cw-spec`, produces a noticeably more detailed and accurate spec than running `/cw-spec` cold
- External context sources provided by the user are successfully incorporated and attributed in the report
- The `agents/researcher.md` definition enables team-based research via `Task(claude-workflow:researcher)`

## Open Questions

- Should research reports support incremental updates (re-running `/cw-research` appends to an existing report) or always produce fresh reports? Current decision: fresh reports only, but this could be revisited.
- Should there be a "quick" mode that skips the interactive refinement phase for users who just want a fast overview? Could be added as a flag (e.g., `/cw-research --quick {topic}`) in a future iteration.
