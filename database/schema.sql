-- ============================================================
-- SupplyIQ 2.0
-- Enterprise Supply Chain Analytics Warehouse
-- PostgreSQL 17
-- ============================================================

CREATE SCHEMA IF NOT EXISTS supplyiq;

SET search_path TO supplyiq;

-- ============================================================
-- DIMENSION TABLES
-- ============================================================

-- Date Dimension
CREATE TABLE dim_date (
    date_key        INTEGER PRIMARY KEY,
    full_date       DATE NOT NULL UNIQUE,
    day             INTEGER NOT NULL,
    day_name        VARCHAR(10) NOT NULL,
    week            INTEGER NOT NULL,
    month           INTEGER NOT NULL,
    month_name      VARCHAR(15) NOT NULL,
    quarter         INTEGER NOT NULL,
    year            INTEGER NOT NULL,
    is_weekend      BOOLEAN NOT NULL
);

-- Product Dimension
CREATE TABLE dim_product (
    product_key     BIGSERIAL PRIMARY KEY,
    product_id      VARCHAR(30) NOT NULL UNIQUE,
    product_name    VARCHAR(150) NOT NULL,
    category        VARCHAR(80) NOT NULL,
    sub_category    VARCHAR(80),
    brand           VARCHAR(80),
    unit_cost       NUMERIC(12,2) NOT NULL,
    unit_price      NUMERIC(12,2) NOT NULL,
    weight_kg       NUMERIC(10,3),
    status          VARCHAR(20) DEFAULT 'Active'
);

-- Supplier Dimension
CREATE TABLE dim_supplier (
    supplier_key    BIGSERIAL PRIMARY KEY,
    supplier_id     VARCHAR(30) NOT NULL UNIQUE,
    supplier_name   VARCHAR(150) NOT NULL,
    country         VARCHAR(80) NOT NULL,
    region          VARCHAR(80),
    supplier_type   VARCHAR(50),
    quality_rating  NUMERIC(5,2),
    status          VARCHAR(20) DEFAULT 'Active'
);

-- Customer Dimension
CREATE TABLE dim_customer (
    customer_key    BIGSERIAL PRIMARY KEY,
    customer_id     VARCHAR(30) NOT NULL UNIQUE,
    customer_name   VARCHAR(150) NOT NULL,
    segment         VARCHAR(50),
    country         VARCHAR(80),
    region          VARCHAR(80)
);

-- Warehouse Dimension
CREATE TABLE dim_warehouse (
    warehouse_key   BIGSERIAL PRIMARY KEY,
    warehouse_id    VARCHAR(30) NOT NULL UNIQUE,
    warehouse_name  VARCHAR(150) NOT NULL,
    city            VARCHAR(80),
    country         VARCHAR(80),
    region          VARCHAR(80),
    warehouse_type  VARCHAR(50),
    capacity_units  INTEGER
);

-- Carrier Dimension
CREATE TABLE dim_carrier (
    carrier_key     BIGSERIAL PRIMARY KEY,
    carrier_id      VARCHAR(30) NOT NULL UNIQUE,
    carrier_name    VARCHAR(120) NOT NULL,
    carrier_type    VARCHAR(50),
    service_level   VARCHAR(50)
);

-- ============================================================
-- FACT TABLE: SALES
-- Grain: One row per sales transaction
-- ============================================================

CREATE TABLE fact_sales (
    sales_key       BIGSERIAL PRIMARY KEY,
    date_key        INTEGER NOT NULL,
    product_key     BIGINT NOT NULL,
    customer_key    BIGINT NOT NULL,
    warehouse_key   BIGINT NOT NULL,

    quantity        INTEGER NOT NULL,
    unit_price      NUMERIC(12,2) NOT NULL,
    revenue         NUMERIC(14,2) NOT NULL,
    discount        NUMERIC(14,2) DEFAULT 0,
    cost            NUMERIC(14,2) NOT NULL,
    profit          NUMERIC(14,2) NOT NULL,

    CONSTRAINT fk_sales_date
        FOREIGN KEY (date_key) REFERENCES dim_date(date_key),

    CONSTRAINT fk_sales_product
        FOREIGN KEY (product_key) REFERENCES dim_product(product_key),

    CONSTRAINT fk_sales_customer
        FOREIGN KEY (customer_key) REFERENCES dim_customer(customer_key),

    CONSTRAINT fk_sales_warehouse
        FOREIGN KEY (warehouse_key) REFERENCES dim_warehouse(warehouse_key)
);

-- ============================================================
-- FACT TABLE: INVENTORY
-- Grain: One row per product/warehouse/day
-- ============================================================

CREATE TABLE fact_inventory (
    inventory_key       BIGSERIAL PRIMARY KEY,
    date_key            INTEGER NOT NULL,
    product_key         BIGINT NOT NULL,
    warehouse_key       BIGINT NOT NULL,

    opening_stock       INTEGER NOT NULL,
    received_quantity   INTEGER DEFAULT 0,
    sold_quantity       INTEGER DEFAULT 0,
    closing_stock       INTEGER NOT NULL,

    inventory_value     NUMERIC(16,2) NOT NULL,

    CONSTRAINT fk_inventory_date
        FOREIGN KEY (date_key) REFERENCES dim_date(date_key),

    CONSTRAINT fk_inventory_product
        FOREIGN KEY (product_key) REFERENCES dim_product(product_key),

    CONSTRAINT fk_inventory_warehouse
        FOREIGN KEY (warehouse_key) REFERENCES dim_warehouse(warehouse_key)
);

-- ============================================================
-- FACT TABLE: PROCUREMENT
-- Grain: One row per purchase order line
-- ============================================================

CREATE TABLE fact_procurement (
    procurement_key         BIGSERIAL PRIMARY KEY,
    date_key                INTEGER NOT NULL,
    product_key             BIGINT NOT NULL,
    supplier_key            BIGINT NOT NULL,
    warehouse_key           BIGINT NOT NULL,

    po_quantity             INTEGER NOT NULL,
    unit_cost               NUMERIC(12,2) NOT NULL,
    procurement_value       NUMERIC(16,2) NOT NULL,

    expected_delivery_date  DATE NOT NULL,
    actual_delivery_date    DATE,

    CONSTRAINT fk_procurement_date
        FOREIGN KEY (date_key) REFERENCES dim_date(date_key),

    CONSTRAINT fk_procurement_product
        FOREIGN KEY (product_key) REFERENCES dim_product(product_key),

    CONSTRAINT fk_procurement_supplier
        FOREIGN KEY (supplier_key) REFERENCES dim_supplier(supplier_key),

    CONSTRAINT fk_procurement_warehouse
        FOREIGN KEY (warehouse_key) REFERENCES dim_warehouse(warehouse_key)
);

-- ============================================================
-- FACT TABLE: SHIPMENTS
-- Grain: One row per shipment
-- ============================================================

CREATE TABLE fact_shipments (
    shipment_key           BIGSERIAL PRIMARY KEY,
    date_key               INTEGER NOT NULL,
    product_key            BIGINT NOT NULL,
    customer_key           BIGINT NOT NULL,
    warehouse_key          BIGINT NOT NULL,
    carrier_key            BIGINT NOT NULL,

    quantity               INTEGER NOT NULL,
    shipping_cost          NUMERIC(14,2) NOT NULL,

    order_date             DATE NOT NULL,
    ship_date              DATE NOT NULL,
    expected_delivery_date DATE NOT NULL,
    actual_delivery_date   DATE,

    delay_days             INTEGER DEFAULT 0,
    delivery_status        VARCHAR(30) NOT NULL,

    CONSTRAINT fk_shipments_date
        FOREIGN KEY (date_key) REFERENCES dim_date(date_key),

    CONSTRAINT fk_shipments_product
        FOREIGN KEY (product_key) REFERENCES dim_product(product_key),

    CONSTRAINT fk_shipments_customer
        FOREIGN KEY (customer_key) REFERENCES dim_customer(customer_key),

    CONSTRAINT fk_shipments_warehouse
        FOREIGN KEY (warehouse_key) REFERENCES dim_warehouse(warehouse_key),

    CONSTRAINT fk_shipments_carrier
        FOREIGN KEY (carrier_key) REFERENCES dim_carrier(carrier_key)
);

-- ============================================================
-- FACT TABLE: RETURNS
-- Grain: One row per return transaction
-- ============================================================

CREATE TABLE fact_returns (
    return_key       BIGSERIAL PRIMARY KEY,
    date_key         INTEGER NOT NULL,
    product_key      BIGINT NOT NULL,
    customer_key     BIGINT NOT NULL,
    warehouse_key    BIGINT NOT NULL,

    quantity         INTEGER NOT NULL,
    return_reason    VARCHAR(100),
    refund_amount    NUMERIC(14,2) NOT NULL,

    CONSTRAINT fk_returns_date
        FOREIGN KEY (date_key) REFERENCES dim_date(date_key),

    CONSTRAINT fk_returns_product
        FOREIGN KEY (product_key) REFERENCES dim_product(product_key),

    CONSTRAINT fk_returns_customer
        FOREIGN KEY (customer_key) REFERENCES dim_customer(customer_key),

    CONSTRAINT fk_returns_warehouse
        FOREIGN KEY (warehouse_key) REFERENCES dim_warehouse(warehouse_key)
);

-- ============================================================
-- INDEXES
-- ============================================================

CREATE INDEX idx_sales_date
    ON fact_sales(date_key);

CREATE INDEX idx_sales_product
    ON fact_sales(product_key);

CREATE INDEX idx_sales_customer
    ON fact_sales(customer_key);

CREATE INDEX idx_inventory_date
    ON fact_inventory(date_key);

CREATE INDEX idx_inventory_product
    ON fact_inventory(product_key);

CREATE INDEX idx_inventory_warehouse
    ON fact_inventory(warehouse_key);

CREATE INDEX idx_procurement_date
    ON fact_procurement(date_key);

CREATE INDEX idx_procurement_supplier
    ON fact_procurement(supplier_key);

CREATE INDEX idx_shipments_date
    ON fact_shipments(date_key);

CREATE INDEX idx_shipments_carrier
    ON fact_shipments(carrier_key);

CREATE INDEX idx_shipments_status
    ON fact_shipments(delivery_status);

CREATE INDEX idx_returns_date
    ON fact_returns(date_key);

CREATE INDEX idx_returns_product
    ON fact_returns(product_key);