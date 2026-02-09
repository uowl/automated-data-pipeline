package com.pipeline;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.SQLException;

/** Updates StepRuns with row-level progress (RowsProcessed / RowsTotal). Uses separate connection so updates are visible immediately. */
public final class StepProgress {

    private static final int UPDATE_INTERVAL = 10_000;

    private static final ThreadLocal<Object[]> DB_PARAMS = new ThreadLocal<>();

    /** Set DB connection params for progress updates (same DB as pipeline run). Call from PipelineRunner before steps. */
    public static void setDbParams(String host, Integer port, String user, String password) {
        DB_PARAMS.set(new Object[] { host, port, user, password });
    }

    /** Clear DB params. Call after pipeline completes. */
    public static void clearDbParams() {
        DB_PARAMS.remove();
    }

    /** Call periodically from steps to update progress. Uses its own connection so UI sees updates before step commits. */
    public static void update(String runId, int stepNumber, int processed, Integer total) {
        if (runId == null) return;
        try {
            Object[] p = DB_PARAMS.get();
            Connection conn = (p != null && (p[0] != null || p[1] != null || p[2] != null || p[3] != null))
                ? Database.getConnection((String) p[0], (Integer) p[1], (String) p[2], (String) p[3])
                : Database.getConnection();
            try (PreparedStatement ps = conn.prepareStatement(
                "UPDATE dbo.StepRuns SET RowsProcessed = ?, RowsTotal = ? WHERE RunId = ? AND StepNumber = ?")) {
                ps.setInt(1, processed);
                ps.setObject(2, total);
                ps.setString(3, runId);
                ps.setInt(4, stepNumber);
                ps.executeUpdate();
                conn.commit();
            } finally {
                conn.close();
            }
        } catch (SQLException e) {
            // Progress is best-effort; don't fail the step
        }
    }

    /** Whether to update (every UPDATE_INTERVAL rows to avoid excessive DB writes). */
    public static boolean shouldUpdate(int processed) {
        return processed > 0 && (processed % UPDATE_INTERVAL == 0 || processed < UPDATE_INTERVAL);
    }
}
