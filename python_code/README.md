# Automated Data Pipeline — Sample Project

This folder contains a **sample implementation** of the automated data pipeline described in [projectplan.md](./projectplan.md) and [devplan-and-technical-requirements.md](./devplan-and-technical-requirements.md). It implements all four steps (Data Pull → Extract → Transform → Migrate), control tables, a local orchestrator, a scraper (HTTP API + Playwright), and a Web GUI to view runs and step status.

## What’s Included

| Component | Location | Purpose |
|-----------|----------|---------|
| **SQL Server scripts** | `database/sqlserver/` | Control tables (`PipelineRuns`, `StepRuns`), landing/staging/target tables, and SPs: `usp_Extract_Orders`, `usp_Transform_Orders`, `usp_Migrate_Orders` |
| **SQLite schema** | `database/sqlite_schema.sql` | Same structure for local demo (orchestrator + API use SQLite when no SQL Server) |
| **Sample data** | `data/landing/` | `sample_orders.csv`, `sample_orders.json`, `sample_orders_trigger.csv`, `sample_orders_20k.csv`, `sample_orders_100k.csv`, `sample_orders_10k.json` (10k records) for Data Pull / trigger |
| **Orchestrator** | `orchestrator/` | Runs the 4-step pipeline: Data Pull (CSV/JSON) → Extract → Transform → Migrate; writes to control tables |
| **Scraper** | `scraper/` | HTTP API + Playwright for headless Chrome (simulates Azure VM scraper). `POST /scrape` with `{ url, selectors }` |
| **API** | `api/` | `GET /runs`, `GET /runs/:runId` for the Web GUI (reads `PipelineRuns` + `StepRuns`) |
| **Web GUI** | `web/` | Run list and run detail with **4-step strip** (Data Pull, Extract, Transform, Migrate) and status/duration/rows |

## Quick Start (Local Demo with SQLite)

**Requirements:** Node.js 18+; for SQLite, `better-sqlite3` needs a C++ build (Python + build-essential on Linux). If `npm install` fails for `better-sqlite3`, install system deps (e.g. `build-essential`) or use Docker.

1. **Create DB and schema**
   ```bash
   cd orchestrator && npm install && npm run init-db && cd ..
   ```

2. **Run a pipeline** (creates one run and executes all 4 steps)
   ```bash
   cd orchestrator && npm run pipeline && cd ..
   ```
   To run with a specific CSV (or JSON) file:
   ```bash
   cd orchestrator && node index.js /path/to/your/file.csv && cd ..
   ```
   Or use the default sample: `SOURCE_FILE=sample_orders_trigger.csv npm run pipeline`

3. **Start the API**
   ```bash
   cd api && npm install && npm start
   ```
   (Leave running; default port 3000.)

4. **Start the Web GUI**
   ```bash
   cd web && npm install && npm run dev
   ```
   Open http://localhost:5173 — you should see the run list and can open a run to see the 4 steps. You can **trigger a pipeline** by uploading a CSV or JSON file in the "Trigger pipeline with CSV or JSON" box; the file must have columns `OrderId`, `CustomerId`, `Amount`, `OrderDate`. Sample files: `data/landing/sample_orders.csv`, `data/landing/sample_orders_trigger.csv`.

5. **Optional: Scraper** (for headless Chrome / scraping)
   ```bash
   cd scraper && npm install && npm start
   ```
   Then `POST http://localhost:3080/scrape` with body: `{ "url": "https://example.com", "selectors": { "title": "h1" } }`.

**One-command run:** From the `AutomatedDataPipeline` folder you can run `./run-all.sh` to install, init DB, and start API + Web + Scraper (it does **not** run a pipeline automatically; trigger one via the Web GUI or CLI). To stop all services, run `./kill-all.sh`. If `run-all.sh` fails (e.g. during `npm install` for the orchestrator), start the Web GUI and API separately with:
```bash
./start-web.sh
```
Then open **http://localhost:5173** (or the “Network” URL Vite prints, e.g. http://192.168.1.x:5173, if you’re on another machine).

## Using SQL Server Instead of SQLite

1. Create a staging database and run the scripts in order:
   - `database/sqlserver/001_control_tables.sql`
   - `database/sqlserver/002_landing_staging_target.sql`
   - `database/sqlserver/003_sp_extract.sql`
   - `database/sqlserver/004_sp_transform.sql`
   - `database/sqlserver/005_sp_migrate.sql`

2. Point the orchestrator and API at SQL Server by setting a connection string (and use a driver that supports executing the SPs). The sample orchestrator currently uses **SQLite** only; for SQL Server you would replace the orchestrator’s `db.js` and step logic with a SQL Server client and call the stored procedures for steps 2–4.

## Pipeline Flow (Sample)

1. **Data Pull (Step 1)** — Orchestrator reads `data/landing/sample_orders.csv` (or `.json`) and inserts into `Landing_Orders`. In production, ADF would do this (Copy from Blob, REST, etc.) or call the scraper VM.
2. **Extract (Step 2)** — Normalize from landing to `Staging_Orders` (in sample: JS in orchestrator; in production: `dbo.usp_Extract_Orders @RunId`).
3. **Transform (Step 3)** — Apply rules (e.g. `AmountCategory`: Low/Medium/High) into `Staging_Orders_Transformed` (in production: `dbo.usp_Transform_Orders @RunId`).
4. **Migrate (Step 4)** — Load into `Target_Orders` (in production: `dbo.usp_Migrate_Orders @RunId`).

Each step updates `StepRuns` (StartedAt, FinishedAt, Status, RowsAffected, ErrorMessage). The Web GUI reads `PipelineRuns` and `StepRuns` to show the 4-step strip.

## Triggering the pipeline with your own CSV

- **Web GUI:** On the run list page, use "Trigger pipeline with CSV or JSON": choose a file (CSV or JSON) and click "Run pipeline". You are redirected to the new run’s detail page.
- **API:** `POST /pipeline/trigger` with form field `file` (multipart/form-data). Example:
  ```bash
  curl -X POST -F "file=@/path/to/orders.csv" http://localhost:3000/pipeline/trigger
  ```
  Response: `{ "runId": "...", "message": "Pipeline started", "file": "upload_..." }`.
- **CLI:** Run the orchestrator with a file path:
  ```bash
  cd orchestrator && node index.js /path/to/orders.csv
  ```
- **CSV format:** Header row with columns `OrderId`, `CustomerId`, `Amount`, `OrderDate` (case-insensitive). Sample files: `data/landing/sample_orders.csv`, `sample_orders_trigger.csv`, `sample_orders_20k.csv`, `sample_orders_100k.csv`. Regenerate: `node scripts/generate-large-csv.mjs [rows]`.
- **JSON format:** Array of objects with `OrderId`, `CustomerId`, `Amount`, `OrderDate`. Sample: `data/landing/sample_orders_10k.json` (10k records). Regenerate: `node scripts/generate-large-json.mjs [rows]` (e.g. `node scripts/generate-large-json.mjs 10000`).

## Logging

Pipeline runs write log entries to the **PipelineLogs** table (Info, Warning, Error) for pipeline start, each step start/end, row counts, and failures. The Web GUI shows:

- **Run detail page** — A "Logs" section with all log entries for that run (chronological).
- **All logs** — Header link **"All logs"** (`/logs`) shows recent logs across all pipelines, with filters by level and limit.

API: `GET /runs/:runId/logs` returns logs for one run; `GET /logs?level=Error&limit=200` returns recent logs (optional `runId`, `pipeline`, `level`, `limit`). If you had an existing DB before this feature, run `npm run init-db` in the orchestrator once to create the `PipelineLogs` table.

## Troubleshooting

- **localhost:5173 refused to connect**  
  - If you used `run-all.sh`, it may have exited before starting the web app (e.g. `npm install` failed in the orchestrator). Run **`./start-web.sh`** to start only the API and Web GUI.  
  - If you use a different machine or a VM (e.g. WSL, Docker), open the **Network** URL Vite prints (e.g. `http://192.168.x.x:5173`) instead of `http://localhost:5173`.  
  - Ensure nothing else is using port 5173, or let Vite use another port (it will print the URL).

- **Web GUI loads but shows “No runs”**  
  Run the pipeline once so the DB has data: `cd orchestrator && npm run init-db && npm run pipeline`. Then ensure the API is running (port 3000) and refresh the page.

- **API proxy error / ECONNREFUSED 127.0.0.1:3000**  
  The Web GUI proxies `/api` to the API. Start the API first (`cd api && npm start`) or use `./start-web.sh`, which starts both API and Web.

## Environment Variables

| Variable | Used by | Description |
|---------|--------|-------------|
| `DB_PATH` | orchestrator, api | Path to SQLite file (default: `data/pipeline.sqlite`) |
| `PIPELINE_NAME` | orchestrator | Pipeline name (default: `SamplePipeline`) |
| `SOURCE_FILE` | orchestrator | Landing file name (default: `sample_orders.csv`) |
| `LANDING_DATA_DIR` | orchestrator | Directory for CSV/JSON (default: `data/landing`) |
| `API_PORT` | api | Port for API (default: 3000) |
| `SCRAPER_PORT` | scraper | Port for scraper API (default: 3080) |
| `VITE_API_URL` | web | API base URL (default: `/api`; Vite proxies to API in dev) |

## Document References

- [projectplan.md](./projectplan.md) — Architecture, four steps, Web GUI spec, SP strategy.
- [devplan-and-technical-requirements.md](./devplan-and-technical-requirements.md) — Azure resources, dev phases, technical requirements.
