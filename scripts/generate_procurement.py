from datetime import timedelta
import os

import numpy as np
import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import create_engine, text


# ============================================================
# CONFIGURATION
# ============================================================

SEED = 42

NUM_RECORDS = 500_000
CHUNK_SIZE = 50_000

load_dotenv()

DATABASE_URL = os.environ["DATABASE_URL"]

rng = np.random.default_rng(SEED)

engine = create_engine(
    DATABASE_URL,
    pool_pre_ping=True,
)


# ============================================================
# LOAD DIMENSION KEYS
# ============================================================

def load_dimension_keys():

    print("Loading dimension keys...")

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
                SELECT product_key, unit_cost
                FROM supplyiq.dim_product
                ORDER BY product_key;
                """
            ),
            connection,
        )

        suppliers = pd.read_sql(
            text(
                """
                SELECT supplier_key, quality_rating
                FROM supplyiq.dim_supplier
                ORDER BY supplier_key;
                """
            ),
            connection,
        )

        warehouses = pd.read_sql(
            text(
                """
                SELECT warehouse_key
                FROM supplyiq.dim_warehouse
                ORDER BY warehouse_key;
                """
            ),
            connection,
        )

    print(f"Dates:      {len(dates):,}")
    print(f"Products:   {len(products):,}")
    print(f"Suppliers:  {len(suppliers):,}")
    print(f"Warehouses: {len(warehouses):,}")

    return dates, products, suppliers, warehouses


# ============================================================
# GENERATE PROCUREMENT CHUNK
# ============================================================

def generate_chunk(
    dates,
    products,
    suppliers,
    warehouses,
    chunk_number,
):

    size = min(
        CHUNK_SIZE,
        NUM_RECORDS - chunk_number * CHUNK_SIZE,
    )

    # --------------------------------------------------------
    # Select dimension records
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

    supplier_indexes = rng.integers(
        0,
        len(suppliers),
        size=size,
    )

    warehouse_indexes = rng.integers(
        0,
        len(warehouses),
        size=size,
    )

    selected_dates = dates.iloc[date_indexes].reset_index(
        drop=True
    )

    selected_products = products.iloc[
        product_indexes
    ].reset_index(drop=True)

    selected_suppliers = suppliers.iloc[
        supplier_indexes
    ].reset_index(drop=True)

    selected_warehouses = warehouses.iloc[
        warehouse_indexes
    ].reset_index(drop=True)

    # --------------------------------------------------------
    # Procurement dates
    # --------------------------------------------------------

    procurement_dates = pd.to_datetime(
        selected_dates["full_date"]
    )

    # --------------------------------------------------------
    # Quantity
    # --------------------------------------------------------

    po_quantity = rng.integers(
        10,
        2_001,
        size=size,
    )

    # --------------------------------------------------------
    # Supplier quality affects procurement cost
    # --------------------------------------------------------

    base_cost = selected_products[
        "unit_cost"
    ].to_numpy()

    supplier_quality = selected_suppliers[
        "quality_rating"
    ].to_numpy()

    # Lower quality suppliers have slightly higher
    # procurement costs.
    quality_adjustment = (
        1.12
        - ((supplier_quality - 65) / 34) * 0.10
    )

    cost_noise = rng.uniform(
        0.97,
        1.03,
        size=size,
    )

    unit_cost = (
        base_cost
        * quality_adjustment
        * cost_noise
    )

    unit_cost = np.round(
        unit_cost,
        2,
    )

    procurement_value = np.round(
        po_quantity * unit_cost,
        2,
    )

    # --------------------------------------------------------
    # Expected delivery
    # --------------------------------------------------------

    lead_times = rng.integers(
        5,
        46,
        size=size,
    )

    expected_delivery_dates = (
        procurement_dates
        + pd.to_timedelta(
            lead_times,
            unit="D",
        )
    )

    # --------------------------------------------------------
    # Actual delivery
    #
    # Most procurement orders arrive.
    # Some arrive late.
    # A small percentage have no actual delivery yet.
    # --------------------------------------------------------

    delivery_status = rng.random(size)

    actual_delivery_dates = []

    for i in range(size):

        status = delivery_status[i]

        expected_date = (
            expected_delivery_dates.iloc[i]
        )

        if status < 0.96:

            # Delivered
            delay_days = rng.choice(
                [
                    0,
                    0,
                    0,
                    1,
                    1,
                    2,
                    3,
                    5,
                    7,
                    10,
                    14,
                ]
            )

            actual_date = (
                expected_date
                + timedelta(
                    days=int(delay_days)
                )
            )

            actual_delivery_dates.append(
                actual_date.date()
            )

        else:

            # Still pending
            actual_delivery_dates.append(
                None
            )

    # --------------------------------------------------------
    # Build dataframe
    # --------------------------------------------------------

    df = pd.DataFrame(
        {
            "date_key": selected_dates[
                "date_key"
            ].astype(int),

            "product_key": selected_products[
                "product_key"
            ].astype(int),

            "supplier_key": selected_suppliers[
                "supplier_key"
            ].astype(int),

            "warehouse_key": selected_warehouses[
                "warehouse_key"
            ].astype(int),

            "po_quantity": po_quantity.astype(int),

            "unit_cost": unit_cost,

            "procurement_value": procurement_value,

            "expected_delivery_date":
                expected_delivery_dates.dt.date,

            "actual_delivery_date":
                actual_delivery_dates,
        }
    )

    return df


# ============================================================
# LOAD CHUNK
# ============================================================

def load_chunk(df):

    df.to_sql(
        "fact_procurement",
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
    print("SupplyIQ 2.0 — Procurement Fact Generator")
    print("=" * 65)

    # --------------------------------------------------------
    # Validate connection
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
        suppliers,
        warehouses,
    ) = load_dimension_keys()

    print("\nGenerating procurement data...\n")

    # --------------------------------------------------------
    # Generate and load
    # --------------------------------------------------------

    total_chunks = (
        NUM_RECORDS + CHUNK_SIZE - 1
    ) // CHUNK_SIZE

    for chunk_number in range(total_chunks):

        start_record = (
            chunk_number * CHUNK_SIZE
        ) + 1

        end_record = min(
            (chunk_number + 1) * CHUNK_SIZE,
            NUM_RECORDS,
        )

        print(
            f"Chunk "
            f"{chunk_number + 1}/{total_chunks} "
            f"| Records "
            f"{start_record:,}–{end_record:,}"
        )

        df = generate_chunk(
            dates,
            products,
            suppliers,
            warehouses,
            chunk_number,
        )

        load_chunk(df)

        del df

    # --------------------------------------------------------
    # Verify
    # --------------------------------------------------------

    with engine.connect() as connection:

        count = connection.execute(
            text(
                """
                SELECT COUNT(*)
                FROM supplyiq.fact_procurement;
                """
            )
        ).scalar()

    print("\n" + "=" * 65)
    print("Procurement generation completed.")
    print(
        f"Rows in fact_procurement: {count:,}"
    )
    print("=" * 65)


if __name__ == "__main__":
    main()