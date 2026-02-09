package com.pipeline.steps;

import com.pipeline.Database;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import com.google.gson.Gson;
import com.google.gson.reflect.TypeToken;

public class PullStep {

    private static final Gson GSON = new Gson();

    public static int run(Connection conn, String runId, String filePath, int stepNumber) throws SQLException, IOException {
        if (filePath == null || filePath.isEmpty()) return 0;
        Path p = Paths.get(filePath);
        String fileName = p.getFileName().toString();
        String ext = fileName.contains(".") ? fileName.substring(fileName.lastIndexOf('.')).toLowerCase() : "";

        List<LandingRow> rows = new ArrayList<>();
        if (".csv".equals(ext)) {
            List<String> lines = Files.readAllLines(p);
            if (lines.isEmpty()) return 0;
            String[] headers = lines.get(0).split(",");
            for (int i = 1; i < lines.size(); i++) {
                String[] vals = parseCsvLine(lines.get(i));
                LandingRow row = new LandingRow();
                row.runId = runId;
                row.orderId = getVal(vals, headers, "OrderId", "orderId");
                row.customerId = getVal(vals, headers, "CustomerId", "customerId");
                row.amount = getVal(vals, headers, "Amount", "amount");
                row.orderDate = getVal(vals, headers, "OrderDate", "orderDate");
                row.sourceType = "CSV";
                row.rawPayload = null;
                rows.add(row);
            }
        } else if (".json".equals(ext)) {
            String json = Files.readString(p);
            List<Map<String, Object>> list = GSON.fromJson(json, new TypeToken<List<Map<String, Object>>>(){}.getType());
            if (list == null) return 0;
            for (Map<String, Object> m : list) {
                LandingRow row = new LandingRow();
                row.runId = runId;
                row.orderId = get(m, "OrderId", "orderId");
                row.customerId = get(m, "CustomerId", "customerId");
                Object amt = m.get("Amount");
                if (amt == null) amt = m.get("amount");
                row.amount = amt != null ? String.valueOf(amt) : null;
                row.orderDate = get(m, "OrderDate", "orderDate");
                row.sourceType = "JSON";
                row.rawPayload = GSON.toJson(m);
                rows.add(row);
            }
        }

        final int batchSize = 2000;
        final int total = rows.size();
        String insert = "INSERT INTO dbo.Landing_Orders (RunId, OrderId, CustomerId, Amount, OrderDate, SourceType, RawPayload) VALUES (?,?,?,?,?,?,?)";
        try (PreparedStatement ps = conn.prepareStatement(insert)) {
            int n = 0;
            for (LandingRow r : rows) {
                ps.setString(1, r.runId);
                ps.setString(2, r.orderId);
                ps.setString(3, r.customerId);
                ps.setString(4, r.amount);
                ps.setString(5, r.orderDate);
                ps.setString(6, r.sourceType);
                ps.setString(7, r.rawPayload);
                ps.addBatch();
                n++;
                if (n % batchSize == 0) {
                    ps.executeBatch();
                    if (com.pipeline.StepProgress.shouldUpdate(n)) {
                        com.pipeline.StepProgress.update(runId, stepNumber, n, total);
                    }
                }
            }
            if (n % batchSize != 0) ps.executeBatch();
            if (com.pipeline.StepProgress.shouldUpdate(n)) {
                com.pipeline.StepProgress.update(runId, stepNumber, n, total);
            }
        }
        return rows.size();
    }

    private static String getVal(String[] vals, String[] headers, String... keys) {
        for (String key : keys) {
            for (int i = 0; i < headers.length; i++) {
                if (headers[i].trim().equalsIgnoreCase(key) && i < vals.length) {
                    String v = vals[i];
                    return v != null ? v.trim() : null;
                }
            }
        }
        return null;
    }

    private static String get(Map<String, Object> m, String... keys) {
        for (String k : keys) {
            Object v = m.get(k);
            if (v != null) return v.toString();
        }
        return null;
    }

    private static String[] parseCsvLine(String line) {
        List<String> out = new ArrayList<>();
        StringBuilder cur = new StringBuilder();
        boolean inQuotes = false;
        for (int i = 0; i < line.length(); i++) {
            char c = line.charAt(i);
            if (c == '"') inQuotes = !inQuotes;
            else if ((c == ',' && !inQuotes) || c == '\n') {
                out.add(cur.toString().trim());
                cur = new StringBuilder();
            } else cur.append(c);
        }
        out.add(cur.toString().trim());
        return out.toArray(new String[0]);
    }

    static class LandingRow {
        String runId, orderId, customerId, amount, orderDate, sourceType, rawPayload;
    }
}
