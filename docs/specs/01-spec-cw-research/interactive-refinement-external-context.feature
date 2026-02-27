# Source: docs/specs/01-spec-cw-research/01-spec-cw-research.md
# Pattern: CLI/Process + Error Handling
# Recommended test type: Integration

Feature: Interactive Refinement with External Context Sources

  Scenario: Auto-explore findings are presented for user confirmation
    Given the auto-explore phase has completed and produced initial findings
    When the interactive refinement phase begins
    Then a summary of the auto-explore findings is presented to the user
    And an AskUserQuestion prompt offers options to confirm, refine, or redirect focus areas

  Scenario: User is prompted for external context sources with examples
    Given the auto-explore findings have been presented to the user
    When the system asks about external context sources
    Then the prompt includes example source types: GitHub issues/PRs, Jira tickets, Confluence pages, Google Docs, filesystem paths, images, web URLs, documentation links, knowledgebase articles, and architecture decision records

  Scenario: Multiple external context sources are accepted in a single interaction
    Given the user is prompted for external context sources
    When the user provides a list containing a GitHub URL, a local file path, and a documentation URL
    Then all three sources are acknowledged and queued for processing
    And the system does not require separate prompts for each source

  Scenario: Web-based external sources are fetched and incorporated
    Given the user has provided a web URL as an external context source
    When the system processes the external sources
    Then the web URL content is fetched using WebFetch or WebSearch tools
    And relevant information from the fetched content is incorporated into the research report
    And the report attributes the information to the original web URL

  Scenario: Local file and directory sources are read and incorporated
    Given the user has provided a local file path as an external context source
    When the system processes the external sources
    Then the file content is read using Read, Glob, or Grep tools
    And relevant information is incorporated into the research report
    And the report attributes the information to the original file path

  Scenario: User-provided images are read and described in the report
    Given the user has provided a screenshot or diagram as an external context source
    When the system processes the image source
    Then the image is read via the Read tool
    And a description of the image content is included in the research report

  Scenario: Deep-dive exploration targets user-selected focus areas
    Given the user has confirmed or refined focus areas during interactive refinement
    When the deep-dive phase begins
    Then targeted Task(Explore) subagents are launched for the user-selected focus areas
    And the subagent results are integrated into the research report under the relevant dimension sections

  Scenario: Research report is updated with deep-dive findings and source attribution
    Given the deep-dive exploration and external context processing have completed
    When the report is updated
    Then the research report includes both auto-explore and deep-dive findings
    And each piece of external context information is clearly attributed to its source
    And the report distinguishes between codebase findings and external context

  Scenario: Inaccessible external source is noted without failing the research
    Given the user has provided a URL that requires authentication or is a broken link
    When the system attempts to fetch the inaccessible source
    Then the source is marked as "inaccessible" in the research report with the reason
    And the rest of the research process continues without interruption
    And no error is thrown that halts the overall research workflow
