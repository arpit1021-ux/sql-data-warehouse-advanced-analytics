"""Every declarative check in sql/quality must hold on a fresh build."""

import pytest

from pipeline import config
from pipeline.quality import load_checks, run_check

CHECKS = [check for path in config.QUALITY_FILES for check in load_checks(path)]

# Known source-data issues surfaced as warnings. Pinning the counts means a new
# bad record in the extracts fails the build instead of passing silently.
EXPECTED_WARNINGS = {
    "crm_sales_details: every line has a valid order date (invalid source dates are nulled)": 19,
    "erp_cust_az12: birthdates are after 1924-01-01 and not in the future": 15,
}


def test_quality_files_are_parsed():
    assert len(CHECKS) >= 25
    assert {c.severity for c in CHECKS} == {"error", "warn"}


@pytest.mark.parametrize("check", [c for c in CHECKS if c.severity == "error"], ids=lambda c: c.name)
def test_error_check_passes(warehouse, check):
    result = run_check(warehouse, check)
    assert result.passed, f"{result.failing_rows} rows violate: {check.name}"


@pytest.mark.parametrize("check", [c for c in CHECKS if c.severity == "warn"], ids=lambda c: c.name)
def test_warning_check_matches_known_issue_count(warehouse, check):
    assert check.name in EXPECTED_WARNINGS, f"undocumented warning check: {check.name}"
    assert run_check(warehouse, check).failing_rows == EXPECTED_WARNINGS[check.name]
