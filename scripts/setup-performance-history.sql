/*
╔══════════════════════════════════════════════════════════════════════╗
║                                                                      ║
║      SQL Server Expert Skill - Performance Dashboard Setup           ║
║                                                                      ║
║  Creates schema and tables for tracking performance metrics over     ║
║  time. Run this once per database to initialize the dashboard.       ║
║                                                                      ║
╚══════════════════════════════════════════════════════════════════════╝
*/

SET NOCOUNT ON;

PRINT '';
PRINT '╔══════════════════════════════════════════════════════════════════════╗';
PRINT '║  PERFORMANCE DASHBOARD - SETUP                                      ║';
PRINT '║  Database: ' + DB_NAME();
PRINT '╚══════════════════════════════════════════════════════════════════════╝';
PRINT '';

-- ============================================================================
-- Create PerfDashboard schema
-- ============================================================================
PRINT '[1/4] Creating schema...';

IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'PerfDashboard')
BEGIN
    EXEC('CREATE SCHEMA PerfDashboard');
    PRINT '  ✓ Schema PerfDashboard created';
END
ELSE
BEGIN
    PRINT '  ✓ Schema PerfDashboard already exists';
END

PRINT '';

-- ============================================================================
-- Create MetricSnapshots table - Daily/hourly snapshots of DB state
-- ============================================================================
PRINT '[2/4] Creating metric tables...';

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'MetricSnapshots' AND schema_id = SCHEMA_ID('PerfDashboard'))
BEGIN
    CREATE TABLE PerfDashboard.MetricSnapshots (
        SnapshotID INT IDENTITY(1,1) PRIMARY KEY,
        SnapshotDate DATETIME2 DEFAULT GETDATE(),
        DatabaseName NVARCHAR(255),

        -- Performance Metrics
        TotalQueryCount BIGINT,
        AvgExecutionTimeMs DECIMAL(10,2),
        MaxExecutionTimeMs DECIMAL(10,2),
        TotalWaitTimeMs BIGINT,

        -- Resource Metrics
        TotalBufferPoolUsedMB DECIMAL(10,2),
        TotalCPUTimeMs BIGINT,

        -- Index Metrics
        TotalIndexFragmentation DECIMAL(5,2),
        MissingIndexCount INT,
        UnusedIndexCount INT,

        -- Table Metrics
        LargeTableCount INT,
        TablesWithoutPKCount INT,

        -- Transaction Metrics
        LongRunningTransactionCount INT,
        BlockingCount INT,
        DeadlockCount INT
    );

    CREATE CLUSTERED INDEX CIX_MetricSnapshots ON PerfDashboard.MetricSnapshots(SnapshotDate DESC);
    PRINT '  ✓ MetricSnapshots table created';
END
ELSE
BEGIN
    PRINT '  ✓ MetricSnapshots table already exists';
END

-- ============================================================================
-- Create QueryPerformanceHistory - Track individual query performance
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'QueryPerformanceHistory' AND schema_id = SCHEMA_ID('PerfDashboard'))
BEGIN
    CREATE TABLE PerfDashboard.QueryPerformanceHistory (
        QueryHistoryID INT IDENTITY(1,1) PRIMARY KEY,
        CaptureDate DATETIME2 DEFAULT GETDATE(),

        QueryHash BINARY(8),
        QueryPlanHash BINARY(8),
        QueryText NVARCHAR(MAX),

        ExecutionCount BIGINT,
        TotalExecutionTimeMs BIGINT,
        AvgExecutionTimeMs DECIMAL(10,2),
        MaxExecutionTimeMs DECIMAL(10,2),
        MinExecutionTimeMs DECIMAL(10,2),

        TotalLogicalReads BIGINT,
        TotalPhysicalReads BIGINT,
        TotalLogicalWrites BIGINT,

        TotalWorkerTime BIGINT,
        TotalElapsedTime BIGINT,

        CreationTime DATETIME2,
        LastExecutionTime DATETIME2
    );

    CREATE CLUSTERED INDEX CIX_QueryPerformanceHistory ON PerfDashboard.QueryPerformanceHistory(CaptureDate DESC);
    CREATE NONCLUSTERED INDEX NIX_QueryHash ON PerfDashboard.QueryPerformanceHistory(QueryHash);
    PRINT '  ✓ QueryPerformanceHistory table created';
END
ELSE
BEGIN
    PRINT '  ✓ QueryPerformanceHistory table already exists';
END

-- ============================================================================
-- Create IndexFragmentationHistory - Track index fragmentation over time
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'IndexFragmentationHistory' AND schema_id = SCHEMA_ID('PerfDashboard'))
BEGIN
    CREATE TABLE PerfDashboard.IndexFragmentationHistory (
        FragmentationID INT IDENTITY(1,1) PRIMARY KEY,
        CaptureDate DATETIME2 DEFAULT GETDATE(),

        SchemaName NVARCHAR(255),
        TableName NVARCHAR(255),
        IndexName NVARCHAR(255),

        FragmentationPercent DECIMAL(5,2),
        PageCount BIGINT,

        IndexType NVARCHAR(50)
    );

    CREATE CLUSTERED INDEX CIX_IndexFragmentationHistory ON PerfDashboard.IndexFragmentationHistory(CaptureDate DESC);
    CREATE NONCLUSTERED INDEX NIX_IndexName ON PerfDashboard.IndexFragmentationHistory(TableName, IndexName);
    PRINT '  ✓ IndexFragmentationHistory table created';
END
ELSE
BEGIN
    PRINT '  ✓ IndexFragmentationHistory table already exists';
END

-- ============================================================================
-- Create WaitEventHistory - Track wait events and bottlenecks
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'WaitEventHistory' AND schema_id = SCHEMA_ID('PerfDashboard'))
BEGIN
    CREATE TABLE PerfDashboard.WaitEventHistory (
        WaitEventID INT IDENTITY(1,1) PRIMARY KEY,
        CaptureDate DATETIME2 DEFAULT GETDATE(),

        WaitType NVARCHAR(60),
        WaitTimeMs BIGINT,
        SignalWaitTimeMs BIGINT,
        WaitCount BIGINT,

        Percentage DECIMAL(5,2)
    );

    CREATE CLUSTERED INDEX CIX_WaitEventHistory ON PerfDashboard.WaitEventHistory(CaptureDate DESC);
    CREATE NONCLUSTERED INDEX NIX_WaitType ON PerfDashboard.WaitEventHistory(WaitType);
    PRINT '  ✓ WaitEventHistory table created';
END
ELSE
BEGIN
    PRINT '  ✓ WaitEventHistory table already exists';
END

-- ============================================================================
-- Create PerformanceBaseline - Reference baseline for comparisons
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'PerformanceBaseline' AND schema_id = SCHEMA_ID('PerfDashboard'))
BEGIN
    CREATE TABLE PerfDashboard.PerformanceBaseline (
        BaselineID INT IDENTITY(1,1) PRIMARY KEY,
        BaselineName NVARCHAR(255),
        BaselineDate DATETIME2 DEFAULT GETDATE(),
        Description NVARCHAR(MAX),

        AvgQueryTimeMs DECIMAL(10,2),
        AvgIndexFragmentation DECIMAL(5,2),
        AvgCPUTimeMs BIGINT,
        TotalBufferPoolMB DECIMAL(10,2),

        CreatedDate DATETIME2 DEFAULT GETDATE(),
        IsActive BIT DEFAULT 1
    );

    CREATE CLUSTERED INDEX CIX_PerformanceBaseline ON PerfDashboard.PerformanceBaseline(BaselineDate DESC);
    PRINT '  ✓ PerformanceBaseline table created';
END
ELSE
BEGIN
    PRINT '  ✓ PerformanceBaseline table already exists';
END

-- ============================================================================
-- Create data retention policy info
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'DashboardConfig' AND schema_id = SCHEMA_ID('PerfDashboard'))
BEGIN
    CREATE TABLE PerfDashboard.DashboardConfig (
        ConfigID INT IDENTITY(1,1) PRIMARY KEY,
        ConfigKey NVARCHAR(255) UNIQUE,
        ConfigValue NVARCHAR(MAX),
        Description NVARCHAR(MAX),
        ModifiedDate DATETIME2 DEFAULT GETDATE()
    );

    -- Insert default configuration
    INSERT INTO PerfDashboard.DashboardConfig (ConfigKey, ConfigValue, Description)
    VALUES
        ('RetentionDays', '90', 'Number of days to keep historical metrics'),
        ('SnapshotFrequency', 'Daily', 'How often to capture metrics (Daily/Hourly/Weekly)'),
        ('AlertThreshold_AvgQueryTimeMs', '5000', 'Alert if avg query time exceeds this'),
        ('AlertThreshold_FragmentationPercent', '20', 'Alert if index fragmentation exceeds this');

    PRINT '  ✓ DashboardConfig table created';
END
ELSE
BEGIN
    PRINT '  ✓ DashboardConfig table already exists';
END

PRINT '';

-- ============================================================================
-- Create stored procedures for common operations
-- ============================================================================
PRINT '[3/4] Creating stored procedures...';

-- SP: Capture snapshot
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'sp_CaptureMetricsSnapshot' AND schema_id = SCHEMA_ID('PerfDashboard'))
    DROP PROCEDURE PerfDashboard.sp_CaptureMetricsSnapshot;

CREATE PROCEDURE PerfDashboard.sp_CaptureMetricsSnapshot
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO PerfDashboard.MetricSnapshots (
        DatabaseName,
        TotalQueryCount,
        AvgExecutionTimeMs,
        MaxExecutionTimeMs,
        TotalWaitTimeMs,
        TotalBufferPoolUsedMB,
        TotalCPUTimeMs,
        TotalIndexFragmentation,
        MissingIndexCount,
        UnusedIndexCount,
        LargeTableCount,
        TablesWithoutPKCount,
        LongRunningTransactionCount,
        BlockingCount,
        DeadlockCount
    )
    SELECT
        DB_NAME(),
        COUNT(*),
        AVG(CAST(qs.total_elapsed_time AS FLOAT) / NULLIF(qs.execution_count, 0) / 1000.0),
        MAX(CAST(qs.max_elapsed_time AS FLOAT) / 1000.0),
        SUM(qs.total_elapsed_time),
        (SELECT CAST(SUM(sp.bpool_allocated_pages) * 8 / 1024.0 FROM sys.dm_os_buffer_descriptors sp WHERE sp.database_id = DB_ID())),
        SUM(qs.total_worker_time),
        AVG(ips.avg_fragmentation_in_percent),
        (SELECT COUNT(*) FROM sys.dm_db_missing_index_details WHERE database_id = DB_ID()),
        0,
        (SELECT COUNT(*) FROM sys.tables t JOIN sys.dm_db_partition_stats s ON t.object_id = s.object_id WHERE s.in_row_data_page_count > 1000),
        (SELECT COUNT(*) FROM sys.tables t WHERE NOT EXISTS (SELECT 1 FROM sys.key_constraints kc WHERE t.object_id = kc.parent_object_id AND kc.type = 'PK')),
        (SELECT COUNT(*) FROM sys.dm_tran_active_transactions WHERE transaction_begin_time < DATEADD(MINUTE, -5, GETDATE())),
        0,
        0
    FROM sys.dm_exec_query_stats qs
    FULL OUTER JOIN sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips ON 1=1;

    PRINT '✓ Snapshot captured: ' + CAST(SCOPE_IDENTITY() AS NVARCHAR(10));
END;

PRINT '  ✓ Stored procedures created';

PRINT '';

-- ============================================================================
-- Create views for easy querying
-- ============================================================================
PRINT '[4/4] Creating views...';

IF EXISTS (SELECT * FROM sys.views WHERE name = 'vw_LatestMetrics' AND schema_id = SCHEMA_ID('PerfDashboard'))
    DROP VIEW PerfDashboard.vw_LatestMetrics;

CREATE VIEW PerfDashboard.vw_LatestMetrics AS
SELECT TOP 1
    SnapshotID,
    SnapshotDate,
    DatabaseName,
    TotalQueryCount,
    AvgExecutionTimeMs,
    MaxExecutionTimeMs,
    TotalBufferPoolUsedMB,
    TotalIndexFragmentation,
    MissingIndexCount
FROM PerfDashboard.MetricSnapshots
ORDER BY SnapshotDate DESC;

PRINT '  ✓ Views created';

PRINT '';
PRINT '════════════════════════════════════════════════════════════════════════';
PRINT '✅ PERFORMANCE DASHBOARD SETUP COMPLETE';
PRINT '════════════════════════════════════════════════════════════════════════';
PRINT '';
PRINT 'Next steps:';
PRINT '1. Run: capture-performance-metrics.sql (to capture initial metrics)';
PRINT '2. Schedule capture to run daily/hourly';
PRINT '3. View dashboard: performance-dashboard.sql';
PRINT '';
PRINT 'Tables created:';
PRINT '  └─ PerfDashboard.MetricSnapshots';
PRINT '  └─ PerfDashboard.QueryPerformanceHistory';
PRINT '  └─ PerfDashboard.IndexFragmentationHistory';
PRINT '  └─ PerfDashboard.WaitEventHistory';
PRINT '  └─ PerfDashboard.PerformanceBaseline';
PRINT '  └─ PerfDashboard.DashboardConfig';
PRINT '';
