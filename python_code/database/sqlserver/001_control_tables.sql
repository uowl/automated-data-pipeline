-- Control tables for pipeline runs and step tracking (Web GUI + orchestration)
-- Run against your staging database.

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'PipelineRuns')
BEGIN
    CREATE TABLE dbo.PipelineRuns (
        RunId           UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
        RunNumber       BIGINT IDENTITY(1,1) NOT NULL,
        PipelineName    NVARCHAR(256)    NOT NULL,
        ADFRunId        NVARCHAR(128)    NULL,
        StartedAt       DATETIME2        NULL,
        FinishedAt      DATETIME2        NULL,
        Status          NVARCHAR(32)     NOT NULL DEFAULT 'Running',
        CreatedAt       DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
    );
    CREATE UNIQUE INDEX IX_PipelineRuns_RunNumber ON dbo.PipelineRuns(RunNumber);
END

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'StepRuns')
BEGIN
    CREATE TABLE dbo.StepRuns (
        StepRunId       BIGINT IDENTITY(1,1) PRIMARY KEY,
        RunId           UNIQUEIDENTIFIER NOT NULL,
        StepNumber      TINYINT          NOT NULL,
        StepName        NVARCHAR(64)     NOT NULL,
        StartedAt       DATETIME2        NULL,
        FinishedAt      DATETIME2        NULL,
        Status          NVARCHAR(32)    NOT NULL DEFAULT 'Pending',
        RowsAffected    BIGINT           NULL,
        ErrorMessage    NVARCHAR(MAX)    NULL,
        CreatedAt       DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT FK_StepRuns_PipelineRuns FOREIGN KEY (RunId) REFERENCES dbo.PipelineRuns(RunId)
    );
    CREATE INDEX IX_StepRuns_RunId ON dbo.StepRuns(RunId);
END
GO
