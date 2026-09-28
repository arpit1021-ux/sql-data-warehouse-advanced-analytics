"""Load behaviour: completeness, auditing and failure handling."""

import csv

import psycopg
import pytest

from pipeline import config

from .conftest import scalar

SOURCE_FILES = {
    "crm_cust_info": "crm/cust_info.csv",
    "crm_prd_info": "crm/prd_info.csv",
    "crm_sales_details": "crm/sales_details.csv",
    "erp_loc_a101": "erp/LOC_A101.csv",
    "erp_cust_az12": "erp/CUST_AZ12.csv",
    "erp_px_cat_g1v2": "erp/PX_CAT_G1V2.csv",
}


def data_rows(relative_path: str) -> int:
    with (config.RAW_DATA_DIR / relative_path).open(newline="", encoding="utf-8") as handle:
        return sum(1 for _ in csv.reader(handle)) - 1


@pytest.mark.parametrize("table, file", SOURCE_FILES.items())
def test_bronze_loads_every_source_row(warehouse, table, file):
    assert scalar(warehouse, f"SELECT COUNT(*) FROM bronze.{table}") == data_rows(file)


def test_load_log_records_every_table(warehouse):
    rows = warehouse.execute(
        "SELECT layer, table_name, rows_loaded FROM etl.load_log ORDER BY log_id"
    ).fetchall()
    assert [(layer, table) for layer, table, _ in rows] == [("bronze", t) for t in SOURCE_FILES] + [
        ("silver", t)
        for t in (
            "crm_cust_info",
            "crm_prd_info",
            "crm_sales_details",
            "erp_cust_az12",
            "erp_loc_a101",
            "erp_px_cat_g1v2",
        )
    ]
    for layer, table, logged in rows:
        assert logged == scalar(warehouse, f"SELECT COUNT(*) FROM {layer}.{table}")


def test_silver_deduplicates_customers(warehouse):
    bronze_ids = scalar(warehouse, "SELECT COUNT(DISTINCT cst_id) FROM bronze.crm_cust_info")
    assert scalar(warehouse, "SELECT COUNT(*) FROM silver.crm_cust_info") == bronze_ids


def test_failed_bronze_load_rolls_back_and_raises(warehouse):
    before = scalar(warehouse, "SELECT COUNT(*) FROM bronze.crm_cust_info")
    with pytest.raises(psycopg.errors.UndefinedFile):
        warehouse.execute("CALL bronze.load_bronze('/path/that/does/not/exist')")
    assert scalar(warehouse, "SELECT COUNT(*) FROM bronze.crm_cust_info") == before
