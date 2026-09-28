/*
===============================================================================
Stored Procedure: Load Silver Layer (Bronze -> Silver)
===============================================================================
Script Purpose:
    Cleanses and standardises bronze data into the silver tables (full reload):
      crm_cust_info      keep the latest record per customer, trim names,
                         decode marital status / gender codes
      crm_prd_info       split the product key into category id + product key,
                         decode product line, derive end dates (SCD type 2)
      crm_sales_details  convert YYYYMMDD integers to dates, repair sales and
                         price values that break sales = quantity x price
      erp_cust_az12      strip the 'NAS' prefix, null out future birthdates,
                         standardise gender
      erp_loc_a101       strip dashes from ids, standardise country names
      erp_px_cat_g1v2    loaded as-is (already clean)
    Row counts and durations are written to etl.load_log. Any error aborts the
    whole load and is raised to the caller.

Usage:
    CALL silver.load_silver();
===============================================================================
*/

CREATE OR REPLACE PROCEDURE silver.load_silver()
LANGUAGE plpgsql
AS $$
DECLARE
    v_rows     BIGINT;
    v_started  TIMESTAMPTZ;
    v_batch    TIMESTAMPTZ := clock_timestamp();
BEGIN
    RAISE NOTICE 'Loading silver layer';

    -- -------------------------------------------------------------------------
    -- silver.crm_cust_info
    -- -------------------------------------------------------------------------
    v_started := clock_timestamp();
    TRUNCATE TABLE silver.crm_cust_info;
    INSERT INTO silver.crm_cust_info (
        cst_id, cst_key, cst_firstname, cst_lastname,
        cst_marital_status, cst_gndr, cst_create_date
    )
    SELECT
        cst_id,
        cst_key,
        TRIM(cst_firstname),
        TRIM(cst_lastname),
        CASE UPPER(TRIM(cst_marital_status))
            WHEN 'S' THEN 'Single'
            WHEN 'M' THEN 'Married'
            ELSE 'n/a'
        END,
        CASE UPPER(TRIM(cst_gndr))
            WHEN 'F' THEN 'Female'
            WHEN 'M' THEN 'Male'
            ELSE 'n/a'
        END,
        cst_create_date
    FROM (
        SELECT
            *,
            ROW_NUMBER() OVER (PARTITION BY cst_id ORDER BY cst_create_date DESC) AS recency_rank
        FROM bronze.crm_cust_info
        WHERE cst_id IS NOT NULL
    ) AS ranked_customers
    WHERE recency_rank = 1;          -- most recent record per customer
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    CALL etl.log_load('silver', 'crm_cust_info', v_rows, v_started);

    -- -------------------------------------------------------------------------
    -- silver.crm_prd_info
    -- -------------------------------------------------------------------------
    v_started := clock_timestamp();
    TRUNCATE TABLE silver.crm_prd_info;
    INSERT INTO silver.crm_prd_info (
        prd_id, cat_id, prd_key, prd_nm, prd_cost, prd_line, prd_start_dt, prd_end_dt
    )
    SELECT
        prd_id,
        REPLACE(SUBSTRING(prd_key, 1, 5), '-', '_'),        -- category id, matches erp_px_cat_g1v2.id
        SUBSTRING(prd_key, 7),                               -- product key, matches sales sls_prd_key
        TRIM(prd_nm),
        COALESCE(prd_cost, 0),
        CASE UPPER(TRIM(prd_line))
            WHEN 'M' THEN 'Mountain'
            WHEN 'R' THEN 'Road'
            WHEN 'S' THEN 'Other Sales'
            WHEN 'T' THEN 'Touring'
            ELSE 'n/a'
        END,
        CAST(prd_start_dt AS DATE),
        -- a version ends the day before the next version of the same product starts
        CAST(LEAD(prd_start_dt) OVER (PARTITION BY prd_key ORDER BY prd_start_dt)
             - INTERVAL '1 day' AS DATE)
    FROM bronze.crm_prd_info;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    CALL etl.log_load('silver', 'crm_prd_info', v_rows, v_started);

    -- -------------------------------------------------------------------------
    -- silver.crm_sales_details
    -- -------------------------------------------------------------------------
    v_started := clock_timestamp();
    TRUNCATE TABLE silver.crm_sales_details;
    INSERT INTO silver.crm_sales_details (
        sls_ord_num, sls_prd_key, sls_cust_id, sls_order_dt, sls_ship_dt, sls_due_dt,
        sls_sales, sls_quantity, sls_price
    )
    SELECT
        sls_ord_num,
        sls_prd_key,
        sls_cust_id,
        CASE WHEN LENGTH(sls_order_dt::TEXT) = 8 THEN TO_DATE(sls_order_dt::TEXT, 'YYYYMMDD') END,
        CASE WHEN LENGTH(sls_ship_dt::TEXT)  = 8 THEN TO_DATE(sls_ship_dt::TEXT,  'YYYYMMDD') END,
        CASE WHEN LENGTH(sls_due_dt::TEXT)   = 8 THEN TO_DATE(sls_due_dt::TEXT,   'YYYYMMDD') END,
        repaired_sales,
        sls_quantity,
        -- derive a missing / non-positive price from the (repaired) sales amount
        CASE
            WHEN sls_price IS NULL OR sls_price <= 0
                THEN repaired_sales / NULLIF(sls_quantity, 0)
            ELSE sls_price
        END
    FROM (
        SELECT
            *,
            -- recompute sales when missing, non-positive or inconsistent with quantity x price
            CASE
                WHEN sls_sales IS NULL OR sls_sales <= 0 OR sls_sales <> sls_quantity * ABS(sls_price)
                    THEN sls_quantity * ABS(sls_price)
                ELSE sls_sales
            END AS repaired_sales
        FROM bronze.crm_sales_details
    ) AS sales;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    CALL etl.log_load('silver', 'crm_sales_details', v_rows, v_started);

    -- -------------------------------------------------------------------------
    -- silver.erp_cust_az12
    -- -------------------------------------------------------------------------
    v_started := clock_timestamp();
    TRUNCATE TABLE silver.erp_cust_az12;
    INSERT INTO silver.erp_cust_az12 (cid, bdate, gen)
    SELECT
        CASE WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid, 4) ELSE cid END,   -- align with CRM cst_key
        CASE WHEN bdate > CURRENT_DATE THEN NULL ELSE bdate END,        -- future birthdates are invalid
        CASE
            WHEN UPPER(TRIM(gen)) IN ('F', 'FEMALE') THEN 'Female'
            WHEN UPPER(TRIM(gen)) IN ('M', 'MALE')   THEN 'Male'
            ELSE 'n/a'
        END
    FROM bronze.erp_cust_az12;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    CALL etl.log_load('silver', 'erp_cust_az12', v_rows, v_started);

    -- -------------------------------------------------------------------------
    -- silver.erp_loc_a101
    -- -------------------------------------------------------------------------
    v_started := clock_timestamp();
    TRUNCATE TABLE silver.erp_loc_a101;
    INSERT INTO silver.erp_loc_a101 (cid, cntry)
    SELECT
        REPLACE(cid, '-', ''),                                            -- align with CRM cst_key
        CASE
            WHEN TRIM(cntry) = 'DE'                  THEN 'Germany'
            WHEN TRIM(cntry) IN ('US', 'USA')        THEN 'United States'
            WHEN cntry IS NULL OR TRIM(cntry) = ''   THEN 'n/a'
            ELSE TRIM(cntry)
        END
    FROM bronze.erp_loc_a101;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    CALL etl.log_load('silver', 'erp_loc_a101', v_rows, v_started);

    -- -------------------------------------------------------------------------
    -- silver.erp_px_cat_g1v2
    -- -------------------------------------------------------------------------
    v_started := clock_timestamp();
    TRUNCATE TABLE silver.erp_px_cat_g1v2;
    INSERT INTO silver.erp_px_cat_g1v2 (id, cat, subcat, maintenance)
    SELECT id, cat, subcat, maintenance
    FROM bronze.erp_px_cat_g1v2;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    CALL etl.log_load('silver', 'erp_px_cat_g1v2', v_rows, v_started);

    RAISE NOTICE 'Silver layer loaded in % s', ROUND(EXTRACT(EPOCH FROM clock_timestamp() - v_batch), 2);
END
$$;
