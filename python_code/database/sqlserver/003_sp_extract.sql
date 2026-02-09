-- Extract: read from Landing_Orders, normalize into Staging_Orders, update StepRuns (Step 2)
CREATE OR ALTER PROCEDURE dbo.usp_Extract_Orders
    @RunId UNIQUEIDENTIFIER
AS
SET NOCOUNT ON;
DECLARE @StepRunId BIGINT, @RowsAffected BIGINT, @ErrMsg NVARCHAR(MAX);

BEGIN TRY
    -- Mark step as Running
    INSERT INTO dbo.StepRuns (RunId, StepNumber, StepName, Status, StartedAt)
    VALUES (@RunId, 2, 'Extract (SP)', 'Running', SYSUTCDATETIME());
    SET @StepRunId = SCOPE_IDENTITY();

    -- Extract: landing -> staging (normalize types, filter invalid)
    INSERT INTO dbo.Staging_Orders (RunId, OrderId, CustomerId, Amount, OrderDate)
    SELECT
        RunId,
        NULLIF(LTRIM(RTRIM(OrderId)), ''),
        NULLIF(LTRIM(RTRIM(CustomerId)), ''),
        TRY_CAST(NULLIF(LTRIM(RTRIM(Amount)), '') AS DECIMAL(18,2)),
        TRY_CAST(NULLIF(LTRIM(RTRIM(OrderDate)), '') AS DATE)
    FROM dbo.Landing_Orders
    WHERE RunId = @RunId
      AND OrderId IS NOT NULL AND LTRIM(RTRIM(OrderId)) <> '';

    SET @RowsAffected = @@ROWCOUNT;

    -- Mark step as Success
    UPDATE dbo.StepRuns
    SET Status = 'Success', FinishedAt = SYSUTCDATETIME(), RowsAffected = @RowsAffected
    WHERE StepRunId = @StepRunId;
END TRY
BEGIN CATCH
    SET @ErrMsg = ERROR_MESSAGE();
    UPDATE dbo.StepRuns
    SET Status = 'Failed', FinishedAt = SYSUTCDATETIME(), ErrorMessage = @ErrMsg
    WHERE StepRunId = @StepRunId;
    THROW;
END CATCH
GO
