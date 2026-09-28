# 🐍 Python Analysis

Statistical and customer analytics on the Gold layer that go beyond the SQL scripts.
Open **[`retail_sales_analysis.ipynb`](retail_sales_analysis.ipynb)** (GitHub renders it with all outputs and charts).

| Section | Technique |
|---|---|
| Data quality audit | Referential integrity, uniqueness and business-rule checks with pandas |
| Revenue trend | Resampling, rolling averages, YoY growth, category-mix decomposition |
| Pareto | Cumulative revenue concentration (customers & products) |
| Category economics | Gross margin and profit share |
| Cross-sell | Basket analysis: accessory/clothing attach rate for bike buyers |
| Market performance | Revenue per customer, orders per customer, AOV by country |
| RFM segmentation | Recency / Frequency / Monetary scoring → 7 actionable segments, exported to Power BI |
| Cohort retention | Quarterly first-purchase cohorts, repeat-purchase heatmap |
| Demographics | Welch's t-test + Cohen's d, separating statistical from practical significance |

**Outputs**
* `charts/`: the six charts used in [`../INSIGHTS.md`](../INSIGHTS.md)
* `output/rfm_segments.csv`: one row per customer with R/F/M scores and segment, loaded into the Power BI model

**Run it**
```bash
cd analysis
pip install -r requirements.txt
jupyter notebook retail_sales_analysis.ipynb
```
