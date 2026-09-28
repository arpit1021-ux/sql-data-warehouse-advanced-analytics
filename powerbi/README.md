# 📊 Power BI Dashboard: Sales Performance on the Gold Layer

A 4-page interactive Power BI report built on the warehouse's Gold star schema, plus the RFM segments from the [Python analysis](../analysis/).

**Open it:** [`Sales_Performance.pbix`](Sales_Performance.pbix) in Power BI Desktop, or skim the [PDF export](Sales_Performance.pdf).

```
ERP + CRM → BRONZE → SILVER → GOLD (star schema) ─┬─→ Power BI semantic model → 4-page report
                                                  └─→ Python RFM segments ──┘
```

## Pages

### 1. Executive Overview
KPIs, monthly trend with a 3-month rolling average, and sales by category, country and customer segment.
![Executive Overview](screenshots/01_overview.png)

### 2. Sales Trends
Selected-year vs. prior-year comparison (defaults to the latest full year), YoY growth, running total, and a year × quarter matrix.
![Sales Trends](screenshots/02_trends.png)

### 3. Product Performance
Dynamic title, profit and margin KPIs, accessory attach rate, top 10 products, category → subcategory treemap, volume vs. margin scatter, and product ranking.
![Product Performance](screenshots/03_products.png)

### 4. Customer Insights
RFM segments (revenue vs. headcount), revenue per customer by country, age at first order, and top 10 customers.
![Customer Insights](screenshots/04_customers.png)

All pages share **synced Year / Country / Category slicers**.

---

## Data model

```
                    dim_date (marked date table)
                       │ 1   active:   order_date    → date
                       │     inactive: shipping_date → date   (used via USERELATIONSHIP)
                       ▼ *
dim_customers 1 ──▶ * fact_sales * ◀── 1 dim_products
 (+ RFM segment merged in Power Query from Python output)
```

* One-to-many, single-direction relationships; keys and raw numeric columns hidden, so report authors only use measures.
* Auto date/time turned off in favour of a proper calendar dimension.
* **Row-Level Security:** role `Country Manager - US` filters `dim_customers[country] = "United States"` (test with *Modeling → View as*).
* **33 DAX measures** in a dedicated `_Measures` table, organised into display folders (Sales, Profit, Customers, Time Intelligence, Ranking). Full list: [`dax/measures.dax`](dax/measures.dax).

Highlights:
| Measure | Technique |
|---|---|
| `Gross Profit`, `Total Cost` | `SUMX` + `RELATED` across the star |
| `Sales YTD`, `Sales PY`, `Sales YoY %`, `Sales MoM %` | Time intelligence on the marked date table |
| `Sales 3M Rolling Avg`, `Running Total Sales` | `DATESINPERIOD`, `ALLSELECTED` |
| `Selected Year` & friends | Default to the latest full year when no year is selected |
| `Repeat Customer Rate` | Customers with >1 order via `FILTER(VALUES(...))` + context transition |
| `Accessory Attach Rate` | `INTERSECT` of bike buyers and accessory buyers |
| `Product Rank`, `Top 10 Product Sales` | `RANKX` + `ISINSCOPE` |
| `Sales by Ship Date` | `USERELATIONSHIP` on the inactive date relationship |
| Customer/Product segments | SQL segmentation logic re-implemented as calculated columns |

## Validation
Every number on the report reconciles with the warehouse. See [`validation/expected_kpis.md`](validation/expected_kpis.md) and [`validation/reconcile_kpis.sql`](validation/reconcile_kpis.sql).

| KPI | SQL / Python | Power BI |
|---|---|---|
| Total Sales | 29,356,250 | $29.36M ✅ |
| Total Orders | 27,659 | 27.7K ✅ |
| Customers | 18,484 | 18.5K ✅ |
| Gross Margin | 39.81% | 39.8% ✅ |
| Repeat-purchase rate | 37.1% (Python) | 37.1% ✅ |
| Accessory attach rate | 71.5% (Python) | 71.5% ✅ |
| 2013 YoY growth | +179.8% | 179.8% ✅ |

## Source control (Power BI Project format)
Besides the `.pbix`, the report is saved as a **Power BI Project** (`Sales_Performance.pbip`), so the model and report are plain text and diff cleanly in Git:
* `Sales_Performance.SemanticModel/definition/`: tables, measures, relationships and roles in **TMDL**
* `Sales_Performance.Report/definition/`: pages and visuals as **PBIR** JSON
* `Sales_Performance.Report/StaticResources/RegisteredResources/`: the custom theme ([`theme/warehouse_theme.json`](theme/warehouse_theme.json))

## Run it on your machine
1. Install **Power BI Desktop** (free, Windows).
2. Open `Sales_Performance.pbix` (or `.pbip`).
3. *Home → Transform data → Edit parameters* → set **RepoFolder** to where you cloned this repo (ending with `\`).
4. *Home → Refresh*.

**Switching to live PostgreSQL:** run [`sql/01_bi_layer.sql`](sql/01_bi_layer.sql) (adds `gold.dim_date` and a read-only `bi_reader` login). Then in Power Query change each table's source from `Csv.Document(...)` to `PostgreSQL.Database("localhost:5432", "<db>"){[Schema="gold",Item="<table>"]}[Data]`. Column names are identical, so the model and visuals don't change.

## Folder contents
| Path | What |
|---|---|
| `Sales_Performance.pbix` / `.pdf` | The report and its PDF export |
| `Sales_Performance.pbip` + `*.SemanticModel/` + `*.Report/` | Same report in text (PBIP) format |
| `dax/measures.dax` | All measures and calculated columns |
| `sql/01_bi_layer.sql` | Calendar dimension + read-only BI role for PostgreSQL |
| `theme/warehouse_theme.json` | Report theme (colour-blind-safe palette) |
| `validation/` | KPI reconciliation SQL and expected values |
| `screenshots/` | Page images used above |
