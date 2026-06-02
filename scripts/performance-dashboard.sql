/*
╔══════════════════════════════════════════════════════════════════════╗
║                                                                      ║
║     SQL Server Expert Skill - Performance Dashboard Report            ║
║                                                                      ║
║  Visual dashboard showing performance metrics over time.             ║
║  Requires: setup-performance-history.sql and at least 1 capture      ║
║                                                                      ║
╚══════════════════════════════════════════════════════════════════════╝
*/

SET NOCOUNT ON;

PRINT '';
PRINT '╔══════════════════════════════════════════════════════════════════════╗';
PRINT '║  PERFORMANCE DASHBOARD REPORT                                       ║';
PRINT '║  Database: ' + DB_NAME();
PRINT '║  Generated: ' + CONVERT(NVARCHAR(20), GETDATE(), 121);
PRINT '╚══════════════════════════════════════════════════════════════════════╝';
PRINT '';

-- Check if schema exists
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'PerfDashboard')
BEGIN
    PRINT '❌ ERROR: PerfDashboard schema not found!';
    PRINT 'Run setup-performance-history.sql and capture-performance-metrics.sql first';
    RETURN;
END

-- Check if there's any data
IF NOT EXISTS (SELECT 1 FROM PerfDashboard.MetricSnapshots)
BEGIN
    PRINT '⚠️  No data available yet.';
    PRINT '';
    PRINT 'Please run: capture-performance-metrics.sql';
    PRINT 'Then run this dashboard again in a few hours/days to see trends.';
    RETURN;
END

-- ============================================================================
-- SECTION 1: CURRENT PERFORMANCE SNAPSHOT
-- ============================================================================
PRINT '┌─────────────────────────────────────────────────────────────────────┐';
PRINT '│ 📊 CURRENT PERFORMANCE SNAPSHOT                                     │';
PRINT '└─────────────────────────────────────────────────────────────────────┘';
PRINT '';

SELECT TOP 1
    'Captured at' AS Metric,
    CONVERT(NVARCHAR(20), SnapshotDate, 121) AS Value
FROM PerfDashboard.MetricSnapshots
ORDER BY SnapshotDate DESC;

SELECT TOP 1
    'Average Query Time' AS Metric,
    CAST(AvgExecutionTimeMs AS NVARCHAR(20)) + ' ms' AS Value
FROM PerfDashboard.MetricSnapshots
ORDER BY SnapshotDate DESC;

SELECT TOP 1
    'Max Query Time' AS Metric,
    CAST(MaxExecutionTimeMs AS NVARCHAR(20)) + ' ms' AS Value
FROM PerfDashboard.MetricSnapshots
ORDER BY SnapshotDate DESC;

SELECT TOP 1
    'Total Queries' AS Metric,
    CAST(TotalQueryCount AS NVARCHAR(20)) AS Value
FROM PerfDashboard.MetricSnapshots
ORDER BY SnapshotDate DESC;

SELECT TOP 1
    'Buffer Pool (MB)' AS Metric,
    CAST(TotalBufferPoolUsedMB AS NVARCHAR(20)) + ' MB' AS Value
FROM PerfDashboard.MetricSnapshots
ORDER BY SnapshotDate DESC;

SELECT TOP 1
    'Avg Index Fragmentation' AS Metric,
    CAST(TotalIndexFragmentation AS NVARCHAR(20)) + ' %' AS Value
FROM PerfDashboard.MetricSnapshots
ORDER BY SnapshotDate DESC;

SELECT TOP 1
    'Missing Indexes' AS Metric,
    CAST(MissingIndexCount AS NVARCHAR(20)) AS Value
FROM PerfDashboard.MetricSnapshots
ORDER BY SnapshotDate DESC;

PRINT '';

-- ============================================================================
-- SECTION 2: PERFORMANCE TREND (Last 30 days)
-- ============================================================================
PRINT '┌─────────────────────────────────────────────────────────────────────┐';
PRINT '│ 📈 PERFORMANCE TREND (Last 30 Days)                                 │';
PRINT '└─────────────────────────────────────────────────────────────────────┘';
PRINT '';

PRINT 'Avg Query Time Trend:';
PRINT '─────────────────────────────────────────────────';

SELECT
    ROW_NUMBER() OVER (ORDER BY SnapshotDate DESC) AS DayNum,
    CONVERT(NVARCHAR(10), SnapshotDate, 23) AS Date,
    CAST(AvgExecutionTimeMs AS DECIMAL(10,2)) AS AvgTimeMs,
    CAST(MaxExecutionTimeMs AS DECIMAL(10,2)) AS MaxTimeMs,
    TotalQueryCount AS QueryCount
FROM PerfDashboard.MetricSnapshots
WHERE SnapshotDate >= DATEADD(DAY, -30, GETDATE())
ORDER BY SnapshotDate DESC;

PRINT '';

-- ============================================================================
-- SECTION 3: TOP SLOW QUERIES
-- ============================================================================
PRINT '┌─────────────────────────────────────────────────────────────────────┐';
PRINT '│ 🐌 TOP 10 SLOWEST QUERIES                                           │';
PRINT '└─────────────────────────────────────────────────────────────────────┘';
PRINT '';

SELECT TOP 10
    ROW_NUMBER() OVER (ORDER BY AvgExecutionTimeMs DESC) AS Rank,
    CAST(AvgExecutionTimeMs AS DECIMAL(10,2)) AS AvgTimeMs,
    ExecutionCount,
    CAST(TotalExecutionTimeMs / 1000.0 / 60.0 AS DECIMAL(10,2)) AS TotalMinutes,
    LEFT(QueryText, 100) AS QueryPreview
FROM PerfDashboard.QueryPerformanceHistory
WHERE CaptureDate = (SELECT MAX(CaptureDate) FROM PerfDashboard.QueryPerformanceHistory)
ORDER BY AvgExecutionTimeMs DESC;

PRINT '';

-- ============================================================================
-- SECTION 4: INDEX FRAGMENTATION ANALYSIS
-- ============================================================================
PRINT '┌─────────────────────────────────────────────────────────────────────┐';
PRINT '│ 🔧 INDEX FRAGMENTATION STATUS                                       │';
PRINT '└─────────────────────────────────────────────────────────────────────┘';
PRINT '';

SELECT TOP 1
    CAST(AVG(FragmentationPercent) AS DECIMAL(5,2)) AS AvgFragmentation,
    CAST(MAX(FragmentationPercent) AS DECIMAL(5,2)) AS MaxFragmentation,
    COUNT(*) AS IndexCount
FROM PerfDashboard.IndexFragmentationHistory
WHERE CaptureDate = (SELECT MAX(CaptureDate) FROM PerfDashboard.IndexFragmentationHistory)
AND FragmentationPercent > 5;

PRINT '';
PRINT 'Most Fragmented Indexes:';

SELECT TOP 5
    TableName,
    IndexName,
    CAST(FragmentationPercent AS DECIMAL(5,2)) AS FragmentationPercent,
    PageCount
FROM PerfDashboard.IndexFragmentationHistory
WHERE CaptureDate = (SELECT MAX(CaptureDate) FROM PerfDashboard.IndexFragmentationHistory)
ORDER BY FragmentationPercent DESC;

PRINT '';

-- ============================================================================
-- SECTION 5: WAIT EVENTS ANALYSIS
-- ============================================================================
PRINT '┌─────────────────────────────────────────────────────────────────────┐';
PRINT '│ ⏳ TOP WAIT EVENTS (Bottlenecks)                                     │';
PRINT '└─────────────────────────────────────────────────────────────────────┘';
PRINT '';

SELECT TOP 10
    WaitType,
    CAST(WaitTimeMs / 1000.0 / 60.0 AS DECIMAL(10,2)) AS TotalWaitMinutes,
    WaitCount,
    CAST(Percentage AS DECIMAL(5,2)) AS Percentage
FROM PerfDashboard.WaitEventHistory
WHERE CaptureDate = (SELECT MAX(CaptureDate) FROM PerfDashboard.WaitEventHistory)
ORDER BY WaitTimeMs DESC;

PRINT '';

-- ============================================================================
-- SECTION 6: TREND COMPARISON (Current vs Previous)
-- ============================================================================
PRINT '┌─────────────────────────────────────────────────────────────────────┐';
PRINT '│ 📊 COMPARISON: Current vs 7 Days Ago                                │';
PRINT '└─────────────────────────────────────────────────────────────────────┘';
PRINT '';

DECLARE @Current TABLE (
    AvgTime DECIMAL(10,2),
    MaxTime DECIMAL(10,2),
    Queries BIGINT,
    Fragmentation DECIMAL(5,2)
);

DECLARE @Previous TABLE (
    AvgTime DECIMAL(10,2),
    MaxTime DECIMAL(10,2),
    Queries BIGINT,
    Fragmentation DECIMAL(5,2)
);

INSERT INTO @Current
SELECT TOP 1
    AvgExecutionTimeMs,
    MaxExecutionTimeMs,
    TotalQueryCount,
    TotalIndexFragmentation
FROM PerfDashboard.MetricSnapshots
ORDER BY SnapshotDate DESC;

INSERT INTO @Previous
SELECT TOP 1
    AvgExecutionTimeMs,
    MaxExecutionTimeMs,
    TotalQueryCount,
    TotalIndexFragmentation
FROM PerfDashboard.MetricSnapshots
WHERE SnapshotDate < DATEADD(DAY, -7, GETDATE())
ORDER BY SnapshotDate DESC;

SELECT
    'Avg Query Time (ms)' AS Metric,
    CAST(c.AvgTime AS NVARCHAR(20)) AS Current,
    CAST(p.AvgTime AS NVARCHAR(20)) AS Previous,
    CASE
        WHEN p.AvgTime > 0 THEN
            CAST(CAST((c.AvgTime - p.AvgTime) / p.AvgTime * 100 AS DECIMAL(5,2)) AS NVARCHAR(20)) + '%'
        ELSE 'N/A'
    END AS ChangePct,
    CASE
        WHEN c.AvgTime < p.AvgTime THEN '✅ Better'
        WHEN c.AvgTime > p.AvgTime THEN '⚠️  Worse'
        ELSE '→ Same'
    END AS Trend
FROM @Current c, @Previous p;

PRINT '';

-- ============================================================================
-- SECTION 7: HEALTH ASSESSMENT
-- ============================================================================
PRINT '┌─────────────────────────────────────────────────────────────────────┐';
PRINT '│ 🏥 HEALTH ASSESSMENT                                                │';
PRINT '└─────────────────────────────────────────────────────────────────────┘';
PRINT '';

DECLARE @AvgQueryTime DECIMAL(10,2);
DECLARE @IndexFragmentation DECIMAL(5,2);
DECLARE @MissingIndexes INT;

SELECT TOP 1
    @AvgQueryTime = AvgExecutionTimeMs,
    @IndexFragmentation = TotalIndexFragmentation,
    @MissingIndexes = MissingIndexCount
FROM PerfDashboard.MetricSnapshots
ORDER BY SnapshotDate DESC;

PRINT 'Database Health Summary:';
PRINT '';

-- Query Performance
IF @AvgQueryTime < 100
    PRINT '✅ QUERY PERFORMANCE: Excellent (Avg < 100ms)';
ELSE IF @AvgQueryTime < 500
    PRINT '⚠️  QUERY PERFORMANCE: Good (Avg ' + CAST(@AvgQueryTime AS NVARCHAR(20)) + 'ms)';
ELSE IF @AvgQueryTime < 2000
    PRINT '⚠️  QUERY PERFORMANCE: Fair (Avg ' + CAST(@AvgQueryTime AS NVARCHAR(20)) + 'ms) - Consider optimization';
ELSE
    PRINT '❌ QUERY PERFORMANCE: Poor (Avg ' + CAST(@AvgQueryTime AS NVARCHAR(20)) + 'ms) - Immediate action needed';

-- Index Fragmentation
IF @IndexFragmentation < 10
    PRINT '✅ INDEX HEALTH: Excellent (Avg fragmentation < 10%)';
ELSE IF @IndexFragmentation < 20
    PRINT '⚠️  INDEX HEALTH: Good (Avg fragmentation ' + CAST(@IndexFragmentation AS NVARCHAR(20)) + '%)';
ELSE
    PRINT '⚠️  INDEX HEALTH: Needs maintenance (Avg fragmentation ' + CAST(@IndexFragmentation AS NVARCHAR(20)) + '%) - Run defrag';

-- Missing Indexes
IF @MissingIndexes = 0
    PRINT '✅ INDEXES: All identified missing indexes are created';
ELSE
    PRINT '⚠️  MISSING INDEXES: ' + CAST(@MissingIndexes AS NVARCHAR(20)) + ' indexes could improve performance';

PRINT '';

-- ============================================================================
-- SECTION 8: RECOMMENDATIONS
-- ============================================================================
PRINT '┌─────────────────────────────────────────────────────────────────────┐';
PRINT '│ 💡 RECOMMENDATIONS                                                  │';
PRINT '└─────────────────────────────────────────────────────────────────────┘';
PRINT '';

IF @AvgQueryTime > 500
    PRINT '1. Review slow queries: Run find_missing_indexes.sql';

IF @IndexFragmentation > 20
    PRINT '2. Defragment indexes: Consider REBUILD or REORGANIZE';

IF @MissingIndexes > 0
    PRINT '3. Create missing indexes: Check find_missing_indexes.sql for recommendations';

PRINT '4. Continue monitoring: Run capture-performance-metrics.sql regularly';
PRINT '';

-- ============================================================================
-- FOOTER
-- ============================================================================
PRINT '════════════════════════════════════════════════════════════════════════';
PRINT 'Report generated: ' + CONVERT(NVARCHAR(20), GETDATE(), 121);
PRINT '';
PRINT 'Next steps:';
PRINT '  1. Review findings above';
PRINT '  2. Apply recommendations';
PRINT '  3. Run capture-performance-metrics.sql daily to track trends';
PRINT '  4. Compare dashboard weekly to see improvement';
PRINT '';
PRINT 'For detailed analysis:';
PRINT '  - See: references-query_patterns.md';
PRINT '  - See: references-index_design_guidelines.md';
PRINT '  - Try: LAB-01 for hands-on optimization';
PRINT '';
