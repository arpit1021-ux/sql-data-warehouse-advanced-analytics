/*
===============================================================================
Initialise Warehouse Schemas
===============================================================================
Script Purpose:
    Creates the four schemas used by the warehouse:
        bronze  - raw copies of the CRM and ERP source files
        silver  - cleansed, standardised and de-duplicated data
        gold    - business-ready star schema and reporting views
        etl     - pipeline metadata (load audit log)
    and the etl.load_log table that every load procedure writes to.

    Run this in the target database (e.g. `DataWarehouse`), which must
    already exist:  CREATE DATABASE "DataWarehouse";

WARNING:
    Re-running this script drops all four schemas and everything in them.
===============================================================================
*/

DROP SCHEMA IF EXISTS gold   CASCADE;
DROP SCHEMA IF EXISTS silver CASCADE;
DROP SCHEMA IF EXISTS bronze CASCADE;
DROP SCHEMA IF EXISTS etl    CASCADE;

CREATE SCHEMA bronze;
CREATE SCHEMA silver;
CREATE SCHEMA gold;
CREATE SCHEMA etl;

-- =============================================================================
-- Load audit log: one row per table loaded, written by the load procedures
-- =============================================================================
CREATE TABLE etl.load_log (
    log_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    layer         TEXT        NOT NULL,
    table_name    TEXT        NOT NULL,
    rows_loaded   BIGINT      NOT NULL,
    started_at    TIMESTAMPTZ NOT NULL,
    finished_at   TIMESTAMPTZ NOT NULL,
    duration_ms   NUMERIC(12, 1) GENERATED ALWAYS AS
                  (EXTRACT(EPOCH FROM (finished_at - started_at)) * 1000) STORED
);

CREATE PROCEDURE etl.log_load(p_layer TEXT, p_table TEXT, p_rows BIGINT, p_started_at TIMESTAMPTZ)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO etl.load_log (layer, table_name, rows_loaded, started_at, finished_at)
    VALUES (p_layer, p_table, p_rows, p_started_at, clock_timestamp());

    RAISE NOTICE '>> %.%: % rows in % ms', p_layer, p_table, p_rows,
        ROUND(EXTRACT(EPOCH FROM (clock_timestamp() - p_started_at)) * 1000);
END
$$;
