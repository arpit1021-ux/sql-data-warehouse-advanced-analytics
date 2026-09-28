/*
===============================================================================
Quality Checks: Gold Layer
===============================================================================
Same format as silver_checks.sql: each query returns offending rows, empty
means pass. These checks protect the star schema and the reporting views.
===============================================================================
*/

-- @check    dim_customers: customer_key is unique
-- @severity error
SELECT customer_key, COUNT(*) AS occurrences
FROM gold.dim_customers
GROUP BY customer_key
HAVING COUNT(*) > 1;

-- @check    dim_products: product_key is unique
-- @severity error
SELECT product_key, COUNT(*) AS occurrences
FROM gold.dim_products
GROUP BY product_key
HAVING COUNT(*) > 1;

-- @check    fact_sales: every row joins to a customer and a product
-- @severity error
SELECT f.order_number, f.customer_key, f.product_key
FROM gold.fact_sales f
LEFT JOIN gold.dim_customers c ON c.customer_key = f.customer_key
LEFT JOIN gold.dim_products  p ON p.product_key  = f.product_key
WHERE c.customer_key IS NULL OR p.product_key IS NULL;

-- @check    fact_sales: no rows lost or duplicated between silver and gold
-- @severity error
SELECT s.silver_rows, g.gold_rows, s.silver_sales, g.gold_sales
FROM (SELECT COUNT(*) AS silver_rows, SUM(sls_sales) AS silver_sales FROM silver.crm_sales_details) s
CROSS JOIN (SELECT COUNT(*) AS gold_rows, SUM(sales_amount) AS gold_sales FROM gold.fact_sales) g
WHERE s.silver_rows <> g.gold_rows OR s.silver_sales <> g.gold_sales;

-- @check    dim_date: one row per day with no gaps
-- @severity error
SELECT MIN(date) AS first_day, MAX(date) AS last_day, COUNT(*) AS days, COUNT(DISTINCT date) AS distinct_days
FROM gold.dim_date
HAVING COUNT(*) <> MAX(date) - MIN(date) + 1
    OR COUNT(*) <> COUNT(DISTINCT date);

-- @check    dim_date: covers every order, ship and due date
-- @severity error
SELECT f.order_number, f.order_date, f.shipping_date, f.due_date
FROM gold.fact_sales f
WHERE f.order_date    NOT BETWEEN (SELECT MIN(date) FROM gold.dim_date) AND (SELECT MAX(date) FROM gold.dim_date)
   OR f.shipping_date NOT BETWEEN (SELECT MIN(date) FROM gold.dim_date) AND (SELECT MAX(date) FROM gold.dim_date)
   OR f.due_date      NOT BETWEEN (SELECT MIN(date) FROM gold.dim_date) AND (SELECT MAX(date) FROM gold.dim_date);

-- @check    report_customers: one row per customer with at least one dated order
-- @severity error
SELECT r.report_rows, e.expected_rows
FROM (SELECT COUNT(*) AS report_rows, COUNT(DISTINCT customer_key) AS report_keys FROM gold.report_customers) r
CROSS JOIN (SELECT COUNT(DISTINCT customer_key) AS expected_rows FROM gold.fact_sales WHERE order_date IS NOT NULL) e
WHERE r.report_rows <> e.expected_rows OR r.report_keys <> r.report_rows;

-- @check    report_customers: segment and KPI values are valid
-- @severity error
SELECT customer_key, customer_segment, lifespan, recency, total_orders, avg_order_value
FROM gold.report_customers
WHERE customer_segment NOT IN ('VIP', 'Regular', 'New')
   OR lifespan < 0 OR recency < 0 OR total_orders < 1 OR avg_order_value <= 0;

-- @check    report_products: one row per product sold and valid segments
-- @severity error
SELECT product_key, product_segment, total_orders
FROM gold.report_products
WHERE product_segment NOT IN ('High-Performer', 'Mid-Range', 'Low-Performer')
   OR total_orders < 1
   OR product_key IN (SELECT product_key FROM gold.report_products GROUP BY product_key HAVING COUNT(*) > 1);

-- @check    report totals reconcile with fact_sales (dated orders)
-- @severity error
SELECT c.customer_sales, p.product_sales, f.fact_sales
FROM (SELECT SUM(total_sales) AS customer_sales FROM gold.report_customers) c
CROSS JOIN (SELECT SUM(total_sales) AS product_sales FROM gold.report_products) p
CROSS JOIN (SELECT SUM(sales_amount) AS fact_sales FROM gold.fact_sales WHERE order_date IS NOT NULL) f
WHERE c.customer_sales <> f.fact_sales OR p.product_sales <> f.fact_sales;
