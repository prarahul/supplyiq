import os
import random

import numpy as np
import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import create_engine, text


# ---------------------------------------------------------
# Configuration
# ---------------------------------------------------------

load_dotenv()

DATABASE_URL = os.environ["DATABASE_URL"]

TOTAL_ROWS = 1_000_000
CHUNK_SIZE = 50_000
SEED = 45

random.seed(SEED)
np.random.seed(SEED)


# ---------------------------------------------------------
# Database
# ---------------------------------------------------------

engine = create_engine(
    DATABASE_URL,
    pool_pre_ping=True,
)


# ---------------------------------------------------------
# Load dimensions
# ---------------------------------------------------------

print("Loading dimension data...")

with engine.connect() as conn:

    products = pd.read_sql(
        text("""
            SELECT product_key, unit_cost
            FROM supplyiq.dim_product
            ORDER BY product_key
        """),
        conn,
    )

    customers = pd.read_sql(
        text("""
            SELECT customer_key
            FROM supplyiq.dim_customer
            ORDER BY customer_key
        """),
        conn,
    )

    warehouses = pd.read_sql(
        text("""
            SELECT warehouse_key
            FROM supplyiq.dim_warehouse
            ORDER BY warehouse_key
        """),
        conn,
    )

    carriers = pd.read_sql(
        text("""
            SELECT carrier_key
            FROM supplyiq.dim_carrier
            ORDER BY carrier_key
        """),
        conn,
    )

    dates = pd.read_sql(
        text("""
            SELECT date_key, full_date
            FROM supplyiq.dim_date
            ORDER BY date_key
        """),
        conn,
    )


print(f"Products loaded:   {len(products):,}")
print(f"Customers loaded:  {len(customers):,}")
print(f"Warehouses loaded: {len(warehouses):,}")
print(f"Carriers loaded:   {len(carriers):,}")
print(f"Dates loaded:      {len(dates):,}")


# ---------------------------------------------------------
# Convert dimensions to NumPy arrays
# ---------------------------------------------------------

product_keys = products["product_key"].to_numpy()
product_costs = products["unit_cost"].astype(float).to_numpy()

customer_keys = customers["customer_key"].to_numpy()
warehouse_keys = warehouses["warehouse_key"].to_numpy()
carrier_keys = carriers["carrier_key"].to_numpy()

date_keys = dates["date_key"].to_numpy()

date_values = pd.to_datetime(
    dates["full_date"]
).to_numpy(
    dtype="datetime64[D]"
)


# ---------------------------------------------------------
# Generate shipments
# ---------------------------------------------------------

print()
print("Starting shipment generation...")
print(f"Target rows: {TOTAL_ROWS:,}")
print(f"Chunk size:  {CHUNK_SIZE:,}")
print()

rows_generated = 0


while rows_generated < TOTAL_ROWS:

    current_chunk = min(
        CHUNK_SIZE,
        TOTAL_ROWS - rows_generated,
    )

    # -----------------------------------------------------
    # Dimension keys
    # -----------------------------------------------------

    product_idx = np.random.randint(
        0,
        len(product_keys),
        current_chunk,
    )

    customer_idx = np.random.randint(
        0,
        len(customer_keys),
        current_chunk,
    )

    warehouse_idx = np.random.randint(
        0,
        len(warehouse_keys),
        current_chunk,
    )

    carrier_idx = np.random.randint(
        0,
        len(carrier_keys),
        current_chunk,
    )

    date_idx = np.random.randint(
        0,
        len(date_keys),
        current_chunk,
    )

    selected_products = product_keys[product_idx]
    selected_customers = customer_keys[customer_idx]
    selected_warehouses = warehouse_keys[warehouse_idx]
    selected_carriers = carrier_keys[carrier_idx]

    selected_date_keys = date_keys[date_idx]
    order_dates = date_values[date_idx].copy()

    selected_costs = product_costs[product_idx]


    # -----------------------------------------------------
    # Ship date
    # -----------------------------------------------------

    ship_delay = np.random.choice(
        [0, 1, 2, 3],
        size=current_chunk,
        p=[0.35, 0.40, 0.20, 0.05],
    )

    ship_dates = (
        order_dates
        + ship_delay.astype("timedelta64[D]")
    )


    # -----------------------------------------------------
    # Transit time
    # -----------------------------------------------------

    transit_days = np.random.choice(
        [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
        size=current_chunk,
        p=[
            0.10,
            0.18,
            0.22,
            0.18,
            0.12,
            0.08,
            0.05,
            0.03,
            0.025,
            0.015,
        ],
    )

    expected_dates = (
        ship_dates
        + transit_days.astype("timedelta64[D]")
    )


    # -----------------------------------------------------
    # Delivery status
    # -----------------------------------------------------

    delivery_status = np.random.choice(
        [
            "Delivered",
            "Delayed",
            "Pending",
        ],
        size=current_chunk,
        p=[
            0.93,
            0.05,
            0.02,
        ],
    )


    # -----------------------------------------------------
    # Actual delivery date
    # -----------------------------------------------------

    actual_dates = expected_dates.copy()

    delivered_mask = (
        delivery_status == "Delivered"
    )

    delayed_mask = (
        delivery_status == "Delayed"
    )

    pending_mask = (
        delivery_status == "Pending"
    )


    # Delivered:
    # 10% one day early
    # 80% on time
    # 10% one day late

    delivered_variation = np.random.choice(
        [-1, 0, 1],
        size=current_chunk,
        p=[0.10, 0.80, 0.10],
    )

    delivered_dates = (
        expected_dates
        + delivered_variation.astype(
            "timedelta64[D]"
        )
    )

    actual_dates[delivered_mask] = (
        delivered_dates[delivered_mask]
    )


    # Delayed:
    # 1-10 days late

    delayed_days = np.random.choice(
        np.arange(1, 11),
        size=current_chunk,
        p=[
            0.25,
            0.20,
            0.15,
            0.12,
            0.09,
            0.07,
            0.05,
            0.04,
            0.02,
            0.01,
        ],
    )

    delayed_dates = (
        expected_dates
        + delayed_days.astype(
            "timedelta64[D]"
        )
    )

    actual_dates[delayed_mask] = (
        delayed_dates[delayed_mask]
    )


    # Pending shipments have no actual date.

    actual_dates[pending_mask] = (
        np.datetime64("NaT", "D")
    )


    # -----------------------------------------------------
    # Delay days
    # -----------------------------------------------------

    delay_days = np.zeros(
        current_chunk,
        dtype=np.int32,
    )

    delay_days[delayed_mask] = (
        delayed_days[delayed_mask]
    )

    delivered_difference = (
        actual_dates[delivered_mask]
        - expected_dates[delivered_mask]
    ) / np.timedelta64(1, "D")

    delay_days[delivered_mask] = np.maximum(
        delivered_difference.astype(np.int32),
        0,
    )


    # -----------------------------------------------------
    # Shipment quantity
    # -----------------------------------------------------

    quantity_values = np.arange(
        1,
        101,
    )

    quantity_weights = (
        1.0 / np.sqrt(quantity_values)
    )

    quantity_probabilities = (
        quantity_weights
        / quantity_weights.sum()
    )

    quantities = np.random.choice(
        quantity_values,
        size=current_chunk,
        p=quantity_probabilities,
    )


    # -----------------------------------------------------
    # Shipping cost
    # -----------------------------------------------------

    base_shipping_cost = (
        15.0
        + quantities * 1.25
        + selected_costs * quantities * 0.015
    )

    carrier_multiplier = np.random.uniform(
        0.85,
        1.35,
        current_chunk,
    )

    shipping_costs = np.round(
        base_shipping_cost
        * carrier_multiplier,
        2,
    )

    shipping_costs = np.maximum(
        shipping_costs,
        5.00,
    )


    # -----------------------------------------------------
    # Convert dates to Python dates
    # -----------------------------------------------------

    order_dates_db = pd.Series(
        order_dates
    ).dt.date

    ship_dates_db = pd.Series(
        ship_dates
    ).dt.date

    expected_dates_db = pd.Series(
        expected_dates
    ).dt.date

    actual_dates_db = pd.Series(
        actual_dates
    ).dt.date


    # -----------------------------------------------------
    # Build DataFrame
    # -----------------------------------------------------

    shipments_df = pd.DataFrame({
        "date_key": selected_date_keys,
        "product_key": selected_products,
        "customer_key": selected_customers,
        "warehouse_key": selected_warehouses,
        "carrier_key": selected_carriers,
        "quantity": quantities.astype(int),
        "shipping_cost": shipping_costs,
        "order_date": order_dates_db,
        "ship_date": ship_dates_db,
        "expected_delivery_date": expected_dates_db,
        "actual_delivery_date": actual_dates_db,
        "delay_days": delay_days,
        "delivery_status": delivery_status,
    })


    # -----------------------------------------------------
    # Insert
    # -----------------------------------------------------

    shipments_df.to_sql(
        "fact_shipments",
        engine,
        schema="supplyiq",
        if_exists="append",
        index=False,
        chunksize=5000,
        method="multi",
    )

    rows_generated += current_chunk

    print(
        f"Generated {rows_generated:,} / "
        f"{TOTAL_ROWS:,} rows "
        f"({rows_generated / TOTAL_ROWS:.0%})"
    )


# ---------------------------------------------------------
# Final validation
# ---------------------------------------------------------

print()
print("Shipment generation completed.")

with engine.connect() as conn:

    result = conn.execute(
        text("""
            SELECT
                COUNT(*) AS shipment_rows,
                MIN(shipping_cost) AS min_shipping_cost,
                MAX(shipping_cost) AS max_shipping_cost,
                SUM(shipping_cost) AS total_shipping_cost
            FROM supplyiq.fact_shipments
        """)
    ).fetchone()

    print()
    print("Shipment validation:")
    print(
        f"Rows:                {result.shipment_rows:,}"
    )
    print(
        f"Min shipping cost:   {result.min_shipping_cost}"
    )
    print(
        f"Max shipping cost:   {result.max_shipping_cost}"
    )
    print(
        f"Total shipping cost: {result.total_shipping_cost}"
    )