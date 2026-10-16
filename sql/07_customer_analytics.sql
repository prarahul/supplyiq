-- ============================================================
-- SupplyIQ 2.0
-- Customer Analytics Layer
-- ============================================================

SET search_path TO supplyiq;

-- ============================================================
-- CLEAN EXISTING VIEWS
-- ============================================================

DROP VIEW IF EXISTS vw_customer_data_quality CASCADE;
DROP VIEW IF EXISTS vw_customer_value_ranking CASCADE;
DROP VIEW IF EXISTS vw_customer_return_analysis CASCADE;
DROP VIEW IF EXISTS vw_customer_logistics CASCADE;
DROP VIEW IF EXISTS vw_customer_geography CASCADE;
DROP VIEW IF EXISTS vw_customer_segment_performance CASCADE;
DROP VIEW IF EXISTS vw_customer_profitability CASCADE;
DROP VIEW IF EXISTS vw_customer_sales_performance CASCADE;


-- ============================================================
-- 1. CUSTOMER SALES PERFORMANCE
-- ============================================================

CREATE VIEW vw_customer_sales_performance AS
SELECT
    c.customer_key,
    c.customer_id,
    c.customer_name,
    c.segment,
    c.country,
    c.region,

    COUNT(*) AS total_orders,

    SUM(s.quantity) AS units_sold,

    ROUND(
        SUM(s.revenue),
        2
    ) AS revenue,

    ROUND(
        SUM(s.cost),
        2
    ) AS cost,

    ROUND(
        SUM(s.profit),
        2
    ) AS profit,

    ROUND(
        SUM(s.profit) * 100.0
        / NULLIF(SUM(s.revenue), 0),
        2
    ) AS profit_margin_pct,

    ROUND(
        SUM(s.revenue)
        / NULLIF(COUNT(*), 0),
        2
    ) AS average_order_value,

    ROUND(
        AVG(s.discount),
        2
    ) AS average_discount,

    COUNT(*) FILTER (
        WHERE s.profit < 0
    ) AS loss_making_orders

FROM fact_sales s

JOIN dim_customer c
    ON s.customer_key = c.customer_key

GROUP BY
    c.customer_key,
    c.customer_id,
    c.customer_name,
    c.segment,
    c.country,
    c.region;


-- ============================================================
-- 2. CUSTOMER PROFITABILITY
-- ============================================================

CREATE VIEW vw_customer_profitability AS
SELECT
    c.customer_key,
    c.customer_id,
    c.customer_name,
    c.segment,
    c.country,
    c.region,

    COUNT(*) AS orders,

    SUM(s.quantity) AS units_sold,

    ROUND(
        SUM(s.revenue),
        2
    ) AS revenue,

    ROUND(
        SUM(s.cost),
        2
    ) AS cost,

    ROUND(
        SUM(s.profit),
        2
    ) AS profit,

    ROUND(
        SUM(s.profit) * 100.0
        / NULLIF(SUM(s.revenue), 0),
        2
    ) AS profit_margin_pct,

    CASE
        WHEN SUM(s.profit) < 0
            THEN 'Loss Making'

        WHEN SUM(s.profit) * 100.0
             / NULLIF(SUM(s.revenue), 0) < 20
            THEN 'Low Margin'

        WHEN SUM(s.profit) * 100.0
             / NULLIF(SUM(s.revenue), 0) < 40
            THEN 'Healthy Margin'

        ELSE 'High Margin'
    END AS profitability_segment

FROM fact_sales s

JOIN dim_customer c
    ON s.customer_key = c.customer_key

GROUP BY
    c.customer_key,
    c.customer_id,
    c.customer_name,
    c.segment,
    c.country,
    c.region;


-- ============================================================
-- 3. CUSTOMER SEGMENT PERFORMANCE
-- ============================================================

CREATE VIEW vw_customer_segment_performance AS
SELECT
    c.segment,

    COUNT(DISTINCT c.customer_key) AS customers,

    COUNT(*) AS total_orders,

    SUM(s.quantity) AS units_sold,

    ROUND(
        SUM(s.revenue),
        2
    ) AS revenue,

    ROUND(
        SUM(s.cost),
        2
    ) AS cost,

    ROUND(
        SUM(s.profit),
        2
    ) AS profit,

    ROUND(
        SUM(s.profit) * 100.0
        / NULLIF(SUM(s.revenue), 0),
        2
    ) AS profit_margin_pct,

    ROUND(
        SUM(s.revenue)
        / NULLIF(COUNT(*), 0),
        2
    ) AS average_order_value,

    ROUND(
        AVG(s.discount),
        2
    ) AS average_discount

FROM fact_sales s

JOIN dim_customer c
    ON s.customer_key = c.customer_key

GROUP BY
    c.segment;


-- ============================================================
-- 4. CUSTOMER GEOGRAPHY
-- ============================================================

CREATE VIEW vw_customer_geography AS
SELECT
    c.country,
    c.region,

    COUNT(DISTINCT c.customer_key) AS customers,

    COUNT(*) AS orders,

    SUM(s.quantity) AS units_sold,

    ROUND(
        SUM(s.revenue),
        2
    ) AS revenue,

    ROUND(
        SUM(s.profit),
        2
    ) AS profit,

    ROUND(
        SUM(s.profit) * 100.0
        / NULLIF(SUM(s.revenue), 0),
        2
    ) AS profit_margin_pct,

    ROUND(
        SUM(s.revenue)
        / NULLIF(COUNT(*), 0),
        2
    ) AS average_order_value

FROM fact_sales s

JOIN dim_customer c
    ON s.customer_key = c.customer_key

GROUP BY
    c.country,
    c.region;


-- ============================================================
-- 5. CUSTOMER LOGISTICS PERFORMANCE
-- ============================================================

CREATE VIEW vw_customer_logistics AS
SELECT
    c.customer_key,
    c.customer_id,
    c.customer_name,
    c.segment,
    c.country,
    c.region,

    COUNT(*) AS shipments,

    SUM(s.quantity) AS units_shipped,

    ROUND(
        SUM(s.shipping_cost),
        2
    ) AS shipping_cost,

    COUNT(*) FILTER (
        WHERE s.delivery_status = 'Delivered'
    ) AS delivered_shipments,

    COUNT(*) FILTER (
        WHERE s.delivery_status = 'Delayed'
    ) AS delayed_shipments,

    COUNT(*) FILTER (
        WHERE s.delivery_status = 'Pending'
    ) AS pending_shipments,

    ROUND(
        COUNT(*) FILTER (
            WHERE s.delivery_status = 'Delivered'
              AND s.delay_days <= 0
        ) * 100.0
        / NULLIF(
            COUNT(*) FILTER (
                WHERE s.delivery_status = 'Delivered'
            ),
            0
        ),
        2
    ) AS on_time_delivery_pct,

    ROUND(
        AVG(
            CASE
                WHEN s.delivery_status <> 'Pending'
                THEN s.delay_days
            END
        ),
        2
    ) AS average_delay_days

FROM fact_shipments s

JOIN dim_customer c
    ON s.customer_key = c.customer_key

GROUP BY
    c.customer_key,
    c.customer_id,
    c.customer_name,
    c.segment,
    c.country,
    c.region;


-- ============================================================
-- 6. CUSTOMER RETURN ANALYSIS
-- ============================================================

CREATE VIEW vw_customer_return_analysis AS
WITH sales AS (
    SELECT
        customer_key,

        COUNT(*) AS orders,

        SUM(quantity) AS units_sold,

        SUM(revenue) AS revenue,

        SUM(profit) AS profit

    FROM fact_sales

    GROUP BY customer_key
),

returns AS (
    SELECT
        customer_key,

        COUNT(*) AS return_transactions,

        SUM(quantity) AS returned_units,

        SUM(refund_amount) AS refund_amount

    FROM fact_returns

    GROUP BY customer_key
)

SELECT
    c.customer_key,
    c.customer_id,
    c.customer_name,
    c.segment,
    c.country,
    c.region,

    COALESCE(s.orders, 0) AS orders,

    COALESCE(s.units_sold, 0) AS units_sold,

    ROUND(
        COALESCE(s.revenue, 0),
        2
    ) AS revenue,

    COALESCE(r.return_transactions, 0)
        AS return_transactions,

    COALESCE(r.returned_units, 0)
        AS returned_units,

    ROUND(
        COALESCE(r.refund_amount, 0),
        2
    ) AS refund_amount,

    ROUND(
        COALESCE(r.returned_units, 0) * 100.0
        / NULLIF(COALESCE(s.units_sold, 0), 0),
        2
    ) AS return_rate_pct,

    ROUND(
        COALESCE(r.refund_amount, 0) * 100.0
        / NULLIF(COALESCE(s.revenue, 0), 0),
        2
    ) AS refund_to_revenue_pct

FROM dim_customer c

LEFT JOIN sales s
    ON c.customer_key = s.customer_key

LEFT JOIN returns r
    ON c.customer_key = r.customer_key;


-- ============================================================
-- 7. CUSTOMER VALUE RANKING
-- ============================================================

CREATE VIEW vw_customer_value_ranking AS
WITH customer_value AS (
    SELECT
        c.customer_key,
        c.customer_id,
        c.customer_name,
        c.segment,
        c.country,
        c.region,

        COUNT(*) AS orders,

        SUM(s.quantity) AS units_sold,

        SUM(s.revenue) AS revenue,

        SUM(s.profit) AS profit

    FROM fact_sales s

    JOIN dim_customer c
        ON s.customer_key = c.customer_key

    GROUP BY
        c.customer_key,
        c.customer_id,
        c.customer_name,
        c.segment,
        c.country,
        c.region
)

SELECT
    customer_key,
    customer_id,
    customer_name,
    segment,
    country,
    region,

    orders,

    units_sold,

    ROUND(
        revenue,
        2
    ) AS revenue,

    ROUND(
        profit,
        2
    ) AS profit,

    RANK() OVER (
        ORDER BY revenue DESC
    ) AS revenue_rank,

    RANK() OVER (
        ORDER BY profit DESC
    ) AS profit_rank,

    ROUND(
        revenue * 100.0
        / NULLIF(
            SUM(revenue) OVER (),
            0
        ),
        4
    ) AS revenue_share_pct

FROM customer_value;


-- ============================================================
-- 8. CUSTOMER DATA QUALITY
-- ============================================================

CREATE VIEW vw_customer_data_quality AS
SELECT
    COUNT(*) AS total_customer_rows,

    COUNT(*) FILTER (
        WHERE customer_id IS NULL
    ) AS null_customer_id_rows,

    COUNT(*) FILTER (
        WHERE customer_name IS NULL
    ) AS null_customer_name_rows,

    COUNT(*) FILTER (
        WHERE segment IS NULL
    ) AS null_segment_rows,

    COUNT(*) FILTER (
        WHERE country IS NULL
    ) AS null_country_rows,

    COUNT(*) FILTER (
        WHERE region IS NULL
    ) AS null_region_rows,

    COUNT(*) FILTER (
        WHERE customer_id = ''
    ) AS blank_customer_id_rows,

    COUNT(*) FILTER (
        WHERE customer_name = ''
    ) AS blank_customer_name_rows,

    COUNT(DISTINCT customer_id) AS distinct_customer_ids,

    COUNT(DISTINCT country) AS distinct_countries,

    COUNT(DISTINCT region) AS distinct_regions,

    COUNT(DISTINCT segment) AS distinct_segments

FROM dim_customer;


-- ============================================================
-- END OF CUSTOMER ANALYTICS LAYER
-- ============================================================