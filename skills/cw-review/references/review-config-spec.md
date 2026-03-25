# REVIEW.md Configuration Specification

A `REVIEW.md` file lets project maintainers customize how code review behaves. It can live at the repository root and in subdirectories alongside CLAUDE.md files. It's optional — sensible defaults apply when absent.

## Format

REVIEW.md is a markdown file with specific sections. Each section is optional.

```markdown
# Review Configuration

## Focus
- bugs
- security

## Skip
- "**/*.generated.cs"
- "**/migrations/**"
- "vendor/**"

## Rules
- All database queries must use parameterized statements, never string concatenation
- Public API endpoints must validate request body schema before processing

## Severity Threshold
medium

## Confidence Threshold
80

## Max Findings
15

## Model Tier
optimized

## Ignore
- compliance:"import order"
- security:"console.log in development mode"
```

## Section Details

### Focus

Controls which review dimensions run. Valid values:
- `bugs` — Bug detection + error handling (bug-detector agent)
- `security` — Security vulnerabilities (security-reviewer agent)
- `cross-file-impact` — Cross-file impact analysis
- `tests` — Test coverage gaps (test-analyzer agent)
- `conventions` — Convention compliance + intent alignment + comments
- `types` — Type design analysis (conditional)

When omitted, all applicable dimensions run. When specified, ONLY listed dimensions run. Overrides light review mode.

### Skip

Glob patterns for files to exclude from review. Common uses: generated code, vendored dependencies, build output, migration files, large data files. Files matching skip patterns are removed from the changed files list before any review.

### Rules

Custom natural-language rules checked by all review agents alongside built-in logic. Rules should be:
- Specific and actionable (not vague guidelines)
- Objectively verifiable (binary pass/fail)
- Focused on code state (not process/workflow)

Limit to 15-25 rules per file. Beyond this, LLM adherence degrades for ALL rules. Place security and correctness rules first. Include rationale for each rule.

### Severity Threshold

Minimum severity to include in the report: `critical`, `high`, `medium` (default), or `low`.

### Confidence Threshold

Integer 0-100. Findings below this score are filtered out. Default: 80. Security findings always use a minimum of 70 regardless of this setting.

### Max Findings

Maximum findings in the report. Default: no limit. When hit, highest-severity findings are kept and a note indicates how many were suppressed. Set `0` for no limit.

### Model Tier

Default review mode. When set, skips the mode selection logic:
- `optimized` (default) — Sonnet for most agents, Opus for security. ~40% cheaper.
- `frontier` — Opus for all agents. Maximum depth for high-stakes reviews.

### Ignore

Patterns for suppressing known false positives. Format: `dimension:"pattern"` where dimension is a review dimension name (or `*` for all) and pattern is a substring to match against finding titles/descriptions.

## Discovery Algorithm

REVIEW.md files are discovered lazily during Step 1 (Gather Context):

1. Check for `REVIEW.md` at the repo root
2. Find all CLAUDE.md locations in directories containing changed files
3. Check each CLAUDE.md location for a matching REVIEW.md

### If no REVIEW.md found anywhere

Offer scaffolding via `AskUserQuestion`:
```
AskUserQuestion(
  question: "No REVIEW.md found. REVIEW.md lets you customize review behavior — confidence thresholds, ignore patterns, project-specific rules. Create one?",
  options: ["Yes — create at repo root", "Not now — continue without it"]
)
```

### If root exists but subdirectory CLAUDE.md lacks matching REVIEW.md

```
AskUserQuestion(
  question: "Found REVIEW.md at repo root, but {directory} has a CLAUDE.md without a matching REVIEW.md. A subdirectory REVIEW.md lets you set different review standards for this area. Create one?",
  options: ["Yes — create it (inherits root, adds directory-specific rules)", "Not now — root config applies"]
)
```

## Hierarchy

Root REVIEW.md is the base. Subdirectory REVIEW.md files layer on top:

| Section | Behavior | Rationale |
|---------|----------|-----------|
| `confidence_threshold` | **Override** | A module may need stricter/looser thresholds |
| `severity_threshold` | **Override** | Some areas warrant lower-severity reporting |
| `max_findings` | **Override** | High-debt areas may need a cap |
| `model_tier` | **Override** | Security-critical directories might always use frontier |
| `focus` | **Override** | A directory may need only specific dimensions |
| `rules` | **Accumulate** | Subdirectory rules add to root rules |
| `ignore` | **Accumulate** | Suppressions are additive |
| `skip` | **Accumulate** | Skip patterns are additive |

In short: **settings override, rules and patterns accumulate.**

## Scaffolding Templates

### Root REVIEW.md

```markdown
# Review Configuration

## Confidence Threshold
80

## Skip
<!-- Uncomment patterns that apply -->
<!-- **/dist/** -->
<!-- **/build/** -->
<!-- **/*.generated.* -->
<!-- **/vendor/** -->

## Rules
<!-- Add 15-25 project-specific rules. Each should be:
     - Specific and verifiable (pass/fail)
     - Include rationale
     - Use CRITICAL: prefix for security/correctness rules (3-4 max)
     - Don't duplicate linters -->

## Ignore
<!-- Suppress known false positives. Format: dimension:"pattern" (reason, date) -->
```

### Subdirectory REVIEW.md

```markdown
# Review Configuration — [directory name]
<!-- Settings override root. Rules and ignore patterns accumulate. -->

## Rules
<!-- Directory-specific rules (add to root rules) -->

## Ignore
<!-- Directory-specific suppressions (add to root ignores) -->
```
