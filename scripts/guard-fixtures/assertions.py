"""AutoResearch assertions for the guard fixture suite.

Each scenario self-grades and emits exactly one `SCENARIO_RESULT:` line. The
oracle is therefore uniform across every test case: the response passes iff that
line says `pass`. Keeping the per-scenario expected outcome inside the scenario
(which has all the state) means these assertions never change as scenarios are
added — only test_cases.jsonl grows.
"""

import re


def assert_scenario_passed(response: str) -> bool:
    """The fixture reported SCENARIO_RESULT: pass (and did not also report fail)."""
    if re.search(r"^SCENARIO_RESULT:\s*fail\b", response, re.MULTILINE):
        return False
    return bool(re.search(r"^SCENARIO_RESULT:\s*pass\s*$", response, re.MULTILINE))


# The runner imports this list. Every assertion function must be registered here.
ASSERTIONS = [
    assert_scenario_passed,
]
