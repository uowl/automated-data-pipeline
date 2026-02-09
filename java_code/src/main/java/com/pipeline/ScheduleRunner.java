package com.pipeline;

import java.sql.*;
import java.time.*;
import java.time.format.DateTimeFormatter;
import java.util.UUID;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

/**
 * Background scheduler: every minute checks PipelineSchedules for due runs,
 * triggers the pipeline and updates NextRunAt.
 */
public class ScheduleRunner {

    private static final ScheduledExecutorService EXECUTOR = Executors.newSingleThreadScheduledExecutor(r -> {
        Thread t = new Thread(r, "schedule-runner");
        t.setDaemon(true);
        return t;
    });

    private static final DateTimeFormatter TIME_FMT = DateTimeFormatter.ofPattern("HH:mm");
    private static final ZoneId ZONE = ZoneId.systemDefault();

    public static void start() {
        EXECUTOR.scheduleWithFixedDelay(() -> {
            try {
                runDueSchedules();
            } catch (Throwable t) {
                t.printStackTrace();
            }
        }, 1, 60, TimeUnit.SECONDS);
    }

    static void runDueSchedules() throws SQLException {
        Database.initSchema();
        try (Connection c = Database.getConnection()) {
            String sql = "SELECT ScheduleId, Name, ScheduleType, RunAtTime, DayOfWeek, DayOfMonth, SourcePath FROM dbo.PipelineSchedules WHERE Enabled = 1 AND NextRunAt IS NOT NULL AND NextRunAt <= SYSDATETIMEOFFSET()";
            try (Statement st = c.createStatement(); ResultSet rs = st.executeQuery(sql)) {
                while (rs.next()) {
                    String scheduleId = rs.getString("ScheduleId");
                    String name = rs.getString("Name");
                    String type = rs.getString("ScheduleType");
                    String runAtTime = rs.getString("RunAtTime");
                    Integer dayOfWeek = (Integer) rs.getObject("DayOfWeek");
                    Integer dayOfMonth = (Integer) rs.getObject("DayOfMonth");
                    String sourcePath = rs.getString("SourcePath");
                    try {
                        PipelineRunner.startPipelineRun(sourcePath);
                    } catch (Exception e) {
                        e.printStackTrace();
                    }
                    updateAfterRun(c, scheduleId, type, runAtTime, dayOfWeek, dayOfMonth);
                }
            }
        }
    }

    private static void updateAfterRun(Connection c, String scheduleId, String type, String runAtTime, Integer dayOfWeek, Integer dayOfMonth) throws SQLException {
        ZonedDateTime now = ZonedDateTime.now(ZONE);
        String next = computeNextRun(type, runAtTime, dayOfWeek, dayOfMonth, now);
        String nowStr = now.format(DateTimeFormatter.ISO_OFFSET_DATE_TIME);
        try (PreparedStatement ps = c.prepareStatement("UPDATE dbo.PipelineSchedules SET LastRunAt = ?, NextRunAt = ?, UpdatedAt = ? WHERE ScheduleId = ?")) {
            ps.setString(1, nowStr);
            ps.setString(2, next);
            ps.setString(3, nowStr);
            ps.setString(4, scheduleId);
            ps.executeUpdate();
        }
    }

    /** Returns next run as ISO string or null. */
    public static String computeNextRun(String scheduleType, String runAtTime, Integer dayOfWeek, Integer dayOfMonth, ZonedDateTime after) {
        LocalTime time;
        try {
            time = LocalTime.parse(runAtTime != null ? runAtTime : "00:00", TIME_FMT);
        } catch (Exception e) {
            time = LocalTime.MIDNIGHT;
        }
        ZonedDateTime next;
        switch (scheduleType != null ? scheduleType : "daily") {
            case "weekly":
                int targetDow = dayOfWeek != null ? dayOfWeek : 0;
                LocalDate d = after.toLocalDate();
                int currentDow = d.getDayOfWeek().getValue() % 7;
                int daysUntil = (targetDow - currentDow + 7) % 7;
                if (daysUntil == 0) {
                    next = ZonedDateTime.of(d, time, ZONE);
                    if (!next.isAfter(after)) next = next.plusWeeks(1);
                } else {
                    next = ZonedDateTime.of(d.plusDays(daysUntil), time, ZONE);
                }
                break;
            case "monthly":
                int dom = dayOfMonth != null ? Math.max(1, Math.min(31, dayOfMonth)) : 1;
                LocalDate start = after.toLocalDate();
                LocalDate cand = start.withDayOfMonth(Math.min(dom, start.lengthOfMonth()));
                next = ZonedDateTime.of(cand, time, ZONE);
                if (!next.isAfter(after)) {
                    cand = start.plusMonths(1).withDayOfMonth(Math.min(dom, start.plusMonths(1).lengthOfMonth()));
                    next = ZonedDateTime.of(cand, time, ZONE);
                }
                break;
            default:
                next = ZonedDateTime.of(after.toLocalDate(), time, ZONE);
                if (!next.isAfter(after)) next = next.plusDays(1);
                break;
        }
        return next.format(DateTimeFormatter.ISO_OFFSET_DATE_TIME);
    }

    public static String createSchedule(String name, String scheduleType, String runAtTime, Integer dayOfWeek, Integer dayOfMonth, String sourcePath) throws SQLException {
        Database.initSchema();
        String scheduleId = UUID.randomUUID().toString();
        ZonedDateTime now = ZonedDateTime.now(ZONE);
        String nextRun = computeNextRun(scheduleType, runAtTime, dayOfWeek, dayOfMonth, now);
        String nowStr = now.format(DateTimeFormatter.ISO_OFFSET_DATE_TIME);
        try (Connection c = Database.getConnection();
             PreparedStatement ps = c.prepareStatement(
                 "INSERT INTO dbo.PipelineSchedules (ScheduleId, Name, ScheduleType, RunAtTime, DayOfWeek, DayOfMonth, SourcePath, Enabled, CreatedAt, UpdatedAt, NextRunAt) VALUES (?,?,?,?,?,?,?,1,?,?,?)")) {
            ps.setString(1, scheduleId);
            ps.setString(2, name);
            ps.setString(3, scheduleType);
            ps.setString(4, runAtTime != null ? runAtTime : "00:00");
            ps.setObject(5, dayOfWeek);
            ps.setObject(6, dayOfMonth);
            ps.setString(7, sourcePath);
            ps.setString(8, nowStr);
            ps.setString(9, nowStr);
            ps.setString(10, nextRun);
            ps.executeUpdate();
        }
        return scheduleId;
    }

    public static void updateSchedule(String scheduleId, String name, String scheduleType, String runAtTime, Integer dayOfWeek, Integer dayOfMonth, String sourcePath, Boolean enabled) throws SQLException {
        Database.initSchema();
        try (Connection c = Database.getConnection()) {
            String curName = null, curType = null, curTime = null;
            Integer curDow = null, curDom = null;
            String curPath = null;
            boolean curEnabled = true;
            try (PreparedStatement sel = c.prepareStatement("SELECT Name, ScheduleType, RunAtTime, DayOfWeek, DayOfMonth, SourcePath, Enabled FROM dbo.PipelineSchedules WHERE ScheduleId=?")) {
                sel.setString(1, scheduleId);
                try (ResultSet rs = sel.executeQuery()) {
                    if (rs.next()) {
                        curName = rs.getString("Name");
                        curType = rs.getString("ScheduleType");
                        curTime = rs.getString("RunAtTime");
                        curDow = (Integer) rs.getObject("DayOfWeek");
                        curDom = (Integer) rs.getObject("DayOfMonth");
                        curPath = rs.getString("SourcePath");
                        curEnabled = rs.getBoolean("Enabled");
                    }
                }
            }
            String n = name != null ? name : curName;
            String t = scheduleType != null ? scheduleType : curType;
            String rt = runAtTime != null ? runAtTime : curTime;
            Integer dow = dayOfWeek != null ? dayOfWeek : curDow;
            Integer dom = dayOfMonth != null ? dayOfMonth : curDom;
            String sp = sourcePath != null ? sourcePath : curPath;
            boolean en = enabled != null ? enabled : curEnabled;
            ZonedDateTime now = ZonedDateTime.now(ZONE);
            String nextRun = en ? computeNextRun(t, rt, dow, dom, now) : null;
            String nowStr = now.format(DateTimeFormatter.ISO_OFFSET_DATE_TIME);
            try (PreparedStatement ps = c.prepareStatement(
                "UPDATE dbo.PipelineSchedules SET Name=?, ScheduleType=?, RunAtTime=?, DayOfWeek=?, DayOfMonth=?, SourcePath=?, Enabled=?, UpdatedAt=?, NextRunAt=? WHERE ScheduleId=?")) {
                ps.setString(1, n != null ? n : "");
                ps.setString(2, t != null ? t : "daily");
                ps.setString(3, rt != null ? rt : "00:00");
                ps.setObject(4, dow);
                ps.setObject(5, dom);
                ps.setString(6, sp);
                ps.setBoolean(7, en);
                ps.setString(8, nowStr);
                ps.setString(9, nextRun);
                ps.setString(10, scheduleId);
                ps.executeUpdate();
            }
        }
    }

    public static void deleteSchedule(String scheduleId) throws SQLException {
        try (Connection c = Database.getConnection();
             PreparedStatement ps = c.prepareStatement("DELETE FROM dbo.PipelineSchedules WHERE ScheduleId=?")) {
            ps.setString(1, scheduleId);
            ps.executeUpdate();
        }
    }
}
