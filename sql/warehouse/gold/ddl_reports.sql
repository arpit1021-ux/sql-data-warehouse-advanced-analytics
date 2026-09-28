/*
===============================================================================
DDL Script: Create Gold Reporting Views
===============================================================================
Script Purpose:
    Customer- and product-level reports built on the star schema:
        gold.report_customers   one row per customer with segment and KPIs
        gold.report_products    one row per product with segment and KPIs

    All "as of" calculations (age, recency) use the last order date in the
    data, not CURRENT_DATE, so results are reproducible no matter when the
    warehouse is rebuilt. Month counts use gold.month_diff().
===============================================================================
*/

DROP VIEW IF EXISTS gold.report_customers;
DROP VIEW IF EXISTS gold.report_products;

-- =============================================================================
-- Report: gold.report_customers
-- =============================================================================
/*
    Segments   VIP      lifespan >= 12 months and total sales > 5,000
               Regular  lifespan >= 12 months and total sales <= 5,000
               New      lifespan < 12 months
    KPIs       recency (months since last order), average order value,
               average monthly spend
*/
CREATE VIEW gold.report_customers AS
WITH as_of AS (
    SELECT MAX(order_date) AS as_of_date FROM gold.fact_sales
),
base_query AS (
    SELECT
        f.order_number,
        f.product_key,
        f.order_date,
        f.sales_amount,
        f.quantity,
        c.customer_key,
        c.customer_number,
        CONCAT(c.first_name, ' ', c.last_name)                       AS customer_name,
        EXTRACT(YEAR FROM AGE(a.as_of_date, c.birthdate))::INT       AS age
    FROM gold.fact_sales f
    JOIN gold.dim_customers c
        ON c.customer_key = f.customer_key
    CROSS JOIN as_of a
    WHERE f.order_date IS NOT NULL
),
customer_aggregation AS (
    SELECT
        customer_key,
        customer_number,
        customer_name,
        age,
        COUNT(DISTINCT order_number)                      AS total_orders,
        SUM(sales_amount)                                 AS total_sales,
        SUM(quantity)                                     AS total_quantity,
        COUNT(DISTINCT product_key)                       AS total_products,
        MAX(order_date)                                   AS last_order_date,
        gold.month_diff(MIN(order_date), MAX(order_date)) AS lifespan
    FROM base_query
    GROUP BY customer_key, customer_number, customer_name, age
)
SELECT
    ca.customer_key,
    ca.customer_number,
    ca.customer_name,
    ca.age,
    CASE
        WHEN ca.age IS NULL THEN 'Unknown'
        WHEN ca.age < 30    THEN 'Under 30'
        WHEN ca.age < 40    THEN '30-39'
        WHEN ca.age < 50    THEN '40-49'
        WHEN ca.age < 60    THEN '50-59'
        ELSE '60+'
    END                                                         AS age_group,
    CASE
        WHEN ca.lifespan >= 12 AND ca.total_sales > 5000 THEN 'VIP'
        WHEN ca.lifespan >= 12                           THEN 'Regular'
        ELSE 'New'
    END                                                         AS customer_segment,
    ca.last_order_date,
    gold.month_diff(ca.last_order_date, a.as_of_date)          AS recency,
    ca.total_orders,
    ca.total_sales,
    ca.total_quantity,
    ca.total_products,
    ca.lifespan,
    ROUND(ca.total_sales::NUMERIC / ca.total_orders, 2)        AS avg_order_value,
    CASE
        WHEN ca.lifespan = 0 THEN ca.total_sales::NUMERIC
        ELSE ROUND(ca.total_sales::NUMERIC / ca.lifespan, 2)
    END                                                         AS avg_monthly_spend
FROM customer_aggregation ca
CROSS JOIN as_of a;

-- =============================================================================
-- Report: gold.report_products
-- =============================================================================
/*
    Segments   High-Performer  total sales > 50,000
               Mid-Range       total sales 10,000 - 50,000
               Low-Performer   total sales < 10,000
    KPIs       recency (months since last sale), average order revenue,
               average monthly revenue
*/
CREATE VIEW gold.report_products AS
WITH as_of AS (
    SELECT MAX(order_date) AS as_of_date FROM gold.fact_sales
),
base_query AS (
    SELECT
        f.order_number,
        f.order_date,
        f.customer_key,
        f.sales_amount,
        f.quantity,
        p.product_key,
        p.product_name,
        p.category,
        p.subcategory,
        p.cost
    FROM gold.fact_sales f
    JOIN gold.dim_products p
        ON f.product_key = p.product_key
    WHERE f.order_date IS NOT NULL
),
product_aggregation AS (
    SELECT
        product_key,
        product_name,
        category,
        subcategory,
        cost,
        gold.month_diff(MIN(order_date), MAX(order_date))           AS lifespan,
        MAX(order_date)                                             AS last_sale_date,
        COUNT(DISTINCT order_number)                                AS total_orders,
        COUNT(DISTINCT customer_key)                                AS total_customers,
        SUM(sales_amount)                                           AS total_sales,
        SUM(quantity)                                               AS total_quantity,
        ROUND(AVG(sales_amount::NUMERIC / NULLIF(quantity, 0)), 2)  AS avg_selling_price
    FROM base_query
    GROUP BY product_key, product_name, category, subcategory, cost
)
SELECT
    pa.product_key,
    pa.product_name,
    pa.category,
    pa.subcategory,
    pa.cost,
    pa.last_sale_date,
    gold.month_diff(pa.last_sale_date, a.as_of_date)          AS recency_in_months,
    CASE
        WHEN pa.total_sales > 50000  THEN 'High-Performer'
        WHEN pa.total_sales >= 10000 THEN 'Mid-Range'
        ELSE 'Low-Performer'
    END                                                        AS product_segment,
    pa.lifespan,
    pa.total_orders,
    pa.total_sales,
    pa.total_quantity,
    pa.total_customers,
    pa.avg_selling_price,
    ROUND(pa.total_sales::NUMERIC / pa.total_orders, 2)       AS avg_order_revenue,
    CASE
        WHEN pa.lifespan = 0 THEN pa.total_sales::NUMERIC
        ELSE ROUND(pa.total_sales::NUMERIC / pa.lifespan, 2)
    END                                                        AS avg_monthly_revenue
FROM product_aggregation pa
CROSS JOIN as_of a;
