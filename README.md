# SupplyIQ 2.0 — Supply Chain Analytics Platform

SupplyIQ 2.0 is a supply chain analytics project that brings together sales, inventory, procurement, shipments, and returns data in PostgreSQL for KPI reporting and business analysis. The project includes Python data-generation scripts, SQL analytical views, Docker-based database setup, and a Power BI executive dashboard.

> **Project status:** The PostgreSQL schema and analytical SQL layer have been developed. The Power BI dashboard is part of the project; verify its visuals and interactions before describing it as production-ready.

## Key Features

- **Supply chain data model:** Dimension tables for dates, products, suppliers, customers, warehouses, and carriers.
- **Fact tables:** Sales, inventory, procurement, shipments, and returns.
- **Analytical SQL:** Executive KPIs and domain-specific views for sales, inventory, procurement, logistics, supplier performance, customer analytics, and supply-chain risk.
- **Data generation:** Python scripts to generate sample dimension and fact data.
- **Containerized database:** PostgreSQL managed through Docker Compose.
- **Reporting:** Power BI executive dashboard for KPI and monthly performance analysis.

## Tech Stack

- **Database:** PostgreSQL
- **Languages:** SQL, Python
- **Data tooling:** pandas, SQLAlchemy, NumPy, Faker, `uv`
- **Containers:** Docker, Docker Compose
- **BI / Visualization:** Microsoft Power BI

## Data Model

The project uses a dimensional model with these tables:

### Dimensions
- `dim_date`
- `dim_product`
- `dim_supplier`
- `dim_customer`
- `dim_warehouse`
- `dim_carrier`

### Fact tables
- `fact_sales`
- `fact_inventory`
- `fact_procurement`
- `fact_shipments`
- `fact_returns`

The project dataset was designed to contain approximately **4.6 million fact records** across the five fact tables. Actual row counts depend on the data-generation scripts and the state of your local database.

## Analytics

The SQL layer includes scripts covering:

| File | Focus |
|---|---|
| `sql/01_executive_kpis.sql` | Executive KPIs |
| `sql/02_sales_demand.sql` | Sales and demand analysis |
| `sql/03_inventory.sql` | Inventory health |
| `sql/04_procurement.sql` | Procurement analytics |
| `sql/05_logistics.sql` | Shipment and delivery performance |
| `sql/06_supplier_performance.sql` | Supplier performance |
| `sql/07_customer_analytics.sql` | Customer analytics |
| `sql/08_supply_chain_risk.sql` | Supply-chain risk |
| `sql/fix_monthly_executive_performance_test.sql` | Monthly executive performance view fix/test |

Analytical outputs are intended to help explore revenue, profit, profit margin, inventory value and stock levels, procurement spend, delivery performance, returns, and supplier/customer performance.

## Repository Structure

```text
supplyiq/
├── database/
│   └── schema.sql
├── powerbi/
│   └── SupplyIQ_Executive_Dashboard.pbix
├── scripts/
│   ├── generate_dimensions.py
│   ├── generate_sales.py
│   ├── generate_inventory.py
│   ├── generate_procurement.py
│   ├── generate_shipments.py
│   └── generate_returns.py
├── sql/
│   ├── 01_executive_kpis.sql
│   ├── 02_sales_demand.sql
│   ├── 03_inventory.sql
│   ├── 04_procurement.sql
│   ├── 05_logistics.sql
│   ├── 06_supplier_performance.sql
│   ├── 07_customer_analytics.sql
│   ├── 08_supply_chain_risk.sql
│   └── fix_monthly_executive_performance_test.sql
├── src/
│   └── supplyiq/
├── .env.example
├── docker-compose.yml
├── pyproject.toml
├── uv.lock
└── README.md
```

## Getting Started

### Prerequisites

Install:
- Git
- Docker Desktop with Docker Compose
- Python version compatible with `.python-version` / `pyproject.toml`
- `uv` (recommended, if the project is configured to use it)
- Power BI Desktop, if you want to open the report

### 1. Clone the repository

```bash
git clone https://github.com/prarahul/supplyiq.git
cd supplyiq
```

### 2. Configure environment variables

Create a local `.env` file from the example:

**PowerShell**
```powershell
Copy-Item .env.example .env
```

Open `.env` and configure the database values to match `docker-compose.yml`. Do not commit `.env` or real credentials.

The SQLAlchemy connection URL typically follows this format:

```text
postgresql+psycopg2://<username>:<password>@127.0.0.1:<host-port>/<database>
```

Use the actual host port configured in `docker-compose.yml`. Do not assume the example values in this README override your local configuration.

### 3. Start PostgreSQL

```bash
docker compose up -d
```

Check that the container is running:

```bash
docker compose ps
```

### 4. Create the database schema

The exact command depends on the database name, username, and container configuration in your `docker-compose.yml`. One common pattern is:

```bash
docker exec -i supplyiq-postgres psql -U supplyiq_user -d supplyiq < database/schema.sql
```

If your container name or credentials differ, adjust the command accordingly.

### 5. Install Python dependencies

If the project uses `uv`:

```bash
uv sync
```

Review `.python-version` and `pyproject.toml` for the expected Python version before running scripts.

### 6. Generate data

Run the scripts from the project root, in the order appropriate for the schema and foreign-key dependencies. A typical sequence is:

```bash
uv run python scripts/generate_dimensions.py
uv run python scripts/generate_sales.py
uv run python scripts/generate_inventory.py
uv run python scripts/generate_procurement.py
uv run python scripts/generate_shipments.py
uv run python scripts/generate_returns.py
```

**Important:** Check the current row counts before running these scripts against an already populated database. The scripts may append records, so rerunning them could create duplicate or additional data. Back up valuable data first.

### 7. Create analytical views

Run the SQL files in `sql/` against the `supplyiq` schema. Execute the schema and foundational SQL scripts in the required order, and inspect each script before running it. The monthly executive performance test/fix script is separate and should be applied only after reviewing its contents and dependencies.

### 8. Open the Power BI report

Open `powerbi/SupplyIQ_Executive_Dashboard.pbix` in Power BI Desktop. Configure the PostgreSQL connection to match your local database settings and refresh the data as needed.

## Security Notes

- Never commit `.env`, passwords, access tokens, or production credentials.
- Keep `.env.example` limited to placeholder values.
- Review `git status` and staged files before each commit.
- Do not publish private or sensitive data in database exports or reports.
- A public repository makes committed files accessible to others. Removing a secret in a later commit does not erase it from Git history.

## Current Scope and Future Improvements

Potential next steps include:
- Complete and validate the executive dashboard layout and slicer interactions.
- Add automated data-quality checks and repeatable validation queries.
- Document KPI definitions and business assumptions.
- Add tests and a reproducible setup workflow.
- Add screenshots or a dashboard preview after the report is finalized.

## Author

**Rahul Kumar**

GitHub: [@prarahul](https://github.com/prarahul)

---

This project is intended as a portfolio project demonstrating supply chain data modeling, SQL analytics, Python-based data preparation, containerized PostgreSQL, and BI reporting.
