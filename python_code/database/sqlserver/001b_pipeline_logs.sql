-- Pipeline logs table: store log entries for each run (show in Web GUI)
-- Run after 001_control_tables.sql

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'PipelineLogs')
BEGIN
    CREATE TABLE dbo.PipelineLogs (
        LogId           BIGINT IDENTITY(1,1) PRIMARY KEY,
        RunId           UNIQUEIDENTIFIER NOT NULL,
        PipelineName    NVARCHAR(256)    NULL,
        LogAt           DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
        Level           NVARCHAR(16)     NOT NULL DEFAULT 'Info',
        StepNumber      TINYINT          NULL,
        StepName        NVARCHAR(64)     NULL,
        Message         NVARCHAR(MAX)    NOT NULL,
        Details         NVARCHAR(MAX)    NULL,
        CONSTRAINT FK_PipelineLogs_PipelineRuns FOREIGN KEY (RunId) REFERENCES dbo.PipelineRuns(RunId)
    );
    CREATE INDEX IX_PipelineLogs_RunId ON dbo.PipelineLogs(RunId);
    CREATE INDEX IX_PipelineLogs_LogAt ON dbo.PipelineLogs(LogAt);
END
GO
