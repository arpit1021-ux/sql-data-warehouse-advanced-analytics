"""Repository paths and ordered SQL build steps."""

import os
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

RAW_DATA_DIR = REPO_ROOT / "data" / "raw"
GOLD_EXPORT_DIR = REPO_ROOT / "data" / "gold"
SQL_DIR = REPO_ROOT / "sql"
WAREHOUSE_SQL_DIR = SQL_DIR / "warehouse"
QUALITY_SQL_DIR = SQL_DIR / "quality"
ANALYTICS_SQL_DIR = SQL_DIR / "analytics"

# Embedded server data lives outside the repo (fast local disk); override with $WAREHOUSE_PGDATA.
EMBEDDED_PGDATA_DIR = Path(os.environ.get("WAREHOUSE_PGDATA", Path.home() / ".sql-dwh" / "pgdata"))
DEFAULT_DATABASE = "DataWarehouse"

# DDL scripts in dependency order; procedures are created here and called by the pipeline.
SCHEMA_SCRIPTS = [WAREHOUSE_SQL_DIR / "00_init_database.sql"]
BRONZE_SCRIPTS = [
    WAREHOUSE_SQL_DIR / "bronze" / "ddl_bronze.sql",
    WAREHOUSE_SQL_DIR / "bronze" / "proc_load_bronze.sql",
]
SILVER_SCRIPTS = [
    WAREHOUSE_SQL_DIR / "silver" / "ddl_silver.sql",
    WAREHOUSE_SQL_DIR / "silver" / "proc_load_silver.sql",
]
GOLD_SCRIPTS = [
    WAREHOUSE_SQL_DIR / "gold" / "ddl_gold.sql",
    WAREHOUSE_SQL_DIR / "gold" / "ddl_reports.sql",
]
QUALITY_FILES = [
    QUALITY_SQL_DIR / "silver_checks.sql",
    QUALITY_SQL_DIR / "gold_checks.sql",
]

# Gold objects exported to CSV for the Python analysis and the Power BI report.
# Each entry: view name -> ORDER BY clause that makes the export deterministic.
GOLD_EXPORTS = {
    "dim_customers": "customer_key",
    "dim_products": "product_key",
    "dim_date": "date",
    "fact_sales": "order_number, product_key",
    "report_customers": "customer_key",
    "report_products": "product_key",
}
