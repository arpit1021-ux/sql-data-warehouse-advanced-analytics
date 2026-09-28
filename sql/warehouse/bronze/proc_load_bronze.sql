/*
===============================================================================
Stored Procedure: Load Bronze Layer (Source -> Bronze)
===============================================================================
Script Purpose:
    Loads the six source CSV files into the bronze tables:
      - truncates each bronze table (full reload),
      - bulk-loads the file with COPY,
      - records row count and duration in etl.load_log.
    Any error aborts the whole load (the transaction is rolled back and the
    error is raised to the caller), so a partial load can never look successful.

Parameters:
    p_source_dir  Absolute path to the data/raw folder *as seen by the
                  PostgreSQL server*, e.g.
                    '/data/raw'                                   (Docker)
                    'C:/projects/sql-data-warehouse/data/raw'    (local Windows)
                  The folder must contain crm/ and erp/ sub-folders.

Permissions:
    COPY ... FROM '<file>' reads the file on the database server, so the
    calling role needs superuser or the pg_read_server_files role.

Usage:
    CALL bronze.load_bronze('/data/raw');
===============================================================================
*/

CREATE OR REPLACE PROCEDURE bronze.load_bronze(p_source_dir TEXT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_source   RECORD;
    v_rows     BIGINT;
    v_started  TIMESTAMPTZ;
    v_batch    TIMESTAMPTZ := clock_timestamp();
    v_dir      TEXT := rtrim(replace(p_source_dir, '\', '/'), '/');
BEGIN
    RAISE NOTICE 'Loading bronze layer from %', v_dir;

    FOR v_source IN
        SELECT *
        FROM (VALUES
            ('crm_cust_info',     'crm/cust_info.csv',     'cst_id, cst_key, cst_firstname, cst_lastname, cst_marital_status, cst_gndr, cst_create_date'),
            ('crm_prd_info',      'crm/prd_info.csv',      'prd_id, prd_key, prd_nm, prd_cost, prd_line, prd_start_dt, prd_end_dt'),
            ('crm_sales_details', 'crm/sales_details.csv', 'sls_ord_num, sls_prd_key, sls_cust_id, sls_order_dt, sls_ship_dt, sls_due_dt, sls_sales, sls_quantity, sls_price'),
            ('erp_loc_a101',      'erp/LOC_A101.csv',      'cid, cntry'),
            ('erp_cust_az12',     'erp/CUST_AZ12.csv',     'cid, bdate, gen'),
            ('erp_px_cat_g1v2',   'erp/PX_CAT_G1V2.csv',   'id, cat, subcat, maintenance')
        ) AS sources (table_name, file_path, column_list)
    LOOP
        v_started := clock_timestamp();

        EXECUTE format('TRUNCATE TABLE bronze.%I', v_source.table_name);
        EXECUTE format(
            'COPY bronze.%I (%s) FROM %L WITH (FORMAT csv, HEADER true)',
            v_source.table_name, v_source.column_list, v_dir || '/' || v_source.file_path
        );
        GET DIAGNOSTICS v_rows = ROW_COUNT;

        CALL etl.log_load('bronze', v_source.table_name, v_rows, v_started);
    END LOOP;

    RAISE NOTICE 'Bronze layer loaded in % s', ROUND(EXTRACT(EPOCH FROM clock_timestamp() - v_batch), 2);
END
$$;
