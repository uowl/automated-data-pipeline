package com.pipeline.servlet;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.pipeline.Database;
import com.pipeline.PipelineRunner;
import com.pipeline.ScheduleRunner;
import org.apache.commons.fileupload.FileItem;
import org.apache.commons.fileupload.disk.DiskFileItemFactory;
import org.apache.commons.fileupload.servlet.ServletFileUpload;

import javax.servlet.ServletException;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.BufferedReader;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.file.Files;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Serves JSON API: GET /api/runs, GET /api/runs/{id}, GET /api/runs/{id}/logs, GET /api/logs, POST /api/pipeline/trigger
 */
public class ApiServlet extends HttpServlet {

    private static final Gson GSON = new GsonBuilder().create();

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse resp) throws ServletException, IOException {
        String path = pathInfo(req);
        resp.setContentType("application/json");
        resp.setCharacterEncoding("UTF-8");

        try {
            if ("/runs".equals(path)) {
                listRuns(req, resp);
                return;
            }
            if (path != null && path.startsWith("/runs/")) {
                String rest = path.substring("/runs/".length());
                if (rest.contains("/logs")) {
                    String runId = rest.substring(0, rest.indexOf("/logs"));
                    runLogs(runId, resp);
                    return;
                }
                runDetail(rest, resp);
                return;
            }
            if ("/logs".equals(path)) {
                allLogs(req, resp);
                return;
            }
            if ("/schedules".equals(path)) {
                listSchedules(resp);
                return;
            }
            if (path != null && path.startsWith("/schedules/")) {
                String id = path.substring("/schedules/".length());
                if (!id.isEmpty()) {
                    getSchedule(id, resp);
                    return;
                }
            }
            resp.setStatus(HttpServletResponse.SC_NOT_FOUND);
            resp.getWriter().write("{\"error\":\"Not found\"}");
        } catch (SQLException e) {
            resp.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            resp.getWriter().write("{\"error\":\"" + escapeJson(e.getMessage()) + "\"}");
        }
    }

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse resp) throws ServletException, IOException {
        String path = pathInfo(req);
        resp.setContentType("application/json");
        resp.setCharacterEncoding("UTF-8");

        if ("/pipeline/trigger".equals(path)) {
            try {
                triggerPipeline(req, resp);
            } catch (Exception e) {
                resp.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
                resp.getWriter().write("{\"error\":\"" + escapeJson(e.getMessage()) + "\"}");
            }
            return;
        }
        if ("/schedules".equals(path)) {
            try {
                createSchedule(req, resp);
            } catch (Exception e) {
                resp.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
                resp.getWriter().write("{\"error\":\"" + escapeJson(e.getMessage()) + "\"}");
            }
            return;
        }
        resp.setStatus(HttpServletResponse.SC_NOT_FOUND);
        resp.getWriter().write("{\"error\":\"Not found\"}");
    }

    @Override
    protected void doPut(HttpServletRequest req, HttpServletResponse resp) throws ServletException, IOException {
        String path = pathInfo(req);
        resp.setContentType("application/json");
        resp.setCharacterEncoding("UTF-8");
        if (path != null && path.startsWith("/schedules/")) {
            String id = path.substring("/schedules/".length());
            if (!id.isEmpty()) {
                try {
                    updateSchedule(id, req, resp);
                } catch (Exception e) {
                    resp.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
                    resp.getWriter().write("{\"error\":\"" + escapeJson(e.getMessage()) + "\"}");
                }
                return;
            }
        }
        resp.setStatus(HttpServletResponse.SC_NOT_FOUND);
        resp.getWriter().write("{\"error\":\"Not found\"}");
    }

    @Override
    protected void doDelete(HttpServletRequest req, HttpServletResponse resp) throws ServletException, IOException {
        String path = pathInfo(req);
        resp.setContentType("application/json");
        resp.setCharacterEncoding("UTF-8");
        if (path != null && path.startsWith("/schedules/")) {
            String id = path.substring("/schedules/".length());
            if (!id.isEmpty()) {
                try {
                    deleteSchedule(id, resp);
                } catch (Exception e) {
                    resp.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
                    resp.getWriter().write("{\"error\":\"" + escapeJson(e.getMessage()) + "\"}");
                }
                return;
            }
        }
        resp.setStatus(HttpServletResponse.SC_NOT_FOUND);
        resp.getWriter().write("{\"error\":\"Not found\"}");
    }

    private static String readBody(HttpServletRequest req) throws IOException {
        StringBuilder sb = new StringBuilder();
        try (BufferedReader r = req.getReader()) {
            String line;
            while ((line = r.readLine()) != null) sb.append(line);
        }
        return sb.toString();
    }

    private void listSchedules(HttpServletResponse resp) throws SQLException, IOException {
        Database.initSchema();
        try (Connection c = Database.getConnection();
             PreparedStatement ps = c.prepareStatement("SELECT ScheduleId, Name, ScheduleType, RunAtTime, DayOfWeek, DayOfMonth, SourcePath, Enabled, CreatedAt, UpdatedAt, LastRunAt, NextRunAt FROM dbo.PipelineSchedules ORDER BY CreatedAt DESC");
             ResultSet rs = ps.executeQuery()) {
            List<Map<String, Object>> rows = resultSetToMaps(rs);
            resp.getWriter().write(GSON.toJson(rows));
        }
    }

    private void getSchedule(String scheduleId, HttpServletResponse resp) throws SQLException, IOException {
        Database.initSchema();
        try (Connection c = Database.getConnection();
             PreparedStatement ps = c.prepareStatement("SELECT ScheduleId, Name, ScheduleType, RunAtTime, DayOfWeek, DayOfMonth, SourcePath, Enabled, CreatedAt, UpdatedAt, LastRunAt, NextRunAt FROM dbo.PipelineSchedules WHERE ScheduleId=?")) {
            ps.setString(1, scheduleId);
            try (ResultSet rs = ps.executeQuery()) {
                if (!rs.next()) {
                    resp.setStatus(HttpServletResponse.SC_NOT_FOUND);
                    resp.getWriter().write("{\"error\":\"Schedule not found\"}");
                    return;
                }
                resp.getWriter().write(GSON.toJson(rowToMap(rs)));
            }
        }
    }

    private void createSchedule(HttpServletRequest req, HttpServletResponse resp) throws Exception {
        if (!ServletFileUpload.isMultipartContent(req)) {
            resp.setStatus(HttpServletResponse.SC_BAD_REQUEST);
            resp.getWriter().write("{\"error\":\"Use multipart form with file (CSV or JSON) and fields: name, scheduleType, runAtTime, dayOfWeek, dayOfMonth.\"}");
            return;
        }
        DiskFileItemFactory factory = new DiskFileItemFactory();
        File tempDir = (File) getServletContext().getAttribute("javax.servlet.context.tempdir");
        if (tempDir != null) factory.setRepository(tempDir);
        ServletFileUpload upload = new ServletFileUpload(factory);
        upload.setSizeMax(100 * 1024 * 1024); // 100 MB
        List<FileItem> items = upload.parseRequest(req);
        String name = "Schedule";
        String scheduleType = "daily";
        String runAtTime = "09:00";
        Integer dayOfWeek = null;
        Integer dayOfMonth = null;
        File savedFile = null;
        for (FileItem item : items) {
            if (item.isFormField()) {
                String fieldName = item.getFieldName();
                String value = item.getString();
                if (value != null) value = value.trim();
                if ("name".equals(fieldName) && value != null && !value.isEmpty()) name = value;
                else if ("scheduleType".equals(fieldName) && value != null) scheduleType = value;
                else if ("runAtTime".equals(fieldName) && value != null) runAtTime = value;
                else if ("dayOfWeek".equals(fieldName) && value != null && !value.isEmpty()) dayOfWeek = parseIntSafe(value);
                else if ("dayOfMonth".equals(fieldName) && value != null && !value.isEmpty()) dayOfMonth = parseIntSafe(value);
                continue;
            }
            if (!"file".equals(item.getFieldName())) continue;
            String fileName = item.getName();
            if (fileName == null || fileName.isEmpty()) continue;
            String ext = fileName.contains(".") ? fileName.substring(fileName.lastIndexOf('.')).toLowerCase() : ".csv";
            if (!".csv".equals(ext) && !".json".equals(ext)) {
                resp.setStatus(HttpServletResponse.SC_BAD_REQUEST);
                resp.getWriter().write("{\"error\":\"Only CSV or JSON files are allowed\"}");
                return;
            }
            File landingDir = new File(Database.getLandingDir());
            landingDir.mkdirs();
            savedFile = new File(landingDir, "schedule_" + System.currentTimeMillis() + ext);
            try (InputStream in = item.getInputStream();
                 OutputStream out = Files.newOutputStream(savedFile.toPath())) {
                byte[] buf = new byte[8192];
                int n;
                while ((n = in.read(buf)) != -1) out.write(buf, 0, n);
            }
        }
        if (savedFile == null || !savedFile.exists()) {
            resp.setStatus(HttpServletResponse.SC_BAD_REQUEST);
            resp.getWriter().write("{\"error\":\"A CSV or JSON file is required. Select a file as with a regular run.\"}");
            return;
        }
        String sourcePath = savedFile.getAbsolutePath();
        String scheduleId = ScheduleRunner.createSchedule(name, scheduleType, runAtTime, dayOfWeek, dayOfMonth, sourcePath);
        resp.setStatus(HttpServletResponse.SC_CREATED);
        resp.getWriter().write("{\"scheduleId\":\"" + scheduleId + "\"}");
    }

    private static Integer parseIntSafe(String s) {
        try {
            return Integer.parseInt(s);
        } catch (NumberFormatException e) {
            return null;
        }
    }

    @SuppressWarnings("unchecked")
    private void updateSchedule(String scheduleId, HttpServletRequest req, HttpServletResponse resp) throws Exception {
        Map<String, Object> body = GSON.fromJson(readBody(req), Map.class);
        if (body == null) body = new HashMap<>();
        String name = getStr(body, "name");
        String scheduleType = getStr(body, "scheduleType");
        String runAtTime = getStr(body, "runAtTime");
        Integer dayOfWeek = getInt(body, "dayOfWeek");
        Integer dayOfMonth = getInt(body, "dayOfMonth");
        String sourcePath = getStr(body, "sourcePath");
        Boolean enabled = getBool(body, "enabled");
        ScheduleRunner.updateSchedule(scheduleId, name, scheduleType, runAtTime, dayOfWeek, dayOfMonth, sourcePath, enabled);
        resp.getWriter().write("{\"ok\":true}");
    }

    private void deleteSchedule(String scheduleId, HttpServletResponse resp) throws SQLException, IOException {
        ScheduleRunner.deleteSchedule(scheduleId);
        resp.getWriter().write("{\"ok\":true}");
    }

    private static String getStr(Map<String, Object> m, String key) {
        Object v = m.get(key);
        return v != null ? v.toString() : null;
    }

    private static Integer getInt(Map<String, Object> m, String key) {
        Object v = m.get(key);
        if (v == null) return null;
        if (v instanceof Number) return ((Number) v).intValue();
        try { return Integer.parseInt(v.toString()); } catch (NumberFormatException e) { return null; }
    }

    private static Boolean getBool(Map<String, Object> m, String key) {
        Object v = m.get(key);
        if (v == null) return null;
        if (v instanceof Boolean) return (Boolean) v;
        return Boolean.parseBoolean(v.toString());
    }

    private static String pathInfo(HttpServletRequest req) {
        String pi = req.getPathInfo();
        return pi == null ? "" : pi;
    }

    private void listRuns(HttpServletRequest req, HttpServletResponse resp) throws SQLException, IOException {
        String pipeline = req.getParameter("pipeline");
        String status = req.getParameter("status");
        StringBuilder sql = new StringBuilder(
            "SELECT TOP 100 RunId, RunNumber, PipelineName, ADFRunId, StartedAt, FinishedAt, Status, CreatedAt FROM dbo.PipelineRuns WHERE 1=1");
        List<Object> params = new ArrayList<>();
        if (pipeline != null && !pipeline.isEmpty()) {
            sql.append(" AND PipelineName = ?");
            params.add(pipeline);
        }
        if (status != null && !status.isEmpty()) {
            sql.append(" AND Status = ?");
            params.add(status);
        }
        sql.append(" ORDER BY CreatedAt DESC");

        Database.initSchema();
        try (Connection c = Database.getConnection();
             PreparedStatement ps = c.prepareStatement(sql.toString())) {
            for (int i = 0; i < params.size(); i++) ps.setObject(i + 1, params.get(i));
            try (ResultSet rs = ps.executeQuery()) {
                List<Map<String, Object>> rows = resultSetToMaps(rs);
                resp.getWriter().write(GSON.toJson(rows));
            }
        }
    }

    private void runDetail(String runId, HttpServletResponse resp) throws SQLException, IOException {
        Database.initSchema();
        try (Connection c = Database.getConnection()) {
            Map<String, Object> run;
            try (PreparedStatement ps = c.prepareStatement(
                "SELECT RunId, RunNumber, PipelineName, ADFRunId, StartedAt, FinishedAt, Status, CreatedAt FROM dbo.PipelineRuns WHERE RunId = ?")) {
                ps.setString(1, runId);
                try (ResultSet rs = ps.executeQuery()) {
                    if (!rs.next()) {
                        resp.setStatus(HttpServletResponse.SC_NOT_FOUND);
                        resp.getWriter().write("{\"error\":\"Run not found\"}");
                        return;
                    }
                    run = rowToMap(rs);
                }
            }
            List<Map<String, Object>> steps = new ArrayList<>();
            try (PreparedStatement ps = c.prepareStatement(
                "SELECT StepRunId, RunId, StepNumber, StepName, StartedAt, FinishedAt, Status, RowsAffected, RowsProcessed, RowsTotal, ErrorMessage, CreatedAt FROM dbo.StepRuns WHERE RunId = ? ORDER BY StepNumber")) {
                ps.setString(1, runId);
                try (ResultSet rs = ps.executeQuery()) {
                    while (rs.next()) steps.add(rowToMap(rs));
                }
            }
            run.put("steps", steps);
            resp.getWriter().write(GSON.toJson(run));
        }
    }

    private void runLogs(String runId, HttpServletResponse resp) throws SQLException, IOException {
        Database.initSchema();
        try (Connection c = Database.getConnection()) {
            try (PreparedStatement ps = c.prepareStatement("SELECT RunId FROM dbo.PipelineRuns WHERE RunId = ?")) {
                ps.setString(1, runId);
                try (ResultSet rs = ps.executeQuery()) {
                    if (!rs.next()) {
                        resp.setStatus(HttpServletResponse.SC_NOT_FOUND);
                        resp.getWriter().write("{\"error\":\"Run not found\"}");
                        return;
                    }
                }
            }
            List<Map<String, Object>> logs = new ArrayList<>();
            try (PreparedStatement ps = c.prepareStatement(
                "SELECT LogId, RunId, PipelineName, LogAt, Level, StepNumber, StepName, Message, Details FROM dbo.PipelineLogs WHERE RunId = ? ORDER BY LogAt ASC")) {
                ps.setString(1, runId);
                try (ResultSet rs = ps.executeQuery()) {
                    while (rs.next()) logs.add(rowToMap(rs));
                }
            }
            resp.getWriter().write(GSON.toJson(logs));
        }
    }

    private void allLogs(HttpServletRequest req, HttpServletResponse resp) throws SQLException, IOException {
        String runId = req.getParameter("runId");
        String pipeline = req.getParameter("pipeline");
        String level = req.getParameter("level");
        int limit = 500;
        String limitParam = req.getParameter("limit");
        if (limitParam != null) {
            try { limit = Math.min(Integer.parseInt(limitParam), 2000); } catch (NumberFormatException ignored) {}
        }
        StringBuilder sql = new StringBuilder(
            "SELECT LogId, RunId, PipelineName, LogAt, Level, StepNumber, StepName, Message, Details FROM dbo.PipelineLogs WHERE 1=1");
        List<Object> params = new ArrayList<>();
        if (runId != null && !runId.isEmpty()) { sql.append(" AND RunId = ?"); params.add(runId); }
        if (pipeline != null && !pipeline.isEmpty()) { sql.append(" AND PipelineName = ?"); params.add(pipeline); }
        if (level != null && !level.isEmpty()) { sql.append(" AND Level = ?"); params.add(level); }
        sql.append(" ORDER BY LogAt DESC OFFSET 0 ROWS FETCH NEXT ? ROWS ONLY");
        params.add(limit);

        Database.initSchema();
        try (Connection c = Database.getConnection();
             PreparedStatement ps = c.prepareStatement(sql.toString())) {
            for (int i = 0; i < params.size(); i++) ps.setObject(i + 1, params.get(i));
            try (ResultSet rs = ps.executeQuery()) {
                List<Map<String, Object>> rows = resultSetToMaps(rs);
                resp.getWriter().write(GSON.toJson(rows));
            }
        }
    }

    private void triggerPipeline(HttpServletRequest req, HttpServletResponse resp) throws Exception {
        if (!ServletFileUpload.isMultipartContent(req)) {
            resp.setStatus(HttpServletResponse.SC_BAD_REQUEST);
            resp.getWriter().write("{\"error\":\"No file uploaded. Use form field \\\"file\\\" with a CSV or JSON file.\"}");
            return;
        }
        DiskFileItemFactory factory = new DiskFileItemFactory();
        File tempDir = (File) getServletContext().getAttribute("javax.servlet.context.tempdir");
        if (tempDir != null) factory.setRepository(tempDir);
        ServletFileUpload upload = new ServletFileUpload(factory);
        upload.setSizeMax(100 * 1024 * 1024); // 100 MB
        List<FileItem> items = upload.parseRequest(req);
        File savedFile = null;
        String dbHost = null;
        Integer dbPort = null;
        String dbUser = null;
        String dbPassword = null;
        for (FileItem item : items) {
            if (item.isFormField()) {
                String fn = item.getFieldName();
                String val = item.getString();
                if (val != null) val = val.trim();
                if ("dbHost".equals(fn) && val != null && !val.isEmpty()) dbHost = val;
                else if ("dbPort".equals(fn) && val != null && !val.isEmpty()) {
                    try { dbPort = Integer.parseInt(val); } catch (NumberFormatException ignored) {}
                }
                else if ("dbUser".equals(fn) && val != null && !val.isEmpty()) dbUser = val;
                else if ("dbPassword".equals(fn)) dbPassword = val != null ? val : "";
                continue;
            }
            if (!"file".equals(item.getFieldName())) continue;
            String name = item.getName();
            if (name == null || name.isEmpty()) continue;
            String ext = name.contains(".") ? name.substring(name.lastIndexOf('.')).toLowerCase() : ".csv";
            if (!".csv".equals(ext) && !".json".equals(ext)) {
                resp.setStatus(HttpServletResponse.SC_BAD_REQUEST);
                resp.getWriter().write("{\"error\":\"Only CSV or JSON files are allowed\"}");
                return;
            }
            File landingDir = new File(Database.getLandingDir());
            landingDir.mkdirs();
            savedFile = new File(landingDir, "upload_" + System.currentTimeMillis() + ext);
            try (InputStream in = item.getInputStream();
                 OutputStream out = Files.newOutputStream(savedFile.toPath())) {
                byte[] buf = new byte[8192];
                int n;
                while ((n = in.read(buf)) != -1) out.write(buf, 0, n);
            }
            break;
        }
        if (savedFile == null || !savedFile.exists()) {
            resp.setStatus(HttpServletResponse.SC_BAD_REQUEST);
            resp.getWriter().write("{\"error\":\"No file uploaded. Use form field \\\"file\\\" with a CSV or JSON file.\"}");
            return;
        }
        // Use overrides only when host, port, or user is explicitly provided
        boolean useOverrides = (dbHost != null && !dbHost.isEmpty()) || dbPort != null || (dbUser != null && !dbUser.isEmpty());
        if (!useOverrides) {
            dbHost = null;
            dbPort = null;
            dbUser = null;
            dbPassword = null;
        }
        String runId = PipelineRunner.startPipelineRun(savedFile.getAbsolutePath(), dbHost, dbPort, dbUser, dbPassword);
        resp.setStatus(HttpServletResponse.SC_CREATED);
        Map<String, Object> body = new HashMap<>();
        body.put("runId", runId);
        body.put("message", "Pipeline started in background");
        body.put("file", savedFile.getName());
        resp.getWriter().write(GSON.toJson(body));
    }

    private static List<Map<String, Object>> resultSetToMaps(ResultSet rs) throws SQLException {
        List<Map<String, Object>> list = new ArrayList<>();
        while (rs.next()) list.add(rowToMap(rs));
        return list;
    }

    private static Map<String, Object> rowToMap(ResultSet rs) throws SQLException {
        Map<String, Object> m = new HashMap<>();
        int cols = rs.getMetaData().getColumnCount();
        for (int i = 1; i <= cols; i++) {
            String label = rs.getMetaData().getColumnLabel(i);
            Object v = rs.getObject(i);
            m.put(label, v);
        }
        return m;
    }

    private static String escapeJson(String s) {
        if (s == null) return "";
        return s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r");
    }
}
