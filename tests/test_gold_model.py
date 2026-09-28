"""Gold layer: helper function, headline KPIs and segment definitions."""

import datetime as dt

import pytest

from .conftest import scalar


@pytest.mark.parametrize(
    "start, end, expected",
    [
        ("2013-01-31", "2013-02-01", 1),  # crossing a month boundary counts as one month
        ("2013-01-01", "2013-01-31", 0),
        ("2012-12-15", "2014-01-10", 13),
        ("2014-01-28", "2014-01-28", 0),
    ],
)
def test_month_diff_counts_month_boundaries(warehouse, start, end, expected):
    assert scalar(warehouse, "SELECT gold.month_diff(%s::date, %s::date)", (start, end)) == expected


def test_headline_kpis(warehouse):
    row = warehouse.execute("""
        SELECT SUM(f.sales_amount), SUM(f.quantity), COUNT(DISTINCT f.order_number),
               COUNT(DISTINCT f.customer_key), COUNT(DISTINCT f.product_key),
               SUM(f.sales_amount - f.quantity * p.cost)
        FROM gold.fact_sales f JOIN gold.dim_products p USING (product_key)
    """).fetchone()
    assert row == (29_356_250, 60_423, 27_659, 18_484, 130, 11_685_757)


def test_sales_by_year(warehouse):
    rows = dict(
        warehouse.execute("""
        SELECT EXTRACT(YEAR FROM order_date)::int, SUM(sales_amount)
        FROM gold.fact_sales WHERE order_date IS NOT NULL GROUP BY 1
    """).fetchall()
    )
    assert rows == {2010: 43_419, 2011: 7_075_088, 2012: 5_842_231, 2013: 16_344_878, 2014: 45_642}


def test_customer_segments(warehouse):
    rows = dict(
        warehouse.execute(
            "SELECT customer_segment, COUNT(*) FROM gold.report_customers GROUP BY 1"
        ).fetchall()
    )
    assert rows == {"New": 14_629, "Regular": 2_200, "VIP": 1_653}


def test_product_segments(warehouse):
    rows = dict(
        warehouse.execute("SELECT product_segment, COUNT(*) FROM gold.report_products GROUP BY 1").fetchall()
    )
    assert rows == {"High-Performer": 66, "Mid-Range": 58, "Low-Performer": 6}


def test_reports_are_measured_at_last_order_date(warehouse):
    as_of = scalar(warehouse, "SELECT MAX(order_date) FROM gold.fact_sales")
    assert as_of == dt.date(2014, 1, 28)
    assert scalar(warehouse, "SELECT MIN(recency) FROM gold.report_customers") == 0
    assert scalar(warehouse, "SELECT MIN(recency_in_months) FROM gold.report_products") == 0


def test_dim_date_spans_full_calendar_years(warehouse):
    first, last, days = warehouse.execute(
        "SELECT MIN(date), MAX(date), COUNT(*) FROM gold.dim_date"
    ).fetchone()
    assert (first, last) == (dt.date(2010, 1, 1), dt.date(2014, 12, 31))
    assert days == (last - first).days + 1
