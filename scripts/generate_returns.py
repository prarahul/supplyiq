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

TOTAL_ROWS = 100_000
CHUNK_SIZE = 10_000
SEED = 46

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
            SELECT
                date_key,
                full_date
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
# Generate returns
# ---------------------------------------------------------

print()
print("Starting return generation...")
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
    # Select dimensions
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

    date_idx = np.random.randint(
        0,
        len(date_keys),
        current_chunk,
    )

    selected_products = product_keys[product_idx]

    selected_customers = customer_keys[customer_idx]

    selected_warehouses = warehouse_keys[warehouse_idx]

    selected_date_keys = date_keys[date_idx]

    selected_costs = product_costs[product_idx]


    # -----------------------------------------------------
    # Return quantity
    # -----------------------------------------------------

    quantity_values = np.arange(
        1,
        11,
    )

    quantity_weights = np.array([
        0.40,
        0.25,
        0.15,
        0.08,
        0.05,
        0.03,
        0.02,
        0.01,
        0.005,
        0.005,
    ])

    quantity_weights = (
        quantity_weights
        / quantity_weights.sum()
    )

    quantities = np.random.choice(
        quantity_values,
        size=current_chunk,
        p=quantity_weights,
    )


    # -----------------------------------------------------
    # Return reasons
    # -----------------------------------------------------

    return_reasons = np.array([
        "Damaged",
        "Wrong Item",
        "Customer Changed Mind",
        "Defective",
        "Late Delivery",
        "Incorrect Size",
        "Quality Issue",
        "Duplicate Order",
    ])

    return_reason_probabilities = np.array([
        0.18,
        0.14,
        0.20,
        0.16,
        0.08,
        0.10,
        0.09,
        0.05,
    ])

    return_reason_probabilities = (
        return_reason_probabilities
        / return_reason_probabilities.sum()
    )

    selected_reasons = np.random.choice(
        return_reasons,
        size=current_chunk,
        p=return_reason_probabilities,
    )


    # -----------------------------------------------------
    # Refund amount
    #
    # Refund is based on product cost plus a realistic
    # customer refund multiplier.
    # -----------------------------------------------------

    refund_multiplier = np.random.uniform(
        0.90,
        1.20,
        current_chunk,
    )

    refund_amounts = np.round(
        quantities
        * selected_costs
        * refund_multiplier,
        2,
    )

    refund_amounts = np.maximum(
        refund_amounts,
        0.01,
    )


    # -----------------------------------------------------
    # Build DataFrame
    # -----------------------------------------------------

    returns_df = pd.DataFrame({
        "date_key": selected_date_keys,
        "product_key": selected_products,
        "customer_key": selected_customers,
        "warehouse_key": selected_warehouses,
        "quantity": quantities.astype(int),
        "return_reason": selected_reasons,
        "refund_amount": refund_amounts,
    })


    # -----------------------------------------------------
    # Insert into PostgreSQL
    # -----------------------------------------------------

    returns_df.to_sql(
        "fact_returns",
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
print("Return generation completed.")

with engine.connect() as conn:

    result = conn.execute(
        text("""
            SELECT
                COUNT(*) AS return_rows,
                MIN(refund_amount) AS min_refund,
                MAX(refund_amount) AS max_refund,
                SUM(refund_amount) AS total_refund
            FROM supplyiq.fact_returns
        """)
    ).fetchone()

    print()
    print("Return validation:")
    print(
        f"Rows:          {result.return_rows:,}"
    )
    print(
        f"Min refund:    {result.min_refund}"
    )
    print(
        f"Max refund:    {result.max_refund}"
    )
    print(
        f"Total refund:  {result.total_refund}"
    )