# Automated Data Pipeline — Project Plan

**Version:** 1.2  
**Date:** February 7, 2025  
**Target:** Azure-hosted pipeline → SQL Server sink  
**Project folder:** All artifacts and deliverables for this effort are stored under **`AutomatedDataPipeline/`** (plan, specs, and future code/config).

---

## 1. Executive Summary

Build an automated data pipeline that ingests from multiple source types (SOAP API, REST API, headless browser, SQL Server, CSV, JSON) into a SQL Server staging database, with transformation and migration orchestrated via stored procedures and a web GUI for monitoring the four pipeline stages.

---

## 2. Pipeline Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           SOURCES (multi-type)                                    │
├──────────┬──────────┬──────────────┬──────────────┬──────────┬───────────────────┤
│ SOAP API │ REST API │ Headless     │ SQL Server   │ CSV      │ JSON              │
│          │          │ Chrome       │ (source DB)  │ (blob/   │ (blob/file/API)   │
│          │          │ (scraping)   │              │ file)    │                   │
└────┬─────┴────┬─────┴──────┬───────┴──────┬───────┴────┬─────┴─────────┬─────────┘
     │          │            │              │            │               │
     ▼          ▼            ▼              ▼            ▼               ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│  ORCHESTRATION: Azure Data Factory (ADF) / Synapse Pipelines                      │
│  • Linked services, datasets, activities                                          │
│  • Triggers (schedule, event, tumbling window)                                     │
└─────────────────────────────────────────────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│  STAGING DATABASE (SQL Server on Azure SQL / VM)                                  │
│  • Raw / landing tables (Step 1: Data Pull)                                       │
│  • Stored procedures: Extract → Transform → Migrate (Steps 2–4)                   │
└─────────────────────────────────────────────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│  SINK: SQL Server (staging + final target DBs)                                    │
└─────────────────────────────────────────────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│  WEB GUI: Monitor 4 steps (Pull → Extract SP → Transform SP → Migrate SP)         │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. The Four Steps (Visible in Web GUI)

| Step | Name | Description | Where it runs |
|------|------|-------------|---------------|
| **1** | **Data Pull** | Ingest from source (API, browser, DB, file) into staging/landing | ADF pipeline activities |
| **2** | **Extract (SP)** | Stored procedure: read from landing, normalize into staging tables | SQL Server (staging DB) |
| **3** | **Transform (SP)** | Stored procedure: clean, validate, aggregate, business rules | SQL Server (staging DB) |
| **4** | **Migrate (SP)** | Stored procedure: load from staging into final target tables | SQL Server (staging → target) |

The web GUI will show status and history for each of these four steps per pipeline run.

---

## 4. Technology Recommendations (Azure-Centric)

### 4.1 Orchestration: **Azure Data Factory (ADF)** or **Azure Synapse Pipelines**

- **Why:** Native Azure, managed, scales well, supports many connectors, and fits your sources.
- **Use ADF** when the main need is ETL/ELT and integration with other Azure services.
- **Use Synapse** when you also need heavy analytics, Spark, or a unified data warehouse.

**Recommendation:** Start with **Azure Data Factory** for the pipeline orchestration.

### 4.2 Source Connectors in ADF

| Source Type | ADF / Azure Approach | Notes |
|-------------|----------------------|--------|
| **REST API** | **HTTP connector** or **REST linked service** | Pagination, auth (OAuth2, key, etc.) in linked service/dataset. |
| **SOAP API** | **HTTP connector** (POST XML body) or **Custom activity** (e.g. .NET/Python) | SOAP not built-in; HTTP + expression for body or custom code. |
| **SQL Server** | **SQL Server connector** (on-prem via IR or Azure SQL) | Native; use IR if source is on-prem or in VNet. |
| **CSV** | **Azure Blob / Data Lake / File Storage** + **Delimited text** dataset | Blob/ADLS as landing; ADF reads and loads to SQL. |
| **JSON** | **Azure Blob / Data Lake / HTTP** + **JSON** dataset | Same pattern; optional schema. |
| **Headless Chrome (scraping/clicking)** | **Not in ADF** → use **Azure VM** with HTTP API + Playwright, or Logic Apps + browser service | See section 5. |

### 4.3 Headless Chrome / Web Scraping

- ADF has no built-in browser or Chrome.
- **Options:**
  1. **Azure VM** (Linux or Windows) with **Playwright** (or Puppeteer/Selenium) and a small **HTTP API**; ADF invokes via **Web activity** (HTTP POST). Full control over OS, browser, and scaling (e.g. scale set or scheduled start/stop).
  2. **Azure Logic Apps** + **HTTP** to an external scraping service (e.g. API that runs Playwright).
  3. **Databricks** with Selenium/Playwright (heavier).

**Recommendation:** **Azure VM** with **Playwright** and an HTTP API; output to **Blob/ADLS (JSON/CSV)** or directly to **SQL** (via managed identity or Key Vault connection string). ADF calls the VM via **Web activity** and then runs the rest of the pipeline (Copy from Blob if needed, then SPs). This avoids container size limits and gives full control over the scraper environment.

### 4.4 Staging and Sink: **SQL Server**

- **Azure SQL Database** or **SQL Server on Azure VM**.
- Same server can host:
  - **Staging DB** (landing + staging tables, SPs for Extract/Transform/Migrate).
  - **Target DB(s)** (final reporting/operational tables).

### 4.5 Web GUI for the 4 Steps

- **Options:**
  1. **Power BI** (report on pipeline run metadata + SQL run history).
  2. **Custom web app** (e.g. **React/Angular + .NET/Node API**) reading from:
     - **ADF pipeline run API** or **Azure Monitor** for Step 1.
     - **Staging DB tables** (e.g. `PipelineRuns`, `StepRuns` populated by SPs) for Steps 2–4.
  3. **Azure Data Factory monitoring UI** (built-in) + **SQL-based dashboard** for SP steps.

**Recommendation:** **Custom lightweight web app** (e.g. **React + .NET Core API**) that:
- Calls **ADF REST API** or **Azure Monitor** for Data Pull (Step 1).
- Reads **control tables** in the staging DB (updated by your SPs) for Extract / Transform / Migrate (Steps 2–4).
- Shows one view per pipeline with four steps and status (Pending / Running / Success / Failed).

---

## 5. Source-Specific Implementation Notes

### 5.1 SOAP API

- **ADF:** HTTP linked service; Web activity or Copy (if response can be parsed). Use **expression** or **Stored Procedure** to build SOAP envelope; parse response (XML) and map to staging.
- **Alternative:** **Azure Function** (C#/Python) to call SOAP, write result to Blob (XML/JSON) or SQL; ADF triggers function then loads from Blob/SQL.

### 5.2 REST API

- **ADF:** REST linked service + pagination (e.g. relative URL from `next` link). Copy activity to staging table or to Blob; then SP for Extract.

### 5.3 Headless Chrome (Web Scraping + Clicking)

- **Azure VM** with Playwright and an HTTP API:
  - Input: URL, selectors, click sequence (config or parameters) via HTTP POST.
  - Output: JSON/CSV to **Azure Blob** (using VM managed identity or Key Vault) or insert into **staging DB**.
- **ADF:** **Web activity** (HTTP POST to scraper VM) to invoke the scraper; then **Copy** from Blob to SQL (if needed) and run **Stored Procedure** activities for Extract/Transform/Migrate.

### 5.4 SQL Server (Source DB)

- **ADF:** SQL Server linked service; Copy activity (full or incremental via watermark column) to staging tables. Incremental: use **Lookup** + **Stored Procedure** or **Data flow** for watermark logic.

### 5.5 CSV / JSON

- **ADF:** Blob/ADLS linked service + Delimited/JSON dataset; Copy to SQL staging. Optional **Data flow** for light transforms before staging.

---

## 6. Stored Procedures Strategy (Staging DB)

### 6.1 Control Tables (for Web GUI and orchestration)

```sql
-- Pipeline run header (one per ADF pipeline run)
CREATE TABLE dbo.PipelineRuns (
    RunId           UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    PipelineName    NVARCHAR(256),
    ADFRunId        NVARCHAR(128),   -- from ADF
    StartedAt       DATETIME2,
    FinishedAt      DATETIME2,
    Status          NVARCHAR(32),    -- Running, Success, Failed
    CreatedAt       DATETIME2 DEFAULT SYSUTCDATETIME()
);

-- Step runs (one row per step per RunId)
CREATE TABLE dbo.StepRuns (
    StepRunId       BIGINT IDENTITY(1,1) PRIMARY KEY,
    RunId           UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.PipelineRuns(RunId),
    StepNumber      TINYINT NOT NULL,  -- 1=Pull, 2=Extract, 3=Transform, 4=Migrate
    StepName        NVARCHAR(64),
    StartedAt       DATETIME2,
    FinishedAt      DATETIME2,
    Status          NVARCHAR(32),
    RowsAffected    BIGINT,
    ErrorMessage    NVARCHAR(MAX),
    CreatedAt       DATETIME2 DEFAULT SYSUTCDATETIME()
);
```

- **Step 1 (Data Pull):** ADF writes a row to `PipelineRuns` (e.g. via a small “kickoff” SP at pipeline start) and optionally to `StepRuns` for Step 1, or the Web GUI infers Step 1 from ADF run status.
- **Steps 2–4:** Each SP receives `@RunId`, inserts/updates `StepRuns` at start (status = Running) and at end (status = Success/Failed, `RowsAffected`, `ErrorMessage`).

### 6.2 Stored Procedure Signatures (example)

- **Extract:** `dbo.usp_Extract_<SourceName> @RunId UNIQUEIDENTIFIER`  
  - Reads from landing/raw tables, normalizes into staging tables, updates `StepRuns` for Step 2.

- **Transform:** `dbo.usp_Transform_<SourceName> @RunId UNIQUEIDENTIFIER`  
  - Reads from staging tables, applies business rules, writes to transformed staging tables, updates `StepRuns` for Step 3.

- **Migrate:** `dbo.usp_Migrate_<SourceName> @RunId UNIQUEIDENTIFIER`  
  - Moves data from staging to final target tables (same or different DB), updates `StepRuns` for Step 4.

### 6.3 ADF and SP Execution Order

1. **Data Pull:** ADF Copy/Web activities (Web for scraper VM or REST/SOAP) → land data in staging DB (and optionally insert `PipelineRuns` / Step 1).
2. **Extract:** ADF **Stored Procedure activity** → `dbo.usp_Extract_<SourceName> @RunId = ...`
3. **Transform:** ADF **Stored Procedure activity** → `dbo.usp_Transform_<SourceName> @RunId = ...`
4. **Migrate:** ADF **Stored Procedure activity** → `dbo.usp_Migrate_<SourceName> @RunId = ...`

Pass `RunId` from pipeline start through the pipeline (e.g. set variable at start, pass into each SP).

---

## 7. Web GUI — How All Steps Are Displayed

The Web GUI is the single place to see every pipeline run and the status of all four steps. All GUI-related specs and code will live under **`AutomatedDataPipeline/`**.

### 7.1 Main Views (Screens)

| View | Purpose | What the user sees |
|------|--------|--------------------|
| **Run list** | List of pipeline runs (all pipelines or filter by name) | Table/cards: Pipeline name, Run ID, overall status, started/finished time, optional “View steps” action. |
| **Run detail** | One run with all four steps | Header (pipeline name, RunId, overall status, duration). Below: the **4-step strip** and optional **step detail** (timing, rows, errors). |
| **Settings / Filters** (optional) | Filter by pipeline, date range, status | Dropdowns or date pickers that filter the Run list. |

From the **Run list**, clicking a run opens **Run detail**, where all four steps are displayed together.

### 7.2 How the Four Steps Are Displayed (Run Detail)

On the **Run detail** screen, the four steps are always shown in a fixed order so users can see the full flow at a glance.

**A. Step strip (horizontal or vertical)**

- **Four blocks in order:**  
  **1. Data Pull** → **2. Extract (SP)** → **3. Transform (SP)** → **4. Migrate (SP)**  
  Each block shows:
  - **Step number and name** (e.g. “1 – Data Pull”, “2 – Extract (SP)”).
  - **Status badge:** Pending | Running | Success | Failed (with distinct colors/icons).
  - **Optional short summary:** e.g. “Started 10:02, 1,234 rows” or “Failed: timeout”.

**B. Visual flow**

- Steps are laid out left-to-right (or top-to-bottom) with a simple connector (e.g. arrow or line) between them so the sequence is obvious.
- The **current** step (Running) can be highlighted (e.g. pulse or “in progress” label).
- Any **Failed** step is visually emphasized (e.g. red border or icon); steps after it can show “Skipped” or “Pending” depending on pipeline behavior.

**C. Per-step details (expandable or side panel)**

For each of the four steps, the GUI can show (on click or in a details panel):

| Step | Displayed fields | Source of data |
|------|------------------|----------------|
| **1 – Data Pull** | Status, StartedAt, FinishedAt, optional RowsAffected, ErrorMessage (if failed), ADF activity run ID / link | ADF REST API / Azure Monitor; or `StepRuns` if Step 1 is written from ADF |
| **2 – Extract (SP)** | Status, StartedAt, FinishedAt, RowsAffected, ErrorMessage | `dbo.StepRuns` (StepNumber = 2) |
| **3 – Transform (SP)** | Status, StartedAt, FinishedAt, RowsAffected, ErrorMessage | `dbo.StepRuns` (StepNumber = 3) |
| **4 – Migrate (SP)** | Status, StartedAt, FinishedAt, RowsAffected, ErrorMessage | `dbo.StepRuns` (StepNumber = 4) |

- **Duration** can be computed as FinishedAt − StartedAt and shown for each step.
- **ErrorMessage** is shown in full (e.g. in a tooltip or expandable area) when status is Failed.

**D. Run-level summary**

- At the top of Run detail: **Pipeline name**, **RunId** (and optional **ADFRunId**), **overall status** (e.g. derived from the four steps: Success if all Success, Failed if any Failed, Running if any Running).
- **Started** / **Finished** (min of step start, max of step end) and **total duration**.

### 7.3 Data Flow: Backend → GUI

- **Run list:** API returns rows from `PipelineRuns` (and optionally enriches with ADF status). Fields: RunId, PipelineName, ADFRunId, StartedAt, FinishedAt, Status.
- **Run detail:**  
  - **Header:** One row from `PipelineRuns` for the selected RunId.  
  - **Steps:** Up to four rows from `StepRuns` for that RunId, ordered by StepNumber (1–4).  
  - **Step 1:** If not stored in `StepRuns`, backend merges in ADF run/activity status for that RunId (via ADF run ID stored in `PipelineRuns.ADFRunId`) so the GUI still shows one row per step.

This way, the same “four rows per run” model is used for display: the GUI always renders **four step blocks**; for Step 1 the data may come from ADF API or from `StepRuns`.

### 7.4 Refresh and Real-Time Behavior

- **Run list:** Refresh on load; optional manual refresh button or auto-refresh (e.g. every 30 s) when a filter like “status = Running” is applied.
- **Run detail:** While the run is in progress (overall status = Running), auto-refresh (e.g. every 5–10 s) so the four steps update (e.g. Step 2 moves to Running then Success, Step 3 to Running). When overall status is Success or Failed, auto-refresh can stop or slow (e.g. every 60 s).

This ensures **all steps** are always visible and their status stays up to date during and after the run.

### 7.5 Data Sources for the GUI (Summary)

- **Step 1 (Data Pull):** ADF pipeline/activity run status (Azure REST API or Azure Monitor), or `StepRuns` if the pipeline writes Step 1 into the control table (recommended for a single source of truth).
- **Steps 2–4:** Always from `dbo.StepRuns` in the staging DB (updated by the Extract/Transform/Migrate SPs).

### 7.6 Suggested Stack

- **Frontend:** React or Blazor (if .NET-only); all GUI code under **`AutomatedDataPipeline/`** (e.g. `web/` or `frontend/`).
- **Backend:** .NET Core Web API or Node.js API (e.g. under **`AutomatedDataPipeline/api/`**) that:
  - Calls **Azure REST API** (managed identity or service principal) for ADF run details when Step 1 is not in `StepRuns`.
  - Queries **staging SQL Server** for `PipelineRuns` and `StepRuns`.
- **Auth:** Azure AD (MSAL) for users; managed identity for API → ADF and API → SQL.

---

## 8. Implementation Phases

| Phase | Scope | Deliverables |
|-------|--------|--------------|
| **1. Foundation** | Azure resources, staging DB, control tables | Resource group; SQL Server (staging); `PipelineRuns` + `StepRuns`; ADF project with one sample pipeline. |
| **2. Connectors** | One pipeline per source type | ADF pipelines: REST, SOAP (HTTP/custom), SQL Server, CSV, JSON; landing tables and Copy activities. |
| **3. Headless Chrome** | Scraping/clicking | Azure VM + Playwright + HTTP API; ADF Web activity → output to Blob or SQL; Copy if needed. |
| **4. Stored procedures** | Extract / Transform / Migrate | SPs per source (or generic with parameters); update `StepRuns`; ADF SP activities and `RunId` flow. |
| **5. Web GUI** | 4-step monitoring | API (ADF + SQL); frontend showing pipeline runs and four steps with status and details. |
| **6. Hardening** | Security, retries, alerting | Managed identities; retry policies; failure alerts (e.g. Logic Apps or Azure Monitor); optional logging to Log Analytics. |

---

## 9. Azure Resource Checklist

- [ ] **Resource group** (e.g. `rg-data-pipeline-prod`)
- [ ] **Azure Data Factory** (or Synapse workspace)
- [ ] **SQL Server** (Azure SQL or VM) + **staging database**
- [ ] **Azure Storage** (Blob and/or Data Lake) for CSV/JSON and scraping output
- [ ] **Integration Runtime** (if on-prem or VNet sources)
- [ ] **Azure VM(s)** for headless Chrome scraper (Playwright + HTTP API)
- [ ] **App Service** or **Static Web App** for Web GUI (optional)
- [ ] **Azure AD app registration** for GUI and ADF (if needed)
- [ ] **Key Vault** for connection strings and secrets

---

## 10. Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| SOAP/legacy APIs hard to model in ADF | Use Azure Function or custom activity to normalize to JSON/table. |
| Headless Chrome resource-heavy and brittle | Size VM appropriately (e.g. 4 GB RAM); implement retries and timeouts; consider scheduled start/stop to save cost; fallback to vendor API if available. |
| SPs block pipeline on long runs | Design SPs for idempotency and chunking; consider async pattern (queue + worker) for very large migrations. |
| Web GUI shows stale Step 2–4 data | SPs must always update `StepRuns` (including on failure); use short polling or SignalR for “running” state. |

---

## 11. Success Criteria

- All six source types (SOAP, REST, headless Chrome, SQL Server, CSV, JSON) can feed the staging DB via ADF (or ADF + scraper VM).
- Each pipeline run executes the four steps in order: Data Pull → Extract SP → Transform SP → Migrate SP.
- Web GUI shows each run and the status of all four steps with timing and error information.
- Pipelines are scheduled or event-driven and run reliably on Azure with minimal manual intervention.

---

## 12. Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-02-07 | — | Initial project plan |
| 1.1 | 2025-02-07 | — | Project folder set to `AutomatedDataPipeline/`; expanded Section 7 with how all four steps are displayed in the Web GUI (views, step strip, per-step fields, data flow, refresh behavior). |
| 1.2 | 2025-02-07 | — | Headless Chrome: switched from Azure Functions to **Azure VM** (Playwright + HTTP API); ADF uses **Web activity** to call scraper. |
