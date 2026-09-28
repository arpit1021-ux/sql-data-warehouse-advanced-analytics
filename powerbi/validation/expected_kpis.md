# Expected KPI values

Every number on the dashboard (with no slicers applied) must equal the values below.
They are asserted automatically by `tests/test_gold_model.py` against a fresh warehouse build,
and [`reconcile_kpis.sql`](reconcile_kpis.sql) returns the same figures from PostgreSQL.

## Headline KPIs (Executive Overview)

| KPI | Warehouse value | Dashboard |
|---|---|---|
| Total Sales | 29,356,250 | $29.36M |
| Total Orders | 27,659 | 27.7K |
| Active Customers | 18,484 | 18.5K |
| Avg Order Value | 1,061.36 | $1.06K |
| Gross Profit | 11,685,757 | $11.69M |
| Gross Margin % | 39.81% | 39.8% |
| Repeat-purchase rate | 37.1% | 37.1% |
| Accessory attach rate (bike buyers) | 71.5% | 71.5% |

## Sales by year

| Year | Sales | Orders | Customers |
|---|---|---|---|
| 2010 | 43,419 | 14 | 14 |
| 2011 | 7,075,088 | 2,216 | 2,216 |
| 2012 | 5,842,231 | 3,269 | 3,255 |
| 2013 | 16,344,878 | 21,287 | 17,427 |
| 2014 | 45,642 | 871 | 834 |

19 order lines (4,992 in sales) have an invalid source order date. They count in the headline totals but
not in any year, which is why the yearly rows add up to 29,351,258.

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
| Unknown | 226,820 |

## Segments (gold.report_customers / gold.report_products)

| Customer segment | Customers | Sales |
|---|---|---|
| New | 14,629 | 11,086,797 |
| VIP | 1,653 | 10,760,470 |
| Regular | 2,200 | 7,503,991 |

| Product segment | Products |
|---|---|
| High-Performer | 66 |
| Mid-Range | 58 |
| Low-Performer | 6 |

Segments are computed once, in the warehouse views, with lifespan measured by `gold.month_diff()`
(calendar-month boundaries between first and last order). Power BI loads them instead of re-deriving them,
so the dashboard and SQL cannot drift apart.
