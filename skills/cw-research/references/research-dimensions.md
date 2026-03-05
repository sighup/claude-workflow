# Research Dimensions

Five exploration dimensions used by cw-research subagents. Each dimension defines what to look for during auto-explore and deep-dive phases.

## LSP Integration

When `lsp_available = true` (determined during the LSP Availability Check), append LSP-specific instructions to subagent prompts. LSP tools provide precise code intelligence that complements text-based search -- use them for tracing definitions, references, type hierarchies, and call graphs.

**LSP operations available to Explore subagents:**

| Operation | Use Case |
|-----------|----------|
| `documentSymbol` | Enumerate all symbols (functions, classes, variables) in a file |
| `goToDefinition` | Find where a symbol is defined |
| `findReferences` | Find all references to a symbol |
| `hover` | Get type info and documentation for a symbol |
| `goToImplementation` | Find implementations of an interface or abstract method |
| `incomingCalls` | Find all callers of a function |
| `outgoingCalls` | Find all functions called by a function |
| `workspaceSymbol` | Search for symbols across the entire workspace |

**When LSP is unavailable**, subagents fall back to Glob, Grep, and Read only. Prompts below include `{LSP_INSTRUCTIONS}` as a placeholder -- include it only when `lsp_available = true`.

## Dimension 1: Tech Stack & Project Structure

**Focus areas:**
- Languages and frameworks used
- Build tools and package managers
- Directory layout and organization
- Entry points and main modules
- Configuration files and environment setup

**Topic-filtered example (authentication):** Focus on auth-related frameworks (Passport, NextAuth, etc.)

**Subagent prompt:**
```
Explore this codebase and report on Tech Stack & Project Structure. Find: languages and frameworks used, build tools and package managers, directory layout and organization, entry points and main modules, configuration files and environment setup. Topic filter: {topic or 'none'}. Return a structured markdown section with key findings. Keep it focused -- list key files, not every file. Use Glob, Grep, and Read tools. {LSP_INSTRUCTIONS}
```

**LSP_INSTRUCTIONS (when available):**
```
Also use the LSP tool: use documentSymbol on entry point files to enumerate exported symbols and understand module structure. Use workspaceSymbol to search for key framework-specific symbols (e.g., "main", "app", "server", "handler").
```

## Dimension 2: Architecture & Patterns

**Focus areas:**
- Design patterns in use (MVC, plugin, event-driven, etc.)
- Module boundaries and separation of concerns
- Key abstractions and interfaces
- State management approach
- Error handling conventions
- Naming conventions

**Topic-filtered example (authentication):** Focus on auth modules, middleware, session handling

**Subagent prompt:**
```
Explore this codebase and report on Architecture & Patterns. Find: design patterns in use (MVC, plugin, event-driven, etc.), module boundaries and separation of concerns, key abstractions and interfaces, state management approach, error handling conventions, naming conventions. Topic filter: {topic or 'none'}. Return a structured markdown section with key findings and specific file references. Use Glob, Grep, and Read tools. {LSP_INSTRUCTIONS}
```

**LSP_INSTRUCTIONS (when available):**
```
Also use the LSP tool for deeper architectural analysis: use goToImplementation to discover all implementations of key interfaces and abstract classes. Use findReferences to understand how abstractions are consumed across module boundaries. Use incomingCalls and outgoingCalls to map call hierarchies and identify coupling between modules. Use hover to inspect type signatures of key abstractions.
```

## Dimension 3: Dependencies & Integrations

**Focus areas:**
- External dependencies and their purposes
- API integrations and third-party services
- Internal module dependencies and data flow between components
- Integration points where modules connect
- Configuration for external services

**Topic-filtered example (authentication):** Focus on auth libraries, OAuth providers, token services

**Subagent prompt:**
```
Explore this codebase and report on Dependencies & Integrations. Find: external dependencies and their purposes, API integrations and third-party services, internal module dependencies and data flow between components, integration points where modules connect, configuration for external services. Topic filter: {topic or 'none'}. Return a structured markdown section with key findings. Use Glob, Grep, and Read tools. {LSP_INSTRUCTIONS}
```

**LSP_INSTRUCTIONS (when available):**
```
Also use the LSP tool: use findReferences on key integration functions (API clients, database connectors, message queue publishers) to trace how they are used throughout the codebase. Use goToDefinition to trace imported symbols back to their source (especially for internal packages). Use outgoingCalls on integration points to map external service dependencies.
```

## Dimension 4: Test & Quality Patterns

**Focus areas:**
- Test frameworks and testing approach
- Test directory structure and naming conventions
- Coverage tooling and CI/CD configuration
- Linting and formatting tools
- Type checking setup
- Pre-commit hooks or quality gates

**Topic-filtered example (authentication):** Focus on auth test coverage, test patterns for protected routes

**Subagent prompt:**
```
Explore this codebase and report on Test & Quality Patterns. Find: test frameworks and testing approach, test directory structure and naming conventions, coverage tooling and CI/CD configuration, linting and formatting tools, type checking setup, pre-commit hooks or quality gates. Topic filter: {topic or 'none'}. Return a structured markdown section with key findings. Use Glob, Grep, and Read tools. {LSP_INSTRUCTIONS}
```

**LSP_INSTRUCTIONS (when available):**
```
Also use the LSP tool: use documentSymbol on representative test files to understand test structure (describe/it blocks, test classes, setup/teardown patterns). Use findReferences on test utility functions and fixtures to understand test helper reuse patterns.
```

## Dimension 5: Data Models & API Surface

**Focus areas:**
- Database schemas or data models
- API endpoints and route definitions
- Request/response shapes and validation
- Key data structures and types
- Serialization formats

**Topic-filtered example (authentication):** Focus on user models, session schemas, token structures

**Subagent prompt:**
```
Explore this codebase and report on Data Models & API Surface. Find: database schemas or data models, API endpoints and route definitions, request/response shapes and validation, key data structures and types, serialization formats. Topic filter: {topic or 'none'}. Return a structured markdown section with key findings. Use Glob, Grep, and Read tools. {LSP_INSTRUCTIONS}
```

**LSP_INSTRUCTIONS (when available):**
```
Also use the LSP tool: use documentSymbol on model/schema files to enumerate all defined types and their fields. Use goToDefinition to trace type aliases and resolve complex types. Use findReferences on key data model types to discover where they are used (API handlers, services, repositories). Use hover to inspect type signatures and understand generic/parameterized types.
```

## Topic Filtering

When a topic is specified, each subagent prompt includes the topic filter so exploration focuses on relevant areas. The topic filter narrows exploration to files, patterns, and dependencies related to the given topic, while still including other areas where they intersect.
