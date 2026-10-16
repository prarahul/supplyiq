
from datetime import date

import os

import numpy as np
import pandas as pd
from dotenv import load_dotenv
from faker import Faker
from sqlalchemy import create_engine, text


# ============================================================
# CONFIGURATION
# ============================================================

SEED = 42

START_DATE = date(2020, 1, 1)
END_DATE = date(2029, 12, 31)

NUM_PRODUCTS = 2_000
NUM_SUPPLIERS = 500
NUM_CUSTOMERS = 10_000
NUM_WAREHOUSES = 100
NUM_CARRIERS = 50


# ============================================================
# ENVIRONMENT
# ============================================================

# Load variables from C:\Projects\supplyiq\.env
load_dotenv()

DATABASE_URL = os.environ["DATABASE_URL"]


# ============================================================
# RANDOM GENERATORS
# ============================================================

fake = Faker()

fake.seed_instance(SEED)

rng = np.random.default_rng(SEED)


# ============================================================
# DATABASE CONNECTION
# ============================================================

engine = create_engine(
    DATABASE_URL,
    pool_pre_ping=True,
)


# ============================================================
# DATE DIMENSION
# ============================================================

def generate_dates():
    print("Generating dim_date...")

    dates = pd.date_range(
        start=START_DATE,
        end=END_DATE,
        freq="D",
    )

    df = pd.DataFrame(
        {
            "date_key": dates.strftime("%Y%m%d").astype(int),
            "full_date": dates.date,
            "day": dates.day,
            "day_name": dates.day_name(),
            "week": dates.isocalendar().week.astype(int),
            "month": dates.month,
            "month_name": dates.month_name(),
            "quarter": dates.quarter,
            "year": dates.year,
            "is_weekend": dates.dayofweek >= 5,
        }
    )

    return df


# ============================================================
# PRODUCT DIMENSION
# ============================================================

def generate_products():
    print("Generating dim_product...")

    categories = {
        "Electronics": [
            "Laptops",
            "Smartphones",
            "Tablets",
            "Monitors",
            "Accessories",
        ],
        "Home Appliances": [
            "Refrigerators",
            "Washing Machines",
            "Microwaves",
            "Air Conditioners",
            "Vacuum Cleaners",
        ],
        "Industrial": [
            "Motors",
            "Pumps",
            "Sensors",
            "Controllers",
            "Industrial Tools",
        ],
        "Office": [
            "Printers",
            "Office Furniture",
            "Stationery",
            "Networking",
            "Storage",
        ],
        "Automotive": [
            "Engine Parts",
            "Brake Systems",
            "Filters",
            "Batteries",
            "Accessories",
        ],
    }

    brands = [
        "Apex",
        "Vertex",
        "Nova",
        "Orion",
        "Titan",
        "Prime",
        "Nexon",
        "Lumina",
        "Atlas",
        "Zenith",
        "Everest",
        "Matrix",
    ]

    rows = []

    category_names = list(categories.keys())

    for i in range(1, NUM_PRODUCTS + 1):

        category = rng.choice(category_names)

        sub_category = rng.choice(
            categories[category]
        )

        brand = rng.choice(brands)

        unit_cost = round(
            float(rng.uniform(10, 2500)),
            2,
        )

        markup = rng.uniform(1.15, 1.80)

        unit_price = round(
            unit_cost * markup,
            2,
        )

        rows.append(
            {
                "product_id": f"PRD-{i:06d}",
                "product_name": f"{brand} {sub_category} {i:04d}",
                "category": category,
                "sub_category": sub_category,
                "brand": brand,
                "unit_cost": unit_cost,
                "unit_price": unit_price,
                "weight_kg": round(
                    float(rng.uniform(0.1, 100)),
                    3,
                ),
                "status": "Active",
            }
        )

    return pd.DataFrame(rows)


# ============================================================
# SUPPLIER DIMENSION
# ============================================================

def generate_suppliers():
    print("Generating dim_supplier...")

    countries = [
        "India",
        "China",
        "United States",
        "Germany",
        "Japan",
        "South Korea",
        "Vietnam",
        "Singapore",
        "United Kingdom",
        "Netherlands",
        "France",
        "Italy",
        "Malaysia",
        "Thailand",
        "Mexico",
    ]

    regions = {
        "India": "South Asia",
        "China": "East Asia",
        "United States": "North America",
        "Germany": "Europe",
        "Japan": "East Asia",
        "South Korea": "East Asia",
        "Vietnam": "Southeast Asia",
        "Singapore": "Southeast Asia",
        "United Kingdom": "Europe",
        "Netherlands": "Europe",
        "France": "Europe",
        "Italy": "Europe",
        "Malaysia": "Southeast Asia",
        "Thailand": "Southeast Asia",
        "Mexico": "North America",
    }

    supplier_types = [
        "Manufacturer",
        "Distributor",
        "Wholesaler",
        "Specialty Supplier",
    ]

    rows = []

    for i in range(1, NUM_SUPPLIERS + 1):

        country = rng.choice(countries)

        rows.append(
            {
                "supplier_id": f"SUP-{i:05d}",
                "supplier_name": f"{fake.company()} Supply",
                "country": country,
                "region": regions[country],
                "supplier_type": rng.choice(
                    supplier_types
                ),
                "quality_rating": round(
                    float(rng.uniform(65, 99)),
                    2,
                ),
                "status": "Active",
            }
        )

    return pd.DataFrame(rows)


# ============================================================
# CUSTOMER DIMENSION
# ============================================================

def generate_customers():
    print("Generating dim_customer...")

    countries = [
        "India",
        "United States",
        "United Kingdom",
        "Germany",
        "France",
        "Canada",
        "Australia",
        "Singapore",
        "UAE",
        "Japan",
        "South Korea",
    ]

    segments = [
        "Enterprise",
        "SMB",
        "Consumer",
        "Wholesale",
        "Government",
    ]

    regions = {
        "India": "South Asia",
        "United States": "North America",
        "United Kingdom": "Europe",
        "Germany": "Europe",
        "France": "Europe",
        "Canada": "North America",
        "Australia": "Oceania",
        "Singapore": "Southeast Asia",
        "UAE": "Middle East",
        "Japan": "East Asia",
        "South Korea": "East Asia",
    }

    rows = []

    for i in range(1, NUM_CUSTOMERS + 1):

        country = rng.choice(countries)

        rows.append(
            {
                "customer_id": f"CUS-{i:07d}",
                "customer_name": fake.name(),
                "segment": rng.choice(segments),
                "country": country,
                "region": regions[country],
            }
        )

    return pd.DataFrame(rows)


# ============================================================
# WAREHOUSE DIMENSION
# ============================================================

def generate_warehouses():
    print("Generating dim_warehouse...")

    locations = [
        ("Mumbai", "India", "South Asia"),
        ("Delhi", "India", "South Asia"),
        ("Bengaluru", "India", "South Asia"),
        ("Chennai", "India", "South Asia"),
        ("Hyderabad", "India", "South Asia"),
        ("Pune", "India", "South Asia"),
        ("Singapore", "Singapore", "Southeast Asia"),
        ("Shanghai", "China", "East Asia"),
        ("Shenzhen", "China", "East Asia"),
        ("Tokyo", "Japan", "East Asia"),
        ("Seoul", "South Korea", "East Asia"),
        ("Dubai", "UAE", "Middle East"),
        ("London", "United Kingdom", "Europe"),
        ("Frankfurt", "Germany", "Europe"),
        ("Paris", "France", "Europe"),
        ("Amsterdam", "Netherlands", "Europe"),
        ("New York", "United States", "North America"),
        ("Chicago", "United States", "North America"),
        ("Los Angeles", "United States", "North America"),
        ("Toronto", "Canada", "North America"),
        ("Sydney", "Australia", "Oceania"),
    ]

    warehouse_types = [
        "Distribution Center",
        "Fulfillment Center",
        "Regional Hub",
        "Cold Storage",
        "Cross Dock",
    ]

    rows = []

    for i in range(1, NUM_WAREHOUSES + 1):

        city, country, region = locations[
            rng.integers(
                0,
                len(locations),
            )
        ]

        rows.append(
            {
                "warehouse_id": f"WH-{i:04d}",
                "warehouse_name": (
                    f"{city} "
                    f"{rng.choice(warehouse_types)} "
                    f"{i:03d}"
                ),
                "city": city,
                "country": country,
                "region": region,
                "warehouse_type": rng.choice(
                    warehouse_types
                ),
                "capacity_units": int(
                    rng.integers(
                        25_000,
                        500_000,
                    )
                ),
            }
        )

    return pd.DataFrame(rows)


# ============================================================
# CARRIER DIMENSION
# ============================================================

def generate_carriers():
    print("Generating dim_carrier...")

    carrier_types = [
        "Air",
        "Ocean",
        "Road",
        "Rail",
        "Express",
    ]

    service_levels = [
        "Standard",
        "Priority",
        "Express",
        "Economy",
    ]

    rows = []

    for i in range(1, NUM_CARRIERS + 1):

        rows.append(
            {
                "carrier_id": f"CAR-{i:04d}",
                "carrier_name": (
                    f"{fake.company()} Logistics"
                ),
                "carrier_type": rng.choice(
                    carrier_types
                ),
                "service_level": rng.choice(
                    service_levels
                ),
            }
        )

    return pd.DataFrame(rows)


# ============================================================
# DATABASE INSERTION
# ============================================================

def load_dataframe(df, table_name):

    print(
        f"Loading {table_name}: "
        f"{len(df):,} rows"
    )

    df.to_sql(
        table_name,
        engine,
        schema="supplyiq",
        if_exists="append",
        index=False,
        chunksize=5_000,
        method="multi",
    )


# ============================================================
# VALIDATE DATABASE CONNECTION
# ============================================================

def validate_connection():

    print("\nTesting PostgreSQL connection...")

    with engine.connect() as connection:

        result = connection.execute(
            text(
                """
                SELECT
                    current_database(),
                    current_user,
                    current_schema();
                """
            )
        ).fetchone()

    print(
        f"Database: {result[0]}"
    )

    print(
        f"User: {result[1]}"
    )

    print(
        f"Schema: {result[2]}"
    )

    print("PostgreSQL connection: OK")


# ============================================================
# MAIN
# ============================================================

def main():

    print("=" * 60)
    print(
        "SupplyIQ 2.0 — Dimension Data Generator"
    )
    print("=" * 60)

    # Verify database before generating data.
    validate_connection()

    # Generate dimensions.
    dimensions = {
        "dim_date": generate_dates(),
        "dim_product": generate_products(),
        "dim_supplier": generate_suppliers(),
        "dim_customer": generate_customers(),
        "dim_warehouse": generate_warehouses(),
        "dim_carrier": generate_carriers(),
    }

    # Load dimensions.
    for table_name, df in dimensions.items():

        load_dataframe(
            df,
            table_name,
        )

    print(
        "\nDimension generation completed successfully."
    )

    # Verify row counts.
    with engine.connect() as connection:

        result = connection.execute(
            text(
                """
                SELECT
                    table_name,
                    (
                        xpath(
                            '/row/count/text()',
                            query_to_xml(
                                format(
                                    'SELECT COUNT(*) AS count FROM supplyiq.%I',
                                    table_name
                                ),
                                false,
                                true,
                                ''
                            )
                        )
                    )[1]::text::bigint AS row_count
                FROM (
                    VALUES
                        ('dim_date'),
                        ('dim_product'),
                        ('dim_supplier'),
                        ('dim_customer'),
                        ('dim_warehouse'),
                        ('dim_carrier')
                ) AS tables(table_name)
                ORDER BY table_name;
                """
            )
        )

        print("\nDimension table row counts:")

        for row in result:

            print(
                f"{row.table_name}: "
                f"{row.row_count:,}"
            )


# ============================================================
# ENTRY POINT
# ============================================================

if __name__ == "__main__":
    main()
