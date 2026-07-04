# Gherkin Scenario Templates

This directory contains Gherkin scenario templates used by `cw-gherkin` to generate behavioral BDD scenarios from spec acceptance criteria. Each template provides a structured pattern with examples, guidelines, and common mistakes for a specific feature type.

## Template Index

| Template | Signal Keywords | Description |
|----------|----------------|-------------|
| `template-api.md` | API, endpoint, HTTP, REST | Scenarios for HTTP endpoints and REST API request/response cycles |
| `template-async.md` | async, parallel, concurrent | Scenarios for parallel operations, background tasks, and timing constraints |
| `template-cli-process.md` | CLI, command, flag, stdout | Scenarios for command-line interfaces, process invocation, and exit codes |
| `template-error-handling.md` | error, fail, invalid, recovery | Scenarios for failure injection, invalid input rejection, and graceful degradation |
| `template-state.md` | state, persist, restart, file | Scenarios for data persistence across system boundaries like restarts and crashes |
| `template-web-ui.md` | UI, page, browser, form | Scenarios for user-facing browser interactions, pages, and forms |

## Combining Templates

Real features often show signals for multiple types. When a spec contains keywords from more than one category, read the relevant templates and combine their clause patterns. For example, a web form that persists state across restarts would draw from both `template-web-ui.md` and `template-state.md`.
