# Power BI Dashboard: Sales Performance

A 4-page interactive report on the warehouse's Gold layer, plus the RFM segments from the
[Python analysis](../analysis/).

**Open it:** [`Sales_Performance.pbix`](Sales_Performance.pbix) in Power BI Desktop, or read the [PDF export](Sales_Performance.pdf).

## Pages

### 1. Executive Overview
KPI cards, monthly trend with a 3-month rolling average, and sales by category, country and customer segment.
![Executive Overview](screenshots/01_overview.png)

### 2. Sales Trends
Selected year vs. prior year (defaults to the latest full year), YoY growth, running total by quarter and a year × quarter matrix.
![Sales Trends](screenshots/02_trends.png)

### 3. Product Performance
Dynamic title, profit and margin, accessory attach rate, top 10 products, category → subcategory treemap,
units vs. margin scatter and a product ranking table.
![Product Performance](screenshots/03_products.png)

### 4. Customer Insights
RFM segments (revenue vs. headcount), revenue per customer by country, age groups and the top 10 customers.
![Customer Insights](screenshots/04_customers.png)

Year, Country and Category slicers are synced across all pages.

---

## Data model

```
                    dim_date (marked date table)
                       │ 1   active:   order_date    → date
                       │     inactive: shipping_date → date   (used via USERELATIONSHIP)
                       ▼ *
dim_customers 1 ──▶ * fact_sales * ◀── 1 dim_products
```

| Table | Source (`data/gold/`, exported by `python -m pipeline run`) |
|---|---|
| `fact_sales` | `fact_sales.csv` |
| `dim_customers` | `dim_customers.csv` + age, age group, segment and lifespan from `report_customers.csv` + RFM segment from `analysis/output/rfm_segments.csv` |
| `dim_products` | `dim_products.csv` + product segment from `report_products.csv` |
| `dim_date` | `dim_date.csv` (the warehouse's `gold.dim_date`) |

* Single-direction one-to-many relationships; keys and raw numeric columns are hidden so report authors use measures.
* Auto date/time is off; time intelligence runs on the warehouse calendar.
* Business rules (segments, age, lifespan) are computed **once** in the warehouse and loaded, not re-implemented in DAX.
* **Row-Level Security:** role `Country Manager - US` filters `dim_customers[country] = "United States"`
  (test with *Modeling → View as*).
* **33 DAX measures** in a `_Measures` table, grouped into display folders. Full list: [`dax/measures.dax`](dax/measures.dax).

| Measure | Technique |
|---|---|
| `Gross Profit`, `Total Cost` | `SUMX` + `RELATED` across the star |
| `Sales YTD`, `Sales PY`, `Sales YoY %`, `Sales MoM %` | Time intelligence on the marked date table |
| `Sales 3M Rolling Avg`, `Running Total Sales` | `DATESINPERIOD`, `ALLSELECTED` |
| `Selected Year`, `Sales (Selected Year)`, `YoY % (Selected Year)` | Default to the latest full year when no year is selected |
| `Repeat Customer Rate` | Customers with more than one order via `FILTER(VALUES(...))` and context transition |
| `Accessory Attach Rate` | `INTERSECT` of bike buyers and accessory buyers |
| `Product Rank`, `Top 10 Product Sales` | `RANKX` + `ISINSCOPE` |
| `Sales by Ship Date` | `USERELATIONSHIP` on the inactive date relationship |

## Validation
Every dashboard number matches the warehouse: see [`validation/expected_kpis.md`](validation/expected_kpis.md)
(asserted by the test suite) and [`validation/reconcile_kpis.sql`](validation/reconcile_kpis.sql).

## Source control
The report is also saved as a **Power BI Project** (`Sales_Performance.pbip`), so the model and report are
plain text that diffs cleanly in Git:
* `Sales_Performance.SemanticModel/definition/`: tables, Power Query, measures, relationships and roles in **TMDL**
* `Sales_Performance.Report/definition/`: pages and visuals as **PBIR** JSON
* `Sales_Performance.Report/StaticResources/RegisteredResources/`: the custom theme ([`theme/warehouse_theme.json`](theme/warehouse_theme.json))

## Open it on your machine
1. Install **Power BI Desktop** (free, Windows).
2. Open `Sales_Performance.pbix` (or `.pbip`).
3. *Home → Transform data → Edit parameters* → set **RepoFolder** to your clone of this repository, ending with `\`.
4. *Home → Refresh*.

**Live PostgreSQL instead of CSV:** create the read-only login with [`sql/bi/bi_reader_role.sql`](../sql/bi/bi_reader_role.sql),
then change each table's first Power Query step from `Csv.Document(...)` to
`PostgreSQL.Database("localhost:5433", "DataWarehouse"){[Schema="gold", Item="<view>"]}[Data]`.
Column names are identical, so the model and visuals don't change.
