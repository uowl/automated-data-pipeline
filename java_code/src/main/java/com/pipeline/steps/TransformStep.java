package com.pipeline.steps;

import com.pipeline.StepProgress;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;

public class TransformStep {

    private static final int BATCH_SIZE = 2000;

    public static int run(Connection conn, String runId, int stepNumber) throws SQLException {
        Integer total = null;
        try (PreparedStatement cnt = conn.prepareStatement("SELECT COUNT(*) FROM dbo.Staging_Orders WHERE RunId = ?")) {
            cnt.setString(1, runId);
            try (ResultSet rs = cnt.executeQuery()) {
                if (rs.next()) total = rs.getInt(1);
            }
        }
        String sel = "SELECT * FROM dbo.Staging_Orders WHERE RunId = ?";
        String ins = "INSERT INTO dbo.Staging_Orders_Transformed (RunId, OrderId, CustomerId, Amount, OrderDate, AmountCategory) VALUES (?,?,?,?,?,?)";
        int count = 0;
        try (PreparedStatement select = conn.prepareStatement(sel);
             PreparedStatement insert = conn.prepareStatement(ins)) {
            select.setString(1, runId);
            try (ResultSet rs = select.executeQuery()) {
                int batchCount = 0;
                while (rs.next()) {
                    double amount = rs.getDouble("Amount");
                    String category;
                    if (amount < 0) {
                        category = "InvalidNegativeAmountExceedsMaxLength"; // 33 chars -> fails NVARCHAR(32)
                    } else {
                        category = amount < 50 ? "Low" : amount < 200 ? "Medium" : "High";
                    }
                    insert.setString(1, runId);
                    insert.setString(2, rs.getString("OrderId"));
                    insert.setString(3, rs.getString("CustomerId"));
                    insert.setDouble(4, amount);
                    insert.setString(5, rs.getString("OrderDate"));
                    insert.setString(6, category);
                    insert.addBatch();
                    count++;
                    if (++batchCount >= BATCH_SIZE) {
                        insert.executeBatch();
                        batchCount = 0;
                        if (StepProgress.shouldUpdate(count)) {
                            StepProgress.update(runId, stepNumber, count, total);
                        }
                    }
                }
                if (batchCount > 0) insert.executeBatch();
                if (StepProgress.shouldUpdate(count)) {
                    StepProgress.update(runId, stepNumber, count, total);
                }
            }
        }
        return count;
    }
}
