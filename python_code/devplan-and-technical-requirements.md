# Automated Data Pipeline — Development Plan & Technical Requirements

**Version:** 1.1  
**Date:** February 7, 2025  
**Project folder:** `AutomatedDataPipeline/`  
**Related:** [projectplan.md](./projectplan.md)

---

## Part A — Technical Requirements

### 1. Azure Resources to Create

All resources should be created in a dedicated **resource group** (e.g. `rg-automateddatapipeline-prod`) in the target Azure subscription and region.

| # | Resource type | Purpose | Naming example | Notes |
|---|----------------|--------|----------------|-------|
| 1 | **Resource group** | Container for all pipeline resources | `rg-automateddatapipeline-prod` | Single RG per environment (dev/prod). |
| 2 | **Azure Data Factory** | Orchestration: pipelines, activities, triggers | `adf-automateddatapipeline-prod` | Enable Git integration (Azure DevOps/GitHub) for ARM/JSON. |
| 3 | **Azure SQL Server** (logical server) | Host for staging (and optionally target) databases | `sql-automateddatapipeline-prod` | Configure firewall rules and/or VNet integration. |
| 4 | **Azure SQL Database** (staging) | Staging DB: landing tables, control tables, SPs | `sqldb-staging` (on server above) | S1 or higher for production; Basic/Standard for dev. |
| 5 | **Azure SQL Database** (target, optional) | Final target DB for migrated data | `sqldb-target` or per-domain names | Can be same server or separate. |
| 6 | **Storage account** | Blob for CSV/JSON landing; scraping output; ADF staging | `stautomateddatapipeline` (unique globally) | Standard LRS; enable hierarchical namespace if using ADLS Gen2. |
| 7 | **Blob container(s)** | Folders for landing files (CSV, JSON) and scraping output | e.g. `landing`, `scraping-output`, `adf-staging` | Private access; no anonymous. |
| 8 | **Azure Key Vault** | Secrets: SQL connection strings, API keys, ADF credentials | `kv-automateddatapipeline-prod` | Enable soft delete; restrict network if required. |
| 9 | **Azure VM(s)** (scraper) | Run headless Chrome (Playwright) and HTTP API for scraping | `vm-scraper-prod` (or scale set) | Linux or Windows; install Playwright + small HTTP service; ADF calls via **Web activity**. |
| 10 | **App Service / Static Web App** (for Web GUI) | Host Web GUI frontend + API | `app-automateddatapipeline-gui` or `stapp-...` | Or use **Azure Static Web Apps** for frontend + API. |
| 11 | **Application Insights** (optional) | Telemetry for GUI and/or scraper VM app | Created with App Service or standalone | Same region as app. |
| 12 | **Log Analytics workspace** (optional) | Central logs for ADF, scraper VM, GUI | `log-automateddatapipeline-prod` | Link ADF diagnostic settings; optional VM extension for agent. |
| 13 | **Managed identity** (Data Factory) | ADF to access Key Vault, Storage, SQL | System-assigned on ADF | Grant roles: Key Vault Secrets User, Storage Blob Data Contributor, SQL appropriate role. |
| 14 | **Managed identity** (Web API) | API to access ADF, SQL, Key Vault | System-assigned on App Service | Grant: ADF Reader or Data Factory Contributor; SQL; Key Vault Secrets User. |
| 15 | **Azure AD app registration** (optional) | User sign-in for Web GUI (MSAL) | e.g. `app-automateddatapipeline-gui` | Redirect URIs for GUI; API permissions if calling Graph. |
| 16 | **Integration Runtime** (only if on-prem/VNet sources) | Connect ADF to on-prem SQL or VNet | `IR-AutomatedDataPipeline` | Self-hosted or Azure IR in VNet. |
| 17 | **Virtual network** (optional, for scraper VM) | Isolate scraper VM; static IP for ADF Web activity | e.g. `vnet-automateddatapipeline` | Subnet for VM; NSG to allow HTTPS from ADF / allowed IPs only. |

**Summary checklist (Azure):**

- [ ] Resource group  
- [ ] Azure Data Factory  
- [ ] Azure SQL Server + staging DB (+ optional target DB)  
- [ ] Storage account + blob containers  
- [ ] Key Vault  
- [ ] Azure VM(s) for headless Chrome scraper (optional VNet)  
- [ ] App Service or Static Web App (Web GUI)  
- [ ] Application Insights / Log Analytics (optional)  
- [ ] Managed identities (ADF, Web API) and role assignments  
- [ ] Azure AD app registration (if GUI uses Azure AD login)  
- [ ] Integration Runtime (only if on-prem or VNet sources)

---

### 2. Azure Resource Configuration Details

#### 2.1 Data Factory

- **Region:** Same as SQL and Storage (e.g. East US, West Europe).  
- **Git:** Connect to Azure DevOps or GitHub; branch for publishing (e.g. `main` or `adf_publish`).  
- **Managed identity:** Enable system-assigned; grant:
  - **Key Vault:** Secrets User (get connection strings).
  - **Storage:** Storage Blob Data Contributor (read/write landing, staging).
  - **SQL:** Appropriate DB role (e.g. `db_datareader`, `db_datawriter`, `db_ddladmin` on staging DB) or contained user with same.

#### 2.2 SQL Server & Databases

- **Firewall:** Allow Azure services; add rule for App Service outbound IPs or use **VNet rules** / **private endpoint** for production.  
- **Authentication:** Prefer **Azure AD auth** for ADF and Web API (managed identity); alternatively SQL auth with secrets in Key Vault.  
- **Staging DB:** Create control tables `PipelineRuns`, `StepRuns`; landing/staging tables per source; SPs for Extract, Transform, Migrate.  
- **SKU:** Staging DB — e.g. S1 (10 DTU) for prod; Basic for dev. Scale up if SPs are long-running.

#### 2.3 Storage Account

- **Performance:** Standard.  
- **Replication:** LRS for cost; GRS if DR required.  
- **Containers:** `landing` (CSV/JSON from external systems), `scraping-output` (Playwright output), `adf-staging` if ADF uses it.  
- **Access:** No public blob access; ADF and scraper VM (via managed identity or SAS/connection) access; RBAC: Storage Blob Data Contributor for ADF.

#### 2.4 Key Vault

- **Secrets to store:** SQL connection strings (if not using Azure AD only), REST/SOAP API keys, any credentials for headless scraper (e.g. login URLs).  
- **Access:** ADF and Web API managed identities — **Get** on secrets.  
- **Networking:** Default or restricted to selected VNets.

#### 2.5 Azure VM (Headless Chrome / Scraper)

- **OS:** Linux (e.g. Ubuntu 22.04) or Windows Server; sufficient memory for Chromium (e.g. 4 GB RAM minimum; Standard_B2s or similar).  
- **Software:** Install Node.js or Python, then Playwright (or Puppeteer/Selenium) and Chromium; run a small **HTTP API** (e.g. Express/Flask) that accepts scrape requests (URL, selectors, config) and returns or writes results.  
- **Invocation:** ADF calls the VM via **Web activity** (HTTP POST to the scraper API); use VM’s public IP or load balancer, or private IP if ADF uses VNet integration. Secure with API key (stored in Key Vault) or VNet + NSG.  
- **Output:** Scraper writes to Blob (JSON/CSV) via connection string or managed identity (install Azure CLI / SDK on VM and assign VM managed identity + Storage Blob Data Contributor), or writes directly to SQL; ADF then continues pipeline (Copy from Blob if needed, then SPs).  
- **Availability:** Use a single VM for dev; for production consider **availability set** or **scale set** (if multiple scrape jobs in parallel), or scheduled start/stop to save cost when not in use.

#### 2.6 Web GUI (App Service or Static Web Apps)

- **Runtime:** .NET Core (API) + React/Blazor (frontend); or Node API + React.  
- **Settings:** Connection strings and config from **Key Vault** or App Configuration; use managed identity to read Key Vault.  
- **CORS:** Allow GUI origin for API.  
- **Auth:** Optional Azure AD (MSAL) for user sign-in.

---

### 3. Non-Azure Technical Requirements

| Category | Requirement | Notes |
|----------|-------------|--------|
| **Source systems** | REST/SOAP endpoints, base URLs, auth (API keys, OAuth) | Document in config or Key Vault; ADF linked services/datasets. |
| **Source SQL Server** | Connection details, firewall whitelist for ADF (or IR) | On-prem: install Integration Runtime and register to ADF. |
| **File sources** | Paths/containers for CSV/JSON; naming conventions | Blob or ADLS paths; optional Event Grid trigger for new files. |
| **Scraping** | Target URLs, selectors, click flows, output schema | Config (e.g. JSON) passed to scraper API on VM or stored in Key Vault/Blob. |
| **Tooling** | IDE, Azure CLI or PowerShell, Git | VS Code / Visual Studio; Azure CLI; repo for `AutomatedDataPipeline/` (ARM, scripts, code). |
| **CI/CD** | Pipeline to deploy ADF, API, scraper VM (image or script) | Azure DevOps or GitHub Actions; deploy ARM/Bicep; publish ADF from Git; VM via ARM + custom script extension or image. |
| **Monitoring** | Alerts on pipeline/step failure | Azure Monitor alerts on ADF failed runs; optional Logic App or webhook to Teams/email. |
| **Documentation** | Runbooks, connection details (masked), env matrix | Stored under `AutomatedDataPipeline/` (e.g. `docs/`). |

---

### 4. Access and Permissions

| Who/What | Needs access to | How |
|----------|-----------------|-----|
| **Developers** | ADF (edit), SQL (DDL/DML), Storage, Key Vault (read secrets), repo | Azure AD; RBAC (Contributor or custom role) on RG or individual resources. |
| **ADF** | Key Vault, Storage, SQL (staging/target) | Managed identity + RBAC / SQL contained user. |
| **Web API** | ADF (read runs), SQL (read `PipelineRuns`, `StepRuns`), Key Vault | Managed identity + RBAC; SQL user with read on control tables. |
| **Scraper VM** (or app on VM) | Storage (write), optionally SQL (write) | VM managed identity + RBAC, or connection string from Key Vault. |

---

### 5. Naming Conventions (Suggested)

- **Resource group:** `rg-<project>-<env>`  
- **Data Factory:** `adf-<project>-<env>`  
- **SQL server:** `sql-<project>-<env>`  
- **SQL database:** `sqldb-<name>` (e.g. `sqldb-staging`, `sqldb-target`)  
- **Storage:** globally unique, e.g. `st<project><random>` (no dashes in storage account name).  
- **Key Vault:** `kv-<project>-<env>`  
- **VM:** `vm-<purpose>-<env>` (e.g. `vm-scraper-prod`)  
- **App Service:** `app-<project>-<purpose>-<env>` or `stapp-...`  
- **Secrets:** e.g. `ConnectionString--StagingDb`, `ApiKey--RestSource1`.

---

## Part B — Development Plan

### Phase 0 — Prerequisites (Week 0)

| Task | Owner | Deliverable |
|------|--------|-------------|
| Create Azure subscription / get access | Infra/Dev | Access confirmed |
| Create resource group and assign contributors | Infra | RG created |
| Create Key Vault; grant team access to get list/get secrets | Dev | KV created, access verified |
| Create repo (or folder) `AutomatedDataPipeline/`; add projectplan, this doc | Dev | Repo structure |
| Document source systems (REST/SOAP URLs, auth, SQL sources, file locations) | Dev/BA | Config/spec doc in repo |

**Exit criteria:** RG and Key Vault exist; repo has plan and technical requirements; source list documented.

---

### Phase 1 — Foundation (Weeks 1–2)

| Task | Owner | Deliverable |
|------|--------|-------------|
| Create Azure SQL Server + staging database | Dev | Server + `sqldb-staging` |
| Run DDL for control tables: `PipelineRuns`, `StepRuns` | Dev | Tables created |
| Create Storage account + containers (`landing`, `scraping-output`, `adf-staging`) | Dev | Storage + containers |
| Create Azure Data Factory; enable managed identity; connect Git | Dev | ADF created, Git connected |
| Grant ADF managed identity: Key Vault (Secrets User), Storage (Blob Data Contributor), SQL (e.g. db_owner on staging) | Dev | Role assignments done |
| Store staging SQL connection string (or Azure AD only) in Key Vault; reference from ADF | Dev | Linked service uses KV secret |
| Build one minimal ADF pipeline: Set variable (RunId) → Stored Procedure (insert `PipelineRuns` row) → Stored Procedure (insert 4 rows into `StepRuns` with Pending) | Dev | Pipeline creates run + step placeholders |
| Test run; verify rows in `PipelineRuns` and `StepRuns` | Dev | Green run |

**Exit criteria:** Staging DB and control tables exist; ADF can run a pipeline and write RunId + step rows; team can see run in ADF UX.

---

### Phase 2 — Data Pull Connectors (Weeks 3–5)

| Task | Owner | Deliverable |
|------|--------|-------------|
| **REST:** Create REST/HTTP linked service + dataset; Copy activity to staging table or Blob | Dev | REST pipeline (Data Pull only) |
| **SOAP:** HTTP linked service + Web/Copy or Azure Function to call SOAP; land to Blob or SQL | Dev | SOAP pipeline (Data Pull only) |
| **SQL Server (source):** Linked service (and IR if on-prem); Copy to staging tables | Dev | SQL source pipeline (Data Pull only) |
| **CSV:** Blob linked service + Delimited dataset; Copy to staging table | Dev | CSV pipeline (Data Pull only) |
| **JSON:** Blob/HTTP + JSON dataset; Copy to staging table | Dev | JSON pipeline (Data Pull only) |
| Ensure each pipeline: generates RunId, writes `PipelineRuns`, writes/updates Step 1 in `StepRuns` (Data Pull) | Dev | Step 1 visible in DB for GUI later |
| Document connection details and any secrets in Key Vault | Dev | Config doc updated |

**Exit criteria:** All five source types (REST, SOAP, SQL, CSV, JSON) have a pipeline that performs Data Pull and records run + Step 1 in control tables.

---

### Phase 3 — Headless Chrome (Azure VM) (Weeks 4–6)

| Task | Owner | Deliverable |
|------|--------|-------------|
| Create Azure VM (e.g. Ubuntu 22.04); size for Chromium (e.g. Standard_B2s, 4 GB RAM); optional VNet/NSG | Dev | VM created |
| Install Node.js (or Python), Playwright, Chromium on VM | Dev | Browser stack ready |
| Implement HTTP API on VM: POST accepts config (URL, selectors, click flow); runs Playwright; outputs to Blob or SQL | Dev | Scraper API running on VM |
| Configure VM managed identity; grant Storage Blob Data Contributor (and SQL if writing directly); or use Key Vault for connection strings | Dev | Permissions verified |
| Expose scraper endpoint (public IP + NSG restrict to ADF IPs / VNet, or load balancer); secure with API key in Key Vault | Dev | ADF can call scraper securely |
| Create ADF pipeline: **Web activity** (POST to scraper VM) → (optional) Copy from Blob to SQL → same RunId/control table pattern | Dev | Scraping pipeline in ADF |
| Document scraping config format, VM setup, and how to add new targets | Dev | Doc in repo |

**Exit criteria:** One end-to-end pipeline that uses headless Chrome on an Azure VM to scrape, lands data, and records Step 1 in control tables.

---

### Phase 4 — Stored Procedures (Extract, Transform, Migrate) (Weeks 5–7)

| Task | Owner | Deliverable |
|------|--------|-------------|
| Design landing/staging/target table layout per source (or per domain) | Dev | Schema doc or DDL |
| Implement `usp_Extract_*`: read landing, normalize, write staging; update `StepRuns` (Step 2) start/end/status/rows | Dev | Extract SP(s) |
| Implement `usp_Transform_*`: read staging, business rules, write transformed staging; update `StepRuns` (Step 3) | Dev | Transform SP(s) |
| Implement `usp_Migrate_*`: read staging, write target; update `StepRuns` (Step 4) | Dev | Migrate SP(s) |
| Add Stored Procedure activities to each ADF pipeline after Data Pull, in order: Extract → Transform → Migrate; pass RunId | Dev | All pipelines run 4 steps |
| Test full run per pipeline; verify `StepRuns` has all 4 steps with correct status and timings | Dev | Green E2E |

**Exit criteria:** Every pipeline runs Pull → Extract → Transform → Migrate; control tables reflect all four steps.

---

### Phase 5 — Web GUI (Weeks 6–8)

| Task | Owner | Deliverable |
|------|--------|-------------|
| Create Web API project under `AutomatedDataPipeline/api/` | Dev | API project |
| API: endpoint to list runs (from `PipelineRuns`; optional ADF enrichment for Step 1) | Dev | GET /runs |
| API: endpoint to get run detail + 4 steps (from `PipelineRuns` + `StepRuns`) | Dev | GET /runs/:runId |
| Configure API to use managed identity for SQL and (if needed) ADF; store connection string in Key Vault | Dev | API runs in Azure |
| Create frontend under `AutomatedDataPipeline/web/` (e.g. React); Run list page | Dev | Run list UI |
| Run detail page: 4-step strip (status, timing, rows, error); optional auto-refresh when running | Dev | Step display as per projectplan |
| Deploy API + frontend to App Service or Static Web Apps; configure CORS and auth (optional) | Dev | GUI live |
| Document how to run GUI locally and in Azure | Dev | README in repo |

**Exit criteria:** Users can open the Web GUI, see pipeline runs, and for each run see all four steps with status and details.

---

### Phase 6 — Hardening and Operations (Weeks 8–10)

| Task | Owner | Deliverable |
|------|--------|-------------|
| Add retry policies and timeouts to ADF activities and SPs where appropriate | Dev | Retry/timeout configured |
| Configure Azure Monitor alerts (e.g. ADF pipeline failed) and optional notifications (email/Teams) | Dev/Ops | Alerts in place |
| Enable ADF diagnostic settings to Log Analytics (optional) | Dev | Logs centralized |
| Document runbooks: how to fix common failures, how to re-run, how to add a new source | Dev | Runbooks in repo |
| Security review: restrict SQL firewall, Key Vault network, RBAC least privilege | Dev/Infra | Findings addressed |
| Performance: tune SPs or ADF (parallelism, chunking) if needed | Dev | Tuning doc or changes |

**Exit criteria:** Pipelines are reliable, monitored, and documented for operations.

---

### Dependencies Between Phases

```
Phase 0 (Prereqs) ──► Phase 1 (Foundation) ──► Phase 2 (Connectors)
                              │                        │
                              │                        ▼
                              │                 Phase 3 (Chrome)  ──┐
                              │                        │            │
                              ▼                        ▼            │
                        Phase 4 (SPs) ◄─────────────────────────────┘
                              │
                              ▼
                        Phase 5 (Web GUI)
                              │
                              ▼
                        Phase 6 (Hardening)
```

Phase 3 can start in parallel with Phase 2 once Foundation is done. Phase 4 needs at least one connector (Phase 2 or 3) and Foundation. Phase 5 needs Phase 4 (so control tables are populated). Phase 6 is last.

---

### Suggested Timeline (High Level)

| Phase | Duration | Cumulative |
|-------|----------|------------|
| 0 – Prerequisites | 1 week | 1 week |
| 1 – Foundation | 2 weeks | 3 weeks |
| 2 – Data Pull connectors | 3 weeks | 6 weeks |
| 3 – Headless Chrome | 2–3 weeks (can overlap 2) | ~7 weeks |
| 4 – Stored procedures | 2 weeks | 9 weeks |
| 5 – Web GUI | 2 weeks | 11 weeks |
| 6 – Hardening | 2 weeks | 13 weeks |

Total about **12–14 weeks** for one team; can shorten if multiple devs work in parallel on different connectors.

---

## Document History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-02-07 | Initial dev plan and technical requirements (Azure resources, config, non-Azure requirements, access, naming; phased dev plan with tasks and timeline). |
| 1.1 | 2025-02-07 | Headless Chrome: replaced **Azure Functions** with **Azure VM(s)**; added VM resource, config (2.5), Phase 3 tasks (VM + Playwright + HTTP API, ADF Web activity); optional VNet; removed ACR. |
