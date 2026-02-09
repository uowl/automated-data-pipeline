-- SQLite schema (same as Node version)
CREATE TABLE IF NOT EXISTS PipelineRuns (
    RunId           TEXT PRIMARY KEY,
    RunNumber       INTEGER NOT NULL,
    PipelineName    TEXT NOT NULL,
    ADFRunId        TEXT,
    StartedAt       TEXT,
    FinishedAt      TEXT,
    Status          TEXT NOT NULL DEFAULT 'Running',
    CreatedAt       TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE UNIQUE INDEX IF NOT EXISTS IX_PipelineRuns_RunNumber ON PipelineRuns(RunNumber);

CREATE TABLE IF NOT EXISTS StepRuns (
    StepRunId       INTEGER PRIMARY KEY AUTOINCREMENT,
    RunId           TEXT NOT NULL,
    StepNumber      INTEGER NOT NULL,
    StepName        TEXT NOT NULL,
    StartedAt       TEXT,
    FinishedAt      TEXT,
    Status          TEXT NOT NULL DEFAULT 'Pending',
    RowsAffected    INTEGER,
    ErrorMessage    TEXT,
    CreatedAt       TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS IX_StepRuns_RunId ON StepRuns(RunId);

CREATE TABLE IF NOT EXISTS PipelineLogs (
    LogId           INTEGER PRIMARY KEY AUTOINCREMENT,
    RunId           TEXT NOT NULL,
    PipelineName    TEXT,
    LogAt           TEXT NOT NULL DEFAULT (datetime('now')),
    Level           TEXT NOT NULL DEFAULT 'Info',
    StepNumber      INTEGER,
    StepName        TEXT,
    Message         TEXT NOT NULL,
    Details         TEXT
);
CREATE INDEX IF NOT EXISTS IX_PipelineLogs_RunId ON PipelineLogs(RunId);
CREATE INDEX IF NOT EXISTS IX_PipelineLogs_LogAt ON PipelineLogs(LogAt);

CREATE TABLE IF NOT EXISTS Landing_Orders (
    Id              INTEGER PRIMARY KEY AUTOINCREMENT,
    RunId           TEXT NOT NULL,
    OrderId         TEXT,
    CustomerId      TEXT,
    Amount         REAL,
    OrderDate      TEXT,
    SourceType     TEXT,
    RawPayload     TEXT,
    LoadedAt       TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS IX_Landing_Orders_RunId ON Landing_Orders(RunId);

CREATE TABLE IF NOT EXISTS Staging_Orders (
    Id              INTEGER PRIMARY KEY AUTOINCREMENT,
    RunId           TEXT NOT NULL,
    OrderId         TEXT NOT NULL,
    CustomerId      TEXT NOT NULL,
    Amount          REAL NOT NULL,
    OrderDate       TEXT,
    ExtractedAt    TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS IX_Staging_Orders_RunId ON Staging_Orders(RunId);

CREATE TABLE IF NOT EXISTS Staging_Orders_Transformed (
    Id              INTEGER PRIMARY KEY AUTOINCREMENT,
    RunId           TEXT NOT NULL,
    OrderId         TEXT NOT NULL,
    CustomerId      TEXT NOT NULL,
    Amount          REAL NOT NULL,
    OrderDate       TEXT,
    AmountCategory  TEXT,
    TransformedAt   TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS IX_Staging_Orders_Transformed_RunId ON Staging_Orders_Transformed(RunId);

CREATE TABLE IF NOT EXISTS Target_Orders (
    Id              INTEGER PRIMARY KEY AUTOINCREMENT,
    OrderId         TEXT NOT NULL UNIQUE,
    CustomerId      TEXT NOT NULL,
    Amount          REAL NOT NULL,
    OrderDate       TEXT,
    AmountCategory  TEXT,
    MigratedAt      TEXT NOT NULL DEFAULT (datetime('now'))
);
