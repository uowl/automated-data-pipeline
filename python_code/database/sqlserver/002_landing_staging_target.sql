-- Sample domain: Orders
-- Landing (raw from Data Pull), Staging (after Extract/Transform), Target (after Migrate)

-- Landing: raw data from CSV/JSON/REST/SOAP/Scraper
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Landing_Orders')
BEGIN
    CREATE TABLE dbo.Landing_Orders (
        Id              BIGINT IDENTITY(1,1) PRIMARY KEY,
        RunId           UNIQUEIDENTIFIER NOT NULL,
        OrderId         NVARCHAR(64)     NULL,
        CustomerId      NVARCHAR(64)     NULL,
        Amount          DECIMAL(18,2)    NULL,
        OrderDate       NVARCHAR(64)     NULL,
        SourceType      NVARCHAR(32)    NULL,  -- CSV, JSON, REST, etc.
        RawPayload     NVARCHAR(MAX)    NULL,
        LoadedAt        DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
    );
    CREATE INDEX IX_Landing_Orders_RunId ON dbo.Landing_Orders(RunId);
END
GO

-- Staging: normalized after Extract
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Staging_Orders')
BEGIN
    CREATE TABLE dbo.Staging_Orders (
        Id              BIGINT IDENTITY(1,1) PRIMARY KEY,
        RunId           UNIQUEIDENTIFIER NOT NULL,
        OrderId         NVARCHAR(64)     NOT NULL,
        CustomerId      NVARCHAR(64)     NOT NULL,
        Amount          DECIMAL(18,2)    NOT NULL,
        OrderDate       DATE             NULL,
        ExtractedAt    DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
    );
    CREATE INDEX IX_Staging_Orders_RunId ON dbo.Staging_Orders(RunId);
END
GO

-- Staging (transformed): after Transform
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Staging_Orders_Transformed')
BEGIN
    CREATE TABLE dbo.Staging_Orders_Transformed (
        Id              BIGINT IDENTITY(1,1) PRIMARY KEY,
        RunId           UNIQUEIDENTIFIER NOT NULL,
        OrderId         NVARCHAR(64)     NOT NULL,
        CustomerId      NVARCHAR(64)     NOT NULL,
        Amount          DECIMAL(18,2)    NOT NULL,
        OrderDate       DATE             NULL,
        AmountCategory  NVARCHAR(16)     NULL,  -- e.g. Low/Medium/High
        TransformedAt   DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
    );
    CREATE INDEX IX_Staging_Orders_Transformed_RunId ON dbo.Staging_Orders_Transformed(RunId);
END
GO

-- Target: final tables (sink)
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Target_Orders')
BEGIN
    CREATE TABLE dbo.Target_Orders (
        Id              BIGINT IDENTITY(1,1) PRIMARY KEY,
        OrderId         NVARCHAR(64)     NOT NULL,
        CustomerId      NVARCHAR(64)     NOT NULL,
        Amount          DECIMAL(18,2)    NOT NULL,
        OrderDate       DATE             NULL,
        AmountCategory  NVARCHAR(16)     NULL,
        MigratedAt      DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_Target_Orders_OrderId UNIQUE (OrderId)
    );
END
GO
