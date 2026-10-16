-- ============================================================
-- SupplyIQ 2.0
-- Executive KPI Analytical Layer
-- ============================================================

SET search_path TO supplyiq;

-- ============================================================
-- 1. EXECUTIVE KPI SUMMARY
-- ============================================================

DROP VIEW IF EXISTS vw_executive_kpis;

CREATE VIEW vw_executive_kpis AS
WITH
sales_metrics AS (
    SELECT
        COUNT(*) AS total_orders,
        SUM(quantity) AS total_units_sold,
        SUM(revenue) AS total_revenue,
        SUM(profit) AS total_profit,
        AVG(revenue) AS average_order_value,
        COUNT(*) FILTER (WHERE profit < 0) AS loss_making_orders
    FROM fact_sales
),

procurement_metrics AS (
    SELECT
        SUM(procurement_value) AS total_procurement_spend,
        SUM(po_quantity) AS total_procurement_units,
        COUNT(*) AS total_purchase_orders,
        COUNT(*) FILTER (
            WHERE actual_delivery_date IS NULL
        ) AS pending_purchase_orders
    FROM fact_procurement
),

inventory_metrics AS (
    SELECT
        SUM(inventory_value) AS total_inventory_value,
        SUM(closing_stock) AS total_closing_stock
    FROM fact_inventory
),

shipment_metrics AS (
    SELECT
        COUNT(*) AS total_shipments,
        COUNT(*) FILTER (
            WHERE delivery_status = 'Delivered'
        ) AS delivered_shipments,
        COUNT(*) FILTER (
            WHERE delivery_status = 'Delayed'
        ) AS delayed_shipments,
        COUNT(*) FILTER (
            WHERE delivery_status = 'Pending'
        ) AS pending_shipments,
        AVG(delay_days) FILTER (
            WHERE delivery_status = 'Delivered'
        ) AS average_delivery_delay
    FROM fact_shipments
),

return_metrics AS (
    SELECT
        COUNT(*) AS total_returns,
        SUM(quantity) AS total_returned_units,
        SUM(refund_amount) AS total_refund_amount
    FROM fact_returns
)

SELECT
    s.total_orders,
    s.total_units_sold,
    ROUND(s.total_revenue, 2) AS total_revenue,
    ROUND(s.total_profit, 2) AS total_profit,

    ROUND(
        s.total_profit / NULLIF(s.total_revenue, 0) * 100,
        2
    ) AS profit_margin_pct,

    ROUND(s.average_order_value, 2) AS average_order_value,

    s.loss_making_orders,

    ROUND(p.total_procurement_spend, 2)
        AS total_procurement_spend,

    p.total_procurement_units,
    p.total_purchase_orders,
    p.pending_purchase_orders,

    ROUND(i.total_inventory_value, 2)
        AS total_inventory_value,

    i.total_closing_stock,

    sh.total_shipments,
    sh.delivered_shipments,
    sh.delayed_shipments,
    sh.pending_shipments,

    ROUND(
        sh.delivered_shipments::numeric
        / NULLIF(sh.total_shipments, 0) * 100,
        2
    ) AS on_time_delivery_pct,

    ROUND(
        sh.average_delivery_delay,
        2
    ) AS average_delivery_delay_days,

    r.total_returns,
    r.total_returned_units,

    ROUND(r.total_refund_amount, 2)
        AS total_refund_amount,

    ROUND(
        r.total_returns::numeric
        / NULLIF(s.total_orders, 0) * 100,
        2
    ) AS return_rate_pct

FROM sales_metrics s
CROSS JOIN procurement_metrics p
CROSS JOIN inventory_metrics i
CROSS JOIN shipment_metrics sh
CROSS JOIN return_metrics r;


-- ============================================================
-- 2. MONTHLY EXECUTIVE PERFORMANCE
-- ============================================================

DROP VIEW IF EXISTS vw_monthly_executive_performance;

CREATE VIEW vw_monthly_executive_performance AS
SELECT
    d.year,
    d.month,
    d.month_name,

    COUNT(DISTINCT s.sales_key) AS total_orders,

    COALESCE(SUM(s.quantity), 0)
        AS units_sold,

    ROUND(
        COALESCE(SUM(s.revenue), 0),
        2
    ) AS revenue,

    ROUND(
        COALESCE(SUM(s.profit), 0),
        2
    ) AS profit,

    ROUND(
        COALESCE(
            SUM(s.profit)
            / NULLIF(SUM(s.revenue), 0)
            * 100,
            0
        ),
        2
    ) AS profit_margin_pct,

    ROUND(
        COALESCE(
            AVG(s.revenue),
            0
        ),
        2
    ) AS average_order_value,

    ROUND(
        COALESCE(
            SUM(p.procurement_value),
            0
        ),
        2
    ) AS procurement_spend,

    ROUND(
        COALESCE(
            SUM(r.refund_amount),
            0
        ),
        2
    ) AS refund_amount

FROM dim_date d

LEFT JOIN fact_sales s
    ON d.date_key = s.date_key

LEFT JOIN fact_procurement p
    ON d.date_key = p.date_key

LEFT JOIN fact_returns r
    ON d.date_key = r.date_key

GROUP BY
    d.year,
    d.month,
    d.month_name

ORDER BY
    d.year,
    d.month;


-- ============================================================
-- 3. DELIVERY PERFORMANCE SUMMARY
-- ============================================================

DROP VIEW IF EXISTS vw_delivery_performance;

CREATE VIEW vw_delivery_performance AS
SELECT
    COUNT(*) AS total_shipments,

    COUNT(*) FILTER (
        WHERE delivery_status = 'Delivered'
    ) AS delivered_shipments,

    COUNT(*) FILTER (
        WHERE delivery_status = 'Delayed'
    ) AS delayed_shipments,

    COUNT(*) FILTER (
        WHERE delivery_status = 'Pending'
    ) AS pending_shipments,

    ROUND(
        COUNT(*) FILTER (
            WHERE delivery_status = 'Delivered'
        )::numeric
        / NULLIF(COUNT(*), 0) * 100,
        2
    ) AS delivery_success_pct,

    ROUND(
        AVG(delay_days),
        2
    ) AS average_delay_days,

    ROUND(
        MAX(delay_days),
        2
    ) AS maximum_delay_days

FROM fact_shipments;


-- ============================================================
-- 4. PROFITABILITY SUMMARY
-- ============================================================

DROP VIEW IF EXISTS vw_profitability_summary;

CREATE VIEW vw_profitability_summary AS
SELECT
    COUNT(*) AS total_transactions,

    SUM(quantity) AS total_units,

    ROUND(
        SUM(revenue),
        2
    ) AS total_revenue,

    ROUND(
        SUM(cost),
        2
    ) AS total_cost,

    ROUND(
        SUM(profit),
        2
    ) AS total_profit,

    ROUND(
        SUM(profit)
        / NULLIF(SUM(revenue), 0)
        * 100,
        2
    ) AS profit_margin_pct,

    COUNT(*) FILTER (
        WHERE profit < 0
    ) AS loss_making_transactions,

    ROUND(
        COUNT(*) FILTER (
            WHERE profit < 0
        )::numeric
        / NULLIF(COUNT(*), 0) * 100,
        2
    ) AS loss_transaction_pct

FROM fact_sales;


-- ============================================================
-- 5. INVENTORY HEALTH SUMMARY
-- ============================================================

DROP VIEW IF EXISTS vw_inventory_health;

CREATE VIEW vw_inventory_health AS
SELECT
    COUNT(*) AS inventory_records,

    SUM(closing_stock) AS total_closing_stock,

    ROUND(
        SUM(inventory_value),
        2
    ) AS total_inventory_value,

    ROUND(
        AVG(closing_stock),
        2
    ) AS average_closing_stock,

    COUNT(*) FILTER (
        WHERE closing_stock = 0
    ) AS stockout_records,

    ROUND(
        COUNT(*) FILTER (
            WHERE closing_stock = 0
        )::numeric
        / NULLIF(COUNT(*), 0) * 100,
        2
    ) AS stockout_rate_pct

FROM fact_inventory;


-- ============================================================
-- 6. SUPPLY CHAIN EXECUTIVE SCORECARD
-- ============================================================

DROP VIEW IF EXISTS vw_supply_chain_scorecard;

CREATE VIEW vw_supply_chain_scorecard AS
SELECT
    ROUND(
        (
            (
                SELECT
                    COUNT(*) FILTER (
                        WHERE delivery_status = 'Delivered'
                    )::numeric
                    / NULLIF(COUNT(*), 0) * 100
                FROM fact_shipments
            )
            +
            (
                SELECT
                    SUM(profit)
                    / NULLIF(SUM(revenue), 0) * 100
                FROM fact_sales
            )
        ) / 2,
        2
    ) AS overall_business_score,

    ROUND(
        (
            SELECT
                COUNT(*) FILTER (
                    WHERE delivery_status = 'Delivered'
                )::numeric
                / NULLIF(COUNT(*), 0) * 100
            FROM fact_shipments
        ),
        2
    ) AS logistics_score,

    ROUND(
        (
            SELECT
                SUM(profit)
                / NULLIF(SUM(revenue), 0) * 100
            FROM fact_sales
        ),
        2
    ) AS profitability_score,

    ROUND(
        (
            SELECT
                COUNT(*) FILTER (
                    WHERE closing_stock > 0
                )::numeric
                / NULLIF(COUNT(*), 0) * 100
            FROM fact_inventory
        ),
        2
    ) AS inventory_availability_score;