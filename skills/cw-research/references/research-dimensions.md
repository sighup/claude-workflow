# Research Dimensions

Five exploration dimensions used by cw-research subagents. Each dimension defines what to look for during auto-explore and deep-dive phases.

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
Explore this codebase and report on Tech Stack & Project Structure. Find: languages and frameworks used, build tools and package managers, directory layout and organization, entry points and main modules, configuration files and environment setup. Topic filter: {topic or 'none'}. Return a structured markdown section with key findings. Keep it focused -- list key files, not every file. Use Glob, Grep, and Read tools.
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
Explore this codebase and report on Architecture & Patterns. Find: design patterns in use (MVC, plugin, event-driven, etc.), module boundaries and separation of concerns, key abstractions and interfaces, state management approach, error handling conventions, naming conventions. Topic filter: {topic or 'none'}. Return a structured markdown section with key findings and specific file references. Use Glob, Grep, and Read tools.
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
Explore this codebase and report on Dependencies & Integrations. Find: external dependencies and their purposes, API integrations and third-party services, internal module dependencies and data flow between components, integration points where modules connect, configuration for external services. Topic filter: {topic or 'none'}. Return a structured markdown section with key findings. Use Glob, Grep, and Read tools.
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
Explore this codebase and report on Test & Quality Patterns. Find: test frameworks and testing approach, test directory structure and naming conventions, coverage tooling and CI/CD configuration, linting and formatting tools, type checking setup, pre-commit hooks or quality gates. Topic filter: {topic or 'none'}. Return a structured markdown section with key findings. Use Glob, Grep, and Read tools.
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
Explore this codebase and report on Data Models & API Surface. Find: database schemas or data models, API endpoints and route definitions, request/response shapes and validation, key data structures and types, serialization formats. Topic filter: {topic or 'none'}. Return a structured markdown section with key findings. Use Glob, Grep, and Read tools.
```

## Topic Filtering

When a topic is specified, each subagent prompt includes the topic filter so exploration focuses on relevant areas. The topic filter narrows exploration to files, patterns, and dependencies related to the given topic, while still including other areas where they intersect.
