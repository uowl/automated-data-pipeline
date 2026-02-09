package com.pipeline;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.Scanner;

/**
 * SQL Server database access. Connection settings from environment or defaults.
 * Defaults: host=localhost, port=1433, user=sa, password from env.
 */
public class Database {

    private static final String DEFAULT_HOST = "localhost";
    private static final int DEFAULT_PORT = 1433;
    private static final String DEFAULT_USER = "sa";
    private static final String DEFAULT_DATABASE = "pipeline";
    private static final String DEFAULT_LANDING_DIR = "data/landing";

    private static String host;
    private static Integer port;
    private static String user;
    private static String password;
    private static String databaseName;
    private static String landingDir;

    static {
        try {
            Class.forName("com.microsoft.sqlserver.jdbc.SQLServerDriver");
        } catch (ClassNotFoundException e) {
            throw new RuntimeException("SQL Server JDBC driver not found", e);
        }
    }

    public static String getHost() {
        if (host != null) return host;
        String env = System.getenv("DB_HOST");
        return env != null ? env : DEFAULT_HOST;
    }

    public static void setHost(String h) { host = h; }

    public static int getPort() {
        if (port != null) return port;
        String env = System.getenv("DB_PORT");
        if (env != null) {
            try { return Integer.parseInt(env.trim()); } catch (NumberFormatException ignored) {}
        }
        return DEFAULT_PORT;
    }

    public static void setPort(int p) { port = p; }

    public static String getUser() {
        if (user != null) return user;
        String env = System.getenv("DB_USER");
        return env != null ? env : DEFAULT_USER;
    }

    public static void setUser(String u) { user = u; }

    public static String getPassword() {
        if (password != null) return password;
        String env = System.getenv("DB_PASSWORD");
        return env != null ? env : "";
    }

    public static void setPassword(String p) { password = p; }

    public static String getDatabaseName() {
        if (databaseName != null) return databaseName;
        String env = System.getenv("DB_NAME");
        return env != null ? env : DEFAULT_DATABASE;
    }

    public static void setDatabaseName(String d) { databaseName = d; }

    public static void setLandingDir(String dir) { landingDir = dir; }

    public static String getLandingDir() {
        if (landingDir != null) return landingDir;
        String env = System.getenv("LANDING_DATA_DIR");
        return env != null ? env : DEFAULT_LANDING_DIR;
    }

    private static String buildJdbcUrl() {
        String h = getHost();
        int p = getPort();
        String db = getDatabaseName();
        return "jdbc:sqlserver://" + h + ":" + p + ";databaseName=" + db + ";encrypt=true;trustServerCertificate=true";
    }

    public static Connection getConnection() throws SQLException {
        String url = buildJdbcUrl();
        String u = getUser();
        String p = getPassword();
        return DriverManager.getConnection(url, u, p);
    }

    /** Get connection with optional overrides (null = use env/default). */
    public static Connection getConnection(String hostOverride, Integer portOverride, String userOverride, String passwordOverride) throws SQLException {
        String h = (hostOverride != null && !hostOverride.trim().isEmpty()) ? hostOverride.trim() : getHost();
        int p = (portOverride != null) ? portOverride : getPort();
        String u = (userOverride != null && !userOverride.trim().isEmpty()) ? userOverride.trim() : getUser();
        String pass = (passwordOverride != null) ? passwordOverride : getPassword();
        String db = getDatabaseName();
        String url = "jdbc:sqlserver://" + h + ":" + p + ";databaseName=" + db + ";encrypt=true;trustServerCertificate=true";
        return DriverManager.getConnection(url, u, pass);
    }

    public static void initSchema() throws SQLException {
        initSchema(null, null, null, null);
    }

    /** Load schema SQL from classpath with fallbacks for Windows/different classloaders. */
    private static String loadSchemaSql() {
        String[] names = { "/sqlserver_schema.sql", "sqlserver_schema.sql" };
        for (String name : names) {
            InputStream in = null;
            if (name.startsWith("/")) {
                in = Database.class.getResourceAsStream(name);
            } else {
                ClassLoader cl = Thread.currentThread().getContextClassLoader();
                if (cl != null) in = cl.getResourceAsStream(name);
                if (in == null && Database.class.getClassLoader() != null) {
                    in = Database.class.getClassLoader().getResourceAsStream(name);
                }
            }
            if (in != null) {
                try {
                    try (Scanner s = new Scanner(in, StandardCharsets.UTF_8).useDelimiter("\\A")) {
                        return s.hasNext() ? s.next() : "";
                    }
                } catch (Exception e) {
                    // fall through to next name
                } finally {
                    try { if (in != null) in.close(); } catch (IOException ignored) {}
                }
            }
        }
        return null;
    }

    /** Init schema on DB identified by optional overrides (null = use env/default). */
    public static void initSchema(String hostOverride, Integer portOverride, String userOverride, String passwordOverride) throws SQLException {
        String sql = loadSchemaSql();
        if (sql == null) throw new SQLException("sqlserver_schema.sql not found on classpath (tried /sqlserver_schema.sql and sqlserver_schema.sql)");

        Connection c = (hostOverride != null || portOverride != null || userOverride != null || passwordOverride != null)
            ? getConnection(hostOverride, portOverride, userOverride, passwordOverride)
            : getConnection();
        try {
            // Migrate: add RunNumber if PipelineRuns exists but column doesn't
            try (ResultSet rs = c.createStatement().executeQuery(
                "SELECT 1 FROM sys.tables WHERE name = 'PipelineRuns'")) {
                if (rs.next()) {
                    try (ResultSet col = c.createStatement().executeQuery(
                        "SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.PipelineRuns') AND name = 'RunNumber'")) {
                        if (!col.next()) {
                            c.createStatement().execute("ALTER TABLE dbo.PipelineRuns ADD RunNumber INT NULL");
                            try (PreparedStatement sel = c.prepareStatement("SELECT RunId FROM dbo.PipelineRuns ORDER BY CreatedAt ASC");
                                 ResultSet rows = sel.executeQuery()) {
                                int i = 1;
                                PreparedStatement upd = c.prepareStatement("UPDATE dbo.PipelineRuns SET RunNumber = ? WHERE RunId = ?");
                                while (rows.next()) {
                                    upd.setInt(1, i++);
                                    upd.setString(2, rows.getString("RunId"));
                                    upd.executeUpdate();
                                }
                            }
                            c.createStatement().execute("ALTER TABLE dbo.PipelineRuns ALTER COLUMN RunNumber INT NOT NULL");
                        }
                    }
                }
                // Migrate: add RowsProcessed, RowsTotal to StepRuns for row-level progress
                try (ResultSet sr = c.createStatement().executeQuery(
                    "SELECT 1 FROM sys.tables WHERE name = 'StepRuns'")) {
                    if (sr.next()) {
                        try (ResultSet rc = c.createStatement().executeQuery(
                            "SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.StepRuns') AND name = 'RowsProcessed'")) {
                            if (!rc.next()) {
                                c.createStatement().execute("ALTER TABLE dbo.StepRuns ADD RowsProcessed INT NULL");
                            }
                        }
                        try (ResultSet rc = c.createStatement().executeQuery(
                            "SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.StepRuns') AND name = 'RowsTotal'")) {
                            if (!rc.next()) {
                                c.createStatement().execute("ALTER TABLE dbo.StepRuns ADD RowsTotal INT NULL");
                            }
                        }
                    }
                }
            }

            // Run schema batches (GO is not sent to server; we split and execute each batch)
            String[] batches = sql.split("\\s*GO\\s*");
            for (String batch : batches) {
                String s = batch.trim();
                if (s.isEmpty()) continue;
                try {
                    c.createStatement().execute(s);
                } catch (SQLException ex) {
                    if (!ex.getMessage().contains("already exists") && !ex.getMessage().contains("duplicate key")) throw ex;
                }
            }
        } finally {
            c.close();
        }
    }
}
