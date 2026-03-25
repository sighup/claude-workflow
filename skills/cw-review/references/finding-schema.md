# Finding Schema

Standard schema for all review findings. All concern agents write findings in this format. Orchestrators read this format for consolidation, filtering, and FIX task creation.

## Finding Object

```json
{
  "id": "<concern>-<n>",
  "dimension": "<dimension>",
  "category": "<A|B|C|D>",
  "severity": "<critical|high|medium|low>",
  "confidence": <0-100>,
  "file": "<path>",
  "line_start": <number>,
  "line_end": <number>,
  "title": "<one-line summary>",
  "description": "<detailed explanation of the issue>",
  "evidence": "<specific code or context that supports this finding>",
  "suggestion": "<concrete fix or improvement>",
  "hidden_errors": "<for error-handling findings: specific error types that could be hidden, otherwise null>",
  "claude_md_rule": "<quoted rule from CLAUDE.md/REVIEW.md if applicable, otherwise null>",
  "cross_file_refs": ["<other files involved in this finding>"],
  "is_primary": true,
  "validation_status": null,
  "blame_classification": null,
  "challenge_status": null,
  "review_config_source": null
}
```

### Field Documentation

| Field | Required | Description |
|-------|----------|-------------|
| `id` | Yes | Unique within this agent's output. Format: `{concern}-{n}` (e.g., `bug-1`, `security-3`) |
| `dimension` | Yes | The specific review dimension (see Dimension Values below) |
| `category` | Yes | Mapped from dimension (see Dimension-to-Category Mapping) |
| `severity` | Yes | `critical`, `high`, `medium`, or `low` |
| `confidence` | Yes | 0-100 integer (see Confidence Rubric) |
| `file` | Yes | Relative path from repo root |
| `line_start` | Yes | First line of the issue |
| `line_end` | Yes | Last line of the issue |
| `title` | Yes | One-line summary, actionable |
| `description` | Yes | Detailed explanation. Must be >= 10 words |
| `evidence` | Yes | Specific code snippet, call chain, or data flow that proves the issue |
| `suggestion` | Yes | Concrete fix — not "consider improving" but "change X to Y" |
| `hidden_errors` | Conditional | Required for error-handling findings. Lists specific exception types a broad catch could mask |
| `claude_md_rule` | Conditional | Required for convention findings. Quote the exact rule text and cite the source file |
| `cross_file_refs` | Optional | Files outside the finding's `file` that are involved (callers, consumers, implementors) |
| `is_primary` | Yes | `true` if the finding falls within the agent's assigned concern, `false` for secondary findings |
| `validation_status` | Set by orchestrator | `null` (agent output), then set to `"verified"`, `"failed"`, or `"skipped"` by the orchestrator's factual grounding step |
| `blame_classification` | Set by orchestrator | `null` (agent output), then set to `"new"` or `"surfaced"` by validation pipeline step 4a (blame classification) |
| `challenge_status` | Set by orchestrator | `null` (agent output), then set to `"upheld"`, `"downgraded"`, or `"contested"` by validation pipeline step 4f (blind challenge) |
| `review_config_source` | Set by orchestrator | `null` or path to the REVIEW.md that governed this finding's thresholds |

## Dimension Values

| Dimension | Description |
|-----------|-------------|
| `bug` | Logic errors, off-by-one, null handling, race conditions, API misuse, data flow |
| `error-handling` | Silent failures, broad catches, hidden errors, missing error handling, resource leaks in error paths |
| `security` | Injection, SSRF, auth bypass, data exposure, crypto issues, access control, deserialization |
| `cross-file-impact` | Signature breakage, interface violations, data shape breakage, dependency chains, config ripple effects |
| `test-coverage` | Missing tests, untested edge cases, test quality issues, integration gaps, regression risk |
| `conventions` | CLAUDE.md/REVIEW.md rule violations, code comment compliance |
| `intent-alignment` | Spec contradictions, missing requirements, decision record violations, scope drift |
| `comments` | Factually incorrect comments, misleading documentation, stale references |
| `type-design` | Encapsulation, invariant expression, enforcement, usefulness |

## Dimension-to-Category Mapping

| Dimension | Category | Blocking | Creates FIX Task |
|-----------|----------|----------|-----------------|
| `bug` | A (Correctness) | Yes | Yes |
| `error-handling` | A (Correctness) | Yes | Yes |
| `security` | B (Security) | Yes | Yes |
| `conventions` | C (Spec Compliance) | Yes | Yes |
| `intent-alignment` | C (Spec Compliance) | Yes | Yes |
| `comments` | D (Quality) | No | No |
| `cross-file-impact` | A (Correctness) | Yes | Yes |
| `test-coverage` | D (Quality) | No | No |
| `type-design` | D (Quality) | No | No |

**Escalation**: Category D findings with `severity: "critical"` and `confidence >= 90` may be escalated to blocking by the orchestrator when the impact is data loss or security.

## Confidence Rubric

LLMs are systematically overconfident, clustering scores in the 80-100 range. Use the full range with these anchors:

| Score | Meaning | When to use |
|-------|---------|-------------|
| 0 | Pure hallucination | Code doesn't match the finding at all |
| 25 | Plausible but likely wrong | Code probably handles this through a mechanism the agent missed |
| 50 | Genuine ambiguity | Could go either way. Needs human judgment |
| 75 | Likely a real issue | Code does not appear to handle this case, no obvious mitigating factor visible |
| 100 | Certain | Bug/issue directly observable with no reasonable alternative interpretation |

### Dimension-Specific Thresholds

Findings below the post-validation threshold are downgraded to advisory and excluded from FIX task creation.

| Dimension | Minimum Confidence | Rationale |
|-----------|-------------------|-----------|
| `security` | 70 | Security false negatives are costlier than false positives |
| All others | 80 | Standard threshold for high-signal findings |

### Reporting Floor

Only report findings with confidence >= 60. Below 60, the finding is too uncertain to be worth the reviewer's attention even as advisory. The validation pipeline will apply the stricter dimension-specific thresholds above.

## Severity Rules

| Severity | Creates FIX Task | Blocks Merge | Example |
|----------|-----------------|--------------|---------|
| `critical` | Yes (if category A/B/C) | Yes | SQL injection with data access, data-corrupting logic error, empty catch around critical operation |
| `high` | Yes (if category A/B/C) | Yes | Missing auth on endpoint, likely race condition, broad catch hiding bugs |
| `medium` | No | No | Suspicious pattern, poor error context, missing security header |
| `low` | No | No | Minor improvement, informational observation |

**Do NOT create FIX tasks for:**
- Code style preferences already handled by linters
- Minor naming disagreements
- "I would have done it differently" observations
- Test code (tests are the oracle)
- Documentation gaps (unless spec requires it)
