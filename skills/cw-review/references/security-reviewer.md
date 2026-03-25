# Security Reviewer Reference

Expertise for finding security vulnerabilities that an attacker could exploit — not theoretical risks, but concrete attack vectors in the code changes.

## Critical Principle

**Investigate the entire codebase.** Security vulnerabilities often span multiple files. A function that's safe today because its input comes from config may become exploitable when a future route passes user input to it. You MUST trace data flows beyond the diff. Use Read, Grep, and LSP to explore the full repository, not just the changed files.

**Lower confidence threshold.** Security findings use a minimum post-validation threshold of 70 (instead of 80) because security false negatives are costlier than false positives. Report findings with confidence >= 60 to ensure borderline security issues reach validation.

## Quick Reference

### Mandatory Investigation Checklist

Regardless of PR size, you MUST check ALL of the following. Do not skip items even if they seem unlikely.

1. **Path construction** — Search for every `path.join`, `Path.Combine`, `os.path.join`, `filepath.Join`, URL concatenation in the diff. For each, check if ANY component could be user-controlled. If so, check for traversal guards (`../`, `..\\`, encoded variants).
2. **Prompt/template injection** — Search for every string interpolation, template rendering, or concatenation producing a prompt, query, HTML, SQL, or shell command. Check if any interpolated value could contain adversarial content.
3. **Secrets in code** — Search for patterns matching API keys, tokens, passwords, connection strings. Check hardcoded values, config files in the diff, and default values in settings.
4. **Auth checks on new endpoints** — For every new route, controller, API handler, or RPC endpoint, verify authorization is checked before the operation executes.
5. **Deserialization of external input** — Search for deserialization calls on data from outside the process (HTTP bodies, message queues, file reads). Check for unsafe deserialization patterns in any language.

### Vulnerability Classes

**Injection** (SQLi, XSS, command injection, LDAP, template injection) — User input concatenated into SQL, shell commands, HTML, or templates without sanitization. Dynamic query construction from untrusted data. Use of dynamic code evaluation with user-controlled input (eval, Function constructor, etc.). Template literals with unsanitized data in HTML. Command-line arguments built from user input without escaping.

**Server-Side Request Forgery (SSRF)** — User-controlled URLs passed to server-side HTTP clients without allowlist. Redirect-following reaching internal services (169.254.169.254, localhost). URL parsing inconsistencies bypassing allowlists. Webhook URLs without destination validation.

**Broken authentication/session** — Hardcoded credentials, API keys, tokens. Weak password hashing (MD5, SHA1 without salt). Session tokens in URLs or logs. Missing session invalidation. JWT issues (missing expiration, algorithm confusion, weak keys). Missing rate limiting on auth endpoints.

**Sensitive data exposure** — PII/credentials logged or in error messages. Sensitive data in URL parameters. Missing encryption at rest/in transit. Overly permissive CORS. API responses with excess data.

**Broken access control** — Missing authorization checks. IDOR (user-supplied IDs without ownership verification). Privilege escalation paths. Missing CSRF protection on state-changing operations. Path traversal. Mass assignment / over-posting (user input bound to models without field allowlist).

**Unsafe deserialization** — Use of `pickle.loads`, `yaml.load` (without SafeLoader), `Marshal.load` on untrusted data. `JSON.parse` combined with class instantiation or prototype assignment from user input. Any deserialization format that can trigger constructors or callbacks (Java `ObjectInputStream`, PHP `unserialize`, .NET `BinaryFormatter`). Deserialized objects used without type and field validation.

**Security misconfiguration** — Debug modes in production. Default credentials. Overly permissive permissions/IAM. Missing security headers (CSP, X-Frame-Options, HSTS). Disabled TLS verification.

**Resource exhaustion / DoS** — Missing rate limiting on expensive endpoints. ReDoS (nested quantifiers on user input). Unbounded file uploads. Unbounded database queries. Algorithmic complexity attacks.

**Cryptographic issues** — Broken algorithms (MD5, SHA1, DES, RC4). Hardcoded IVs, salts, nonces. Predictable RNG for security (Math.random vs crypto). Rolling custom crypto. Missing integrity checks.

**Dependency/supply chain** — Known vulnerable versions in the diff. Imports from untrusted sources. Postinstall scripts in new dependencies.

## Investigation Methodology

1. **Build an input-to-sink map.** This is your primary methodology:
   - **(a)** List all inputs entering through the diff — HTTP parameters, headers, file uploads, environment variables, database reads, message queue payloads, deserialized objects.
   - **(b)** Trace each input forward through every function call, assignment, and transformation.
   - **(c)** Flag any path where an input reaches a dangerous sink (SQL query, shell command, HTML output, filesystem operation, URL fetch, deserialization call) without passing through adequate sanitization or validation.

2. **Check access boundaries.** For each changed endpoint or function, verify authorization is checked before the operation runs.

3. **Inspect secrets handling.** Look for anything resembling a credential, key, or token. Check if properly managed (env vars, secret managers) vs hardcoded.

4. **Review crypto usage.** If cryptographic operations changed, verify algorithm choices, key management, and randomness sources.

5. **Assess blast radius.** For each finding, think about what an attacker could actually do. Severity should match real-world impact.

## What You Do NOT Report

- Theoretical vulnerabilities requiring an already-compromised system
- Best-practice suggestions with no concrete attack vector
- Issues in test code (test credentials, test-only HTTP calls)
- Issues clearly pre-existing and not affected by this change

## Calibration

WARNING: LLMs are systematically overconfident, clustering scores in the 80-100 range. Calibrate carefully: 90-100 = exact trigger identifiable, 70-89 = likely real but needs more context, 50-69 = suspicious but uncertain. Use the full range.

Report findings with confidence >= 60. The validation pipeline will apply stricter dimension-specific thresholds (70 for security — lower because security false negatives are costlier than false positives).

### Severity

- **Critical**: Remote code injection, SQL injection with data access, authentication bypass, exposed production secrets, unsafe deserialization of untrusted input.
- **High**: XSS in authenticated context, IDOR with data access, CSRF on sensitive operations, path traversal, SSRF reaching internal services, mass assignment allowing privilege escalation.
- **Medium**: Information disclosure (error messages, stack traces), missing security headers, weak but not broken crypto, ReDoS on user-facing input.
- **Low**: Best-practice deviations with minimal practical impact.

### Confidence

- **90-100**: You can describe the specific attack vector step by step.
- **80-89**: Vulnerability pattern clearly present, but exploitation depends on context you can't fully verify.
- **70-79**: Code looks risky and matches a known vulnerability class, but needs more context to confirm.
- **60-69**: Plausible vulnerability but significant uncertainty remains.

Think like an attacker reviewing this diff for exploitation opportunities. But also think like a colleague — report real risks, not paranoia.
