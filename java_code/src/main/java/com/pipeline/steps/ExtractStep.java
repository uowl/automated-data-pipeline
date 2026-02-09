package com.pipeline.steps;

import com.pipeline.StepProgress;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.LocalDate;
import java.time.format.DateTimeParseException;

public class ExtractStep {

    private static final int BATCH_SIZE = 2000;

    public static int run(Connection conn, String runId, int stepNumber) throws SQLException {
        Integer total = null;
        try (PreparedStatement cnt = conn.prepareStatement("SELECT COUNT(*) FROM dbo.Landing_Orders WHERE RunId = ?")) {
            cnt.setString(1, runId);
            try (ResultSet rs = cnt.executeQuery()) {
                if (rs.next()) total = rs.getInt(1);
            }
        }
        String sel = "SELECT * FROM dbo.Landing_Orders WHERE RunId = ?";
        String ins = "INSERT INTO dbo.Staging_Orders (RunId, OrderId, CustomerId, Amount, OrderDate) VALUES (?,?,?,?,?)";
        int count = 0;
        try (PreparedStatement select = conn.prepareStatement(sel);
             PreparedStatement insert = conn.prepareStatement(ins)) {
            select.setString(1, runId);
            try (ResultSet rs = select.executeQuery()) {
                int batchCount = 0;
                while (rs.next()) {
                    String orderId = trim(rs.getString("OrderId"));
                    if (orderId == null || orderId.isEmpty()) continue;
                    String customerId = trim(rs.getString("CustomerId"));
                    if (customerId == null || customerId.isEmpty()) customerId = "UNKNOWN";
                    double amount = 0;
                    try {
                        String a = rs.getString("Amount");
                        if (a != null && !a.isEmpty()) amount = Double.parseDouble(a.trim());
                    } catch (NumberFormatException ignored) {}
                    String orderDateStr = trim(rs.getString("OrderDate"));
                    String orderDate = null;
                    if (orderDateStr != null && !orderDateStr.isEmpty()) {
                        try {
                            orderDate = LocalDate.parse(orderDateStr).toString();
                        } catch (DateTimeParseException ignored) {}
                    }
                    insert.setString(1, runId);
                    insert.setString(2, orderId);
                    insert.setString(3, customerId);
                    insert.setDouble(4, amount);
                    insert.setString(5, orderDate);
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

    private static String trim(String s) {
        return s == null ? null : s.trim();
    }
}
