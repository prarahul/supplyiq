-- ============================================================
-- SupplyIQ 2.0
-- Sales & Demand Analytical Layer
-- ============================================================

SET search_path TO supplyiq;


-- ============================================================
-- 1. DAILY SALES PERFORMANCE
-- ============================================================

DROP VIEW IF EXISTS vw_daily_sales CASCADE;

CREATE VIEW vw_daily_sales AS
SELECT
    d.date_key,
    d.full_date,
    d.year,
    d.month,
    d.month_name,
    d.day_name,
    d.week,
    d.quarter,
    d.is_weekend,

    COUNT(s.sales_key) AS total_orders,

    COALESCE(SUM(s.quantity), 0) AS units_sold,

    ROUND(
        COALESCE(SUM(s.revenue), 0),
        2
    ) AS revenue,

    ROUND(
        COALESCE(SUM(s.cost), 0),
        2
    ) AS cost,

    ROUND(
        COALESCE(SUM(s.profit), 0),
        2
    ) AS profit,

    ROUND(
        COALESCE(
            SUM(s.profit)
            / NULLIF(SUM(s.revenue), 0) * 100,
            0
        ),
        2
    ) AS profit_margin_pct,

    ROUND(
        COALESCE(AVG(s.revenue), 0),
        2
    ) AS average_order_value,

    ROUND(
        COALESCE(AVG(s.discount), 0),
        2
    ) AS average_discount

FROM dim_date d

LEFT JOIN fact_sales s
    ON d.date_key = s.date_key

GROUP BY
    d.date_key,
    d.full_date,
    d.year,
    d.month,
    d.month_name,
    d.day_name,
    d.week,
    d.quarter,
    d.is_weekend;


-- ============================================================
-- 2. MONTHLY SALES PERFORMANCE
-- ============================================================

DROP VIEW IF EXISTS vw_monthly_sales CASCADE;

CREATE VIEW vw_monthly_sales AS
WITH monthly_sales AS (
    SELECT
        date_key,
        COUNT(*) AS total_orders,
        SUM(quantity) AS units_sold,
        SUM(revenue) AS revenue,
        SUM(cost) AS cost,
        SUM(profit) AS profit,
        AVG(discount) AS average_discount
    FROM fact_sales
    GROUP BY date_key
)

SELECT
    d.year,
    d.month,
    d.month_name,

    COALESCE(SUM(ms.total_orders), 0)
        AS total_orders,

    COALESCE(SUM(ms.units_sold), 0)
        AS units_sold,

    ROUND(
        COALESCE(SUM(ms.revenue), 0),
        2
    ) AS revenue,

    ROUND(
        COALESCE(SUM(ms.cost), 0),
        2
    ) AS cost,

    ROUND(
        COALESCE(SUM(ms.profit), 0),
        2
    ) AS profit,

    ROUND(
        COALESCE(
            SUM(ms.profit)
            / NULLIF(SUM(ms.revenue), 0) * 100,
            0
        ),
        2
    ) AS profit_margin_pct,

    ROUND(
        COALESCE(
            SUM(ms.revenue)
            / NULLIF(SUM(ms.total_orders), 0),
            0
        ),
        2
    ) AS average_order_value,

    ROUND(
        COALESCE(
            SUM(ms.average_discount * ms.total_orders)
            / NULLIF(SUM(ms.total_orders), 0),
            0
        ),
        2
    ) AS average_discount

FROM dim_date d

LEFT JOIN monthly_sales ms
    ON d.date_key = ms.date_key

GROUP BY
    d.year,
    d.month,
    d.month_name;


-- ============================================================
-- 3. PRODUCT SALES PERFORMANCE
-- ============================================================

DROP VIEW IF EXISTS vw_product_sales_performance CASCADE;

CREATE VIEW vw_product_sales_performance AS
SELECT
    p.product_key,
    p.product_id,
    p.product_name,
    p.category,
    p.sub_category,
    p.brand,

    COUNT(s.sales_key) AS total_orders,

    COALESCE(SUM(s.quantity), 0)
        AS units_sold,

    ROUND(
        COALESCE(SUM(s.revenue), 0),
        2
    ) AS revenue,

    ROUND(
        COALESCE(SUM(s.cost), 0),
        2
    ) AS cost,

    ROUND(
        COALESCE(SUM(s.profit), 0),
        2
    ) AS profit,

    ROUND(
        COALESCE(
            SUM(s.profit)
            / NULLIF(SUM(s.revenue), 0) * 100,
            0
        ),
        2
    ) AS profit_margin_pct,

    ROUND(
        COALESCE(AVG(s.unit_price), 0),
        2
    ) AS average_selling_price,

    ROUND(
        COALESCE(AVG(s.discount), 0),
        2
    ) AS average_discount,

    COUNT(*) FILTER (
        WHERE s.profit < 0
    ) AS loss_making_orders

FROM dim_product p

LEFT JOIN fact_sales s
    ON p.product_key = s.product_key

GROUP BY
    p.product_key,
    p.product_id,
    p.product_name,
    p.category,
    p.sub_category,
    p.brand;


-- ============================================================
-- 4. CATEGORY PERFORMANCE
-- ============================================================

DROP VIEW IF EXISTS vw_category_sales CASCADE;

CREATE VIEW vw_category_sales AS
SELECT
    p.category,

    COUNT(s.sales_key) AS total_orders,

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
        SUM(s.profit)
        / NULLIF(SUM(s.revenue), 0) * 100,
        2
    ) AS profit_margin_pct,

    ROUND(
        SUM(s.discount),
        2
    ) AS total_discount,

    ROUND(
        AVG(s.discount),
        2
    ) AS average_discount

FROM dim_product p

JOIN fact_sales s
    ON p.product_key = s.product_key

GROUP BY
    p.category;


-- ============================================================
-- 5. CUSTOMER SALES PERFORMANCE
-- ============================================================

DROP VIEW IF EXISTS vw_customer_sales CASCADE;

CREATE VIEW vw_customer_sales AS
SELECT
    c.customer_key,
    c.customer_id,
    c.customer_name,
    c.segment,
    c.country,
    c.region,

    COUNT(s.sales_key) AS total_orders,

    SUM(s.quantity) AS units_purchased,

    ROUND(
        SUM(s.revenue),
        2
    ) AS revenue,

    ROUND(
        SUM(s.profit),
        2
    ) AS profit,

    ROUND(
        SUM(s.profit)
        / NULLIF(SUM(s.revenue), 0) * 100,
        2
    ) AS profit_margin_pct,

    ROUND(
        AVG(s.revenue),
        2
    ) AS average_order_value

FROM dim_customer c

JOIN fact_sales s
    ON c.customer_key = s.customer_key

GROUP BY
    c.customer_key,
    c.customer_id,
    c.customer_name,
    c.segment,
    c.country,
    c.region;


-- ============================================================
-- 6. CUSTOMER SEGMENT PERFORMANCE
-- ============================================================

DROP VIEW IF EXISTS vw_customer_segment_sales CASCADE;

CREATE VIEW vw_customer_segment_sales AS
SELECT
    c.segment,

    COUNT(s.sales_key) AS total_orders,

    SUM(s.quantity) AS units_purchased,

    ROUND(
        SUM(s.revenue),
        2
    ) AS revenue,

    ROUND(
        SUM(s.profit),
        2
    ) AS profit,

    ROUND(
        SUM(s.profit)
        / NULLIF(SUM(s.revenue), 0) * 100,
        2
    ) AS profit_margin_pct,

    ROUND(
        AVG(s.revenue),
        2
    ) AS average_order_value

FROM dim_customer c

JOIN fact_sales s
    ON c.customer_key = s.customer_key

GROUP BY
    c.segment;


-- ============================================================
-- 7. WAREHOUSE SALES PERFORMANCE
-- ============================================================

DROP VIEW IF EXISTS vw_warehouse_sales CASCADE;

CREATE VIEW vw_warehouse_sales AS
SELECT
    w.warehouse_key,
    w.warehouse_id,
    w.warehouse_name,
    w.city,
    w.country,
    w.region,
    w.warehouse_type,

    COUNT(s.sales_key) AS total_orders,

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
        SUM(s.profit)
        / NULLIF(SUM(s.revenue), 0) * 100,
        2
    ) AS profit_margin_pct

FROM dim_warehouse w

JOIN fact_sales s
    ON w.warehouse_key = s.warehouse_key

GROUP BY
    w.warehouse_key,
    w.warehouse_id,
    w.warehouse_name,
    w.city,
    w.country,
    w.region,
    w.warehouse_type;


-- ============================================================
-- 8. LOSS-MAKING PRODUCTS
-- ============================================================

DROP VIEW IF EXISTS vw_loss_making_products CASCADE;

CREATE VIEW vw_loss_making_products AS
SELECT
    product_key,
    product_id,
    product_name,
    category,
    sub_category,
    brand,
    total_orders,
    units_sold,
    revenue,
    profit,
    profit_margin_pct,
    loss_making_orders

FROM vw_product_sales_performance

WHERE profit < 0

ORDER BY
    profit ASC;


-- ============================================================
-- 9. DISCOUNT IMPACT ANALYSIS
-- ============================================================

DROP VIEW IF EXISTS vw_discount_impact CASCADE;

CREATE VIEW vw_discount_impact AS
SELECT
    CASE
        WHEN discount = 0 THEN '0%'
        WHEN discount < quantity * unit_price * 0.05 THEN '1-4%'
        WHEN discount < quantity * unit_price * 0.10 THEN '5-9%'
        WHEN discount < quantity * unit_price * 0.20 THEN '10-19%'
        ELSE '20%+'
    END AS discount_band,

    COUNT(*) AS total_orders,

    SUM(quantity) AS units_sold,

    ROUND(
        SUM(revenue),
        2
    ) AS revenue,

    ROUND(
        SUM(profit),
        2
    ) AS profit,

    ROUND(
        SUM(profit)
        / NULLIF(SUM(revenue), 0) * 100,
        2
    ) AS profit_margin_pct,

    ROUND(
        AVG(discount),
        2
    ) AS average_discount

FROM fact_sales

GROUP BY
    CASE
        WHEN discount = 0 THEN '0%'
        WHEN discount < quantity * unit_price * 0.05 THEN '1-4%'
        WHEN discount < quantity * unit_price * 0.10 THEN '5-9%'
        WHEN discount < quantity * unit_price * 0.20 THEN '10-19%'
        ELSE '20%+'
    END;


-- ============================================================
-- 10. PRODUCT REVENUE RANKING
-- ============================================================

DROP VIEW IF EXISTS vw_product_revenue_ranking CASCADE;

CREATE VIEW vw_product_revenue_ranking AS
SELECT
    product_key,
    product_id,
    product_name,
    category,
    revenue,
    profit,
    profit_margin_pct,

    RANK() OVER (
        ORDER BY revenue DESC
    ) AS revenue_rank,

    RANK() OVER (
        ORDER BY profit DESC
    ) AS profit_rank,

    ROUND(
        revenue
        / NULLIF(
            SUM(revenue) OVER (),
            0
        ) * 100,
        2
    ) AS revenue_contribution_pct

FROM vw_product_sales_performance;


-- ============================================================
-- 11. CATEGORY REVENUE RANKING
-- ============================================================

DROP VIEW IF EXISTS vw_category_revenue_ranking CASCADE;

CREATE VIEW vw_category_revenue_ranking AS
SELECT
    category,
    revenue,
    profit,
    profit_margin_pct,

    RANK() OVER (
        ORDER BY revenue DESC
    ) AS revenue_rank,

    ROUND(
        revenue
        / NULLIF(
            SUM(revenue) OVER (),
            0
        ) * 100,
        2
    ) AS revenue_contribution_pct

FROM vw_category_sales;


-- ============================================================
-- 12. SALES DATA QUALITY CHECK
-- ============================================================

DROP VIEW IF EXISTS vw_sales_data_quality CASCADE;

CREATE VIEW vw_sales_data_quality AS
SELECT
    COUNT(*) AS total_sales_rows,

    COUNT(*) FILTER (
        WHERE quantity <= 0
    ) AS invalid_quantity_rows,

    COUNT(*) FILTER (
        WHERE unit_price <= 0
    ) AS invalid_price_rows,

    COUNT(*) FILTER (
        WHERE revenue <= 0
    ) AS invalid_revenue_rows,

    COUNT(*) FILTER (
        WHERE cost < 0
    ) AS invalid_cost_rows,

    COUNT(*) FILTER (
        WHERE discount < 0
    ) AS invalid_discount_rows,

    COUNT(*) FILTER (
        WHERE revenue <> ROUND(
            quantity * unit_price - discount,
            2
        )
    ) AS revenue_formula_errors,

    COUNT(*) FILTER (
        WHERE profit <> ROUND(
            revenue - cost,
            2
        )
    ) AS profit_formula_errors

FROM fact_sales;