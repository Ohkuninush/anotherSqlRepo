/*
╔══════════════════════════════════════════════════════════════════════╗
║                                                                      ║
║     SQL Server Expert Skill - Performance Metrics Capture             ║
║                                                                      ║
║  Captures performance data and stores in PerfDashboard schema.       ║
║  Run this daily/hourly for trending analysis.                        ║
║                                                                      ║
║  Prerequisites: Run setup-performance-history.sql first              ║
║                                                                      ║
╚══════════════════════════════════════════════════════════════════════╝
*/

SET NOCOUNT ON;

PRINT '';
PRINT '╔══════════════════════════════════════════════════════════════════════╗';
PRINT '║  PERFORMANCE METRICS - CAPTURE                                      ║';
PRINT '║  Database: ' + DB_NAME();
PRINT '║  Time: ' + CONVERT(NVARCHAR(20), GETDATE(), 121);
PRINT '╚══════════════════════════════════════════════════════════════════════╝';
PRINT '';

-- Check if schema exists
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'PerfDashboard')
BEGIN
    PRINT '❌ ERROR: PerfDashboard schema not found!';
    PRINT 'Run setup-performance-history.sql first';
    RETURN;
END

PRINT '[1/4] Capturing metric snapshot...';

-- ============================================================================
-- Capture MetricSnapshots - Overall database health
-- ============================================================================
BEGIN TRY
    DECLARE @AvgQueryTimeMs DECIMAL(10,2) = 0;
    DECLARE @MaxQueryTimeMs DECIMAL(10,2) = 0;
    DECLARE @TotalQueries BIGINT = 0;

    SELECT TOP 1
        @AvgQueryTimeMs = ISNULL(AVG(CAST(total_elapsed_time AS FLOAT) / NULLIF(execution_count, 0) / 1000.0), 0),
        @MaxQueryTimeMs = ISNULL(MAX(CAST(max_elapsed_time AS FLOAT) / 1000.0), 0),
        @TotalQueries = COUNT(*)
    FROM sys.dm_exec_query_stats;

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
        SUM(CAST(qs.total_elapsed_time AS BIGINT)),
        (SELECT ISNULL(CAST(SUM(sp.bpool_allocated_pages) * 8 / 1024.0 AS DECIMAL(10,2)), 0)
         FROM sys.dm_os_buffer_descriptors sp WHERE sp.database_id = DB_ID()),
        SUM(CAST(qs.total_worker_time AS BIGINT)),
        (SELECT ISNULL(AVG(ips.avg_fragmentation_in_percent), 0)
         FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
         WHERE ips.avg_fragmentation_in_percent > 0),
        (SELECT COUNT(*) FROM sys.dm_db_missing_index_details mid WHERE mid.database_id = DB_ID()),
        0,
        (SELECT COUNT(*) FROM sys.tables t
         JOIN sys.dm_db_partition_stats s ON t.object_id = s.object_id
         WHERE s.in_row_data_page_count > 1000 GROUP BY t.object_id HAVING SUM(s.in_row_data_page_count) > 1000),
        (SELECT COUNT(*) FROM sys.tables t
         WHERE NOT EXISTS (SELECT 1 FROM sys.key_constraints kc
         WHERE t.object_id = kc.parent_object_id AND kc.type = 'PK')),
        (SELECT COUNT(*) FROM sys.dm_tran_active_transactions
         WHERE transaction_begin_time < DATEADD(MINUTE, -5, GETDATE())),
        (SELECT COUNT(*) FROM sys.dm_tran_locks WHERE request_status = 'WAIT'),
        ISNULL((SELECT COUNT(*) FROM sys.dm_exec_session_wait_stats WHERE wait_type = 'DEADLOCK'), 0)
    FROM sys.dm_exec_query_stats qs;

    PRINT '  ✓ Snapshot captured';
END TRY
BEGIN CATCH
    PRINT '  ⚠️  Warning: Could not capture full snapshot - ' + ERROR_MESSAGE();
END CATCH

PRINT '';
PRINT '[2/4] Capturing query performance history...';

-- ============================================================================
-- Capture QueryPerformanceHistory - Individual query stats
-- ============================================================================
BEGIN TRY
    INSERT INTO PerfDashboard.QueryPerformanceHistory (
        QueryHash,
        QueryPlanHash,
        QueryText,
        ExecutionCount,
        TotalExecutionTimeMs,
        AvgExecutionTimeMs,
        MaxExecutionTimeMs,
        MinExecutionTimeMs,
        TotalLogicalReads,
        TotalPhysicalReads,
        TotalLogicalWrites,
        TotalWorkerTime,
        TotalElapsedTime,
        CreationTime,
        LastExecutionTime
    )
    SELECT TOP 50
        qs.query_hash,
        qs.query_plan_hash,
        SUBSTRING(st.text, (qs.statement_start_offset/2)+1,
                  ((CASE WHEN qs.statement_end_offset = -1
                         THEN LEN(CONVERT(NVARCHAR(MAX), st.text)) * 2
                         ELSE qs.statement_end_offset
                    END - qs.statement_start_offset)/2) + 1),
        qs.execution_count,
        CAST(qs.total_elapsed_time / 1000.0 AS BIGINT),
        CAST(qs.total_elapsed_time AS FLOAT) / NULLIF(qs.execution_count, 0) / 1000.0,
        CAST(qs.max_elapsed_time AS FLOAT) / 1000.0,
        CAST(qs.min_elapsed_time AS FLOAT) / 1000.0,
        qs.total_logical_reads,
        qs.total_physical_reads,
        qs.total_logical_writes,
        qs.total_worker_time,
        qs.total_elapsed_time,
        qs.creation_time,
        qs.last_execution_time
    FROM sys.dm_exec_query_stats qs
    CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
    WHERE qs.total_elapsed_time > 0
    ORDER BY qs.total_elapsed_time DESC;

    PRINT '  ✓ Top 50 queries captured';
END TRY
BEGIN CATCH
    PRINT '  ⚠️  Warning: Could not capture query history - ' + ERROR_MESSAGE();
END CATCH

PRINT '';
PRINT '[3/4] Capturing index fragmentation...';

-- ============================================================================
-- Capture IndexFragmentationHistory
-- ============================================================================
BEGIN TRY
    INSERT INTO PerfDashboard.IndexFragmentationHistory (
        SchemaName,
        TableName,
        IndexName,
        FragmentationPercent,
        PageCount,
        IndexType
    )
    SELECT
        OBJECT_SCHEMA_NAME(ips.object_id),
        OBJECT_NAME(ips.object_id),
        i.name,
        CAST(ips.avg_fragmentation_in_percent AS DECIMAL(5,2)),
        ips.page_count,
        ips.index_type_desc
    FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
    INNER JOIN sys.indexes i ON ips.object_id = i.object_id
                            AND ips.index_id = i.index_id
    WHERE ips.index_type > 0
    AND ips.avg_fragmentation_in_percent > 5
    AND ips.page_count > 100;

    PRINT '  ✓ Index fragmentation captured';
END TRY
BEGIN CATCH
    PRINT '  ⚠️  Warning: Could not capture index stats - ' + ERROR_MESSAGE();
END CATCH

PRINT '';
PRINT '[4/4] Capturing wait events...';

-- ============================================================================
-- Capture WaitEventHistory
-- ============================================================================
BEGIN TRY
    DECLARE @TotalWaitTimeMs BIGINT;
    SELECT @TotalWaitTimeMs = SUM(wait_time_ms) FROM sys.dm_os_wait_stats WHERE wait_type NOT IN ('SQLTRACE_BUFFER_FLUSH', 'LAZYWRITER_SLEEP', 'LOGMGR_QUEUE', 'CHECKPOINT_QUEUE', 'BROKER_EVENTHANDLER', 'BROKER_RECEIVE_WAITFOR', 'BROKER_TASK_STOP', 'CLR_AUTO_EVENT', 'CLR_MANUAL_EVENT', 'CLR_SEMAPHORE', 'DBMIRROR_DBM_EVENT', 'DBMIRROR_EVENTS_QUEUE', 'DBMIRROR_WORKER_QUEUE', 'DBMIRROR_HADR_OPERATION_QUEUE', 'DBMIRROR_HADR_TRANSPORT_QUEUE', 'SLEEP_TASK', 'SLEEP_SYSTEMTASK', 'WAITFOR', 'HADR_CLUSAPI_CALL', 'HADR_FILESTREAM_IOMGR_IOCTL', 'HADR_LOGCAPTURE_WAIT', 'HADR_NOTIFICATION_DEQUEUE', 'HADR_TIMER_TASK', 'HADR_WORK_QUEUE', 'DAC_INIT_SLEEP', 'DAC_BOOTSTRAP_SLEEP', 'INSTANCE_LOG_RATE_GOVERNOR', 'XE_DISPATCHER_JOIN', 'XE_DISPATCHER_WAIT', 'XE_TIMER_EVENT');

    INSERT INTO PerfDashboard.WaitEventHistory (
        WaitType,
        WaitTimeMs,
        SignalWaitTimeMs,
        WaitCount,
        Percentage
    )
    SELECT TOP 20
        wait_type,
        wait_time_ms,
        signal_wait_time_ms,
        waiting_tasks_count,
        CAST(CAST(wait_time_ms AS FLOAT) / NULLIF(@TotalWaitTimeMs, 0) * 100.0 AS DECIMAL(5,2))
    FROM sys.dm_os_wait_stats
    WHERE wait_type NOT IN ('SQLTRACE_BUFFER_FLUSH', 'LAZYWRITER_SLEEP', 'LOGMGR_QUEUE', 'CHECKPOINT_QUEUE')
    ORDER BY wait_time_ms DESC;

    PRINT '  ✓ Wait events captured';
END TRY
BEGIN CATCH
    PRINT '  ⚠️  Warning: Could not capture wait events - ' + ERROR_MESSAGE();
END CATCH

PRINT '';

-- ============================================================================
-- Cleanup old data (retention policy)
-- ============================================================================
DECLARE @RetentionDays INT = 90;
SELECT @RetentionDays = CAST(ConfigValue AS INT) FROM PerfDashboard.DashboardConfig WHERE ConfigKey = 'RetentionDays';

DELETE FROM PerfDashboard.MetricSnapshots WHERE SnapshotDate < DATEADD(DAY, -@RetentionDays, GETDATE());
DELETE FROM PerfDashboard.QueryPerformanceHistory WHERE CaptureDate < DATEADD(DAY, -@RetentionDays, GETDATE());
DELETE FROM PerfDashboard.IndexFragmentationHistory WHERE CaptureDate < DATEADD(DAY, -@RetentionDays, GETDATE());
DELETE FROM PerfDashboard.WaitEventHistory WHERE CaptureDate < DATEADD(DAY, -@RetentionDays, GETDATE());

PRINT '════════════════════════════════════════════════════════════════════════';
PRINT '✅ METRICS CAPTURE COMPLETE';
PRINT '════════════════════════════════════════════════════════════════════════';
PRINT '';
PRINT 'Data captured:';
PRINT '  ✓ Overall metrics snapshot';
PRINT '  ✓ Top 50 queries by execution time';
PRINT '  ✓ Index fragmentation data';
PRINT '  ✓ Wait events analysis';
PRINT '';
PRINT 'Next: View dashboard using performance-dashboard.sql';
PRINT '';
