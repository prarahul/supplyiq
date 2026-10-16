-- ============================================================
-- SupplyIQ 2.0
-- Inventory Analytics Layer
-- ============================================================

SET search_path TO supplyiq;

-- ============================================================
-- CLEAN EXISTING VIEWS
-- ============================================================

DROP VIEW IF EXISTS vw_inventory_data_quality CASCADE;
DROP VIEW IF EXISTS vw_stockout_analysis CASCADE;
DROP VIEW IF EXISTS vw_inventory_turnover CASCADE;
DROP VIEW IF EXISTS vw_warehouse_inventory CASCADE;
DROP VIEW IF EXISTS vw_product_inventory CASCADE;
DROP VIEW IF EXISTS vw_monthly_inventory CASCADE;
DROP VIEW IF EXISTS vw_daily_inventory CASCADE;


-- ============================================================
-- 1. DAILY INVENTORY
-- ============================================================

CREATE VIEW vw_daily_inventory AS
SELECT
    d.full_date,
    d.year,
    d.month,
    d.month_name,
    d.quarter,

    COUNT(*) AS inventory_records,

    SUM(i.opening_stock) AS opening_stock,
    SUM(i.received_quantity) AS received_quantity,
    SUM(i.sold_quantity) AS sold_quantity,
    SUM(i.closing_stock) AS closing_stock,

    ROUND(
        SUM(i.inventory_value),
        2
    ) AS inventory_value,

    COUNT(*) FILTER (
        WHERE i.closing_stock = 0
    ) AS stockout_records,

    ROUND(
        COUNT(*) FILTER (
            WHERE i.closing_stock = 0
        ) * 100.0 / NULLIF(COUNT(*), 0),
        2
    ) AS stockout_rate_pct

FROM fact_inventory i
JOIN dim_date d
    ON i.date_key = d.date_key

GROUP BY
    d.full_date,
    d.year,
    d.month,
    d.month_name,
    d.quarter;


-- ============================================================
-- 2. MONTHLY INVENTORY
-- ============================================================

CREATE VIEW vw_monthly_inventory AS
WITH monthly_inventory AS (
    SELECT
        date_key,

        SUM(opening_stock) AS opening_stock,
        SUM(received_quantity) AS received_quantity,
        SUM(sold_quantity) AS sold_quantity,
        SUM(closing_stock) AS closing_stock,
        SUM(inventory_value) AS inventory_value,

        COUNT(*) AS inventory_records,

        COUNT(*) FILTER (
            WHERE closing_stock = 0
        ) AS stockout_records

    FROM fact_inventory

    GROUP BY date_key
)

SELECT
    d.year,
    d.month,
    d.month_name,
    d.quarter,

    SUM(mi.inventory_records) AS inventory_records,

    SUM(mi.opening_stock) AS opening_stock,
    SUM(mi.received_quantity) AS received_quantity,
    SUM(mi.sold_quantity) AS sold_quantity,
    SUM(mi.closing_stock) AS closing_stock,

    ROUND(
        SUM(mi.inventory_value),
        2
    ) AS inventory_value,

    SUM(mi.stockout_records) AS stockout_records,

    ROUND(
        SUM(mi.stockout_records) * 100.0
        / NULLIF(SUM(mi.inventory_records), 0),
        2
    ) AS stockout_rate_pct

FROM dim_date d
LEFT JOIN monthly_inventory mi
    ON d.date_key = mi.date_key

GROUP BY
    d.year,
    d.month,
    d.month_name,
    d.quarter;


-- ============================================================
-- 3. PRODUCT INVENTORY PERFORMANCE
-- ============================================================

CREATE VIEW vw_product_inventory AS
SELECT
    p.product_key,
    p.product_id,
    p.product_name,
    p.category,
    p.sub_category,
    p.brand,

    COUNT(*) AS inventory_records,

    SUM(i.opening_stock) AS opening_stock,
    SUM(i.received_quantity) AS received_quantity,
    SUM(i.sold_quantity) AS sold_quantity,
    SUM(i.closing_stock) AS closing_stock,

    ROUND(
        SUM(i.inventory_value),
        2
    ) AS inventory_value,

    ROUND(
        AVG(i.closing_stock),
        2
    ) AS average_closing_stock,

    COUNT(*) FILTER (
        WHERE i.closing_stock = 0
    ) AS stockout_days,

    ROUND(
        COUNT(*) FILTER (
            WHERE i.closing_stock = 0
        ) * 100.0 / NULLIF(COUNT(*), 0),
        2
    ) AS stockout_rate_pct

FROM fact_inventory i
JOIN dim_product p
    ON i.product_key = p.product_key

GROUP BY
    p.product_key,
    p.product_id,
    p.product_name,
    p.category,
    p.sub_category,
    p.brand;


-- ============================================================
-- 4. WAREHOUSE INVENTORY PERFORMANCE
-- ============================================================

CREATE VIEW vw_warehouse_inventory AS
SELECT
    w.warehouse_key,
    w.warehouse_id,
    w.warehouse_name,
    w.city,
    w.country,
    w.region,
    w.warehouse_type,
    w.capacity_units,

    COUNT(*) AS inventory_records,

    SUM(i.opening_stock) AS opening_stock,
    SUM(i.received_quantity) AS received_quantity,
    SUM(i.sold_quantity) AS sold_quantity,
    SUM(i.closing_stock) AS closing_stock,

    ROUND(
        SUM(i.inventory_value),
        2
    ) AS inventory_value,

    ROUND(
        AVG(i.closing_stock),
        2
    ) AS average_closing_stock,

    COUNT(*) FILTER (
        WHERE i.closing_stock = 0
    ) AS stockout_records,

    ROUND(
        COUNT(*) FILTER (
            WHERE i.closing_stock = 0
        ) * 100.0 / NULLIF(COUNT(*), 0),
        2
    ) AS stockout_rate_pct,

    ROUND(
        AVG(
            i.closing_stock * 100.0
            / NULLIF(w.capacity_units, 0)
        ),
        2
    ) AS average_capacity_utilization_pct

FROM fact_inventory i
JOIN dim_warehouse w
    ON i.warehouse_key = w.warehouse_key

GROUP BY
    w.warehouse_key,
    w.warehouse_id,
    w.warehouse_name,
    w.city,
    w.country,
    w.region,
    w.warehouse_type,
    w.capacity_units;


-- ============================================================
-- 5. INVENTORY TURNOVER
-- ============================================================
--
-- Inventory turnover =
-- Cost of goods sold / Average inventory value
--
-- Sales and inventory are aggregated independently first
-- to prevent fact-table multiplication.
-- ============================================================

CREATE VIEW vw_inventory_turnover AS
WITH sales AS (
    SELECT
        product_key,
        warehouse_key,

        SUM(cost) AS total_cogs,
        SUM(quantity) AS units_sold

    FROM fact_sales

    GROUP BY
        product_key,
        warehouse_key
),

inventory AS (
    SELECT
        product_key,
        warehouse_key,

        AVG(inventory_value) AS average_inventory_value,
        AVG(closing_stock) AS average_closing_stock

    FROM fact_inventory

    GROUP BY
        product_key,
        warehouse_key
)

SELECT
    p.product_key,
    p.product_id,
    p.product_name,
    p.category,
    p.sub_category,
    p.brand,

    w.warehouse_key,
    w.warehouse_id,
    w.warehouse_name,
    w.region,

    COALESCE(s.total_cogs, 0) AS total_cogs,
    COALESCE(s.units_sold, 0) AS units_sold,

    ROUND(
        COALESCE(i.average_inventory_value, 0),
        2
    ) AS average_inventory_value,

    ROUND(
        COALESCE(i.average_closing_stock, 0),
        2
    ) AS average_closing_stock,

    ROUND(
        COALESCE(s.total_cogs, 0)
        / NULLIF(i.average_inventory_value, 0),
        2
    ) AS inventory_turnover_ratio

FROM dim_product p

CROSS JOIN dim_warehouse w

LEFT JOIN sales s
    ON p.product_key = s.product_key
    AND w.warehouse_key = s.warehouse_key

LEFT JOIN inventory i
    ON p.product_key = i.product_key
    AND w.warehouse_key = i.warehouse_key

WHERE
    s.product_key IS NOT NULL
    OR i.product_key IS NOT NULL;


-- ============================================================
-- 6. STOCKOUT ANALYSIS
-- ============================================================

CREATE VIEW vw_stockout_analysis AS
SELECT
    p.product_key,
    p.product_id,
    p.product_name,
    p.category,
    p.sub_category,

    w.warehouse_key,
    w.warehouse_id,
    w.warehouse_name,
    w.region,

    COUNT(*) AS observed_days,

    COUNT(*) FILTER (
        WHERE i.closing_stock = 0
    ) AS stockout_days,

    ROUND(
        COUNT(*) FILTER (
            WHERE i.closing_stock = 0
        ) * 100.0 / NULLIF(COUNT(*), 0),
        2
    ) AS stockout_rate_pct,

    SUM(i.sold_quantity) AS total_units_sold,

    SUM(i.received_quantity) AS total_units_received,

    SUM(i.closing_stock) AS total_closing_stock,

    CASE
        WHEN COUNT(*) FILTER (
            WHERE i.closing_stock = 0
        ) >= 30
            THEN 'Critical'

        WHEN COUNT(*) FILTER (
            WHERE i.closing_stock = 0
        ) >= 15
            THEN 'High'

        WHEN COUNT(*) FILTER (
            WHERE i.closing_stock = 0
        ) >= 5
            THEN 'Medium'

        ELSE 'Low'
    END AS stockout_risk

FROM fact_inventory i

JOIN dim_product p
    ON i.product_key = p.product_key

JOIN dim_warehouse w
    ON i.warehouse_key = w.warehouse_key

GROUP BY
    p.product_key,
    p.product_id,
    p.product_name,
    p.category,
    p.sub_category,
    w.warehouse_key,
    w.warehouse_id,
    w.warehouse_name,
    w.region;


-- ============================================================
-- 7. INVENTORY DATA QUALITY
-- ============================================================

CREATE VIEW vw_inventory_data_quality AS
SELECT
    COUNT(*) AS total_inventory_rows,

    COUNT(*) FILTER (
        WHERE opening_stock < 0
    ) AS negative_opening_stock_rows,

    COUNT(*) FILTER (
        WHERE received_quantity < 0
    ) AS negative_received_quantity_rows,

    COUNT(*) FILTER (
        WHERE sold_quantity < 0
    ) AS negative_sold_quantity_rows,

    COUNT(*) FILTER (
        WHERE closing_stock < 0
    ) AS negative_closing_stock_rows,

    COUNT(*) FILTER (
        WHERE inventory_value < 0
    ) AS negative_inventory_value_rows,

    COUNT(*) FILTER (
        WHERE opening_stock
            + received_quantity
            - sold_quantity
            <> closing_stock
    ) AS stock_equation_errors,

    COUNT(*) FILTER (
        WHERE inventory_value IS NULL
    ) AS null_inventory_value_rows,

    COUNT(DISTINCT product_key) AS distinct_products,

    COUNT(DISTINCT warehouse_key) AS distinct_warehouses,

    COUNT(DISTINCT date_key) AS distinct_dates

FROM fact_inventory;


-- ============================================================
-- END OF INVENTORY ANALYTICS LAYER
-- ============================================================