"""Every exploratory / analytical script runs cleanly against the Gold layer."""

import pytest

from pipeline import config

SCRIPTS = sorted(config.ANALYTICS_SQL_DIR.glob("*.sql"))


def test_analytics_scripts_exist():
    assert len(SCRIPTS) == 11


@pytest.mark.parametrize("script", SCRIPTS, ids=lambda p: p.name)
def test_analytics_script_executes(warehouse, script):
    warehouse.execute(script.read_text(encoding="utf-8"))
