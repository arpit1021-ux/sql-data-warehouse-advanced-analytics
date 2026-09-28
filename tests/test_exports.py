"""The committed data/gold CSVs must be exactly what the pipeline produces."""

import pytest

from pipeline import config, steps


@pytest.fixture(scope="module")
def fresh_exports(warehouse, tmp_path_factory):
    export_dir = tmp_path_factory.mktemp("gold")
    steps.export_gold(warehouse, export_dir)
    return export_dir


@pytest.mark.parametrize("view", config.GOLD_EXPORTS)
def test_committed_export_is_up_to_date(fresh_exports, view):
    committed = (config.GOLD_EXPORT_DIR / f"{view}.csv").read_bytes().replace(b"\r\n", b"\n")
    fresh = (fresh_exports / f"{view}.csv").read_bytes()
    assert committed == fresh, f"data/gold/{view}.csv is stale - run `python -m pipeline run`"
