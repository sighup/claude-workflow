# Type Design Analyzer Reference

Expertise for evaluating whether types are designed to make invalid states unrepresentable, enforce their invariants, and communicate contracts clearly through structure. **This concern is conditional** — only activated when new types (class, interface, struct, record, enum, union type) are introduced or substantially modified.

## Quick Reference — Four Dimensions

For each significant type added or substantially modified, rate on four dimensions (1-10 each):

### 1. Encapsulation (1-10)

- Are internal implementation details hidden from consumers?
- Can invariants be violated from outside the type without going through its public API?
- Is the public interface minimal and complete — exposing what's needed but nothing more?
- Are mutable fields exposed directly, or mediated through methods that maintain invariants?

### 2. Invariant Expression (1-10)

- Are the type's rules and constraints clearly communicated through its structure?
- Are invariants enforced at compile time where possible (union types, enums, branded types, sealed classes)?
- Is the type self-documenting — can a reader understand valid states from the definition alone?
- Are impossible states excluded by type structure, or only by documentation?

### 3. Invariant Usefulness (1-10)

- Do invariants prevent real bugs that would plausibly occur?
- Are they aligned with business rules and domain constraints?
- Neither too restrictive (preventing valid use cases) nor too permissive (allowing invalid states)?
- Right level of precision for this domain?

### 4. Invariant Enforcement (1-10)

- Are invariants checked at construction time (constructor, factory, builder)?
- Are all mutation points guarded to maintain invariants?
- Is it impossible to create an instance in an invalid state?
- Are partial construction and intermediate invalid states prevented?

## Anti-Patterns to Flag

**Anemic domain models** — Types that are just bags of public fields with no behavior. Business logic scattered across service classes instead of living on the types. Types that can be put into any state because they have no constraints.

**Exposed mutable internals** — Public mutable collections bypassing invariant checks. Mutable fields that should be readonly/final. Getter methods returning mutable references to internal state.

**Invariants enforced only by documentation** — Comments saying "this field must be positive" without validation. README constraints not checked in code. Naming conventions as sole enforcement mechanism.

**Types with too many responsibilities** — God objects accumulating unrelated fields. Types serving multiple bounded contexts with different invariants. Types where half the fields are optional because they only apply in certain modes.

**Missing validation at construction boundaries** — Constructors accepting raw primitives without validation. Factory methods not checking preconditions. Deserialization creating instances without invariant checks. Builders allowing `build()` in incomplete states.

## Design Principles

- **Prefer compile-time guarantees over runtime checks.** A type that can't represent an invalid state is better than one that validates at runtime.
- **Make illegal states unrepresentable.** Use the type system to exclude impossible combinations.
- **Immutability simplifies invariant maintenance.** Immutable + valid at construction = valid forever.
- **Parse, don't validate.** Convert unstructured data into structured types at the boundary, then work with structured types internally.

## What You Do NOT Report

- Type design in test code (different design pressures)
- Trivial DTOs that are intentionally anemic data carriers with no invariants
- Pre-existing issues in types the author didn't substantially modify
- Language limitations preventing ideal type design
- Style preferences about naming, casing, or organization

## Calibration

WARNING: LLMs are systematically overconfident, clustering scores in the 80-100 range. Calibrate carefully: 90-100 = exact trigger identifiable, 70-89 = likely real but needs more context, 50-69 = suspicious but uncertain. Use the full range.

Report findings with confidence >= 60. The validation pipeline will apply stricter dimension-specific thresholds (80 for type design).

### Confidence

- **90-100**: Clear invariant violation — you can show a code path that creates an invalid instance or bypasses enforcement.
- **80-89**: Significant weakness likely leading to bugs — exposed mutable internals, missing construction validation, anemic design in a domain needing invariants.
- **70-79**: Type design could be improved and creates maintenance risk, but not immediately dangerous.
- **60-69**: Plausible type design issue but significant uncertainty remains.

### Output Format

For each finding, include the four dimension ratings in the description field: "Encapsulation: 4/10, Expression: 6/10, Usefulness: 8/10, Enforcement: 3/10" followed by the specific issue and recommendation.
