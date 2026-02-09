-- Add RunNumber (auto-increment project id) to PipelineRuns
-- Run after 001_control_tables.sql. For new installs, add RunNumber to the CREATE TABLE in 001 instead.

IF NOT EXISTS (
    SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.PipelineRuns') AND name = 'RunNumber'
)
BEGIN
    ALTER TABLE dbo.PipelineRuns ADD RunNumber BIGINT IDENTITY(1,1) NOT NULL;
    CREATE UNIQUE INDEX IX_PipelineRuns_RunNumber ON dbo.PipelineRuns(RunNumber);
END
GO
