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
        Database.initSchema(dbHost, dbPort, dbUser, dbPassword);
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
                } catch (Exception e) {
                    e.printStackTrace();
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
        Connection conn = null;
        try {
            conn = (dbHost != null || dbPort != null || dbUser != null || dbPassword != null)
                ? Database.getConnection(dbHost, dbPort, dbUser, dbPassword)
                : Database.getConnection();
            boolean wasAutoCommit = conn.getAutoCommit();
            conn.setAutoCommit(false);
            try {
                runPipeline(conn, runId, csvPath);
            } finally {
                try {
                    conn.setAutoCommit(wasAutoCommit);
                } catch (SQLException ignored) {}
            }
        } catch (SQLException e) {
            e.printStackTrace();
        } finally {
            StepProgress.clearDbParams();
            if (conn != null) {
                try { conn.close(); } catch (SQLException ignored) {}
            }
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
                StepRow step = steps.get(i);
                updateStepRunning(c, step.stepRunId);
                PipelineLogger.log(c, runId, "Info", "Step " + (i + 1) + " started", PIPELINE_NAME, i + 1, STEP_NAMES[i], null);

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
