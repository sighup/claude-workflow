# Scenario Template: Web / UI Feature

Use for user-facing features involving browsers, pages, forms, or visual interactions.

**Recommended test type:** E2E

## Template

```gherkin
Feature: [Demoable Unit Title]

  Scenario: [Functional requirement as observable UI behavior]
    Given [page or application state — URL, login status, seed data]
    When [user action — navigation, form input, button click]
    Then [primary visible outcome — content rendered, redirect, modal shown]
    And [secondary verification — form state, URL changed, error/success message]
```

## Example

```gherkin
Feature: User Login

  Scenario: Valid credentials redirect to dashboard
    Given the login page is displayed at /login
    When the user enters "user@example.com" and a valid password and clicks Login
    Then the page redirects to /dashboard
    And a welcome message containing "user@example.com" is visible

  Scenario: Invalid credentials show inline error
    Given the login page is displayed at /login
    When the user enters "user@example.com" and an incorrect password and clicks Login
    Then the page remains at /login
    And an error message "Invalid email or password" appears below the form
    And the password field is cleared
```

## Guidelines

- `Given`: Set up page state with specific URL, seed data, or login status
- `When`: One user action — navigate, fill, click, select, upload
- `Then`: Primary observable UI change — rendered text, URL, visible element
- `And`: Additional observable state — form value, error badge, network indicator

## Common Mistakes

- ❌ `Then the component renders` (not observable — which component? what content?)
- ❌ `Then the API returns 200` (not visually verifiable in E2E)
- ❌ `Then the state is updated` (inspect the UI, not internal state)
- ✅ `Then the success banner "Saved" appears at the top of the page`
