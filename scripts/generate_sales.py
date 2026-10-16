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
SEED = 44

random.seed(SEED)
np.random.seed(SEED)


# ---------------------------------------------------------
# Database connection
# ---------------------------------------------------------

engine = create_engine(
    DATABASE_URL,
    pool_pre_ping=True,
)


# ---------------------------------------------------------
# Load dimension data
# ---------------------------------------------------------

print("Loading dimension data...")

with engine.connect() as conn:
    products = pd.read_sql(
        text("""
            SELECT
                product_key,
                unit_cost
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
print(f"Dates loaded:      {len(dates):,}")


# ---------------------------------------------------------
# Prepare arrays
# ---------------------------------------------------------

product_keys = products["product_key"].to_numpy()
product_costs = products["unit_cost"].astype(float).to_numpy()

customer_keys = customers["customer_key"].to_numpy()
warehouse_keys = warehouses["warehouse_key"].to_numpy()

date_keys = dates["date_key"].to_numpy()


# ---------------------------------------------------------
# Generate sales
# ---------------------------------------------------------

print()
print("Starting sales generation...")
print(f"Target rows: {TOTAL_ROWS:,}")
print(f"Chunk size:  {CHUNK_SIZE:,}")
print()

rows_generated = 0

while rows_generated < TOTAL_ROWS:

    current_chunk = min(
        CHUNK_SIZE,
        TOTAL_ROWS - rows_generated,
    )

    # -----------------------------
    # Random dimension selection
    # -----------------------------

    selected_product_idx = np.random.randint(
        0,
        len(product_keys),
        current_chunk,
    )

    selected_customer_idx = np.random.randint(
        0,
        len(customer_keys),
        current_chunk,
    )

    selected_warehouse_idx = np.random.randint(
        0,
        len(warehouse_keys),
        current_chunk,
    )

    selected_date_idx = np.random.randint(
        0,
        len(date_keys),
        current_chunk,
    )

    selected_products = product_keys[selected_product_idx]

    selected_customers = customer_keys[selected_customer_idx]

    selected_warehouses = warehouse_keys[selected_warehouse_idx]

    selected_dates = date_keys[selected_date_idx]

    selected_costs = product_costs[selected_product_idx]


    # -----------------------------
    # Quantity
    # -----------------------------
         # -----------------------------
    # Quantity
    # -----------------------------

    quantity_values = np.arange(1, 21)

    quantity_probabilities = np.array([
        0.20,
        0.15,
        0.12,
        0.10,
        0.08,
        0.07,
        0.06,
        0.05,
        0.04,
        0.03,
        0.02,
        0.02,
        0.01,
        0.01,
        0.01,
        0.01,
        0.005,
        0.005,
        0.00125,
        0.00125,
    ])

    quantity_probabilities = (
        quantity_probabilities
        / quantity_probabilities.sum()
    )

    quantities = np.random.choice(
        quantity_values,
        size=current_chunk,
        p=quantity_probabilities,
    )
        
    # -----------------------------
    # Selling price
    # -----------------------------

    price_multiplier = np.random.uniform(
        1.15,
        2.20,
        current_chunk,
    )

    unit_prices = selected_costs * price_multiplier

    unit_prices = np.round(
        unit_prices,
        2,
    )

    unit_prices = np.maximum(
        unit_prices,
        1.00,
    )


    # -----------------------------
    # Revenue before discount
    # -----------------------------

    gross_revenue = quantities * unit_prices


    # -----------------------------
    # Discount
    # -----------------------------

    discount_rates = np.random.choice(
        np.array([
            0.00,
            0.02,
            0.05,
            0.10,
            0.15,
            0.20,
        ]),
        size=current_chunk,
        p=np.array([
            0.45,
            0.10,
            0.20,
            0.15,
            0.07,
            0.03,
        ]),
    )

    discounts = np.round(
        gross_revenue * discount_rates,
        2,
    )


    # -----------------------------
    # Net revenue
    # -----------------------------

    revenues = np.round(
        gross_revenue - discounts,
        2,
    )


    # -----------------------------
    # Cost
    # -----------------------------

    costs = np.round(
        quantities * selected_costs,
        2,
    )


    # -----------------------------
    # Profit
    # -----------------------------

    profits = np.round(
        revenues - costs,
        2,
    )


    # -----------------------------
    # Build DataFrame
    # -----------------------------

    sales_df = pd.DataFrame({
        "date_key": selected_dates,
        "product_key": selected_products,
        "customer_key": selected_customers,
        "warehouse_key": selected_warehouses,
        "quantity": quantities.astype(int),
        "unit_price": unit_prices,
        "revenue": revenues,
        "discount": discounts,
        "cost": costs,
        "profit": profits,
    })


    # -----------------------------
    # Insert into PostgreSQL
    # -----------------------------

    sales_df.to_sql(
        "fact_sales",
        engine,
        schema="supplyiq",
        if_exists="append",
        index=False,
        chunksize=5000,
        method="multi",
    )

    rows_generated += current_chunk

    print(
        f"Generated {rows_generated:,} / {TOTAL_ROWS:,} rows "
        f"({rows_generated / TOTAL_ROWS:.0%})"
    )


# ---------------------------------------------------------
# Validation
# ---------------------------------------------------------

print()
print("Sales generation completed.")

with engine.connect() as conn:

    result = conn.execute(
        text("""
            SELECT
                COUNT(*) AS sales_rows,
                MIN(revenue) AS min_revenue,
                MAX(revenue) AS max_revenue,
                SUM(revenue) AS total_revenue,
                SUM(profit) AS total_profit
            FROM supplyiq.fact_sales
        """)
    ).fetchone()

    print()
    print("Sales validation:")
    print(f"Rows:          {result.sales_rows:,}")
    print(f"Min revenue:   {result.min_revenue}")
    print(f"Max revenue:   {result.max_revenue}")
    print(f"Total revenue: {result.total_revenue}")
    print(f"Total profit:  {result.total_profit}")