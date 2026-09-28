/*
===============================================================================
DDL Script: Create Gold Layer (Star Schema)
===============================================================================
Script Purpose:
    Creates the business-ready Gold layer as views over Silver:
        gold.dim_customers   customer dimension (CRM + ERP demographics + location)
        gold.dim_products    current product catalogue with categories
        gold.fact_sales      sales order lines keyed to both dimensions
        gold.dim_date        calendar dimension covering every year with sales
    plus gold.month_diff(), the single definition of "months between two dates"
    used by every report and analysis.
===============================================================================
*/

DROP VIEW IF EXISTS gold.dim_date;
DROP VIEW IF EXISTS gold.fact_sales;
DROP VIEW IF EXISTS gold.dim_customers;
DROP VIEW IF EXISTS gold.dim_products;

-- =============================================================================
-- Helper: calendar months between two dates, counted as month boundaries
-- crossed (2013-01-31 -> 2013-02-01 = 1). Same semantics as DATEDIFF(MONTH)
-- in Power BI / SQL Server, so SQL, Python and the dashboard always agree.
-- =============================================================================
CREATE OR REPLACE FUNCTION gold.month_diff(p_from DATE, p_to DATE)
RETURNS INT
LANGUAGE sql
IMMUTABLE
RETURN (EXTRACT(YEAR FROM p_to) - EXTRACT(YEAR FROM p_from)) * 12
     + (EXTRACT(MONTH FROM p_to) - EXTRACT(MONTH FROM p_from));

-- =============================================================================
-- Dimension: gold.dim_customers
-- =============================================================================
CREATE VIEW gold.dim_customers AS
SELECT
    ROW_NUMBER() OVER (ORDER BY ci.cst_id) AS customer_key,     -- surrogate key
    ci.cst_id                              AS customer_id,
    ci.cst_key                             AS customer_number,
    ci.cst_firstname                       AS first_name,
    ci.cst_lastname                        AS last_name,
    la.cntry                               AS country,
    ci.cst_marital_status                  AS marital_status,
    CASE
        WHEN ci.cst_gndr <> 'n/a' THEN ci.cst_gndr               -- CRM is the master for gender
        ELSE COALESCE(ca.gen, 'n/a')                             -- fall back to ERP
    END                                    AS gender,
    ca.bdate                               AS birthdate,
    ci.cst_create_date                     AS create_date
FROM silver.crm_cust_info ci
LEFT JOIN silver.erp_cust_az12 ca
    ON ci.cst_key = ca.cid
LEFT JOIN silver.erp_loc_a101 la
    ON ci.cst_key = la.cid;

-- =============================================================================
-- Dimension: gold.dim_products (current versions only)
-- =============================================================================
CREATE VIEW gold.dim_products AS
SELECT
    ROW_NUMBER() OVER (ORDER BY pn.prd_start_dt, pn.prd_key) AS product_key,   -- surrogate key
    pn.prd_id       AS product_id,
    pn.prd_key      AS product_number,
    pn.prd_nm       AS product_name,
    pn.cat_id       AS category_id,
    pc.cat          AS category,
    pc.subcat       AS subcategory,
    pc.maintenance  AS maintenance,
    pn.prd_cost     AS cost,
    pn.prd_line     AS product_line,
    pn.prd_start_dt AS start_date
FROM silver.crm_prd_info pn
LEFT JOIN silver.erp_px_cat_g1v2 pc
    ON pn.cat_id = pc.id
WHERE pn.prd_end_dt IS NULL;                -- drop historical product versions

-- =============================================================================
-- Fact: gold.fact_sales
-- =============================================================================
CREATE VIEW gold.fact_sales AS
SELECT
    sd.sls_ord_num  AS order_number,
    pr.product_key  AS product_key,
    cu.customer_key AS customer_key,
    sd.sls_order_dt AS order_date,
    sd.sls_ship_dt  AS shipping_date,
    sd.sls_due_dt   AS due_date,
    sd.sls_sales    AS sales_amount,
    sd.sls_quantity AS quantity,
    sd.sls_price    AS price
FROM silver.crm_sales_details sd
LEFT JOIN gold.dim_products pr
    ON sd.sls_prd_key = pr.product_number
LEFT JOIN gold.dim_customers cu
    ON sd.sls_cust_id = cu.customer_id;

-- =============================================================================
-- Dimension: gold.dim_date
-- Every day from 1 Jan of the first sales year to 31 Dec of the last one,
-- so time-intelligence calculations (YTD, prior year) never hit gaps.
-- =============================================================================
CREATE VIEW gold.dim_date AS
WITH bounds AS (
    SELECT
        DATE_TRUNC('year', MIN(order_date))::DATE                                AS first_day,
        (DATE_TRUNC('year', MAX(order_date)) + INTERVAL '1 year - 1 day')::DATE  AS last_day
    FROM gold.fact_sales
)
SELECT
    d::DATE                                       AS date,
    TO_CHAR(d, 'YYYYMMDD')::INT                   AS date_key,
    EXTRACT(YEAR FROM d)::INT                     AS year,
    EXTRACT(QUARTER FROM d)::INT                  AS quarter,
    'Q' || EXTRACT(QUARTER FROM d)                AS quarter_name,
    TO_CHAR(d, 'YYYY') || '-Q' || EXTRACT(QUARTER FROM d) AS year_quarter,
    EXTRACT(MONTH FROM d)::INT                    AS month,
    TO_CHAR(d, 'Mon')                             AS month_short,
    TO_CHAR(d, 'YYYY-MM')                         AS year_month,
    EXTRACT(ISODOW FROM d)::INT                   AS day_of_week,       -- 1 = Monday
    TO_CHAR(d, 'Dy')                              AS day_name,
    EXTRACT(ISODOW FROM d) IN (6, 7)              AS is_weekend
FROM bounds,
     GENERATE_SERIES(bounds.first_day, bounds.last_day, INTERVAL '1 day') AS d;
