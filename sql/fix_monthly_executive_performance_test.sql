CREATE OR REPLACE VIEW supplyiq.vw_monthly_executive_performance_test AS
WITH monthly_calendar AS (
    SELECT DISTINCT year, month, month_name
    FROM supplyiq.dim_date
),
sales_monthly AS (
    SELECT
        d.year,
        d.month,
        d.month_name,
        COUNT(DISTINCT s.sales_key) AS total_orders,
        COALESCE(SUM(s.quantity), 0) AS units_sold,
        ROUND(COALESCE(SUM(s.revenue), 0), 2) AS revenue,
        ROUND(COALESCE(SUM(s.profit), 0), 2) AS profit,
        ROUND(
            COALESCE(
                SUM(s.profit) / NULLIF(SUM(s.revenue), 0) * 100,
                0
            ), 2
        ) AS profit_margin_pct,
        ROUND(COALESCE(AVG(s.revenue), 0), 2) AS average_order_value
    FROM supplyiq.dim_date d
    JOIN supplyiq.fact_sales s ON s.date_key = d.date_key
    GROUP BY d.year, d.month, d.month_name
),
procurement_monthly AS (
    SELECT
        d.year,
        d.month,
        d.month_name,
        ROUND(COALESCE(SUM(p.procurement_value), 0), 2) AS procurement_spend
    FROM supplyiq.dim_date d
    JOIN supplyiq.fact_procurement p ON p.date_key = d.date_key
    GROUP BY d.year, d.month, d.month_name
),
returns_monthly AS (
    SELECT
        d.year,
        d.month,
        d.month_name,
        ROUND(COALESCE(SUM(r.refund_amount), 0), 2) AS refund_amount
    FROM supplyiq.dim_date d
    JOIN supplyiq.fact_returns r ON r.date_key = d.date_key
    GROUP BY d.year, d.month, d.month_name
)
SELECT
    c.year,
    c.month,
    c.month_name,
    COALESCE(s.total_orders, 0) AS total_orders,
    COALESCE(s.units_sold, 0) AS units_sold,
    COALESCE(s.revenue, 0) AS revenue,
    COALESCE(s.profit, 0) AS profit,
    COALESCE(s.profit_margin_pct, 0) AS profit_margin_pct,
    COALESCE(s.average_order_value, 0) AS average_order_value,
    COALESCE(p.procurement_spend, 0) AS procurement_spend,
    COALESCE(r.refund_amount, 0) AS refund_amount
FROM monthly_calendar c
LEFT JOIN sales_monthly s
    ON s.year = c.year AND s.month = c.month
LEFT JOIN procurement_monthly p
    ON p.year = c.year AND p.month = c.month
LEFT JOIN returns_monthly r
    ON r.year = c.year AND r.month = c.month;
