package com.pipeline;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.SQLException;
import java.time.Instant;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;

public class PipelineLogger {

    private static final ZoneId LOCAL_ZONE = ZoneId.systemDefault();
    private static final DateTimeFormatter LOCAL_FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss.SSS");

    public static void log(Connection conn, String runId, String level, String message,
                           String pipelineName, Integer stepNumber, String stepName, String details) throws SQLException {
        Instant instant = Instant.now();
        String nowUtc = instant.toString();
        String nowLocal = instant.atZone(LOCAL_ZONE).format(LOCAL_FMT);
        String prefix = "Error".equals(level) ? "ERROR" : "Warning".equals(level) ? "WARN" : "INFO";
        System.out.println(nowLocal + " " + prefix + (stepNumber != null ? " [Step " + stepNumber + "]" : "") + " " + message);

        String sql = "INSERT INTO dbo.PipelineLogs (RunId, PipelineName, LogAt, Level, StepNumber, StepName, Message, Details) VALUES (?,?,?,?,?,?,?,?)";
        try (PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, runId);
            ps.setString(2, pipelineName);
            ps.setString(3, nowUtc);
            ps.setString(4, level != null ? level : "Info");
            ps.setObject(5, stepNumber);
            ps.setString(6, stepName);
            ps.setString(7, message);
            ps.setString(8, details);
            ps.executeUpdate();
        }
    }
}
