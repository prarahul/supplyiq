-- ============================================================
-- SupplyIQ 2.0
-- Logistics / Shipment Analytics Layer
-- ============================================================

SET search_path TO supplyiq;

-- ============================================================
-- CLEAN EXISTING VIEWS
-- ============================================================

DROP VIEW IF EXISTS vw_logistics_data_quality CASCADE;
DROP VIEW IF EXISTS vw_pending_shipments CASCADE;
DROP VIEW IF EXISTS vw_shipping_cost_analysis CASCADE;
DROP VIEW IF EXISTS vw_customer_delivery_performance CASCADE;
DROP VIEW IF EXISTS vw_warehouse_logistics CASCADE;
DROP VIEW IF EXISTS vw_carrier_performance CASCADE;
DROP VIEW IF EXISTS vw_monthly_logistics CASCADE;
DROP VIEW IF EXISTS vw_delivery_delay_analysis CASCADE;
DROP VIEW IF EXISTS vw_shipment_performance CASCADE;


-- ============================================================
-- 1. OVERALL SHIPMENT PERFORMANCE
-- ============================================================

CREATE VIEW vw_shipment_performance AS
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
        ) * 100.0 / NULLIF(COUNT(*), 0),
        2
    ) AS delivered_pct,

    ROUND(
        COUNT(*) FILTER (
            WHERE delivery_status = 'Delayed'
        ) * 100.0 / NULLIF(COUNT(*), 0),
        2
    ) AS delayed_pct,

    ROUND(
        COUNT(*) FILTER (
            WHERE delivery_status = 'Pending'
        ) * 100.0 / NULLIF(COUNT(*), 0),
        2
    ) AS pending_pct,

    SUM(quantity) AS total_units_shipped,

    ROUND(
        SUM(shipping_cost),
        2
    ) AS total_shipping_cost,

    ROUND(
        AVG(shipping_cost),
        2
    ) AS average_shipping_cost,

    ROUND(
        AVG(delay_days),
        2
    ) AS average_delay_days,

    ROUND(
        AVG(
            CASE
                WHEN delivery_status <> 'Pending'
                THEN delay_days
            END
        ),
        2
    ) AS average_completed_delay_days,

    COUNT(*) FILTER (
        WHERE delivery_status = 'Delivered'
          AND delay_days <= 0
    ) AS on_time_deliveries,

    ROUND(
        COUNT(*) FILTER (
            WHERE delivery_status = 'Delivered'
              AND delay_days <= 0
        ) * 100.0
        / NULLIF(
            COUNT(*) FILTER (
                WHERE delivery_status = 'Delivered'
            ),
            0
        ),
        2
    ) AS on_time_delivery_pct

FROM fact_shipments;


-- ============================================================
-- 2. DELIVERY DELAY ANALYSIS
-- ============================================================

CREATE VIEW vw_delivery_delay_analysis AS
SELECT
    CASE
        WHEN delay_days <= 0 THEN 'On Time'
        WHEN delay_days BETWEEN 1 AND 2 THEN '1-2 Days Late'
        WHEN delay_days BETWEEN 3 AND 5 THEN '3-5 Days Late'
        WHEN delay_days BETWEEN 6 AND 10 THEN '6-10 Days Late'
        ELSE '10+ Days Late'
    END AS delay_bucket,

    COUNT(*) AS shipments,

    SUM(quantity) AS units_shipped,

    ROUND(
        SUM(shipping_cost),
        2
    ) AS shipping_cost,

    ROUND(
        AVG(delay_days),
        2
    ) AS average_delay_days,

    ROUND(
        COUNT(*) * 100.0
        / NULLIF(
            SUM(COUNT(*)) OVER (),
            0
        ),
        2
    ) AS shipment_pct

FROM fact_shipments

WHERE
    delivery_status <> 'Pending'

GROUP BY
    CASE
        WHEN delay_days <= 0 THEN 'On Time'
        WHEN delay_days BETWEEN 1 AND 2 THEN '1-2 Days Late'
        WHEN delay_days BETWEEN 3 AND 5 THEN '3-5 Days Late'
        WHEN delay_days BETWEEN 6 AND 10 THEN '6-10 Days Late'
        ELSE '10+ Days Late'
    END;


-- ============================================================
-- 3. MONTHLY LOGISTICS PERFORMANCE
-- ============================================================

CREATE VIEW vw_monthly_logistics AS
WITH monthly_shipments AS (
    SELECT
        date_key,

        COUNT(*) AS shipments,

        SUM(quantity) AS units_shipped,

        SUM(shipping_cost) AS shipping_cost,

        COUNT(*) FILTER (
            WHERE delivery_status = 'Delivered'
        ) AS delivered_shipments,

        COUNT(*) FILTER (
            WHERE delivery_status = 'Delayed'
        ) AS delayed_shipments,

        COUNT(*) FILTER (
            WHERE delivery_status = 'Pending'
        ) AS pending_shipments,

        COUNT(*) FILTER (
            WHERE delivery_status = 'Delivered'
              AND delay_days <= 0
        ) AS on_time_deliveries,

        AVG(
            CASE
                WHEN delivery_status <> 'Pending'
                THEN delay_days
            END
        ) AS average_delay_days

    FROM fact_shipments

    GROUP BY date_key
)

SELECT
    d.year,
    d.month,
    d.month_name,
    d.quarter,

    COALESCE(
        SUM(ms.shipments),
        0
    ) AS shipments,

    COALESCE(
        SUM(ms.units_shipped),
        0
    ) AS units_shipped,

    ROUND(
        COALESCE(
            SUM(ms.shipping_cost),
            0
        ),
        2
    ) AS shipping_cost,

    COALESCE(
        SUM(ms.delivered_shipments),
        0
    ) AS delivered_shipments,

    COALESCE(
        SUM(ms.delayed_shipments),
        0
    ) AS delayed_shipments,

    COALESCE(
        SUM(ms.pending_shipments),
        0
    ) AS pending_shipments,

    ROUND(
        COALESCE(
            SUM(ms.delivered_shipments) * 100.0
            / NULLIF(SUM(ms.shipments), 0),
            0
        ),
        2
    ) AS delivered_pct,

    ROUND(
        COALESCE(
            SUM(ms.delayed_shipments) * 100.0
            / NULLIF(
                SUM(ms.shipments)
                - SUM(ms.pending_shipments),
                0
            ),
            0
        ),
        2
    ) AS delayed_pct,

    ROUND(
        COALESCE(
            SUM(ms.on_time_deliveries) * 100.0
            / NULLIF(
                SUM(ms.delivered_shipments),
                0
            ),
            0
        ),
        2
    ) AS on_time_delivery_pct,

    ROUND(
        COALESCE(
            SUM(
                ms.average_delay_days
                * ms.shipments
            )
            / NULLIF(SUM(ms.shipments), 0),
            0
        ),
        2
    ) AS average_delay_days

FROM dim_date d

LEFT JOIN monthly_shipments ms
    ON d.date_key = ms.date_key

GROUP BY
    d.year,
    d.month,
    d.month_name,
    d.quarter;


-- ============================================================
-- 4. CARRIER PERFORMANCE
-- ============================================================

CREATE VIEW vw_carrier_performance AS
SELECT
    c.carrier_key,
    c.carrier_id,
    c.carrier_name,
    c.carrier_type,
    c.service_level,

    COUNT(*) AS shipments,

    SUM(s.quantity) AS units_shipped,

    ROUND(
        SUM(s.shipping_cost),
        2
    ) AS shipping_cost,

    ROUND(
        AVG(s.shipping_cost),
        2
    ) AS average_shipping_cost,

    COUNT(*) FILTER (
        WHERE s.delivery_status = 'Delivered'
    ) AS delivered_shipments,

    COUNT(*) FILTER (
        WHERE s.delivery_status = 'Delayed'
    ) AS delayed_shipments,

    COUNT(*) FILTER (
        WHERE s.delivery_status = 'Pending'
    ) AS pending_shipments,

    COUNT(*) FILTER (
        WHERE s.delivery_status = 'Delivered'
          AND s.delay_days <= 0
    ) AS on_time_deliveries,

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

JOIN dim_carrier c
    ON s.carrier_key = c.carrier_key

GROUP BY
    c.carrier_key,
    c.carrier_id,
    c.carrier_name,
    c.carrier_type,
    c.service_level;


-- ============================================================
-- 5. WAREHOUSE LOGISTICS PERFORMANCE
-- ============================================================

CREATE VIEW vw_warehouse_logistics AS
SELECT
    w.warehouse_key,
    w.warehouse_id,
    w.warehouse_name,
    w.city,
    w.country,
    w.region,
    w.warehouse_type,

    COUNT(*) AS shipments,

    SUM(s.quantity) AS units_shipped,

    ROUND(
        SUM(s.shipping_cost),
        2
    ) AS shipping_cost,

    ROUND(
        AVG(s.shipping_cost),
        2
    ) AS average_shipping_cost,

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

JOIN dim_warehouse w
    ON s.warehouse_key = w.warehouse_key

GROUP BY
    w.warehouse_key,
    w.warehouse_id,
    w.warehouse_name,
    w.city,
    w.country,
    w.region,
    w.warehouse_type;


-- ============================================================
-- 6. CUSTOMER DELIVERY PERFORMANCE
-- ============================================================

CREATE VIEW vw_customer_delivery_performance AS
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
-- 7. SHIPPING COST ANALYSIS
-- ============================================================

CREATE VIEW vw_shipping_cost_analysis AS
SELECT
    p.product_key,
    p.product_id,
    p.product_name,
    p.category,
    p.sub_category,

    COUNT(*) AS shipments,

    SUM(s.quantity) AS units_shipped,

    ROUND(
        SUM(s.shipping_cost),
        2
    ) AS total_shipping_cost,

    ROUND(
        AVG(s.shipping_cost),
        2
    ) AS average_shipping_cost,

    ROUND(
        SUM(s.shipping_cost)
        / NULLIF(SUM(s.quantity), 0),
        2
    ) AS shipping_cost_per_unit,

    ROUND(
        MIN(s.shipping_cost),
        2
    ) AS minimum_shipping_cost,

    ROUND(
        MAX(s.shipping_cost),
        2
    ) AS maximum_shipping_cost

FROM fact_shipments s

JOIN dim_product p
    ON s.product_key = p.product_key

GROUP BY
    p.product_key,
    p.product_id,
    p.product_name,
    p.category,
    p.sub_category;


-- ============================================================
-- 8. PENDING SHIPMENTS
-- ============================================================

CREATE VIEW vw_pending_shipments AS
SELECT
    s.shipment_key,

    d.full_date AS order_date,

    s.ship_date,

    s.expected_delivery_date,

    CURRENT_DATE - s.expected_delivery_date
        AS days_past_expected,

    p.product_id,
    p.product_name,
    p.category,

    c.customer_id,
    c.customer_name,
    c.segment,

    w.warehouse_id,
    w.warehouse_name,
    w.region,

    ca.carrier_id,
    ca.carrier_name,
    ca.service_level,

    s.quantity,

    ROUND(
        s.shipping_cost,
        2
    ) AS shipping_cost,

    CASE
        WHEN CURRENT_DATE > s.expected_delivery_date
            THEN 'Overdue'
        ELSE 'Pending'
    END AS shipment_status

FROM fact_shipments s

JOIN dim_date d
    ON s.date_key = d.date_key

JOIN dim_product p
    ON s.product_key = p.product_key

JOIN dim_customer c
    ON s.customer_key = c.customer_key

JOIN dim_warehouse w
    ON s.warehouse_key = w.warehouse_key

JOIN dim_carrier ca
    ON s.carrier_key = ca.carrier_key

WHERE
    s.delivery_status = 'Pending';


-- ============================================================
-- 9. LOGISTICS DATA QUALITY
-- ============================================================

CREATE VIEW vw_logistics_data_quality AS
SELECT
    COUNT(*) AS total_shipment_rows,

    COUNT(*) FILTER (
        WHERE quantity <= 0
    ) AS invalid_quantity_rows,

    COUNT(*) FILTER (
        WHERE shipping_cost < 0
    ) AS invalid_shipping_cost_rows,

    COUNT(*) FILTER (
        WHERE delay_days < 0
    ) AS negative_delay_rows,

    COUNT(*) FILTER (
        WHERE order_date IS NULL
    ) AS null_order_date_rows,

    COUNT(*) FILTER (
        WHERE ship_date IS NOT NULL
          AND ship_date < order_date
    ) AS invalid_ship_dates,

    COUNT(*) FILTER (
        WHERE expected_delivery_date IS NOT NULL
          AND ship_date IS NOT NULL
          AND expected_delivery_date < ship_date
    ) AS invalid_expected_delivery_dates,

    COUNT(*) FILTER (
        WHERE actual_delivery_date IS NOT NULL
          AND expected_delivery_date IS NOT NULL
          AND actual_delivery_date < expected_delivery_date
          AND delay_days > 0
    ) AS delay_calculation_errors,

    COUNT(*) FILTER (
        WHERE delivery_status NOT IN (
            'Delivered',
            'Delayed',
            'Pending'
        )
    ) AS invalid_delivery_status_rows,

    COUNT(DISTINCT product_key) AS distinct_products,

    COUNT(DISTINCT customer_key) AS distinct_customers,

    COUNT(DISTINCT warehouse_key) AS distinct_warehouses,

    COUNT(DISTINCT carrier_key) AS distinct_carriers,

    COUNT(DISTINCT date_key) AS distinct_dates

FROM fact_shipments;


-- ============================================================
-- END OF LOGISTICS ANALYTICS LAYER
-- ============================================================