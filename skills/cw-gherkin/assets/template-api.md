# Scenario Template: API / HTTP Feature

Use for features involving HTTP endpoints, REST APIs, request/response cycles, or service integrations.

**Recommended test type:** Integration

## Template

```gherkin
Feature: [Demoable Unit Title]

  Scenario: [Functional requirement as observable request/response behavior]
    Given [server state — running, seeded data, auth token]
    When [HTTP request — method, path, headers, body]
    Then [HTTP response — status code, response body shape]
    And [secondary verification — database state, emitted event, side-effect]
```

## Example

```gherkin
Feature: Create User Endpoint

  Scenario: Valid request creates user and returns 201
    Given the API server is running
    And no user with email "new@example.com" exists
    When a POST request is sent to /users with body {"email":"new@example.com","name":"Alice"}
    Then the response status is 201
    And the response body contains an "id" field
    And the response body contains "email": "new@example.com"
    And a user record exists in the database with that email

  Scenario: Duplicate email returns 409 Conflict
    Given a user with email "existing@example.com" already exists
    When a POST request is sent to /users with body {"email":"existing@example.com","name":"Bob"}
    Then the response status is 409
    And the response body contains "error": "Email already registered"
    And no new user record is created in the database
```

## Guidelines

- `Given`: Real server state — running application, seeded database rows, valid auth token
- `When`: Full request specification — method, path, headers (auth), body
- `Then`: HTTP status code first, then response body fields
- `And`: Verify side effects — database rows created/modified, events emitted, cache updated

## Common Mistakes

- ❌ `Then the handler function is called` (verify the response, not the internals)
- ❌ `Then the request is valid` (submit the request and verify the actual response)
- ✅ `Then the response status is 201`
- ✅ `And the response body contains "id"`
