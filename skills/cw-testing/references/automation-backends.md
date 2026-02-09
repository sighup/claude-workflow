# Automation Backends

Reference for supported automation backends in cw-testing.

## Available Backends

| Backend | Tools Required | Best For |
|---------|---------------|----------|
| `chrome-devtools` | Chrome DevTools MCP | Web UI testing with browser automation |
| `playwright` | Playwright MCP | Web UI testing with Playwright |
| `cli` | Bash only | API testing, CLI tools, non-browser tests |
| `manual` | None | Manual verification with user confirmation |

## Detection

During `init`, check which tools are available:

```
# Chrome DevTools MCP
try: mcp__chrome-devtools__list_pages() → available

# Playwright MCP
try: mcp__playwright__* → available

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

## Playwright MCP

Requires Playwright MCP server. Use equivalent Playwright commands.

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

## Backend Verification

During `run`, verify the selected backend is available:

| Backend | Verification |
|---------|-------------|
| `chrome-devtools` | Call `mcp__chrome-devtools__list_pages()` |
| `playwright` | Call `mcp__playwright__list_browsers()` |
| `cli` | Verify `curl` or test commands work |
| `manual` | No verification needed |

If backend unavailable, offer to switch to `manual` or `cli`.
