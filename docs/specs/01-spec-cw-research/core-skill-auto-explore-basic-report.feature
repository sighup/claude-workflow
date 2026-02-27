# Source: docs/specs/01-spec-cw-research/01-spec-cw-research.md
# Pattern: CLI/Process + Async
# Recommended test type: Integration

Feature: Core Skill with Auto-Explore and Basic Report

  Scenario: Skill file is created with required frontmatter and protocol
    Given the claude-workflow plugin directory exists with standard skill structure
    When a developer runs the implementation for Unit 1
    Then a file "skills/cw-research/SKILL.md" is created
    And the file begins with YAML frontmatter containing "name: cw-research"
    And the frontmatter contains "user-invocable: true"
    And the frontmatter contains allowed-tools including Glob, Grep, Read, Write, Bash, WebFetch, WebSearch, AskUserQuestion, and Task
    And the file body contains a markdown protocol section

  Scenario: Invoking cw-research produces a response with the correct context marker
    Given the skill "cw-research" is installed and available
    When a user invokes "/cw-research"
    Then the response begins with "CW-RESEARCH" as the context marker

  Scenario: Topic argument scopes the exploration to the given subject
    Given the skill "cw-research" is installed and available
    And a codebase with multiple modules including "authentication" and "billing"
    When a user invokes "/cw-research authentication"
    Then the research report focuses on authentication-related files, patterns, and dependencies
    And billing-specific details are not prominently featured unless they intersect with authentication

  Scenario: Auto-explore phase covers all five research dimensions
    Given the skill "cw-research" is installed and available
    And a codebase with recognizable tech stack, patterns, dependencies, tests, and data models
    When the auto-explore phase executes
    Then the research report contains a "Tech Stack & Project Structure" section with languages, frameworks, and directory layout
    And the report contains an "Architecture & Patterns" section with design patterns and module boundaries
    And the report contains a "Dependencies & Integrations" section with external deps and integration points
    And the report contains a "Test & Quality Patterns" section with test frameworks and CI/CD info
    And the report contains a "Data Models & API Surface" section with schemas and API endpoints

  Scenario: Auto-explore uses parallel subagents for simultaneous dimension exploration
    Given the skill protocol defines Task(Explore) subagent usage for research dimensions
    When the auto-explore phase executes on a codebase
    Then multiple Task(Explore) subagents are launched concurrently
    And each subagent explores a separate research dimension
    And all subagent results are collected into the final report

  Scenario: Research report is saved to the correct output path
    Given the skill "cw-research" is installed and available
    When a user invokes "/cw-research my-feature"
    And the auto-explore phase completes
    Then a file "docs/specs/research-my-feature.md" is created
    And the file uses structured markdown with section headers for each research dimension

  Scenario: Research report includes a summary section with key findings
    Given the skill "cw-research" is installed and available
    When the auto-explore phase completes and the report is saved
    Then the top of the report contains a summary section
    And the summary lists key findings and notable patterns discovered during exploration
