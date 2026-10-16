-- ============================================================
-- SupplyIQ 2.0
-- Procurement Analytics Layer
-- ============================================================

SET search_path TO supplyiq;

-- ============================================================
-- CLEAN EXISTING VIEWS
-- ============================================================

DROP VIEW IF EXISTS vw_procurement_data_quality CASCADE;
DROP VIEW IF EXISTS vw_pending_procurement CASCADE;
DROP VIEW IF EXISTS vw_procurement_cost_analysis CASCADE;
DROP VIEW IF EXISTS vw_warehouse_procurement CASCADE;
DROP VIEW IF EXISTS vw_product_procurement CASCADE;
DROP VIEW IF EXISTS vw_supplier_procurement CASCADE;
DROP VIEW IF EXISTS vw_monthly_procurement CASCADE;
DROP VIEW IF EXISTS vw_procurement_delivery_performance CASCADE;


-- ============================================================
-- 1. PROCUREMENT DELIVERY PERFORMANCE
-- ============================================================

CREATE VIEW vw_procurement_delivery_performance AS
SELECT
    COUNT(*) AS total_purchase_orders,

    COUNT(*) FILTER (
        WHERE actual_delivery_date IS NOT NULL
    ) AS completed_purchase_orders,

    COUNT(*) FILTER (
        WHERE actual_delivery_date IS NULL
    ) AS pending_purchase_orders,

    COUNT(*) FILTER (
        WHERE actual_delivery_date IS NOT NULL
          AND actual_delivery_date <= expected_delivery_date
    ) AS on_time_purchase_orders,

    COUNT(*) FILTER (
        WHERE actual_delivery_date IS NOT NULL
          AND actual_delivery_date > expected_delivery_date
    ) AS late_purchase_orders,

    ROUND(
        COUNT(*) FILTER (
            WHERE actual_delivery_date IS NOT NULL
              AND actual_delivery_date <= expected_delivery_date
        ) * 100.0
        / NULLIF(
            COUNT(*) FILTER (
                WHERE actual_delivery_date IS NOT NULL
            ),
            0
        ),
        2
    ) AS on_time_delivery_pct,

    ROUND(
        AVG(
            CASE
                WHEN actual_delivery_date IS NOT NULL
                THEN actual_delivery_date - expected_delivery_date
            END
        ),
        2
    ) AS average_delivery_variance_days,

    SUM(po_quantity) AS total_procurement_units,

    ROUND(
        SUM(procurement_value),
        2
    ) AS total_procurement_spend

FROM fact_procurement;


-- ============================================================
-- 2. MONTHLY PROCUREMENT
-- ============================================================

CREATE VIEW vw_monthly_procurement AS
WITH monthly_procurement AS (
    SELECT
        date_key,

        COUNT(*) AS purchase_orders,
        SUM(po_quantity) AS procurement_units,
        SUM(procurement_value) AS procurement_spend,

        COUNT(*) FILTER (
            WHERE actual_delivery_date IS NOT NULL
              AND actual_delivery_date <= expected_delivery_date
        ) AS on_time_orders,

        COUNT(*) FILTER (
            WHERE actual_delivery_date IS NOT NULL
              AND actual_delivery_date > expected_delivery_date
        ) AS late_orders,

        COUNT(*) FILTER (
            WHERE actual_delivery_date IS NULL
        ) AS pending_orders,

        AVG(
            CASE
                WHEN actual_delivery_date IS NOT NULL
                THEN actual_delivery_date - expected_delivery_date
            END
        ) AS average_delivery_variance_days

    FROM fact_procurement

    GROUP BY date_key
)

SELECT
    d.year,
    d.month,
    d.month_name,
    d.quarter,

    COALESCE(
        SUM(mp.purchase_orders),
        0
    ) AS purchase_orders,

    COALESCE(
        SUM(mp.procurement_units),
        0
    ) AS procurement_units,

    ROUND(
        COALESCE(SUM(mp.procurement_spend), 0),
        2
    ) AS procurement_spend,

    COALESCE(
        SUM(mp.on_time_orders),
        0
    ) AS on_time_orders,

    COALESCE(
        SUM(mp.late_orders),
        0
    ) AS late_orders,

    COALESCE(
        SUM(mp.pending_orders),
        0
    ) AS pending_orders,

    ROUND(
        COALESCE(
            SUM(mp.on_time_orders) * 100.0
            / NULLIF(
                SUM(mp.on_time_orders)
                + SUM(mp.late_orders),
                0
            ),
            0
        ),
        2
    ) AS on_time_delivery_pct,

    ROUND(
        COALESCE(
            SUM(mp.average_delivery_variance_days
                * mp.purchase_orders)
            / NULLIF(SUM(mp.purchase_orders), 0),
            0
        ),
        2
    ) AS average_delivery_variance_days

FROM dim_date d

LEFT JOIN monthly_procurement mp
    ON d.date_key = mp.date_key

GROUP BY
    d.year,
    d.month,
    d.month_name,
    d.quarter;


-- ============================================================
-- 3. SUPPLIER PROCUREMENT PERFORMANCE
-- ============================================================

CREATE VIEW vw_supplier_procurement AS
SELECT
    s.supplier_key,
    s.supplier_id,
    s.supplier_name,

    COUNT(*) AS purchase_orders,

    SUM(p.po_quantity) AS procurement_units,

    ROUND(
        SUM(p.procurement_value),
        2
    ) AS procurement_spend,

    ROUND(
        AVG(p.unit_cost),
        2
    ) AS average_unit_cost,

    COUNT(*) FILTER (
        WHERE p.actual_delivery_date IS NOT NULL
    ) AS completed_orders,

    COUNT(*) FILTER (
        WHERE p.actual_delivery_date IS NULL
    ) AS pending_orders,

    COUNT(*) FILTER (
        WHERE p.actual_delivery_date IS NOT NULL
          AND p.actual_delivery_date <= p.expected_delivery_date
    ) AS on_time_orders,

    COUNT(*) FILTER (
        WHERE p.actual_delivery_date IS NOT NULL
          AND p.actual_delivery_date > p.expected_delivery_date
    ) AS late_orders,

    ROUND(
        COUNT(*) FILTER (
            WHERE p.actual_delivery_date IS NOT NULL
              AND p.actual_delivery_date <= p.expected_delivery_date
        ) * 100.0
        / NULLIF(
            COUNT(*) FILTER (
                WHERE p.actual_delivery_date IS NOT NULL
            ),
            0
        ),
        2
    ) AS on_time_delivery_pct,

    ROUND(
        AVG(
            CASE
                WHEN p.actual_delivery_date IS NOT NULL
                THEN p.actual_delivery_date
                     - p.expected_delivery_date
            END
        ),
        2
    ) AS average_delivery_variance_days

FROM fact_procurement p

JOIN dim_supplier s
    ON p.supplier_key = s.supplier_key

GROUP BY
    s.supplier_key,
    s.supplier_id,
    s.supplier_name;


-- ============================================================
-- 4. PRODUCT PROCUREMENT PERFORMANCE
-- ============================================================

CREATE VIEW vw_product_procurement AS
SELECT
    p.product_key,
    p.product_id,
    p.product_name,
    p.category,
    p.sub_category,
    p.brand,

    COUNT(*) AS purchase_orders,

    SUM(pr.po_quantity) AS procurement_units,

    ROUND(
        SUM(pr.procurement_value),
        2
    ) AS procurement_spend,

    ROUND(
        AVG(pr.unit_cost),
        2
    ) AS average_purchase_cost,

    ROUND(
        MIN(pr.unit_cost),
        2
    ) AS minimum_purchase_cost,

    ROUND(
        MAX(pr.unit_cost),
        2
    ) AS maximum_purchase_cost,

    COUNT(*) FILTER (
        WHERE pr.actual_delivery_date IS NULL
    ) AS pending_orders,

    COUNT(*) FILTER (
        WHERE pr.actual_delivery_date IS NOT NULL
          AND pr.actual_delivery_date
              <= pr.expected_delivery_date
    ) AS on_time_orders,

    COUNT(*) FILTER (
        WHERE pr.actual_delivery_date IS NOT NULL
          AND pr.actual_delivery_date
              > pr.expected_delivery_date
    ) AS late_orders,

    ROUND(
        COUNT(*) FILTER (
            WHERE pr.actual_delivery_date IS NOT NULL
              AND pr.actual_delivery_date
                  <= pr.expected_delivery_date
        ) * 100.0
        / NULLIF(
            COUNT(*) FILTER (
                WHERE pr.actual_delivery_date IS NOT NULL
            ),
            0
        ),
        2
    ) AS on_time_delivery_pct

FROM fact_procurement pr

JOIN dim_product p
    ON pr.product_key = p.product_key

GROUP BY
    p.product_key,
    p.product_id,
    p.product_name,
    p.category,
    p.sub_category,
    p.brand;


-- ============================================================
-- 5. WAREHOUSE PROCUREMENT PERFORMANCE
-- ============================================================

CREATE VIEW vw_warehouse_procurement AS
SELECT
    w.warehouse_key,
    w.warehouse_id,
    w.warehouse_name,
    w.city,
    w.country,
    w.region,
    w.warehouse_type,

    COUNT(*) AS purchase_orders,

    SUM(p.po_quantity) AS procurement_units,

    ROUND(
        SUM(p.procurement_value),
        2
    ) AS procurement_spend,

    ROUND(
        AVG(p.unit_cost),
        2
    ) AS average_unit_cost,

    COUNT(*) FILTER (
        WHERE p.actual_delivery_date IS NULL
    ) AS pending_orders,

    COUNT(*) FILTER (
        WHERE p.actual_delivery_date IS NOT NULL
          AND p.actual_delivery_date
              <= p.expected_delivery_date
    ) AS on_time_orders,

    COUNT(*) FILTER (
        WHERE p.actual_delivery_date IS NOT NULL
          AND p.actual_delivery_date
              > p.expected_delivery_date
    ) AS late_orders,

    ROUND(
        COUNT(*) FILTER (
            WHERE p.actual_delivery_date IS NOT NULL
              AND p.actual_delivery_date
                  <= p.expected_delivery_date
        ) * 100.0
        / NULLIF(
            COUNT(*) FILTER (
                WHERE p.actual_delivery_date IS NOT NULL
            ),
            0
        ),
        2
    ) AS on_time_delivery_pct

FROM fact_procurement p

JOIN dim_warehouse w
    ON p.warehouse_key = w.warehouse_key

GROUP BY
    w.warehouse_key,
    w.warehouse_id,
    w.warehouse_name,
    w.city,
    w.country,
    w.region,
    w.warehouse_type;


-- ============================================================
-- 6. PROCUREMENT COST ANALYSIS
-- ============================================================

CREATE VIEW vw_procurement_cost_analysis AS
SELECT
    p.product_key,
    p.product_id,
    p.product_name,
    p.category,
    p.sub_category,

    ROUND(
        AVG(pr.unit_cost),
        2
    ) AS average_procurement_cost,

    ROUND(
        MIN(pr.unit_cost),
        2
    ) AS minimum_procurement_cost,

    ROUND(
        MAX(pr.unit_cost),
        2
    ) AS maximum_procurement_cost,

    ROUND(
        MAX(pr.unit_cost)
        - MIN(pr.unit_cost),
        2
    ) AS procurement_cost_range,

    ROUND(
        STDDEV_POP(pr.unit_cost),
        2
    ) AS procurement_cost_stddev,

    COUNT(*) AS procurement_transactions,

    SUM(pr.po_quantity) AS total_units_procured,

    ROUND(
        SUM(pr.procurement_value),
        2
    ) AS total_procurement_spend

FROM fact_procurement pr

JOIN dim_product p
    ON pr.product_key = p.product_key

GROUP BY
    p.product_key,
    p.product_id,
    p.product_name,
    p.category,
    p.sub_category;


-- ============================================================
-- 7. PENDING PROCUREMENT
-- ============================================================

CREATE VIEW vw_pending_procurement AS
SELECT
    pr.procurement_key,

    d.full_date AS procurement_date,

    pr.expected_delivery_date,

    CURRENT_DATE - pr.expected_delivery_date
        AS days_past_expected,

    p.product_id,
    p.product_name,
    p.category,
    p.sub_category,

    s.supplier_id,
    s.supplier_name,

    w.warehouse_id,
    w.warehouse_name,
    w.region,

    pr.po_quantity,

    ROUND(
        pr.unit_cost,
        2
    ) AS unit_cost,

    ROUND(
        pr.procurement_value,
        2
    ) AS procurement_value,

    CASE
        WHEN CURRENT_DATE > pr.expected_delivery_date
            THEN 'Overdue'
        ELSE 'Pending'
    END AS procurement_status

FROM fact_procurement pr

JOIN dim_date d
    ON pr.date_key = d.date_key

JOIN dim_product p
    ON pr.product_key = p.product_key

JOIN dim_supplier s
    ON pr.supplier_key = s.supplier_key

JOIN dim_warehouse w
    ON pr.warehouse_key = w.warehouse_key

WHERE
    pr.actual_delivery_date IS NULL;


-- ============================================================
-- 8. PROCUREMENT DATA QUALITY
-- ============================================================

CREATE VIEW vw_procurement_data_quality AS
SELECT
    COUNT(*) AS total_procurement_rows,

    COUNT(*) FILTER (
        WHERE po_quantity <= 0
    ) AS invalid_quantity_rows,

    COUNT(*) FILTER (
        WHERE unit_cost < 0
    ) AS invalid_unit_cost_rows,

    COUNT(*) FILTER (
        WHERE procurement_value < 0
    ) AS invalid_procurement_value_rows,

    COUNT(*) FILTER (
        WHERE expected_delivery_date IS NULL
    ) AS null_expected_delivery_rows,

    COUNT(*) FILTER (
        WHERE actual_delivery_date IS NOT NULL
          AND actual_delivery_date < expected_delivery_date
    ) AS early_delivery_rows,

    COUNT(*) FILTER (
        WHERE procurement_value
              <> ROUND(po_quantity * unit_cost, 2)
    ) AS procurement_value_formula_errors,

    COUNT(*) FILTER (
        WHERE actual_delivery_date IS NOT NULL
          AND actual_delivery_date < (
              SELECT MIN(full_date)
              FROM dim_date
          )
    ) AS invalid_actual_delivery_dates,

    COUNT(DISTINCT product_key) AS distinct_products,

    COUNT(DISTINCT supplier_key) AS distinct_suppliers,

    COUNT(DISTINCT warehouse_key) AS distinct_warehouses,

    COUNT(DISTINCT date_key) AS distinct_dates

FROM fact_procurement;


-- ============================================================
-- END OF PROCUREMENT ANALYTICS LAYER
-- ============================================================