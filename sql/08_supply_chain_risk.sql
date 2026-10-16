-- ============================================================
-- 08_supply_chain_risk.sql
-- SupplyIQ 2.0 - Supply Chain Risk Analytics
-- ============================================================

SET search_path TO supplyiq;

-- ============================================================
-- 1. PRODUCT-LEVEL SUPPLY CHAIN RISK
-- ============================================================

DROP VIEW IF EXISTS vw_supply_chain_risk CASCADE;

CREATE VIEW vw_supply_chain_risk AS
WITH sales AS (
    SELECT
        product_key,
        SUM(quantity) AS units_sold,
        SUM(revenue) AS revenue,
        SUM(profit) AS profit,
        COUNT(*) AS orders,
        COUNT(*) FILTER (WHERE profit < 0) AS loss_making_orders
    FROM fact_sales
    GROUP BY product_key
),

inventory AS (
    SELECT
        product_key,
        AVG(closing_stock) AS avg_closing_stock,
        AVG(inventory_value) AS avg_inventory_value,
        COUNT(*) FILTER (WHERE closing_stock = 0) AS stockout_days,
        COUNT(*) AS inventory_days
    FROM fact_inventory
    GROUP BY product_key
),

procurement AS (
    SELECT
        product_key,
        SUM(po_quantity) AS procured_units,
        SUM(procurement_value) AS procurement_spend,
        COUNT(*) AS purchase_orders,
        COUNT(*) FILTER (
            WHERE actual_delivery_date > expected_delivery_date
        ) AS late_purchase_orders
    FROM fact_procurement
    GROUP BY product_key
),

shipments AS (
    SELECT
        product_key,
        COUNT(*) AS shipments,
        COUNT(*) FILTER (
            WHERE delivery_status = 'Delayed'
        ) AS delayed_shipments,
        COUNT(*) FILTER (
            WHERE delivery_status = 'Pending'
        ) AS pending_shipments,
        AVG(delay_days) FILTER (
            WHERE delivery_status <> 'Pending'
        ) AS avg_delay_days
    FROM fact_shipments
    GROUP BY product_key
),

returns AS (
    SELECT
        product_key,
        SUM(quantity) AS returned_units,
        SUM(refund_amount) AS refund_amount
    FROM fact_returns
    GROUP BY product_key
),

metrics AS (
    SELECT
        p.product_key,
        p.product_id,
        p.product_name,
        p.category,
        p.sub_category,
        p.brand,
        p.unit_cost,
        p.unit_price,

        COALESCE(s.units_sold, 0) AS units_sold,
        COALESCE(s.revenue, 0) AS revenue,
        COALESCE(s.profit, 0) AS profit,
        COALESCE(s.orders, 0) AS orders,
        COALESCE(s.loss_making_orders, 0) AS loss_making_orders,

        CASE
            WHEN COALESCE(s.revenue, 0) > 0
            THEN ROUND(
                (s.profit / s.revenue * 100)::numeric,
                2
            )
            ELSE 0
        END AS profit_margin_pct,

        COALESCE(i.avg_closing_stock, 0) AS avg_closing_stock,
        COALESCE(i.avg_inventory_value, 0) AS avg_inventory_value,
        COALESCE(i.stockout_days, 0) AS stockout_days,
        COALESCE(i.inventory_days, 0) AS inventory_days,

        CASE
            WHEN COALESCE(i.inventory_days, 0) > 0
            THEN ROUND(
                (i.stockout_days::numeric / i.inventory_days * 100),
                2
            )
            ELSE 0
        END AS stockout_rate_pct,

        COALESCE(pr.procured_units, 0) AS procured_units,
        COALESCE(pr.procurement_spend, 0) AS procurement_spend,
        COALESCE(pr.purchase_orders, 0) AS purchase_orders,
        COALESCE(pr.late_purchase_orders, 0) AS late_purchase_orders,

        CASE
            WHEN COALESCE(pr.purchase_orders, 0) > 0
            THEN ROUND(
                (
                    pr.late_purchase_orders::numeric
                    / pr.purchase_orders * 100
                ),
                2
            )
            ELSE 0
        END AS procurement_late_rate_pct,

        COALESCE(sh.shipments, 0) AS shipments,
        COALESCE(sh.delayed_shipments, 0) AS delayed_shipments,
        COALESCE(sh.pending_shipments, 0) AS pending_shipments,
        COALESCE(sh.avg_delay_days, 0) AS avg_delay_days,

        CASE
            WHEN COALESCE(sh.shipments, 0) > 0
            THEN ROUND(
                (
                    sh.delayed_shipments::numeric
                    / sh.shipments * 100
                ),
                2
            )
            ELSE 0
        END AS shipment_delay_rate_pct,

        COALESCE(r.returned_units, 0) AS returned_units,
        COALESCE(r.refund_amount, 0) AS refund_amount,

        CASE
            WHEN COALESCE(s.units_sold, 0) > 0
            THEN ROUND(
                (
                    COALESCE(r.returned_units, 0)::numeric
                    / s.units_sold * 100
                ),
                2
            )
            ELSE 0
        END AS return_rate_pct

    FROM dim_product p

    LEFT JOIN sales s
        ON p.product_key = s.product_key

    LEFT JOIN inventory i
        ON p.product_key = i.product_key

    LEFT JOIN procurement pr
        ON p.product_key = pr.product_key

    LEFT JOIN shipments sh
        ON p.product_key = sh.product_key

    LEFT JOIN returns r
        ON p.product_key = r.product_key
),

risk_scores AS (
    SELECT
        *,
        
        -- Procurement risk
        LEAST(procurement_late_rate_pct, 100) AS procurement_risk_score,

        -- Logistics risk
        LEAST(shipment_delay_rate_pct, 100) AS logistics_risk_score,

        -- Return risk
        LEAST(return_rate_pct * 5, 100) AS return_risk_score,

        -- Margin risk
        CASE
            WHEN profit_margin_pct >= 40 THEN 0
            WHEN profit_margin_pct >= 30 THEN 25
            WHEN profit_margin_pct >= 20 THEN 50
            WHEN profit_margin_pct >= 10 THEN 75
            ELSE 100
        END AS profitability_risk_score,

        -- Inventory risk
        CASE
            WHEN stockout_rate_pct > 10 THEN 100
            WHEN stockout_rate_pct > 5 THEN 75
            WHEN stockout_rate_pct > 2 THEN 50
            WHEN stockout_rate_pct > 0 THEN 25
            ELSE 0
        END AS inventory_risk_score

    FROM metrics
)

SELECT
    product_key,
    product_id,
    product_name,
    category,
    sub_category,
    brand,

    units_sold,
    revenue,
    profit,
    profit_margin_pct,
    loss_making_orders,

    avg_closing_stock,
    avg_inventory_value,
    stockout_days,
    stockout_rate_pct,

    procured_units,
    procurement_spend,
    purchase_orders,
    late_purchase_orders,
    procurement_late_rate_pct,

    shipments,
    delayed_shipments,
    pending_shipments,
    shipment_delay_rate_pct,
    avg_delay_days,

    returned_units,
    refund_amount,
    return_rate_pct,

    ROUND(
        (
            procurement_risk_score * 0.25
            + logistics_risk_score * 0.25
            + return_risk_score * 0.20
            + profitability_risk_score * 0.15
            + inventory_risk_score * 0.15
        )::numeric,
        2
    ) AS overall_risk_score,

    ROUND(procurement_risk_score::numeric, 2)
        AS procurement_risk_score,

    ROUND(logistics_risk_score::numeric, 2)
        AS logistics_risk_score,

    ROUND(return_risk_score::numeric, 2)
        AS return_risk_score,

    ROUND(profitability_risk_score::numeric, 2)
        AS profitability_risk_score,

    ROUND(inventory_risk_score::numeric, 2)
        AS inventory_risk_score,

    CASE
    WHEN (
        procurement_risk_score * 0.25
        + logistics_risk_score * 0.25
        + return_risk_score * 0.20
        + profitability_risk_score * 0.15
        + inventory_risk_score * 0.15
    ) >= 30 THEN 'Critical'

    WHEN (
        procurement_risk_score * 0.25
        + logistics_risk_score * 0.25
        + return_risk_score * 0.20
        + profitability_risk_score * 0.15
        + inventory_risk_score * 0.15
    ) >= 29 THEN 'High'

    WHEN (
        procurement_risk_score * 0.25
        + logistics_risk_score * 0.25
        + return_risk_score * 0.20
        + profitability_risk_score * 0.15
        + inventory_risk_score * 0.15
    ) >= 26 THEN 'Medium'

    ELSE 'Low'
END AS risk_level
FROM risk_scores;

-- ============================================================
-- 2. PRODUCT RISK RANKING
-- ============================================================

DROP VIEW IF EXISTS vw_product_risk CASCADE;

CREATE VIEW vw_product_risk AS
SELECT
    product_key,
    product_id,
    product_name,
    category,
    sub_category,
    overall_risk_score,
    risk_level,
    revenue,
    profit,
    profit_margin_pct,
    procurement_late_rate_pct,
    shipment_delay_rate_pct,
    return_rate_pct,
    stockout_rate_pct
FROM vw_supply_chain_risk
ORDER BY overall_risk_score DESC;


-- ============================================================
-- 3. WAREHOUSE RISK
-- ============================================================

DROP VIEW IF EXISTS vw_warehouse_risk CASCADE;

CREATE VIEW vw_warehouse_risk AS
WITH inventory AS (
    SELECT
        warehouse_key,
        AVG(closing_stock) AS avg_closing_stock,
        AVG(inventory_value) AS avg_inventory_value,
        COUNT(*) FILTER (
            WHERE closing_stock = 0
        ) AS stockout_days,
        COUNT(*) AS inventory_days
    FROM fact_inventory
    GROUP BY warehouse_key
),

procurement AS (
    SELECT
        warehouse_key,
        COUNT(*) AS purchase_orders,
        COUNT(*) FILTER (
            WHERE actual_delivery_date > expected_delivery_date
        ) AS late_purchase_orders,
        SUM(procurement_value) AS procurement_spend
    FROM fact_procurement
    GROUP BY warehouse_key
),

logistics AS (
    SELECT
        warehouse_key,
        COUNT(*) AS shipments,
        COUNT(*) FILTER (
            WHERE delivery_status = 'Delayed'
        ) AS delayed_shipments,
        COUNT(*) FILTER (
            WHERE delivery_status = 'Pending'
        ) AS pending_shipments,
        AVG(delay_days) FILTER (
            WHERE delivery_status <> 'Pending'
        ) AS avg_delay_days
    FROM fact_shipments
    GROUP BY warehouse_key
)

SELECT
    w.warehouse_key,
    w.warehouse_id,
    w.warehouse_name,
    w.city,
    w.country,
    w.region,
    w.warehouse_type,
    w.capacity_units,

    COALESCE(i.avg_closing_stock, 0) AS avg_closing_stock,
    COALESCE(i.avg_inventory_value, 0) AS avg_inventory_value,
    COALESCE(i.stockout_days, 0) AS stockout_days,

    CASE
        WHEN COALESCE(i.inventory_days, 0) > 0
        THEN ROUND(
            (
                i.stockout_days::numeric
                / i.inventory_days * 100
            ),
            2
        )
        ELSE 0
    END AS stockout_rate_pct,

    COALESCE(p.purchase_orders, 0) AS purchase_orders,
    COALESCE(p.late_purchase_orders, 0) AS late_purchase_orders,
    COALESCE(p.procurement_spend, 0) AS procurement_spend,

    CASE
        WHEN COALESCE(p.purchase_orders, 0) > 0
        THEN ROUND(
            (
                p.late_purchase_orders::numeric
                / p.purchase_orders * 100
            ),
            2
        )
        ELSE 0
    END AS procurement_late_rate_pct,

    COALESCE(l.shipments, 0) AS shipments,
    COALESCE(l.delayed_shipments, 0) AS delayed_shipments,
    COALESCE(l.pending_shipments, 0) AS pending_shipments,
    COALESCE(l.avg_delay_days, 0) AS avg_delay_days,

    CASE
        WHEN COALESCE(l.shipments, 0) > 0
        THEN ROUND(
            (
                l.delayed_shipments::numeric
                / l.shipments * 100
            ),
            2
        )
        ELSE 0
    END AS shipment_delay_rate_pct,

    ROUND(
        (
            LEAST(
                CASE
                    WHEN COALESCE(p.purchase_orders, 0) > 0
                    THEN p.late_purchase_orders::numeric
                         / p.purchase_orders * 100
                    ELSE 0
                END,
                100
            ) * 0.40

            +

            LEAST(
                CASE
                    WHEN COALESCE(l.shipments, 0) > 0
                    THEN l.delayed_shipments::numeric
                         / l.shipments * 100
                    ELSE 0
                END,
                100
            ) * 0.40

            +

            LEAST(
                CASE
                    WHEN COALESCE(i.inventory_days, 0) > 0
                    THEN i.stockout_days::numeric
                         / i.inventory_days * 100
                    ELSE 0
                END,
                100
            ) * 0.20
        )::numeric,
        2
    ) AS warehouse_risk_score,

    CASE
        WHEN (
            LEAST(
                CASE
                    WHEN COALESCE(p.purchase_orders, 0) > 0
                    THEN p.late_purchase_orders::numeric
                         / p.purchase_orders * 100
                    ELSE 0
                END,
                100
            ) * 0.40

            +

            LEAST(
                CASE
                    WHEN COALESCE(l.shipments, 0) > 0
                    THEN l.delayed_shipments::numeric
                         / l.shipments * 100
                    ELSE 0
                END,
                100
            ) * 0.40

            +

            LEAST(
                CASE
                    WHEN COALESCE(i.inventory_days, 0) > 0
                    THEN i.stockout_days::numeric
                         / i.inventory_days * 100
                    ELSE 0
                END,
                100
            ) * 0.20
        ) >= 70 THEN 'Critical'

        WHEN (
            LEAST(
                CASE
                    WHEN COALESCE(p.purchase_orders, 0) > 0
                    THEN p.late_purchase_orders::numeric
                         / p.purchase_orders * 100
                    ELSE 0
                END,
                100
            ) * 0.40

            +

            LEAST(
                CASE
                    WHEN COALESCE(l.shipments, 0) > 0
                    THEN l.delayed_shipments::numeric
                         / l.shipments * 100
                    ELSE 0
                END,
                100
            ) * 0.40

            +

            LEAST(
                CASE
                    WHEN COALESCE(i.inventory_days, 0) > 0
                    THEN i.stockout_days::numeric
                         / i.inventory_days * 100
                    ELSE 0
                END,
                100
            ) * 0.20
        ) >= 50 THEN 'High'

        WHEN (
            LEAST(
                CASE
                    WHEN COALESCE(p.purchase_orders, 0) > 0
                    THEN p.late_purchase_orders::numeric
                         / p.purchase_orders * 100
                    ELSE 0
                END,
                100
            ) * 0.40

            +

            LEAST(
                CASE
                    WHEN COALESCE(l.shipments, 0) > 0
                    THEN l.delayed_shipments::numeric
                         / l.shipments * 100
                    ELSE 0
                END,
                100
            ) * 0.40

            +

            LEAST(
                CASE
                    WHEN COALESCE(i.inventory_days, 0) > 0
                    THEN i.stockout_days::numeric
                         / i.inventory_days * 100
                    ELSE 0
                END,
                100
            ) * 0.20
        ) >= 25 THEN 'Medium'

        ELSE 'Low'
    END AS risk_level

FROM dim_warehouse w

LEFT JOIN inventory i
    ON w.warehouse_key = i.warehouse_key

LEFT JOIN procurement p
    ON w.warehouse_key = p.warehouse_key

LEFT JOIN logistics l
    ON w.warehouse_key = l.warehouse_key;


-- ============================================================
-- 4. SUPPLIER RISK SUMMARY
-- ============================================================

DROP VIEW IF EXISTS vw_supplier_risk_summary CASCADE;

CREATE VIEW vw_supplier_risk_summary AS
SELECT
    supplier_key,
    supplier_id,
    supplier_name,
    purchase_orders,
    procurement_spend,
    completed_orders,
    pending_orders,
    late_orders,
    late_delivery_pct,
    average_delivery_variance_days,
    supplier_risk
FROM vw_supplier_risk;
-- ============================================================
-- 5. OVERALL RISK DISTRIBUTION
-- ============================================================

DROP VIEW IF EXISTS vw_risk_distribution CASCADE;

CREATE VIEW vw_risk_distribution AS
SELECT
    risk_level,
    COUNT(*) AS product_count,
    ROUND(
        (
            COUNT(*)::numeric
            / SUM(COUNT(*)) OVER () * 100
        ),
        2
    ) AS product_share_pct,
    SUM(revenue) AS revenue,
    SUM(profit) AS profit,
    SUM(procurement_spend) AS procurement_spend
FROM vw_supply_chain_risk
GROUP BY risk_level
ORDER BY
    CASE risk_level
        WHEN 'Critical' THEN 1
        WHEN 'High' THEN 2
        WHEN 'Medium' THEN 3
        WHEN 'Low' THEN 4
    END;


-- ============================================================
-- 6. CRITICAL RISK ITEMS
-- ============================================================

DROP VIEW IF EXISTS vw_critical_risk_items CASCADE;

CREATE VIEW vw_critical_risk_items AS
SELECT
    product_key,
    product_id,
    product_name,
    category,
    sub_category,
    overall_risk_score,
    risk_level,
    revenue,
    profit,
    profit_margin_pct,
    procurement_late_rate_pct,
    shipment_delay_rate_pct,
    return_rate_pct,
    stockout_rate_pct
FROM vw_supply_chain_risk
WHERE risk_level IN ('Critical', 'High')
ORDER BY overall_risk_score DESC;


-- ============================================================
-- 7. SUPPLY CHAIN RISK DATA QUALITY
-- ============================================================

DROP VIEW IF EXISTS vw_supply_chain_risk_data_quality CASCADE;

CREATE VIEW vw_supply_chain_risk_data_quality AS
SELECT
    COUNT(*) AS total_product_rows,

    COUNT(*) FILTER (
        WHERE product_id IS NULL
    ) AS null_product_ids,

    COUNT(*) FILTER (
        WHERE product_name IS NULL
    ) AS null_product_names,

    COUNT(*) FILTER (
        WHERE revenue < 0
    ) AS negative_revenue_rows,

    COUNT(*) FILTER (
        WHERE profit_margin_pct < -100
    ) AS extreme_negative_margin_rows,

    COUNT(*) FILTER (
        WHERE overall_risk_score < 0
           OR overall_risk_score > 100
    ) AS invalid_risk_scores,

    COUNT(*) FILTER (
        WHERE risk_level IS NULL
    ) AS null_risk_levels

FROM vw_supply_chain_risk;