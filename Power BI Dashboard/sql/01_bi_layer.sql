/*
===============================================================================
BI Serving Layer: objects Power BI connects to
===============================================================================
Script Purpose:
    Extends the Gold layer with what a BI tool needs on top of the star schema:
      1. gold.dim_date       - a conformed calendar dimension (required for
                               time-intelligence DAX such as YTD / YoY)
      2. bi_reader role      - a least-privilege, read-only login for Power BI
                               (the dashboard never uses the admin account)

Run order:
    Run AFTER Data Warehouse/scripts/gold/ddl_gold.sql
    (or after EDA + Advanced Data Analysis/scripts/00_init_database.sql
     if you loaded the Gold CSVs directly).
===============================================================================
*/

-- =============================================================================
-- 1. Calendar dimension: gold.dim_date
--    Covers every day from Jan of the first order year to Dec of the last,
--    so there are no gaps for time-intelligence functions.
-- =============================================================================
DROP VIEW IF EXISTS gold.dim_date;

CREATE VIEW gold.dim_date AS
WITH bounds AS (
    SELECT
        DATE_TRUNC('year', MIN(order_date))::date                        AS start_date,
        (DATE_TRUNC('year', MAX(order_date)) + INTERVAL '1 year - 1 day')::date AS end_date
    FROM gold.fact_sales
    WHERE order_date IS NOT NULL
)
SELECT
    d::date                                  AS date,
    TO_CHAR(d, 'YYYYMMDD')::int              AS date_key,
    EXTRACT(YEAR    FROM d)::int             AS year,
    EXTRACT(QUARTER FROM d)::int             AS quarter,
    'Q' || EXTRACT(QUARTER FROM d)           AS quarter_name,
    EXTRACT(MONTH   FROM d)::int             AS month,
    TO_CHAR(d, 'Mon')                        AS month_short,
    TO_CHAR(d, 'YYYY-MM')                    AS year_month,
    EXTRACT(ISODOW  FROM d)::int             AS day_of_week,     -- 1 = Monday
    TO_CHAR(d, 'Dy')                         AS day_name,
    (EXTRACT(ISODOW FROM d) IN (6, 7))       AS is_weekend
FROM bounds,
     GENERATE_SERIES(bounds.start_date, bounds.end_date, INTERVAL '1 day') AS d;


-- =============================================================================
-- 2. Read-only role for the BI tool
--    Change the password before running. Power BI connects with this user.
-- =============================================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bi_reader') THEN
        CREATE ROLE bi_reader LOGIN PASSWORD 'change_me';
    END IF;
    -- grant CONNECT on whichever database this script is run in
    EXECUTE format('GRANT CONNECT ON DATABASE %I TO bi_reader', current_database());
END
$$;

GRANT USAGE  ON SCHEMA gold TO bi_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA gold TO bi_reader;           -- covers views too
ALTER DEFAULT PRIVILEGES IN SCHEMA gold GRANT SELECT ON TABLES TO bi_reader;


-- =============================================================================
-- 3. Quick sanity check (should return one row per year, no gaps)
-- =============================================================================
SELECT year, COUNT(*) AS days
FROM gold.dim_date
GROUP BY year
ORDER BY year;
