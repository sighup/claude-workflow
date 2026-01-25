# Proof Artifact Types Reference

How to collect each type of proof artifact during Phase 6 of the execution protocol.

## File Naming Convention

```
{task_id}-{proof_index}-{type}.{ext}
```

- `task_id`: From metadata (T01, T02, T01.1, etc.)
- `proof_index`: 1-based, zero-padded (01, 02, 03...)
- `type`: Artifact type name
- `ext`: `txt` for text, `png` for images

Examples: `T01-01-test.txt`, `T01-02-cli.txt`, `T03-01-browser.png`

## Type: `test`

**Purpose**: Run a test command and capture results.

**Metadata fields**:
```json
{
  "type": "test",
  "command": "npm test -- src/auth/login.test.ts",
  "expected": "All pass"
}
```

**Collection steps**:
1. Execute the `command` via Bash
2. Capture full stdout + stderr
3. Write to output file with header:
   ```
   PROOF ARTIFACT: test
   Command: npm test -- src/auth/login.test.ts
   Expected: All pass
   Timestamp: 2026-01-24T15:30:00Z
   ---
   [full output]
   ```
4. Determine PASS/FAIL by checking output against `expected`

**Pass criteria**: Test command exits 0 AND output matches expected pattern.

## Type: `cli`

**Purpose**: Run a CLI command and verify output.

**Metadata fields**:
```json
{
  "type": "cli",
  "command": "curl -s http://localhost:3000/health",
  "expected": "{\"status\":\"ok\"}"
}
```

**Collection steps**:
1. Execute the `command` via Bash
2. Capture stdout
3. Write to output file with header
4. Compare output against `expected` (substring match or exact match)

**Pass criteria**: Command exits 0 AND output contains/matches expected.

**Notes**:
- For curl commands, consider adding `-s` (silent) and `-w '\n%{http_code}'` for status
- Ensure any servers needed are running before executing
- Use `timeout` wrapper for commands that might hang

## Type: `url`

**Purpose**: Make an HTTP request and verify response.

**Metadata fields**:
```json
{
  "type": "url",
  "url": "http://localhost:3000/api/users",
  "method": "GET",
  "expected": "200 + JSON array"
}
```

**Collection steps**:
1. Execute HTTP request (via curl or similar)
2. Capture: HTTP status code, response headers, response body
3. Write all to output file
4. Verify status code and body match expected

**Pass criteria**: HTTP status matches AND response body matches expected pattern.

## Type: `file`

**Purpose**: Verify a file exists with expected content.

**Metadata fields**:
```json
{
  "type": "file",
  "path": "src/auth/middleware.ts",
  "contains": "export function authMiddleware"
}
```

**Collection steps**:
1. Check file exists at `path`
2. If `contains` specified: search file for the pattern
3. Write to output file:
   ```
   PROOF ARTIFACT: file
   Path: src/auth/middleware.ts
   Contains: export function authMiddleware
   Timestamp: ...
   ---
   File exists: YES
   Pattern found: YES (line 15)
   ```

**Pass criteria**: File exists AND (if `contains` specified) pattern is found.

## Type: `browser`

**Purpose**: Browser-based verification with screenshot.

**Metadata fields**:
```json
{
  "type": "browser",
  "prompt": "Navigate to /login, fill in credentials, submit form",
  "expected": "Redirect to /dashboard with welcome message"
}
```

**Collection steps**:
1. Use available browser automation (Chrome DevTools MCP, Playwright, etc.)
2. Execute the actions described in `prompt`
3. Capture screenshot to `{task_id}-{index}-browser.png`
4. Create text log at `{task_id}-{index}-browser.txt`:
   ```
   PROOF ARTIFACT: browser
   Prompt: Navigate to /login, fill in credentials, submit form
   Expected: Redirect to /dashboard with welcome message
   Timestamp: ...
   ---
   Actions performed:
   1. Navigated to http://localhost:3000/login
   2. Filled email field with test@example.com
   3. Filled password field with [REDACTED]
   4. Clicked submit button
   5. Page redirected to /dashboard

   Result: Welcome message displayed
   Status: PASS
   ```

**Pass criteria**: Final state matches expected description.

**Notes**:
- Always use placeholder credentials (test@example.com, etc.)
- If no browser automation available, mark as SKIP with explanation
- Screenshots must not contain real credentials

## Summary File Template

After all artifacts collected, create `{task_id}-proofs.md`:

```markdown
# Proof Artifacts: {task_id} - {task_title}

**Task ID**: {task_id}
**Status**: PASS | FAIL
**Executed**: {timestamp}
**Spec**: {spec_path}

## Summary

| # | Type | Description | Result | File |
|---|------|-------------|--------|------|
| 01 | test | {description} | PASS | [{task_id}-01-test.txt](./{task_id}-01-test.txt) |
| 02 | cli | {description} | PASS | [{task_id}-02-cli.txt](./{task_id}-02-cli.txt) |

## Requirements Verified

| Requirement | Description | Verified By | Status |
|-------------|-------------|-------------|--------|
| R01.1 | {text} | Artifact 01 | PASS |
| R01.2 | {text} | Artifact 02 | PASS |

## Detailed Results

### 01: test
{Content from test output file}

### 02: cli
{Content from CLI output file}

## Verification Checklist

- [x] All proof artifacts executed
- [x] Output matches expected results
- [x] No sensitive data (security scan passed)
- [x] Files staged with implementation commit
```
