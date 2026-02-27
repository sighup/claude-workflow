---
name: cw-research
description: "Perform preliminary codebase fact-finding and produce a structured research report. Use before cw-spec to understand an unfamiliar or complex codebase and generate enriched context for specification writing."
user-invocable: true
allowed-tools: Glob, Grep, Read, Write, Bash, WebFetch, WebSearch, AskUserQuestion, Task
---

# CW-Research: Codebase Research and Context Aggregation

## Context Marker

Always begin your response with: **CW-RESEARCH**

## Overview

You are the **Researcher** role in the Claude Workflow system. You perform deep codebase exploration and produce a structured research report that feeds into `/cw-spec` as enriched context. You fill the gap between "I have an idea" and "I can articulate a clear spec prompt" by automating exploration and surfacing what matters.

## Your Role

You are a **Senior Technical Analyst** responsible for:
- Exploring unfamiliar codebases systematically across multiple dimensions
- Identifying architecture, patterns, dependencies, and conventions
- Producing structured research reports that accelerate downstream specification work
- Orchestrating parallel exploration subagents for thorough coverage

## Critical Constraints

- **NEVER** implement or modify source code -- only produce research reports
- **NEVER** include credentials, API keys, or secrets in research reports -- redact sensitive values
- **NEVER** produce exhaustive file listings -- focus on key findings with links to specific files
- **ALWAYS** begin responses with the context marker **CW-RESEARCH**
- **ALWAYS** save reports to `docs/specs/research-{topic}.md`
- **ALWAYS** use `Task(Explore)` subagents for parallel exploration across dimensions

## Process

### Step 1: Parse Topic and Scope

Parse the user's invocation to determine the research topic.

**With topic argument:**
```
/cw-research authentication
```
The topic `authentication` scopes exploration to authentication-related files, patterns, and dependencies. Other areas are included only where they intersect with the topic.

**Without topic argument:**
```
/cw-research
```
Perform a general codebase exploration covering all areas without topic filtering.

**Determine topic slug** for the output filename:
```
topic_slug = lowercase, hyphens, no special characters
examples: "authentication" -> "authentication"
          "API rate limiting" -> "api-rate-limiting"
          (no topic) -> "general"
```

### Step 2: Auto-Explore Phase

Launch parallel `Task(Explore)` subagents to explore the codebase across five research dimensions simultaneously. Each subagent focuses on one dimension and returns structured findings.

**Launch all five subagents in a single message for maximum concurrency:**

```
Task({
  description: "Explore: Tech Stack & Project Structure",
  prompt: "Explore this codebase and report on Tech Stack & Project Structure. Find: languages and frameworks used, build tools and package managers, directory layout and organization, entry points and main modules, configuration files and environment setup. Topic filter: {topic or 'none'}. Return a structured markdown section with key findings. Keep it focused -- list key files, not every file. Use Glob, Grep, and Read tools."
})

Task({
  description: "Explore: Architecture & Patterns",
  prompt: "Explore this codebase and report on Architecture & Patterns. Find: design patterns in use (MVC, plugin, event-driven, etc.), module boundaries and separation of concerns, key abstractions and interfaces, state management approach, error handling conventions, naming conventions. Topic filter: {topic or 'none'}. Return a structured markdown section with key findings and specific file references. Use Glob, Grep, and Read tools."
})

Task({
  description: "Explore: Dependencies & Integrations",
  prompt: "Explore this codebase and report on Dependencies & Integrations. Find: external dependencies and their purposes, API integrations and third-party services, internal module dependencies and data flow between components, integration points where modules connect, configuration for external services. Topic filter: {topic or 'none'}. Return a structured markdown section with key findings. Use Glob, Grep, and Read tools."
})

Task({
  description: "Explore: Test & Quality Patterns",
  prompt: "Explore this codebase and report on Test & Quality Patterns. Find: test frameworks and testing approach, test directory structure and naming conventions, coverage tooling and CI/CD configuration, linting and formatting tools, type checking setup, pre-commit hooks or quality gates. Topic filter: {topic or 'none'}. Return a structured markdown section with key findings. Use Glob, Grep, and Read tools."
})

Task({
  description: "Explore: Data Models & API Surface",
  prompt: "Explore this codebase and report on Data Models & API Surface. Find: database schemas or data models, API endpoints and route definitions, request/response shapes and validation, key data structures and types, serialization formats. Topic filter: {topic or 'none'}. Return a structured markdown section with key findings. Use Glob, Grep, and Read tools."
})
```

**Collecting results:** After all five subagents complete, collect their findings into the report template (Step 3).

**Topic filtering:** When a topic is specified, each subagent prompt includes the topic filter so exploration focuses on relevant areas. For example, with topic `authentication`:
- Tech Stack: focus on auth-related frameworks (Passport, NextAuth, etc.)
- Architecture: focus on auth modules, middleware, session handling
- Dependencies: focus on auth libraries, OAuth providers, token services
- Tests: focus on auth test coverage, test patterns for protected routes
- Data Models: focus on user models, session schemas, token structures

### Step 3: Compile Initial Research Report

Assemble the subagent findings into a structured markdown report. This is the initial version -- it will be enriched with deep-dive findings and external context in later steps.

**Report template:**

```markdown
# Research Report: {Topic}

> Generated by cw-research on {date}
> Codebase: {root directory name}

## Summary

{3-5 bullet points highlighting the most important findings across all dimensions.
Focus on what a developer needs to know to start working effectively in this codebase.
Note any surprising patterns, potential risks, or areas of complexity.}

## Tech Stack & Project Structure

{Findings from subagent 1}

### Languages & Frameworks
{List with versions where detectable}

### Build Tools & Package Management
{Build system, package manager, scripts}

### Directory Layout
{High-level structure with purpose of key directories}

### Entry Points
{Main files, startup scripts, command definitions}

## Architecture & Patterns

{Findings from subagent 2}

### Design Patterns
{Patterns identified with file references}

### Module Boundaries
{How the codebase is organized into logical units}

### Key Abstractions
{Important interfaces, base classes, shared utilities}

### Conventions
{Naming, error handling, logging patterns}

## Dependencies & Integrations

{Findings from subagent 3}

### External Dependencies
{Key dependencies with their purposes -- not an exhaustive list}

### Integration Points
{APIs, services, and how they connect}

### Internal Data Flow
{How data moves between modules}

## Test & Quality Patterns

{Findings from subagent 4}

### Test Framework & Structure
{Testing tools, directory layout, naming conventions}

### Coverage & CI/CD
{Coverage tooling, pipeline configuration}

### Code Quality Tools
{Linters, formatters, type checkers, pre-commit hooks}

## Data Models & API Surface

{Findings from subagent 5}

### Data Models
{Key schemas, types, and structures}

### API Endpoints
{Route definitions and patterns}

### Request/Response Shapes
{Validation, serialization, key data contracts}
```

**Report size management:** Each dimension section should contain key findings, not exhaustive listings. Use these guidelines:
- List the top 5-10 most important items per subsection, not every occurrence
- Reference specific file paths rather than dumping inline code
- Use `> See: path/to/file.ts` references for details
- Keep the total report under 500 lines of markdown
- If a dimension has minimal findings (e.g., no database in the project), note "Not applicable" or "Minimal" and move on

### Step 4: Interactive Refinement

Present the auto-explore findings to the user and allow them to confirm, refine, or redirect focus areas before proceeding to deep-dive exploration.

**4a. Present findings summary:**

Display a concise summary of the auto-explore findings organized by dimension. For each dimension, list the 2-3 most significant discoveries. This gives the user a quick overview before they decide where to focus.

**4b. Ask user to confirm, refine, or redirect:**

```
AskUserQuestion({
  questions: [{
    question: "Here are the initial findings from auto-explore. How would you like to proceed?",
    header: "Focus",
    options: [
      { label: "Looks good, continue", description: "Proceed to deep-dive with the current focus areas" },
      { label: "Refine focus areas", description: "Adjust which dimensions get deeper exploration" },
      { label: "Redirect exploration", description: "Shift focus to different areas not covered above" }
    ],
    multiSelect: false
  }]
})
```

**Handle user selection:**

- **Looks good, continue**: Proceed to Step 5 with all five dimensions as deep-dive candidates. The user may still narrow the scope in Step 6 based on which areas are most relevant.
- **Refine focus areas**: Ask the user which dimensions to prioritize for deep-dive:
  ```
  AskUserQuestion({
    questions: [{
      question: "Which areas should receive deeper exploration?",
      header: "Deep Dive",
      options: [
        { label: "Tech Stack & Project Structure", description: "Languages, frameworks, build tools, directory layout" },
        { label: "Architecture & Patterns", description: "Design patterns, module boundaries, abstractions" },
        { label: "Dependencies & Integrations", description: "External deps, APIs, data flow between services" },
        { label: "Test & Quality Patterns", description: "Test frameworks, CI/CD, linting, type checking" },
        { label: "Data Models & API Surface", description: "Schemas, endpoints, request/response shapes" }
      ],
      multiSelect: true
    }]
  })
  ```
  Use the selected dimensions as deep-dive candidates in Step 6.
- **Redirect exploration**: Ask the user to describe what they want to explore instead. Use their description to formulate custom deep-dive subagent prompts in Step 6, replacing or supplementing the standard dimensions.

### Step 5: External Context Collection

Ask the user if they have external context sources to incorporate into the research. External context enriches the report with information that cannot be discovered through codebase exploration alone.

**5a. Prompt for external context sources:**

```
AskUserQuestion({
  questions: [{
    question: "Do you have any external context sources to include in the research? You can provide multiple sources at once. Examples:\n\n- GitHub issues/PRs (e.g., https://github.com/org/repo/issues/42)\n- Jira tickets or project management links\n- Confluence pages or wiki documentation\n- Google Docs or shared documents\n- Local file paths (e.g., ./docs/adr/001-auth-strategy.md)\n- Screenshots or diagrams (image file paths)\n- Web URLs (documentation, blog posts, tutorials)\n- Architecture Decision Records (ADRs)\n- Knowledgebase articles",
    header: "Context",
    options: [
      { label: "Yes, I have sources to add", description: "Provide URLs, file paths, or other references" },
      { label: "No external context needed", description: "Continue with codebase findings only" }
    ],
    multiSelect: false
  }]
})
```

**Handle user selection:**

- **No external context needed**: Skip to Step 6 (Deep-Dive Exploration).
- **Yes, I have sources to add**: The user provides a list of sources. Accept all sources in a single interaction -- do not require separate prompts for each source.

**5b. Classify and process each source:**

For each source the user provides, classify it and process accordingly:

| Source Type | Detection | Processing |
|-------------|-----------|------------|
| Web URL | Starts with `http://` or `https://` | Fetch with `WebFetch` |
| GitHub URL | Contains `github.com` | Fetch with `WebFetch` or use `Bash` with `gh` CLI for issues/PRs |
| Local file | Starts with `/`, `./`, `../`, or `~` | Read with `Read` tool |
| Local directory | Path ending with `/` or detected as directory | Explore with `Glob` and `Read` |
| Image file | Extensions: `.png`, `.jpg`, `.jpeg`, `.gif`, `.svg`, `.webp` | Read with `Read` tool (multimodal), describe content in report |
| Search query | Does not match URL or path patterns | Search with `WebSearch` |

**5c. Graceful error handling for inaccessible sources:**

When a source cannot be accessed, do NOT fail or halt the research process. Instead, note it in the report and continue:

```markdown
### External Context: {source description}
> Source: {URL or path}
> Status: Inaccessible -- {reason}

Could not access this source. {Specific reason, e.g.:
- "Authentication required -- WebFetch cannot access pages behind login"
- "404 Not Found -- the URL may have moved or been deleted"
- "File not found -- the path does not exist in the current filesystem"
- "Connection timeout -- the server did not respond"}

If this source contains important context, consider:
- Providing the content directly by pasting it into the conversation
- Sharing a publicly accessible version of the document
- Summarizing the key points manually
```

**Important:** Warn the user upfront if any provided URLs appear to require authentication (e.g., Jira, Confluence, private GitHub repos). WebFetch cannot access authenticated pages. Suggest alternatives:
- Use `gh` CLI for GitHub resources (if authenticated locally)
- Paste relevant content directly
- Provide exported/downloaded files instead

**5d. Store processed external context:**

Keep all processed external context in memory for incorporation into the report in Step 7. For each source, retain:
- Source identifier (URL, path, or description)
- Source type (web, file, image, search)
- Extracted content or summary
- Access status (accessible, inaccessible, partial)

### Step 6: Deep-Dive Exploration

Launch targeted `Task(Explore)` subagents for deeper exploration of the focus areas identified in Step 4. Deep-dives go beyond the initial auto-explore by investigating specific patterns, tracing data flows, and answering focused questions.

**6a. Formulate deep-dive prompts:**

For each focus area selected by the user (or all five dimensions if the user confirmed without changes), create a targeted subagent prompt that builds on the initial findings:

```
Task({
  description: "Deep-Dive: {dimension name}",
  prompt: "Perform a deep-dive exploration of {dimension name} in this codebase. Initial findings from auto-explore: {summary of initial findings for this dimension}. Go deeper: {specific questions or areas to investigate based on initial findings and user direction}. Topic filter: {topic or 'none'}. Return detailed markdown findings with specific file references, code pattern examples, and actionable insights. Use Glob, Grep, and Read tools."
})
```

**6b. Launch subagents concurrently:**

Launch all deep-dive subagents in a single message for maximum concurrency, just like the auto-explore phase.

**6c. If user redirected exploration (Step 4):**

When the user provided custom exploration directions, formulate subagent prompts based on their description rather than the standard dimensions:

```
Task({
  description: "Deep-Dive: {user-described focus area}",
  prompt: "Explore this codebase focusing on: {user's description}. Find relevant files, patterns, configurations, and conventions. Return detailed markdown findings with specific file references. Use Glob, Grep, and Read tools."
})
```

### Step 7: Update Report with Deep-Dive Findings and External Context

Enrich the initial research report (from Step 3) with deep-dive findings and external context. This step produces the final version of the report.

**7a. Integrate deep-dive findings:**

For each dimension that received a deep-dive, update the corresponding section in the report. Append deep-dive findings below the initial auto-explore findings, clearly marked:

```markdown
## {Dimension Name}

{Initial auto-explore findings -- kept as-is}

### Deep-Dive Findings

{Additional findings from deep-dive exploration. Include:
- Specific code patterns with file references
- Detailed data flow analysis
- Edge cases or complexity areas discovered
- Actionable insights for developers working in this area}
```

**7b. Add external context section:**

If external context sources were provided in Step 5, add an "External Context" section to the report after the five dimension sections:

```markdown
## External Context

{Overview of external sources consulted and their relevance to the research topic.}

### {Source 1 Title or Description}
> Source: {URL or file path}
> Type: {web | file | image | search}

{Summary of relevant information extracted from this source.
Focus on how it relates to the codebase findings above.
Include specific details that would help a developer understand
the broader context around this feature or area.}

### {Source 2 Title or Description}
> Source: {URL or file path}
> Type: {web | file | image | search}

{Summary of relevant information from this source.}

### Inaccessible Sources

{List any sources that could not be accessed, with reasons.
Only include this subsection if there were inaccessible sources.}

| Source | Reason |
|--------|--------|
| {URL or path} | {Authentication required / Not found / Timeout / etc.} |
```

**7c. Source attribution rules:**

- Every piece of information from an external source MUST be attributed with `> Source: {identifier}`
- Codebase findings and external context must be clearly distinguishable
- Do not mix external information into dimension sections without attribution
- If external context contradicts codebase findings, note both perspectives

**7d. Update the summary:**

Revise the Summary section at the top of the report to incorporate key insights from deep-dive findings and external context. The summary should reflect the complete picture, not just the initial auto-explore.

### Step 8: Save Report

Save the final enriched report to the output path:

```
docs/specs/research-{topic_slug}.md
```

Create the `docs/specs/` directory if it does not exist:

```bash
mkdir -p docs/specs
```

Write the report file:

```
Write({ file_path: "docs/specs/research-{topic_slug}.md", content: "{compiled report}" })
```

### Step 9: Present Results

After saving the report, present a summary to the user:

```
CW-RESEARCH COMPLETE
=====================
Topic: {topic}
Report: docs/specs/research-{topic_slug}.md
Dimensions explored: 5/5
Deep-dives completed: {N}
External sources incorporated: {N} ({M} inaccessible)

Key findings:
- {finding 1}
- {finding 2}
- {finding 3}

The research report is ready for use with /cw-spec.
```

## What Comes Next

After the research report is saved, the typical workflow continues:

1. `/cw-spec {feature-name}` -- create a specification using the research report as context
2. `/cw-plan` -- transform the spec into a task graph
3. `/cw-dispatch` -- execute tasks in parallel

The research report at `docs/specs/research-{topic_slug}.md` serves as enriched context that accelerates cw-spec's Context Assessment step (Step 2), producing more detailed and accurate specifications.
