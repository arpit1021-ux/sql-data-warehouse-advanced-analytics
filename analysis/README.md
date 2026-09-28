# Python Analysis

Statistical and customer analytics on the Gold layer that go beyond the SQL scripts.
Open [`retail_sales_analysis.ipynb`](retail_sales_analysis.ipynb); GitHub renders it with every output and chart.

| Section | Technique |
|---|---|
| Data-quality audit | Referential integrity, uniqueness and business-rule checks with pandas |
| Revenue trend | Resampling, rolling averages, YoY growth, category-mix decomposition |
| Pareto | Cumulative revenue concentration (customers and products) |
| Category economics | Gross margin and profit share |
| Cross-sell | Basket analysis: accessory and clothing attach rate for bike buyers |
| Market performance | Revenue per customer, orders per customer and AOV by country |
| RFM segmentation | Recency / Frequency / Monetary scoring into 7 segments, exported to Power BI |
| Cohort retention | Quarterly first-purchase cohorts and a repeat-purchase heatmap |
| Demographics | Welch's t-test and Cohen's d to separate statistical from practical significance |

**Inputs:** `data/gold/*.csv`, written by `python -m pipeline run`.

**Outputs**
* `charts/`: the six charts used in [`../INSIGHTS.md`](../INSIGHTS.md)
* `output/rfm_segments.csv`: one row per customer with R/F/M scores and segment, merged into the Power BI customer dimension

**Run it** (from the repository root)
```bash
pip install -r requirements.txt
python -m pipeline run          # refresh data/gold (optional, the CSVs are committed)
jupyter nbconvert --to notebook --execute --inplace analysis/retail_sales_analysis.ipynb
```
CI executes the notebook on every push and fails if `output/rfm_segments.csv` changes.
