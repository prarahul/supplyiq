-- ============================================================
-- SupplyIQ 2.0
-- Supplier Performance Analytics Layer
-- ============================================================

SET search_path TO supplyiq;

-- ============================================================
-- CLEAN EXISTING VIEWS
-- ============================================================

DROP VIEW IF EXISTS vw_supplier_data_quality CASCADE;
DROP VIEW IF EXISTS vw_supplier_risk CASCADE;
DROP VIEW IF EXISTS vw_supplier_concentration CASCADE;
DROP VIEW IF EXISTS vw_supplier_cost_performance CASCADE;
DROP VIEW IF EXISTS vw_supplier_delivery_analysis CASCADE;
DROP VIEW IF EXISTS vw_supplier_spend_ranking CASCADE;
DROP VIEW IF EXISTS vw_supplier_scorecard CASCADE;


-- ============================================================
-- 1. SUPPLIER SCORECARD
-- ============================================================

CREATE VIEW vw_supplier_scorecard AS
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
        COUNT(*) FILTER (
            WHERE p.actual_delivery_date IS NOT NULL
              AND p.actual_delivery_date > p.expected_delivery_date
        ) * 100.0
        / NULLIF(
            COUNT(*) FILTER (
                WHERE p.actual_delivery_date IS NOT NULL
            ),
            0
        ),
        2
    ) AS late_delivery_pct,

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
-- 2. SUPPLIER SPEND RANKING
-- ============================================================

CREATE VIEW vw_supplier_spend_ranking AS
WITH supplier_spend AS (
    SELECT
        supplier_key,
        SUM(procurement_value) AS procurement_spend
    FROM fact_procurement
    GROUP BY supplier_key
)

SELECT
    s.supplier_key,
    s.supplier_id,
    s.supplier_name,

    ROUND(
        ss.procurement_spend,
        2
    ) AS procurement_spend,

    RANK() OVER (
        ORDER BY ss.procurement_spend DESC
    ) AS spend_rank,

    ROUND(
        ss.procurement_spend * 100.0
        / NULLIF(
            SUM(ss.procurement_spend) OVER (),
            0
        ),
        2
    ) AS spend_share_pct,

    ROUND(
        SUM(ss.procurement_spend) OVER (
            ORDER BY ss.procurement_spend DESC
            ROWS BETWEEN UNBOUNDED PRECEDING
                 AND CURRENT ROW
        ) * 100.0
        / NULLIF(
            SUM(ss.procurement_spend) OVER (),
            0
        ),
        2
    ) AS cumulative_spend_pct

FROM supplier_spend ss

JOIN dim_supplier s
    ON ss.supplier_key = s.supplier_key;


-- ============================================================
-- 3. SUPPLIER DELIVERY ANALYSIS
-- ============================================================

CREATE VIEW vw_supplier_delivery_analysis AS
SELECT
    s.supplier_key,
    s.supplier_id,
    s.supplier_name,

    COUNT(*) AS total_orders,

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
        AVG(
            CASE
                WHEN p.actual_delivery_date IS NOT NULL
                THEN p.actual_delivery_date
                     - p.expected_delivery_date
            END
        ),
        2
    ) AS average_delivery_variance_days,

    ROUND(
        MIN(
            CASE
                WHEN p.actual_delivery_date IS NOT NULL
                THEN p.actual_delivery_date
                     - p.expected_delivery_date
            END
        ),
        2
    ) AS best_delivery_variance_days,

    ROUND(
        MAX(
            CASE
                WHEN p.actual_delivery_date IS NOT NULL
                THEN p.actual_delivery_date
                     - p.expected_delivery_date
            END
        ),
        2
    ) AS worst_delivery_variance_days,

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
    ) AS on_time_delivery_pct

FROM fact_procurement p

JOIN dim_supplier s
    ON p.supplier_key = s.supplier_key

GROUP BY
    s.supplier_key,
    s.supplier_id,
    s.supplier_name;


-- ============================================================
-- 4. SUPPLIER COST PERFORMANCE
-- ============================================================

CREATE VIEW vw_supplier_cost_performance AS
SELECT
    s.supplier_key,
    s.supplier_id,
    s.supplier_name,

    COUNT(*) AS procurement_transactions,

    SUM(p.po_quantity) AS total_units_procured,

    ROUND(
        SUM(p.procurement_value),
        2
    ) AS total_procurement_spend,

    ROUND(
        AVG(p.unit_cost),
        2
    ) AS average_unit_cost,

    ROUND(
        MIN(p.unit_cost),
        2
    ) AS minimum_unit_cost,

    ROUND(
        MAX(p.unit_cost),
        2
    ) AS maximum_unit_cost,

    ROUND(
        MAX(p.unit_cost) - MIN(p.unit_cost),
        2
    ) AS unit_cost_range,

    ROUND(
        STDDEV_POP(p.unit_cost),
        2
    ) AS unit_cost_stddev

FROM fact_procurement p

JOIN dim_supplier s
    ON p.supplier_key = s.supplier_key

GROUP BY
    s.supplier_key,
    s.supplier_id,
    s.supplier_name;


-- ============================================================
-- 5. SUPPLIER CONCENTRATION
-- ============================================================
CREATE VIEW vw_supplier_concentration AS
WITH supplier_spend AS (
    SELECT
        supplier_key,
        SUM(procurement_value) AS procurement_spend
    FROM fact_procurement
    GROUP BY supplier_key
),

ranked_suppliers AS (
    SELECT
        supplier_key,
        procurement_spend,

        RANK() OVER (
            ORDER BY procurement_spend DESC
        ) AS spend_rank

    FROM supplier_spend
),

total_spend AS (
    SELECT
        SUM(procurement_spend) AS total_spend
    FROM supplier_spend
),

concentration AS (
    SELECT
        COUNT(*) AS total_suppliers,

        SUM(
            CASE
                WHEN rs.spend_rank <= 5
                THEN rs.procurement_spend
                ELSE 0
            END
        ) AS top_5_supplier_spend,

        SUM(
            CASE
                WHEN rs.spend_rank <= 10
                THEN rs.procurement_spend
                ELSE 0
            END
        ) AS top_10_supplier_spend,

        ts.total_spend

    FROM ranked_suppliers rs

    CROSS JOIN total_spend ts

    GROUP BY
        ts.total_spend
)

SELECT
    total_suppliers,

    ROUND(
        top_5_supplier_spend,
        2
    ) AS top_5_supplier_spend,

    ROUND(
        top_10_supplier_spend,
        2
    ) AS top_10_supplier_spend,

    ROUND(
        top_5_supplier_spend * 100.0
        / NULLIF(total_spend, 0),
        2
    ) AS top_5_spend_share_pct,

    ROUND(
        top_10_supplier_spend * 100.0
        / NULLIF(total_spend, 0),
        2
    ) AS top_10_spend_share_pct,

    ROUND(
        total_spend,
        2
    ) AS total_procurement_spend

FROM concentration;
-- ============================================================
-- 6. SUPPLIER RISK CLASSIFICATION
-- ============================================================

CREATE VIEW vw_supplier_risk AS
WITH supplier_metrics AS (
    SELECT
        s.supplier_key,
        s.supplier_id,
        s.supplier_name,

        COUNT(*) AS purchase_orders,

        SUM(p.procurement_value) AS procurement_spend,

        COUNT(*) FILTER (
            WHERE p.actual_delivery_date IS NOT NULL
        ) AS completed_orders,

        COUNT(*) FILTER (
            WHERE p.actual_delivery_date IS NULL
        ) AS pending_orders,

        COUNT(*) FILTER (
            WHERE p.actual_delivery_date IS NOT NULL
              AND p.actual_delivery_date > p.expected_delivery_date
        ) AS late_orders,

        AVG(
            CASE
                WHEN p.actual_delivery_date IS NOT NULL
                THEN p.actual_delivery_date
                     - p.expected_delivery_date
            END
        ) AS average_delivery_variance_days

    FROM fact_procurement p

    JOIN dim_supplier s
        ON p.supplier_key = s.supplier_key

    GROUP BY
        s.supplier_key,
        s.supplier_id,
        s.supplier_name
)

SELECT
    supplier_key,
    supplier_id,
    supplier_name,

    purchase_orders,

    ROUND(
        procurement_spend,
        2
    ) AS procurement_spend,

    completed_orders,

    pending_orders,

    late_orders,

    ROUND(
        late_orders * 100.0
        / NULLIF(completed_orders, 0),
        2
    ) AS late_delivery_pct,

    ROUND(
        average_delivery_variance_days,
        2
    ) AS average_delivery_variance_days,

    CASE
        WHEN completed_orders = 0
            THEN 'High'

        WHEN late_orders * 100.0
             / NULLIF(completed_orders, 0) >= 75
            THEN 'Critical'

        WHEN late_orders * 100.0
             / NULLIF(completed_orders, 0) >= 50
            THEN 'High'

        WHEN late_orders * 100.0
             / NULLIF(completed_orders, 0) >= 30
            THEN 'Medium'

        ELSE 'Low'
    END AS supplier_risk

FROM supplier_metrics;


-- ============================================================
-- 7. SUPPLIER DATA QUALITY
-- ============================================================

CREATE VIEW vw_supplier_data_quality AS
SELECT
    COUNT(*) AS total_supplier_rows,

    COUNT(*) FILTER (
        WHERE supplier_id IS NULL
    ) AS null_supplier_id_rows,

    COUNT(*) FILTER (
        WHERE supplier_name IS NULL
    ) AS null_supplier_name_rows,

    COUNT(*) FILTER (
        WHERE supplier_id = ''
    ) AS blank_supplier_id_rows,

    COUNT(*) FILTER (
        WHERE supplier_name = ''
    ) AS blank_supplier_name_rows,

    COUNT(*) FILTER (
        WHERE supplier_id IS NOT NULL
          AND supplier_name IS NOT NULL
    ) AS valid_supplier_rows

FROM dim_supplier;


-- ============================================================
-- END OF SUPPLIER PERFORMANCE ANALYTICS LAYER
-- ============================================================