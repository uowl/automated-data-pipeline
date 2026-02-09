-- Migrate: read from Staging_Orders_Transformed, load into Target_Orders, update StepRuns (Step 4)
CREATE OR ALTER PROCEDURE dbo.usp_Migrate_Orders
    @RunId UNIQUEIDENTIFIER
AS
SET NOCOUNT ON;
DECLARE @StepRunId BIGINT, @RowsAffected BIGINT, @ErrMsg NVARCHAR(MAX);

BEGIN TRY
    INSERT INTO dbo.StepRuns (RunId, StepNumber, StepName, Status, StartedAt)
    VALUES (@RunId, 4, 'Migrate (SP)', 'Running', SYSUTCDATETIME());
    SET @StepRunId = SCOPE_IDENTITY();

    -- Migrate: staging -> target (merge/upsert by OrderId)
    MERGE dbo.Target_Orders AS t
    USING (
        SELECT OrderId, CustomerId, Amount, OrderDate, AmountCategory
        FROM dbo.Staging_Orders_Transformed
        WHERE RunId = @RunId
    ) AS s ON t.OrderId = s.OrderId
    WHEN MATCHED THEN
        UPDATE SET CustomerId = s.CustomerId, Amount = s.Amount, OrderDate = s.OrderDate, AmountCategory = s.AmountCategory, MigratedAt = SYSUTCDATETIME()
    WHEN NOT MATCHED THEN
        INSERT (OrderId, CustomerId, Amount, OrderDate, AmountCategory, MigratedAt)
        VALUES (s.OrderId, s.CustomerId, s.Amount, s.OrderDate, s.AmountCategory, SYSUTCDATETIME());

    SET @RowsAffected = @@ROWCOUNT;

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
