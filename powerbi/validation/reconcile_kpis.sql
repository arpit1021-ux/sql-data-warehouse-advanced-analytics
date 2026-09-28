/*
===============================================================================
Dashboard Reconciliation: Power BI vs. Warehouse
===============================================================================
Script Purpose:
    Every number on the dashboard must match the warehouse. Run these queries
    and compare them with the Power BI card / table values (see
    expected_kpis.md). Any mismatch means a broken relationship, a wrong
    filter direction, or a measure bug in the report.
===============================================================================
*/

-- 1. Headline KPIs (Overview page cards)
SELECT
    SUM(f.sales_amount)                                   AS total_sales,
    SUM(f.quantity)                                       AS total_quantity,
    COUNT(DISTINCT f.order_number)                        AS total_orders,
    COUNT(DISTINCT f.customer_key)                        AS total_customers,
    ROUND(SUM(f.sales_amount)::numeric
          / COUNT(DISTINCT f.order_number), 2)            AS avg_order_value,
    SUM(f.sales_amount - f.quantity * p.cost)             AS gross_profit,
    ROUND(100.0 * SUM(f.sales_amount - f.quantity * p.cost)
          / SUM(f.sales_amount), 2)                       AS gross_margin_pct
FROM gold.fact_sales f
LEFT JOIN gold.dim_products p ON f.product_key = p.product_key;

-- 2. Sales by year (Trend page)
SELECT
    EXTRACT(YEAR FROM order_date)::int  AS order_year,
    SUM(sales_amount)                   AS total_sales,
    COUNT(DISTINCT order_number)        AS total_orders,
    COUNT(DISTINCT customer_key)        AS total_customers
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY 1
ORDER BY 1;

-- 3. Sales by category, with % of total (Product page)
SELECT
    p.category,
    SUM(f.sales_amount)                                              AS total_sales,
    ROUND(100.0 * SUM(f.sales_amount) / SUM(SUM(f.sales_amount)) OVER (), 2) AS pct_of_total
FROM gold.fact_sales f
LEFT JOIN gold.dim_products p ON f.product_key = p.product_key
GROUP BY p.category
ORDER BY total_sales DESC;

-- 4. Sales by country (Customer page map)
SELECT
    c.country,
    SUM(f.sales_amount) AS total_sales
FROM gold.fact_sales f
LEFT JOIN gold.dim_customers c ON f.customer_key = c.customer_key
GROUP BY c.country
ORDER BY total_sales DESC;

-- 5. Top 5 products by revenue (Product page)
SELECT
    p.product_name,
    SUM(f.sales_amount) AS total_sales
FROM gold.fact_sales f
LEFT JOIN gold.dim_products p ON f.product_key = p.product_key
GROUP BY p.product_name
ORDER BY total_sales DESC
LIMIT 5;
