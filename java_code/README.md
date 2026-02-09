# Automated Data Pipeline (Java / JSP)

Java port of the 4-step data pipeline with a JSP web UI: **Data Pull → Extract → Transform → Migrate**. Uses **SQL Server** as the database.

## Requirements

- Java 11+
- Maven 3.6+
- SQL Server (local or remote)

## Build

**Linux / macOS:**
```bash
cd java_code
mvn clean package
```

**Windows (cmd):**
```cmd
cd java_code
mvn clean package
```

Produces `target/pipeline.war`.

## Run locally (Jetty)

**Linux / macOS:** (Java and Maven can be auto-downloaded if missing)
```bash
cd java_code
./run.sh
```

**Windows (PowerShell – recommended, auto-downloads Java and Maven if missing):**
```powershell
cd java_code
.\run.ps1
```
If you see an execution policy error, run once: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`

**Windows (cmd, requires Java and Maven on PATH):**
```cmd
cd java_code
run.bat
```

Or with Java and Maven already installed:
```bash
mvn jetty:run
```

- App: **http://localhost:8080/**
- API base: **http://localhost:8080/api**

## SQL Server configuration

Connection settings come from **environment variables** (or defaults). Create the database once (e.g. `CREATE DATABASE pipeline;`) before first run; the app creates tables automatically.

**Using a .env file:** Copy `.env.example` to `.env` in the `java_code` folder and set your values (especially `DB_PASSWORD`). On Linux/macOS, `./run.sh` sources `.env`; on Windows, `run.bat` loads `.env` (lines `KEY=VALUE`; strip `export ` if present). (`.env` is gitignored.)

| Variable | Default | Description |
|----------|---------|-------------|
| `DB_HOST` | `localhost` | SQL Server hostname |
| `DB_PORT` | `1433` | SQL Server port |
| `DB_USER` | `sa` | Login username |
| `DB_PASSWORD` | *(empty)* | Login password (set this in production) |
| `DB_NAME` | `pipeline` | Database name |
| `LANDING_DATA_DIR` | `data/landing` | Directory for uploaded CSV/JSON (trigger) |
| `PIPELINE_NAME` | `SamplePipeline` | Name stored in `PipelineRuns` |

Example:

```bash
export DB_HOST=localhost
export DB_PORT=1433
export DB_USER=sa
export DB_PASSWORD=YourPassword
./run.sh
```

## Web UI

- **/** – Run list, filters (pipeline, status).
- **manual-run.jsp** – Trigger pipeline manually (CSV/JSON upload).
- **run-detail.jsp?runId=…** – Run detail: 4-step strip, status, logs (auto-refresh every 2s when running).
- **logs.jsp** – All pipeline logs with level and limit filters.

## API (JSON)

- `GET /api/runs?pipeline=&status=` – List runs (RunNumber, PipelineName, Status, etc.).
- `GET /api/runs/{runId}` – Run detail with `steps[]`.
- `GET /api/runs/{runId}/logs` – Logs for one run.
- `GET /api/logs?runId=&pipeline=&level=&limit=500` – All logs (optional filters).
- `POST /api/pipeline/trigger` – Multipart form field `file` (CSV or JSON). Returns `{ "runId": "…" }` and runs the pipeline in the background.

## Sample data

Use CSV or JSON with columns/fields: **OrderId**, **CustomerId**, **Amount**, **OrderDate**. Sample files from the parent project can be used with the trigger form.

## Deploy

Deploy `target/pipeline.war` to any Servlet 4.0 container. Set `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, and `DB_NAME` (and optionally `LANDING_DATA_DIR`) for your environment.
