package com.pipeline;

import com.pipeline.steps.PullStep;
import com.pipeline.steps.ExtractStep;
import com.pipeline.steps.TransformStep;
import com.pipeline.steps.MigrateStep;

import java.nio.file.Paths;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Orchestrates the 4-step pipeline: Data Pull → Extract → Transform → Migrate.
 */
public class PipelineRunner {

    private static final String PIPELINE_NAME = System.getenv("PIPELINE_NAME") != null ? System.getenv("PIPELINE_NAME") : "SamplePipeline";
    private static final String[] STEP_NAMES = { "Data Pull", "Extract (SP)", "Transform (SP)", "Migrate (SP)" };
    private static final ExecutorService BACKGROUND = Executors.newCachedThreadPool(r -> {
        Thread t = new Thread(r, "pipeline-worker");
        t.setDaemon(true);
        return t;
    });

    @FunctionalInterface
    private interface StepRunner {
        int run(Connection c, String runId, String csvPath, int stepNumber) throws Exception;
    }

    private static final ConcurrentHashMap<String, Boolean> CANCELLED_RUNS = new ConcurrentHashMap<>();

    /** Request cancellation of a running pipeline. Idempotent. */
    public static void cancelRun(String runId) {
        if (runId != null && !runId.isEmpty()) CANCELLED_RUNS.put(runId, Boolean.TRUE);
    }

    /** True if this run has been requested to cancel. */
    public static boolean isCancelled(String runId) {
        return runId != null && CANCELLED_RUNS.containsKey(runId);
    }

    private static final StepRunner[] STEPS = new StepRunner[] {
        PullStep::run,
        (c, runId, csvPath, stepNum) -> ExtractStep.run(c, runId, stepNum),
        (c, runId, csvPath, stepNum) -> TransformStep.run(c, runId, stepNum),
        (c, runId, csvPath, stepNum) -> MigrateStep.run(c, runId, stepNum),
    };

    /** Creates run + 4 step rows and returns runId. Pipeline steps run in background. */
    public static String startPipelineRun(String csvPath) throws SQLException {
        return startPipelineRun(csvPath, null, null, null, null);
    }

    /** Same as startPipelineRun(csvPath) but with optional DB connection overrides. */
    public static String startPipelineRun(String csvPath, String dbHost, Integer dbPort, String dbUser, String dbPassword) throws SQLException {
        Connection c = (dbHost != null || dbPort != null || dbUser != null || dbPassword != null)
            ? Database.getConnection(dbHost, dbPort, dbUser, dbPassword)
            : Database.getConnection();
        try {
            c.setAutoCommit(false);
            String runId = UUID.randomUUID().toString();
            String now = Instant.now().toString();

            int nextRunNumber = 1;
            try (ResultSet rs = c.createStatement().executeQuery("SELECT COALESCE(MAX(RunNumber), 0) + 1 AS n FROM dbo.PipelineRuns")) {
                if (rs.next()) nextRunNumber = rs.getInt("n");
            }

            try (PreparedStatement ps = c.prepareStatement(
                "INSERT INTO dbo.PipelineRuns (RunId, RunNumber, PipelineName, ADFRunId, StartedAt, Status) VALUES (?,?,?,?,?,?)")) {
                ps.setString(1, runId);
                ps.setInt(2, nextRunNumber);
                ps.setString(3, PIPELINE_NAME);
                ps.setString(4, "local-" + System.currentTimeMillis());
                ps.setString(5, now);
                ps.setString(6, "Running");
                ps.executeUpdate();
            }

            try (PreparedStatement ps = c.prepareStatement(
                "INSERT INTO dbo.StepRuns (RunId, StepNumber, StepName, Status) VALUES (?,?,?,?)")) {
                for (int i = 0; i < 4; i++) {
                    ps.setString(1, runId);
                    ps.setInt(2, i + 1);
                    ps.setString(3, STEP_NAMES[i]);
                    ps.setString(4, "Pending");
                    ps.executeUpdate();
                }
            }
            c.commit();

            final String runIdFinal = runId;
            final String pathFinal = csvPath;
            final String h = dbHost;
            final Integer p = dbPort;
            final String u = dbUser;
            final String pw = dbPassword;
            BACKGROUND.submit(() -> {
                try {
                    executePipelineSteps(runIdFinal, pathFinal, h, p, u, pw);
                } catch (Throwable e) {
                    e.printStackTrace();
                    logRunErrorAndMarkFailed(runIdFinal, e.getMessage(), e.toString(), h, p, u, pw);
                }
            });
            return runId;
        } finally {
            c.close();
        }
    }

    public static void executePipelineSteps(String runId, String csvPath) {
        executePipelineSteps(runId, csvPath, null, null, null, null);
    }

    public static void executePipelineSteps(String runId, String csvPath, String dbHost, Integer dbPort, String dbUser, String dbPassword) {
        StepProgress.setDbParams(dbHost, dbPort, dbUser, dbPassword);
        try {
            if (isCancelled(runId)) return;
            Connection conn = (dbHost != null || dbPort != null || dbUser != null || dbPassword != null)
                ? Database.getConnection(dbHost, dbPort, dbUser, dbPassword)
                : Database.getConnection();
            try {
                try {
                    Database.initSchema(dbHost, dbPort, dbUser, dbPassword);
                } catch (SQLException e) {
                    logRunErrorAndMarkFailed(runId, e.getMessage(), e.toString(), dbHost, dbPort, dbUser, dbPassword);
                    return;
                }
                boolean wasAutoCommit = conn.getAutoCommit();
                conn.setAutoCommit(false);
                // Step 0: run is initialized and visible; log so UI has an immediate entry
                PipelineLogger.log(conn, runId, "Info", "Step 0: Run initialized", PIPELINE_NAME, 0, "Initialization", null);
                conn.commit();
                try {
                    runPipeline(conn, runId, csvPath);
                } finally {
                    try {
                        conn.setAutoCommit(wasAutoCommit);
                    } catch (SQLException ignored) {}
                }
            } finally {
                conn.close();
            }
        } catch (SQLException e) {
            e.printStackTrace();
            logRunErrorAndMarkFailed(runId, e.getMessage(), e.toString(), dbHost, dbPort, dbUser, dbPassword);
        } finally {
            CANCELLED_RUNS.remove(runId);
            StepProgress.clearDbParams();
        }
    }

    /** Write error to run logs and set run status to Failed. Uses best-effort connection (same DB params, then default). */
    private static void logRunErrorAndMarkFailed(String runId, String message, String details,
                                                 String dbHost, Integer dbPort, String dbUser, String dbPassword) {
        if (runId == null) return;
        Connection c = null;
        try {
            c = (dbHost != null || dbPort != null || dbUser != null || dbPassword != null)
                ? Database.getConnection(dbHost, dbPort, dbUser, dbPassword)
                : Database.getConnection();
        } catch (SQLException ignored) {
            try {
                c = Database.getConnection();
            } catch (SQLException ignored2) {
                return;
            }
        }
        try {
            c.setAutoCommit(false);
            PipelineLogger.log(c, runId, "Error", message != null ? message : "Pipeline failed", PIPELINE_NAME, null, null, details);
            markRunFinished(c, runId, "Failed");
        } catch (SQLException ignored) {
        } finally {
            try {
                if (c != null) c.close();
            } catch (SQLException ignored) {}
        }
    }

    private static void runPipeline(Connection c, String runId, String csvPath) throws SQLException {
        PipelineLogger.log(c, runId, "Info",
            "Pipeline started" + (csvPath != null ? " with file: " + Paths.get(csvPath).getFileName() : ""),
            PIPELINE_NAME, null, null, null);

        List<StepRow> steps = loadSteps(c, runId);
        if (steps.size() != 4) {
            PipelineLogger.log(c, runId, "Error", "Expected 4 step rows, got " + steps.size(), PIPELINE_NAME, null, null, null);
            return;
        }

        try {
            int lastRows = 0;
            for (int i = 0; i < 4; i++) {
                if (isCancelled(runId)) {
                    PipelineLogger.log(c, runId, "Info", "Pipeline cancelled by user", PIPELINE_NAME, null, null, null);
                    markFirstRunningStepFailed(c, runId, steps, "Cancelled");
                    markRunFinished(c, runId, "Cancelled");
                    return;
                }
                StepRow step = steps.get(i);
                updateStepRunning(c, step.stepRunId);
                PipelineLogger.log(c, runId, "Info", "Step " + (i + 1) + " started", PIPELINE_NAME, i + 1, STEP_NAMES[i], null);
                c.commit(); // commit so UI and logs show step as "Running" / "In Progress" immediately

                int rows = STEPS[i].run(c, runId, csvPath, i + 1);
                lastRows = rows;
                c.commit();

                updateStepSuccess(c, step.stepRunId, rows, null);
                PipelineLogger.log(c, runId, "Info", STEP_NAMES[i] + " completed: " + rows + " rows",
                    PIPELINE_NAME, i + 1, STEP_NAMES[i], "RowsAffected: " + rows);
            }

            markRunFinished(c, runId, "Success");
            PipelineLogger.log(c, runId, "Info", "Pipeline completed successfully", PIPELINE_NAME, null, null, "Total rows migrated: " + lastRows);

        } catch (Exception e) {
            try {
                c.rollback();
            } catch (SQLException ignored) {}
            PipelineLogger.log(c, runId, "Error", "Pipeline failed: " + e.getMessage(), PIPELINE_NAME, null, null, e.toString());

            markFirstRunningStepFailed(c, runId, steps, e.getMessage());
            markRunFinished(c, runId, "Failed");
        }
    }

    private static List<StepRow> loadSteps(Connection c, String runId) throws SQLException {
        List<StepRow> steps = new ArrayList<>();
        try (PreparedStatement ps = c.prepareStatement("SELECT StepRunId, StepNumber FROM dbo.StepRuns WHERE RunId = ? ORDER BY StepNumber")) {
            ps.setString(1, runId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    StepRow row = new StepRow();
                    row.stepRunId = rs.getLong("StepRunId");
                    row.stepNumber = rs.getInt("StepNumber");
                    steps.add(row);
                }
            }
        }
        return steps;
    }

    private static void markFirstRunningStepFailed(Connection c, String runId, List<StepRow> steps, String errorMessage) {
        for (StepRow step : steps) {
            try (ResultSet r = c.createStatement().executeQuery("SELECT Status FROM dbo.StepRuns WHERE StepRunId = " + step.stepRunId)) {
                if (r.next() && "Running".equals(r.getString("Status"))) {
                    try {
                        updateStepSuccess(c, step.stepRunId, 0, errorMessage);
                        PipelineLogger.log(c, runId, "Error", "Step " + step.stepNumber + " failed", PIPELINE_NAME, step.stepNumber, STEP_NAMES[step.stepNumber - 1], errorMessage);
                    } catch (SQLException ignored) {}
                    break;
                }
            } catch (SQLException ignored) {}
        }
    }

    private static void markRunFinished(Connection c, String runId, String status) throws SQLException {
        try (PreparedStatement ps = c.prepareStatement("UPDATE dbo.PipelineRuns SET Status = ?, FinishedAt = ? WHERE RunId = ?")) {
            ps.setString(1, status);
            ps.setString(2, Instant.now().toString());
            ps.setString(3, runId);
            ps.executeUpdate();
        }
        c.commit();
    }

    private static void updateStepRunning(Connection c, long stepRunId) throws SQLException {
        String now = Instant.now().toString();
        try (PreparedStatement ps = c.prepareStatement("UPDATE dbo.StepRuns SET Status = ?, StartedAt = ? WHERE StepRunId = ?")) {
            ps.setString(1, "Running");
            ps.setString(2, now);
            ps.setLong(3, stepRunId);
            ps.executeUpdate();
        }
    }

    private static void updateStepSuccess(Connection c, long stepRunId, int rowsAffected, String errorMessage) throws SQLException {
        String now = Instant.now().toString();
        try (PreparedStatement ps = c.prepareStatement("UPDATE dbo.StepRuns SET Status = ?, FinishedAt = ?, RowsAffected = ?, ErrorMessage = ? WHERE StepRunId = ?")) {
            ps.setString(1, errorMessage != null ? "Failed" : "Success");
            ps.setString(2, now);
            ps.setInt(3, rowsAffected);
            ps.setString(4, errorMessage);
            ps.setLong(5, stepRunId);
            ps.executeUpdate();
        }
    }

    static class StepRow {
        long stepRunId;
        int stepNumber;
    }
}
