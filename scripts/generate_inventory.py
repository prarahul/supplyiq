from datetime import date

import os

import numpy as np
import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import create_engine, text


# ============================================================
# CONFIGURATION
# ============================================================

SEED = 43

NUM_RECORDS = 2_000_000
CHUNK_SIZE = 50_000

load_dotenv()

DATABASE_URL = os.environ["DATABASE_URL"]

rng = np.random.default_rng(SEED)

engine = create_engine(
    DATABASE_URL,
    pool_pre_ping=True,
)


# ============================================================
# LOAD DIMENSION DATA
# ============================================================

def load_dimension_data():

    print("Loading dimension data...")

    with engine.connect() as connection:

        dates = pd.read_sql(
            text(
                """
                SELECT date_key, full_date
                FROM supplyiq.dim_date
                ORDER BY date_key;
                """
            ),
            connection,
        )

        products = pd.read_sql(
            text(
                """
                SELECT
                    product_key,
                    unit_cost
                FROM supplyiq.dim_product
                ORDER BY product_key;
                """
            ),
            connection,
        )

        warehouses = pd.read_sql(
            text(
                """
                SELECT
                    warehouse_key,
                    capacity_units
                FROM supplyiq.dim_warehouse
                ORDER BY warehouse_key;
                """
            ),
            connection,
        )

    print(f"Dates:      {len(dates):,}")
    print(f"Products:   {len(products):,}")
    print(f"Warehouses: {len(warehouses):,}")

    return dates, products, warehouses


# ============================================================
# GENERATE INVENTORY CHUNK
# ============================================================

def generate_chunk(
    dates,
    products,
    warehouses,
    chunk_number,
):

    remaining = (
        NUM_RECORDS
        - chunk_number * CHUNK_SIZE
    )

    size = min(
        CHUNK_SIZE,
        remaining,
    )

    # --------------------------------------------------------
    # Select dimension keys
    # --------------------------------------------------------

    date_indexes = rng.integers(
        0,
        len(dates),
        size=size,
    )

    product_indexes = rng.integers(
        0,
        len(products),
        size=size,
    )

    warehouse_indexes = rng.integers(
        0,
        len(warehouses),
        size=size,
    )

    selected_dates = dates.iloc[
        date_indexes
    ].reset_index(drop=True)

    selected_products = products.iloc[
        product_indexes
    ].reset_index(drop=True)

    selected_warehouses = warehouses.iloc[
        warehouse_indexes
    ].reset_index(drop=True)

    # --------------------------------------------------------
    # Warehouse capacity
    # --------------------------------------------------------

    capacity = (
        selected_warehouses[
            "capacity_units"
        ]
        .to_numpy()
    )

    # --------------------------------------------------------
    # Opening stock
    #
    # Keep stock below warehouse capacity.
    # --------------------------------------------------------

    capacity_factor = rng.uniform(
        0.05,
        0.45,
        size=size,
    )

    opening_stock = (
        capacity
        * capacity_factor
    ).astype(int)

    opening_stock = np.maximum(
        opening_stock,
        1,
    )

    # --------------------------------------------------------
    # Received quantity
    #
    # Procurement replenishment events.
    # --------------------------------------------------------

    receipt_probability = rng.random(
        size
    )

    received_quantity = np.where(
        receipt_probability < 0.75,
        rng.integers(
            0,
            501,
            size=size,
        ),
        rng.integers(
            500,
            2_001,
            size=size,
        ),
    )

    received_quantity = (
        received_quantity.astype(int)
    )

    # --------------------------------------------------------
    # Demand / sold quantity
    #
    # Generate demand as a fraction of available stock.
    # --------------------------------------------------------

    demand_rate = rng.uniform(
        0.01,
        0.30,
        size=size,
    )

    demand_noise = rng.uniform(
        0.70,
        1.30,
        size=size,
    )

    raw_demand = (
        opening_stock
        * demand_rate
        * demand_noise
    )

    sold_quantity = (
        raw_demand.astype(int)
    )

    # --------------------------------------------------------
    # Some high-demand inventory movements
    # --------------------------------------------------------

    high_demand_mask = (
        rng.random(size) < 0.08
    )

    high_demand = (
        opening_stock
        * rng.uniform(
            0.30,
            0.80,
            size=size,
        )
    ).astype(int)

    sold_quantity = np.where(
        high_demand_mask,
        np.maximum(
            sold_quantity,
            high_demand,
        ),
        sold_quantity,
    )

    # Never sell more than available stock.
    sold_quantity = np.minimum(
        sold_quantity,
        opening_stock
        + received_quantity,
    )

    sold_quantity = np.maximum(
        sold_quantity,
        0,
    ).astype(int)

    # --------------------------------------------------------
    # Closing stock
    # --------------------------------------------------------

    closing_stock = (
        opening_stock
        + received_quantity
        - sold_quantity
    )

    closing_stock = np.maximum(
        closing_stock,
        0,
    ).astype(int)

    # --------------------------------------------------------
    # Inventory value
    #
    # Value is based on closing stock × product cost.
    # --------------------------------------------------------

    unit_cost = (
        selected_products[
            "unit_cost"
        ]
        .to_numpy()
    )

    inventory_value = np.round(
        closing_stock * unit_cost,
        2,
    )

    # --------------------------------------------------------
    # Build DataFrame
    # --------------------------------------------------------

    df = pd.DataFrame(
        {
            "date_key": selected_dates[
                "date_key"
            ].astype(int),

            "product_key": selected_products[
                "product_key"
            ].astype(int),

            "warehouse_key": selected_warehouses[
                "warehouse_key"
            ].astype(int),

            "opening_stock": opening_stock,

            "received_quantity": received_quantity,

            "sold_quantity": sold_quantity,

            "closing_stock": closing_stock,

            "inventory_value": inventory_value,
        }
    )

    return df


# ============================================================
# LOAD CHUNK
# ============================================================

def load_chunk(df):

    df.to_sql(
        "fact_inventory",
        engine,
        schema="supplyiq",
        if_exists="append",
        index=False,
        chunksize=5_000,
        method="multi",
    )


# ============================================================
# MAIN
# ============================================================

def main():

    print("=" * 65)
    print(
        "SupplyIQ 2.0 — Inventory Fact Generator"
    )
    print("=" * 65)

    # --------------------------------------------------------
    # Validate database connection
    # --------------------------------------------------------

    with engine.connect() as connection:

        result = connection.execute(
            text(
                """
                SELECT
                    current_database(),
                    current_user;
                """
            )
        ).fetchone()

    print(
        f"Database: {result[0]}"
    )

    print(
        f"User:     {result[1]}"
    )

    print(
        f"Target records: {NUM_RECORDS:,}"
    )

    print(
        f"Chunk size:     {CHUNK_SIZE:,}"
    )

    # --------------------------------------------------------
    # Load dimensions
    # --------------------------------------------------------

    (
        dates,
        products,
        warehouses,
    ) = load_dimension_data()

    print(
        "\nGenerating inventory data...\n"
    )

    # --------------------------------------------------------
    # Generate chunks
    # --------------------------------------------------------

    total_chunks = (
        NUM_RECORDS
        + CHUNK_SIZE
        - 1
    ) // CHUNK_SIZE

    for chunk_number in range(
        total_chunks
    ):

        start_record = (
            chunk_number
            * CHUNK_SIZE
        ) + 1

        end_record = min(
            (chunk_number + 1)
            * CHUNK_SIZE,
            NUM_RECORDS,
        )

        print(
            f"Chunk "
            f"{chunk_number + 1}/"
            f"{total_chunks} "
            f"| Records "
            f"{start_record:,}–"
            f"{end_record:,}"
        )

        df = generate_chunk(
            dates,
            products,
            warehouses,
            chunk_number,
        )

        load_chunk(df)

        del df

    # --------------------------------------------------------
    # Verify final row count
    # --------------------------------------------------------

    with engine.connect() as connection:

        count = connection.execute(
            text(
                """
                SELECT COUNT(*)
                FROM supplyiq.fact_inventory;
                """
            )
        ).scalar()

    print("\n" + "=" * 65)

    print(
        "Inventory generation completed."
    )

    print(
        f"Rows in fact_inventory: "
        f"{count:,}"
    )

    print("=" * 65)


# ============================================================
# ENTRY POINT
# ============================================================

if __name__ == "__main__":
    main()