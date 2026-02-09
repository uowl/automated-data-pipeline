-- SQL Server pipeline schema

IF OBJECT_ID('dbo.PipelineRuns', 'U') IS NULL
CREATE TABLE dbo.PipelineRuns (
    RunId           NVARCHAR(64) NOT NULL PRIMARY KEY,
    RunNumber       INT NOT NULL,
    PipelineName    NVARCHAR(256) NOT NULL,
    ADFRunId        NVARCHAR(256),
    StartedAt       NVARCHAR(64),
    FinishedAt      NVARCHAR(64),
    Status          NVARCHAR(32) NOT NULL DEFAULT N'Running',
    CreatedAt       DATETIME2 NOT NULL DEFAULT SYSDATETIMEOFFSET()
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_PipelineRuns_RunNumber' AND object_id = OBJECT_ID('dbo.PipelineRuns'))
CREATE UNIQUE INDEX IX_PipelineRuns_RunNumber ON dbo.PipelineRuns(RunNumber);
GO
IF OBJECT_ID('dbo.StepRuns', 'U') IS NULL
CREATE TABLE dbo.StepRuns (
    StepRunId       INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    RunId           NVARCHAR(64) NOT NULL,
    StepNumber      INT NOT NULL,
    StepName        NVARCHAR(128) NOT NULL,
    StartedAt       NVARCHAR(64),
    FinishedAt      NVARCHAR(64),
    Status          NVARCHAR(32) NOT NULL DEFAULT N'Pending',
    RowsAffected    INT,
    ErrorMessage    NVARCHAR(MAX),
    CreatedAt       DATETIME2 NOT NULL DEFAULT SYSDATETIMEOFFSET()
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_StepRuns_RunId' AND object_id = OBJECT_ID('dbo.StepRuns'))
CREATE INDEX IX_StepRuns_RunId ON dbo.StepRuns(RunId);
GO
IF OBJECT_ID('dbo.PipelineLogs', 'U') IS NULL
CREATE TABLE dbo.PipelineLogs (
    LogId           INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    RunId           NVARCHAR(64) NOT NULL,
    PipelineName    NVARCHAR(256),
    LogAt           NVARCHAR(64) NOT NULL,
    Level           NVARCHAR(32) NOT NULL DEFAULT N'Info',
    StepNumber      INT,
    StepName        NVARCHAR(128),
    Message         NVARCHAR(MAX) NOT NULL,
    Details         NVARCHAR(MAX)
);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_PipelineLogs_RunId' AND object_id = OBJECT_ID('dbo.PipelineLogs'))
CREATE INDEX IX_PipelineLogs_RunId ON dbo.PipelineLogs(RunId);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_PipelineLogs_LogAt' AND object_id = OBJECT_ID('dbo.PipelineLogs'))
CREATE INDEX IX_PipelineLogs_LogAt ON dbo.PipelineLogs(LogAt);
GO
IF OBJECT_ID('dbo.Landing_Orders', 'U') IS NULL
CREATE TABLE dbo.Landing_Orders (
    Id              INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    RunId           NVARCHAR(64) NOT NULL,
    OrderId         NVARCHAR(128),
    CustomerId      NVARCHAR(128),
    Amount          FLOAT,
    OrderDate       NVARCHAR(64),
    SourceType      NVARCHAR(32),
    RawPayload      NVARCHAR(MAX),
    LoadedAt        DATETIME2 NOT NULL DEFAULT SYSDATETIMEOFFSET()
);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Landing_Orders_RunId' AND object_id = OBJECT_ID('dbo.Landing_Orders'))
CREATE INDEX IX_Landing_Orders_RunId ON dbo.Landing_Orders(RunId);
GO
IF OBJECT_ID('dbo.Staging_Orders', 'U') IS NULL
CREATE TABLE dbo.Staging_Orders (
    Id              INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    RunId           NVARCHAR(64) NOT NULL,
    OrderId         NVARCHAR(128) NOT NULL,
    CustomerId      NVARCHAR(128) NOT NULL,
    Amount          FLOAT NOT NULL,
    OrderDate       NVARCHAR(64),
    ExtractedAt     DATETIME2 NOT NULL DEFAULT SYSDATETIMEOFFSET()
);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Staging_Orders_RunId' AND object_id = OBJECT_ID('dbo.Staging_Orders'))
CREATE INDEX IX_Staging_Orders_RunId ON dbo.Staging_Orders(RunId);
GO
IF OBJECT_ID('dbo.Staging_Orders_Transformed', 'U') IS NULL
CREATE TABLE dbo.Staging_Orders_Transformed (
    Id              INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    RunId           NVARCHAR(64) NOT NULL,
    OrderId         NVARCHAR(128) NOT NULL,
    CustomerId      NVARCHAR(128) NOT NULL,
    Amount          FLOAT NOT NULL,
    OrderDate       NVARCHAR(64),
    AmountCategory  NVARCHAR(32),
    TransformedAt   DATETIME2 NOT NULL DEFAULT SYSDATETIMEOFFSET()
);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Staging_Orders_Transformed_RunId' AND object_id = OBJECT_ID('dbo.Staging_Orders_Transformed'))
CREATE INDEX IX_Staging_Orders_Transformed_RunId ON dbo.Staging_Orders_Transformed(RunId);
GO
IF OBJECT_ID('dbo.Target_Orders', 'U') IS NULL
CREATE TABLE dbo.Target_Orders (
    Id              INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    OrderId         NVARCHAR(128) NOT NULL UNIQUE,
    CustomerId      NVARCHAR(128) NOT NULL,
    Amount          FLOAT NOT NULL,
    OrderDate       NVARCHAR(64),
    AmountCategory  NVARCHAR(32),
    MigratedAt      DATETIME2 NOT NULL DEFAULT SYSDATETIMEOFFSET()
);
GO
IF OBJECT_ID('dbo.PipelineSchedules', 'U') IS NULL
CREATE TABLE dbo.PipelineSchedules (
    ScheduleId      NVARCHAR(64) NOT NULL PRIMARY KEY,
    Name            NVARCHAR(256) NOT NULL,
    ScheduleType    NVARCHAR(16) NOT NULL,
    RunAtTime       NVARCHAR(8) NOT NULL,
    DayOfWeek       INT NULL,
    DayOfMonth      INT NULL,
    SourcePath      NVARCHAR(512) NULL,
    Enabled         BIT NOT NULL DEFAULT 1,
    CreatedAt       DATETIME2 NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    UpdatedAt       DATETIME2 NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    LastRunAt       DATETIME2 NULL,
    NextRunAt       DATETIME2 NULL
);
GO
