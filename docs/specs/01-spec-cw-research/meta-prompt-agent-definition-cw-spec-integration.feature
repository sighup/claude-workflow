# Source: docs/specs/01-spec-cw-research/01-spec-cw-research.md
# Pattern: CLI/Process + State
# Recommended test type: Integration

Feature: Meta-Prompt Generation, Agent Definition, and cw-spec Integration

  Scenario: Research report includes a meta-prompt section with cw-spec starter prompt
    Given the research report has been completed with all dimension findings
    When the meta-prompt generation phase executes
    Then the research report contains a "Meta-Prompt" section at the end
    And the section includes a ready-to-use /cw-spec starter prompt

  Scenario: Meta-prompt contains all required enriched context fields
    Given the research report has been completed with findings across multiple dimensions
    When the meta-prompt is generated
    Then the meta-prompt includes a feature name derived from the research topic
    And the meta-prompt includes a problem statement derived from the research findings
    And the meta-prompt includes key components and files identified during exploration
    And the meta-prompt includes architectural constraints discovered
    And the meta-prompt includes relevant patterns to follow
    And the meta-prompt includes suggested demoable unit themes
    And the meta-prompt includes references to specific code locations in the codebase

  Scenario: User is presented with next-step options after report completion
    Given the research report and meta-prompt have been generated
    When the report completion phase is reached
    Then an AskUserQuestion prompt is displayed with three options
    And the first option is "Run /cw-spec with context (Recommended)"
    And the second option is "Review report first"
    And the third option is "Done for now"

  Scenario: Selecting cw-spec integration invokes cw-spec with the meta-prompt
    Given the user is presented with next-step options
    When the user selects "Run /cw-spec with context"
    Then /cw-spec is invoked with the meta-prompt content as the argument
    And the cw-spec session begins with the enriched research context available

  Scenario: Agent definition file is created with correct frontmatter and structure
    Given the claude-workflow plugin directory exists with standard agent structure
    When a developer runs the implementation for Unit 3
    Then a file "agents/researcher.md" is created
    And the file contains YAML frontmatter with description, capabilities, tools, and skills fields
    And the frontmatter "skills" field includes "cw-research"

  Scenario: Agent definition specifies researcher role and coordination handoff
    Given the file "agents/researcher.md" has been created
    When a team lead or dispatcher reads the agent definition
    Then the file contains a role section identifying the agent as "Researcher"
    And the file contains a coordination section stating it receives work from Team Lead
    And the file contains a coordination section stating it produces a research report
    And the file contains a coordination section stating it hands off to Spec Writer
    And the file contains a constraint that the researcher never implements code and only produces research reports

  Scenario: Skill is registered in the plugin skill listing
    Given the skill file "skills/cw-research/SKILL.md" has been created
    When the plugin's skill listing is checked
    Then cw-research appears alongside existing skills such as cw-spec, cw-plan, and cw-dispatch
