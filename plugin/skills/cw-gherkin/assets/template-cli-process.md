# Scenario Template: CLI / Process Feature

Use for features involving command-line interfaces, spawned processes, flags, stdout/stderr output, or exit codes.

**Recommended test type:** Integration

## Template

```gherkin
Feature: [Demoable Unit Title]

  Scenario: [Functional requirement as observable process behavior]
    Given [environment setup — files present, env vars set, working directory]
    When [command invocation with specific flags/arguments]
    Then [primary observable outcome — stdout output, file created, exit code]
    And [secondary verification — stderr clean, side-effect file, downstream state]
```

## Example

```gherkin
Feature: Generate Report Command

  Scenario: --format flag produces CSV output
    Given a data directory with 3 records
    When the user runs "mytool generate --format csv --output report.csv"
    Then the command exits with code 0
    And a file "report.csv" is created in the current directory
    And the file contains a header row and 3 data rows

  Scenario: Missing required argument prints usage and exits non-zero
    Given the tool is installed
    When the user runs "mytool generate" with no arguments
    Then the command exits with code 1
    And stderr contains "Error: --output is required"
    And a usage example is printed to stderr
```

## Guidelines

- `Given`: Real file system setup — create input files, set env vars
- `When`: Exact command invocation including flags and values
- `Then`: Exit code, stdout content, or created file — all observable without reading source
- `And`: Stderr state, side-effect files, downstream artifacts

## Common Mistakes

- ❌ `Then the flag is parsed correctly` (check the effect of the flag, not that parsing happened)
- ❌ `When I call the parseArgs function` (test the CLI, not internals)
- ✅ `Then stdout contains "Generated 3 records"`
- ✅ `And the command exits with code 0`
