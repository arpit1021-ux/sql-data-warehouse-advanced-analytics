# Expected KPI values

Computed directly from the Gold layer exports in `data/gold/`.
After building the report, every value below must match your Power BI visuals (with no slicers applied).
Re-run `reconcile_kpis.sql` against PostgreSQL to confirm the warehouse gives the same numbers.

## Headline KPIs

| KPI | Expected value |
|---|---|
| Total Sales | 29,356,250 |
| Total Quantity | 60,423 |
| Total Orders | 27,659 |
| Total Customers (with ≥1 order) | 18,484 |
| Total Products sold | 130 |
| Avg Order Value | 1,061.36 |
| Gross Profit | 11,685,757 |
| Gross Margin % | 39.81% |

## Sales by year

| Year | Sales | Orders | Customers |
|---|---|---|---|
| 2010 | 43,419 | 14 | 14 |
| 2011 | 7,075,088 | 2,216 | 2,216 |
| 2012 | 5,842,231 | 3,269 | 3,255 |
| 2013 | 16,344,878 | 21,287 | 17,427 |
| 2014 | 45,642 | 871 | 834 |

> 19 fact rows have a NULL `order_date` (invalid dates nulled in the Silver layer). They count in the headline totals but not in any year — keep this in mind when the yearly totals don't add up to Total Sales.

## Sales by category

| Category | Sales | % of total |
|---|---|---|
| Bikes | 28,316,272 | 96.46% |
| Accessories | 700,262 | 2.39% |
| Clothing | 339,716 | 1.16% |

## Sales by country

| Country | Sales |
|---|---|
| United States | 9,162,327 |
| Australia | 9,060,172 |
| United Kingdom | 3,391,376 |
| Germany | 2,894,066 |
| France | 2,643,751 |
| Canada | 1,977,738 |
| n/a (unknown) | 226,820 |

## Top 5 products

| Product | Sales |
|---|---|
| Mountain-200 Black- 46 | 1,373,454 |
| Mountain-200 Black- 42 | 1,363,128 |
| Mountain-200 Silver- 38 | 1,339,394 |
| Mountain-200 Silver- 46 | 1,301,029 |
| Mountain-200 Black- 38 | 1,294,854 |

## Customer segments (from gold.report_customers)

| Segment | Customers | Sales |
|---|---|---|
| New | 14,629 | 11,086,797 |
| Regular | 2,200 | 7,503,991 |
| VIP | 1,653 | 10,760,470 |

## ⚠️ Known discrepancy worth talking about: customer lifespan

The Customer Segment rule is *VIP = lifespan ≥ 12 months and sales > 5,000; Regular = lifespan ≥ 12 months; else New*.
"Lifespan in months" can be defined two ways, and they give different segment counts:

| Definition | Where | New | Regular | VIP |
|---|---|---|---|---|
| Month **boundaries** crossed (`DATEDIFF(..., MONTH)`) | Power BI DAX, SQL Server, the exported `gold.report_customers.csv` | 14,629 | 2,200 | 1,653 |
| **Complete** months elapsed (`AGE()` in PostgreSQL) | `12_report_customers.sql` run on PostgreSQL | 14,826 | 2,039 | 1,617 |

Example: first order 2012-01-31, last order 2013-01-01 → 12 boundaries crossed, but only 11 complete months.

Your Power BI segments should match the **first** row. If you want the dashboard to match the PostgreSQL script exactly,
change the `Lifespan Months` column to subtract 1 when `DAY(Last Order Date) < DAY(First Order Date)`.
Pick one definition, document it, and apply it everywhere — this is a real metric-definition issue BI teams deal with.
