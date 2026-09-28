# Data Catalog: Gold Layer

The Gold layer is the business-facing model: a star schema (`dim_*`, `fact_sales`) plus reporting views
(`report_*`). Everything is defined as PostgreSQL views over Silver in
[`sql/warehouse/gold/`](../sql/warehouse/gold/), so it always reflects the latest load.

**Conventions**
* Monetary values are whole currency units (the source data has no currency code).
* "As-of date" means the last order date in the data (**2014-01-28**). Age and recency are measured at that date,
  so results don't change depending on when the warehouse is rebuilt.
* Month counts use `gold.month_diff(from, to)`: calendar-month boundaries crossed (2013-01-31 → 2013-02-01 = 1),
  the same rule as `DATEDIFF(MONTH)` in Power BI.
* Unknown source values are stored as `n/a` (shown as "Unknown" in Power BI).

---

## gold.dim_customers
One row per customer (18,484). CRM is the master record; ERP adds birthdate, gender fallback and country.

| Column | Type | Description |
|---|---|---|
| customer_key | BIGINT | Surrogate key |
| customer_id | INT | CRM customer id |
| customer_number | VARCHAR(50) | Business key, e.g. `AW00011000` |
| first_name | VARCHAR(50) | First name (trimmed) |
| last_name | VARCHAR(50) | Last name (trimmed) |
| country | VARCHAR(50) | Country of residence, from ERP (`n/a` if missing) |
| marital_status | VARCHAR(50) | `Married`, `Single` or `n/a` |
| gender | VARCHAR(50) | CRM gender, falling back to ERP; `Male`, `Female` or `n/a` |
| birthdate | DATE | Date of birth (future dates removed in Silver) |
| create_date | DATE | Date the customer was created in CRM |

## gold.dim_products
One row per **current** product version (295); historical versions are excluded.

| Column | Type | Description |
|---|---|---|
| product_key | BIGINT | Surrogate key |
| product_id | INT | CRM product id |
| product_number | VARCHAR(50) | Business key, e.g. `FR-R92B-58` |
| product_name | VARCHAR(50) | Name including colour and size |
| category_id | VARCHAR(50) | Category id, e.g. `CO_RF` |
| category | VARCHAR(50) | `Bikes`, `Accessories`, `Clothing`, `Components` |
| subcategory | VARCHAR(50) | E.g. `Road Bikes`, `Helmets` |
| maintenance | VARCHAR(50) | Whether the product needs maintenance (`Yes` / `No`) |
| cost | INT | Unit cost |
| product_line | VARCHAR(50) | `Road`, `Mountain`, `Touring`, `Other Sales` or `n/a` |
| start_date | DATE | Date this product version became available |

## gold.fact_sales
One row per order line (60,398).

| Column | Type | Description |
|---|---|---|
| order_number | VARCHAR(50) | Sales order, e.g. `SO54496` |
| product_key | BIGINT | → `dim_products.product_key` |
| customer_key | BIGINT | → `dim_customers.customer_key` |
| order_date | DATE | Order date (NULL for 19 lines whose source date was invalid) |
| shipping_date | DATE | Ship date |
| due_date | DATE | Payment due date |
| sales_amount | INT | Line revenue = quantity × price (repaired in Silver when inconsistent) |
| quantity | INT | Units ordered |
| price | INT | Unit price |

## gold.dim_date
One row per day from 1 Jan of the first sales year to 31 Dec of the last (2010-01-01 to 2014-12-31).

| Column | Type | Description |
|---|---|---|
| date | DATE | Calendar date (key) |
| date_key | INT | `YYYYMMDD` |
| year, quarter, month | INT | Calendar parts |
| quarter_name | TEXT | `Q1`–`Q4` |
| year_quarter | TEXT | `2013-Q4` |
| month_short | TEXT | `Jan`–`Dec` |
| year_month | TEXT | `2013-12` |
| day_of_week | INT | ISO day, 1 = Monday |
| day_name | TEXT | `Mon`–`Sun` |
| is_weekend | BOOLEAN | Saturday or Sunday |

## gold.report_customers
One row per customer with at least one dated order (18,482).

| Column | Type | Description |
|---|---|---|
| customer_key, customer_number, customer_name | | Customer identifiers |
| age | INT | Age at the as-of date |
| age_group | TEXT | `Under 30`, `30-39`, `40-49`, `50-59`, `60+`, `Unknown` |
| customer_segment | TEXT | `VIP` (lifespan ≥ 12 months and sales > 5,000), `Regular` (lifespan ≥ 12 months), `New` |
| last_order_date | DATE | Most recent order |
| recency | INT | Months from last order to the as-of date |
| total_orders, total_sales, total_quantity, total_products | | Lifetime totals |
| lifespan | INT | Months between first and last order |
| avg_order_value | NUMERIC | total_sales / total_orders |
| avg_monthly_spend | NUMERIC | total_sales / lifespan (total_sales when lifespan is 0) |

## gold.report_products
One row per product that has sold (130).

| Column | Type | Description |
|---|---|---|
| product_key, product_name, category, subcategory, cost | | Product attributes |
| last_sale_date | DATE | Most recent sale |
| recency_in_months | INT | Months from last sale to the as-of date |
| product_segment | TEXT | `High-Performer` (sales > 50,000), `Mid-Range` (≥ 10,000), `Low-Performer` |
| lifespan | INT | Months between first and last sale |
| total_orders, total_sales, total_quantity, total_customers | | Lifetime totals |
| avg_selling_price | NUMERIC | Average of sales / quantity per line |
| avg_order_revenue | NUMERIC | total_sales / total_orders |
| avg_monthly_revenue | NUMERIC | total_sales / lifespan (total_sales when lifespan is 0) |

---

## etl.load_log
Audit trail written by `bronze.load_bronze()` and `silver.load_silver()`: one row per table per load.

| Column | Type | Description |
|---|---|---|
| log_id | BIGINT | Identity |
| layer | TEXT | `bronze` or `silver` |
| table_name | TEXT | Table loaded |
| rows_loaded | BIGINT | Rows inserted |
| started_at, finished_at | TIMESTAMPTZ | Load window |
| duration_ms | NUMERIC | Generated from the load window |
