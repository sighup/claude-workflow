# Automation Backends

Reference for supported automation backends in cw-testing.

## Available Backends

| Backend | Tools Required | Best For |
|---------|---------------|----------|
| `chrome-devtools` | Chrome DevTools MCP | Web UI testing with browser automation |
| `playwright-bdd` | `bddgen` CLI, `@playwright/test` | Standard Gherkin → compiled tests, CI-friendly |
| `cli` | Bash only | API testing, CLI tools, non-browser tests |
| `manual` | None | Manual verification with user confirmation |

## Detection

During setup, check which tools are available:

```
# Chrome DevTools MCP — check tool list, do NOT invoke any tool
Check whether mcp__chrome-devtools__take_snapshot is in the available tool list.
Calling any chrome-devtools tool during detection would open a browser uninvited.

# playwright-bdd (global or local install)
command -v bddgen 2>/dev/null  # global install
# OR
npx bddgen --version 2>/dev/null  # local install

# Bash is always available
# Manual mode is always available
```

## Chrome DevTools MCP

Requires the Chrome DevTools MCP server to be configured and running.

| Action | MCP Call |
|--------|----------|
| Navigate | `mcp__chrome-devtools__navigate_page({ url, type: "url" })` |
| Click | `mcp__chrome-devtools__click({ uid })` |
| Type | `mcp__chrome-devtools__fill({ uid, value })` |
| Screenshot | `mcp__chrome-devtools__take_screenshot({ filePath })` |
| Get page state | `mcp__chrome-devtools__take_snapshot()` |
| Wait for text | `mcp__chrome-devtools__wait_for({ text })` |
| Press key | `mcp__chrome-devtools__press_key({ key })` |

## CLI Backend

No MCP required. Uses Bash for all operations:

| Action | Command |
|--------|---------|
| HTTP GET | `curl -s <url>` |
| HTTP POST | `curl -s -X POST -d '<data>' <url>` |
| Assert output | Check command exit code and stdout |
| Run script | `bash <script>` or `npm run <script>` |

## Manual Backend

No tools required. The skill prompts the user to:
1. Perform each action manually
2. Observe the result
3. Confirm success/failure via AskUserQuestion

Best for:
- One-off tests
- Complex scenarios automation can't handle
- Environments without MCP access

## playwright-bdd Backend

Requires `bddgen` CLI and `@playwright/test`. See `playwright-bdd-backend.md` for full details.

This backend compiles `.feature` files into TypeScript test specs **before** execution. Tests run headlessly via Bash — no AI agent involvement during execution. CI-compatible.

**Key constraint**: `bddgen` exits non-zero if any step lacks a TypeScript implementation. All steps must be defined before the suite can run.

## Backend Verification

During execution, verify the selected backend is available:

| Backend | Verification |
|---------|-------------|
| `chrome-devtools` | Check that `mcp__chrome-devtools__take_snapshot` is in the available tool list |
| `playwright-bdd` | `command -v bddgen 2>/dev/null \|\| npx bddgen --version 2>/dev/null` |
| `cli` | Verify `curl` or test commands work |
| `manual` | No verification needed |

If backend unavailable, offer to switch to `manual` or `cli`.
