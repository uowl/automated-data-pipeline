package com.pipeline.steps;

import com.pipeline.StepProgress;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;

public class MigrateStep {

    /** SQL Server MERGE for upsert by OrderId. */
    private static final String MERGE_SQL =
        "MERGE dbo.Target_Orders AS t " +
        "USING (SELECT ? AS OrderId, ? AS CustomerId, ? AS Amount, ? AS OrderDate, ? AS AmountCategory) AS s " +
        "ON t.OrderId = s.OrderId " +
        "WHEN MATCHED THEN UPDATE SET CustomerId = s.CustomerId, Amount = s.Amount, OrderDate = s.OrderDate, AmountCategory = s.AmountCategory, MigratedAt = SYSDATETIMEOFFSET() " +
        "WHEN NOT MATCHED THEN INSERT (OrderId, CustomerId, Amount, OrderDate, AmountCategory, MigratedAt) VALUES (s.OrderId, s.CustomerId, s.Amount, s.OrderDate, s.AmountCategory, SYSDATETIMEOFFSET());";

    private static final int BATCH_SIZE = 2000;

    public static int run(Connection conn, String runId, int stepNumber) throws SQLException {
        Integer total = null;
        try (PreparedStatement cnt = conn.prepareStatement("SELECT COUNT(*) FROM dbo.Staging_Orders_Transformed WHERE RunId = ?")) {
            cnt.setString(1, runId);
            try (ResultSet rs = cnt.executeQuery()) {
                if (rs.next()) total = rs.getInt(1);
            }
        }
        String sel = "SELECT OrderId, CustomerId, Amount, OrderDate, AmountCategory FROM dbo.Staging_Orders_Transformed WHERE RunId = ?";
        int count = 0;
        try (PreparedStatement select = conn.prepareStatement(sel);
             PreparedStatement merge = conn.prepareStatement(MERGE_SQL)) {
            select.setString(1, runId);
            try (ResultSet rs = select.executeQuery()) {
                int batchCount = 0;
                while (rs.next()) {
                    merge.setString(1, rs.getString("OrderId"));
                    merge.setString(2, rs.getString("CustomerId"));
                    merge.setDouble(3, rs.getDouble("Amount"));
                    merge.setString(4, rs.getString("OrderDate"));
                    merge.setString(5, rs.getString("AmountCategory"));
                    merge.addBatch();
                    count++;
                    if (++batchCount >= BATCH_SIZE) {
                        merge.executeBatch();
                        batchCount = 0;
                        if (StepProgress.shouldUpdate(count)) {
                            StepProgress.update(runId, stepNumber, count, total);
                        }
                    }
                }
                if (batchCount > 0) merge.executeBatch();
                if (StepProgress.shouldUpdate(count)) {
                    StepProgress.update(runId, stepNumber, count, total);
                }
            }
        }
        return count;
    }
}
