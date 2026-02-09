-- Transform: read from Staging_Orders, apply business rules, write to Staging_Orders_Transformed, update StepRuns (Step 3)
CREATE OR ALTER PROCEDURE dbo.usp_Transform_Orders
    @RunId UNIQUEIDENTIFIER
AS
SET NOCOUNT ON;
DECLARE @StepRunId BIGINT, @RowsAffected BIGINT, @ErrMsg NVARCHAR(MAX);

BEGIN TRY
    INSERT INTO dbo.StepRuns (RunId, StepNumber, StepName, Status, StartedAt)
    VALUES (@RunId, 3, 'Transform (SP)', 'Running', SYSUTCDATETIME());
    SET @StepRunId = SCOPE_IDENTITY();

    -- Transform: add AmountCategory (business rule)
    INSERT INTO dbo.Staging_Orders_Transformed (RunId, OrderId, CustomerId, Amount, OrderDate, AmountCategory)
    SELECT
        RunId,
        OrderId,
        CustomerId,
        Amount,
        OrderDate,
        CASE
            WHEN Amount < 50 THEN 'Low'
            WHEN Amount < 200 THEN 'Medium'
            ELSE 'High'
        END
    FROM dbo.Staging_Orders
    WHERE RunId = @RunId;

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
