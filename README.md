# SQL Data Warehouse, Python Analytics & Power BI Dashboard

[![CI](https://github.com/arpit1021-ux/sql-data-warehouse-advanced-analytics/actions/workflows/ci.yml/badge.svg)](https://github.com/arpit1021-ux/sql-data-warehouse-advanced-analytics/actions/workflows/ci.yml)
![PostgreSQL 16](https://img.shields.io/badge/PostgreSQL-16-336791)
![Python](https://img.shields.io/badge/Python-pandas%20%7C%20SciPy-3776AB)
![Power BI](https://img.shields.io/badge/Power%20BI-DAX%20%7C%20TMDL-F2C811)
![License: MIT](https://img.shields.io/badge/License-MIT-green)

![Project banner](docs/images/banner.png)

An end-to-end analytics project for a multi-country bicycle retailer whose data is split across a **CRM** and an
**ERP** system. Six raw CSV extracts are loaded into a **PostgreSQL** warehouse (Bronze → Silver → Gold), guarded by
automated **data-quality gates**, analysed with **SQL and Python**, and served in a 4-page **Power BI** dashboard and
a consulting-style **[insights report](INSIGHTS.md)**.

Everything is reproducible with one command, and **CI rebuilds the warehouse and runs 67 tests on every push**.

---

## Headline insights ([full report →](INSIGHTS.md))

| | Finding | Recommendation |
|---|---|---|
| 📈 | 2013 revenue grew **+180%**, driven by 12.5K new customers and an accessories launch; AOV fell 57% purely from product mix | Report AOV by category, not blended |
| 💰 | Accessories earn a **62.8% margin** vs 39% for bikes | Bundle accessories with every bike |
| ⚠️ | **33% of revenue** sits with about 2,900 high-value customers who haven't ordered in about a year (RFM "At Risk") | Win-back programme (≈ $0.3M illustrative upside) |
| 🌎 | US revenue per customer is **half of Australia's** ($1,225 vs $2,523) | US pricing and assortment review (≈ $0.9M at +10%) |
| 🔁 | **63%** of customers bought only once | Second-purchase journey after the first order |

![Executive Overview](powerbi/screenshots/01_overview.png)

---

## Architecture

```mermaid
flowchart LR
    subgraph Sources["data/raw (CSV)"]
        CRM["CRM<br/>customers · products · sales"]
        ERP["ERP<br/>demographics · locations · categories"]
    end
    subgraph Warehouse["PostgreSQL warehouse"]
        B["Bronze<br/>raw tables<br/>bronze.load_bronze()"]
        S["Silver<br/>cleansed tables<br/>silver.load_silver()"]
        G["Gold<br/>star schema + report views"]
        Q{{"Quality gates<br/>28 checks"}}
        L[("etl.load_log")]
    end
    subgraph Consume["Consumption"]
        SQLA["SQL analytics<br/>sql/analytics"]
        PY["Python notebook<br/>RFM · cohorts · stats"]
        PBI["Power BI<br/>4-page dashboard"]
        INS["INSIGHTS.md"]
    end
    CRM --> B
    ERP --> B
    B --> S --> G
    B -.-> L
    S -.-> L
    S --> Q
    G --> Q
    G --> SQLA
    G -->|"data/gold/*.csv"| PY
    G -->|"data/gold/*.csv"| PBI
    PY -->|"rfm_segments.csv"| PBI
    PY --> INS
```

| Layer | Object type | Load | What happens |
|---|---|---|---|
| **Bronze** | Tables | Full load (truncate + `COPY`) | Source files loaded as-is for traceability |
| **Silver** | Tables | Full load (truncate + insert) | De-duplication, trimming, code decoding, date repair, SCD-2 end dates, sales = qty × price repair |
| **Gold** | Views | – | Star schema (`dim_customers`, `dim_products`, `dim_date`, `fact_sales`) and reports (`report_customers`, `report_products`) |

| Source → layer lineage | Source-system relationships |
|---|---|
| ![Data flow](docs/images/data_flow.png) | ![Data integration](docs/images/data_integration.png) |

![Star schema](docs/images/data_model.png)

---

## Quick start

**Option A: zero setup (Python 3.10–3.12).** The pipeline starts an embedded PostgreSQL 16 automatically.

```bash
git clone https://github.com/arpit1021-ux/sql-data-warehouse-advanced-analytics.git
cd sql-data-warehouse-advanced-analytics
pip install -r requirements.txt

python -m pipeline run      # build bronze → silver → gold, run quality gates, export data/gold/*.csv
pytest                      # 67 tests against a fresh build
```

**Option B: Docker (any Python 3.10+).** Use this on Python 3.13+, where the embedded server isn't available.

```powershell
docker compose up -d                      # PostgreSQL 16 on port 5433, data/raw mounted at /data/raw
pip install -r requirements.txt

# PowerShell (bash: export DATABASE_URL=... WAREHOUSE_SOURCE_DIR=/data/raw)
$env:DATABASE_URL = "postgresql://postgres:postgres@localhost:5433/DataWarehouse"
$env:WAREHOUSE_SOURCE_DIR = "/data/raw"

python -m pipeline run
pytest
```
`WAREHOUSE_SOURCE_DIR` is the `data/raw` folder **as the database server sees it**, because `COPY` reads files
server-side. The same two variables point the pipeline and tests at any PostgreSQL 16 server
(`--database-url` / `--source-dir` work too).

Sample run:
```
== Bronze: load source files
Bronze layer loaded: 6 tables, 116294 rows
== Silver: cleanse and standardise
Silver layer loaded: 6 tables, 116284 rows
== Gold: star schema and reports
  gold.fact_sales            60398 rows
  gold.report_customers      18482 rows
== Quality gates
  [PASS] gold_checks: fact_sales: no rows lost or duplicated between silver and gold
  [WARN] silver_checks: erp_cust_az12: birthdates are after 1924-01-01 and not in the future  (15 rows)
Quality checks: 26 passed, 2 warnings, 0 failed
Pipeline finished successfully
```

---

## Data quality and testing

**Quality gates** ([`sql/quality/`](sql/quality/)): 28 declarative checks, each a query returning the offending rows.
`error` checks fail the pipeline; `warn` checks surface known source issues that are handled downstream
(19 order lines with invalid dates, 15 implausibly old birthdates).

| Area | Examples |
|---|---|
| Keys | Primary keys unique and not null; one current version per product |
| Standardisation | Gender, marital status, product line, country and maintenance use a fixed vocabulary |
| Business rules | sales = quantity × price and all positive; order date ≤ ship/due date; cost ≥ 0 |
| Integrity | Every sale joins to a customer and product; every CRM customer has ERP records |
| Reconciliation | No rows or revenue lost between Silver and Gold; report totals equal fact totals |
| Calendar | `dim_date` has no gaps and covers every order, ship and due date |

**Test suite** ([`tests/`](tests/), 67 tests): every quality check; bronze row counts equal the source files;
`etl.load_log` completeness; a failed load raises and rolls back; `gold.month_diff` semantics; headline KPIs, yearly
sales and segment counts; all analytics SQL executes; the committed `data/gold` CSVs match a fresh export byte for byte.

**CI** ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)): ruff lint → pipeline → export-reproducibility check →
pytest → notebook execution, plus a second job that runs the pipeline against a PostgreSQL 16 server container.

---

## Analytics

### SQL ([`sql/analytics/`](sql/analytics/))
Eleven scripts following an EDA → advanced-analytics progression:

![Analytics roadmap](docs/images/eda_roadmap.png)

| # | Script | Techniques |
|---|---|---|
| 01–04 | Database, dimension, date-range and measure exploration | `INFORMATION_SCHEMA`, `DISTINCT`, `AGE()`, aggregates |
| 05 | Magnitude | `GROUP BY` across dimensions |
| 06 | Ranking | `ROW_NUMBER()`, top/bottom N |
| 07 | Change over time | `DATE_TRUNC`, monthly trends |
| 08 | Cumulative | Running totals and moving averages with window frames |
| 09 | Performance | `LAG()`, YoY and vs-average comparisons |
| 10 | Part-to-whole | `SUM() OVER ()` shares |
| 11 | Segmentation | Cost bands, VIP / Regular / New customers |

Customer and product reports live in the warehouse itself as `gold.report_customers` and `gold.report_products`.

### Python ([`analysis/`](analysis/))
[`retail_sales_analysis.ipynb`](analysis/retail_sales_analysis.ipynb): data-quality audit, revenue decomposition,
Pareto concentration, category margins, cross-sell attach rate, market performance, **RFM segmentation**
(exported to Power BI), **quarterly cohort retention** and **Welch's t-tests with effect sizes**.

| RFM segments | Cohort retention |
|---|---|
| ![RFM](analysis/charts/05_rfm_segments.png) | ![Cohorts](analysis/charts/06_cohort_retention.png) |

### Power BI ([`powerbi/`](powerbi/))
[`Sales_Performance.pbix`](powerbi/Sales_Performance.pbix) · [PDF](powerbi/Sales_Performance.pdf):
star-schema model on the Gold exports, 33 DAX measures (time intelligence, ranking, attach and repeat rates),
synced slicers, Row-Level Security, and a text-based Power BI Project (TMDL + PBIR) for version control.

| | |
|---|---|
| ![Trends](powerbi/screenshots/02_trends.png) | ![Products](powerbi/screenshots/03_products.png) |
| ![Customers](powerbi/screenshots/04_customers.png) | ![Overview](powerbi/screenshots/01_overview.png) |

---

## Repository structure

```
├── data/
│   ├── raw/{crm,erp}/          source extracts (6 CSV files)
│   └── gold/                   Gold layer exports written by the pipeline
├── sql/
│   ├── warehouse/              00_init_database, bronze/, silver/, gold/ (DDL + load procedures)
│   ├── quality/                silver_checks.sql, gold_checks.sql (quality gates)
│   ├── analytics/              01–11 exploratory and advanced analytics
│   └── bi/                     read-only role for BI tools
├── pipeline/                   python -m pipeline (build, check, export)
├── tests/                      pytest suite
├── analysis/                   notebook, charts, RFM output
├── powerbi/                    .pbix, .pbip project, DAX, theme, validation, screenshots
├── docs/                       data catalog, naming conventions, diagrams
├── INSIGHTS.md                 business findings and recommendations
├── docker-compose.yml          PostgreSQL 16 server option
└── .github/workflows/ci.yml    continuous integration
```

## Documentation
* [Data catalog](docs/data_catalog.md): every Gold column, metric definitions and the as-of-date convention
* [Naming conventions](docs/naming_conventions.md)
* [Layer design](docs/images/mesh_architecture_layers.png)
* [Power BI model and measures](powerbi/README.md)

## Tech stack
PostgreSQL 16 (PL/pgSQL procedures, window functions, CTEs, views) · Python (psycopg 3, pandas, NumPy, SciPy,
Matplotlib, Jupyter) · pytest · ruff · GitHub Actions · Docker Compose · Power BI Desktop (Power Query, DAX, TMDL/PBIR)

---

**Dataset:** synthetic retail data for portfolio use; no real customer data.
**License:** [MIT](LICENSE).

## Author
**Arpit Singh**, Computer & Communication Engineering, LNMIIT Jaipur
[LinkedIn](https://www.linkedin.com/in/arpitsingh05) · [GitHub](https://github.com/arpit1021-ux) · [arpit.singh1183@gmail.com](mailto:arpit.singh1183@gmail.com)
