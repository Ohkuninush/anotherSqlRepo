-- ========================================
-- DEADLOCK ANALYZER
-- Purpose: Diagnose deadlock causes and identify solutions
-- ========================================

-- 1. Enable Deadlock Tracing (Run once)
-- DBCC TRACEON (1222, -1);  -- Global trace flag
-- Check: DBCC TRACESTATUS(1222);

-- 2. Find Recent Deadlock Information
SELECT TOP 20
    spid = er.session_id,
    blocked_by_spid = er.blocking_session_id,
    command = er.command,
    status = er.status,
    wait_type = er.wait_type,
    wait_time_ms = er.wait_time_ms,
    open_transaction_count = es.open_transaction_count,
    query = SUBSTRING(st.text, 1, 100)
FROM sys.dm_exec_requests AS er
INNER JOIN sys.dm_exec_sessions AS es ON er.session_id = es.session_id
CROSS APPLY sys.dm_exec_sql_text(er.sql_handle) AS st
WHERE er.blocking_session_id > 0
ORDER BY er.wait_time_ms DESC;

-- 3. Transaction Blocking Chain
WITH BlockingHierarchy AS (
    SELECT
        er.session_id,
        er.blocking_session_id,
        es.login_name,
        es.program_name,
        SUBSTRING(st.text, 1, 50) AS query,
        1 AS level
    FROM sys.dm_exec_requests AS er
    INNER JOIN sys.dm_exec_sessions AS es ON er.session_id = es.session_id
    CROSS APPLY sys.dm_exec_sql_text(er.sql_handle) AS st
    WHERE er.blocking_session_id = 0
    UNION ALL
    SELECT
        er.session_id,
        er.blocking_session_id,
        es.login_name,
        es.program_name,
        SUBSTRING(st.text, 1, 50),
        bh.level + 1
    FROM sys.dm_exec_requests AS er
    INNER JOIN sys.dm_exec_sessions AS es ON er.session_id = es.session_id
    CROSS APPLY sys.dm_exec_sql_text(er.sql_handle) AS st
    INNER JOIN BlockingHierarchy AS bh ON er.blocking_session_id = bh.session_id
)
SELECT
    REPLICATE('  ', level - 1) + 'Session ' + CAST(session_id AS VARCHAR(5)) AS session_chain,
    session_id,
    blocking_session_id,
    login_name,
    program_name,
    query,
    level
FROM BlockingHierarchy
ORDER BY level, session_id;

-- 4. Lock Information (Current locks)
SELECT
    request_session_id,
    resource_type,
    resource_associated_entity_id,
    request_type,
    request_mode,
    request_status,
    OBJECT_NAME(resource_associated_entity_id) AS table_name
FROM sys.dm_tran_locks
WHERE request_session_id > 50
ORDER BY request_session_id, resource_type;

-- 5. Open Transactions
SELECT
    transaction_id,
    session_id,
    transaction_begin_time,
    DATEDIFF(SECOND, transaction_begin_time, GETDATE()) AS transaction_age_seconds,
    transaction_type,
    transaction_state,
    CASE
        WHEN transaction_type = 1 THEN 'Read/Write'
        WHEN transaction_type = 2 THEN 'Read Only'
        WHEN transaction_type = 3 THEN 'System'
        ELSE 'Unknown'
    END AS trans_type_desc,
    CASE
        WHEN transaction_state = 0 THEN 'Initialized'
        WHEN transaction_state = 1 THEN 'Active'
        WHEN transaction_state = 2 THEN 'Ended'
        WHEN transaction_state = 3 THEN 'Will Commit'
        WHEN transaction_state = 4 THEN 'Committing'
        WHEN transaction_state = 5 THEN 'Rolling Back'
        WHEN transaction_state = 6 THEN 'Will Rollback'
        ELSE 'Unknown'
    END AS state_desc
FROM sys.dm_tran_active_transactions
ORDER BY transaction_begin_time;

-- 6. Identify Lock Escalation Candidates
SELECT TOP 20
    OBJECT_NAME(p.object_id) AS table_name,
    COUNT(DISTINCT lock_id) AS lock_count,
    resource_type,
    resource_associated_entity_id,
    p.rows AS row_count
FROM sys.dm_tran_locks AS tl
INNER JOIN sys.partitions AS p ON tl.resource_associated_entity_id = p.partition_id
WHERE resource_type = 'RID'  -- Row ID locks indicate escalation risk
GROUP BY p.object_id, resource_type, resource_associated_entity_id, p.rows
ORDER BY lock_count DESC;

-- 7. Session Details (For deadlock investigation)
SELECT
    session_id,
    login_name,
    program_name,
    host_name,
    status,
    open_transaction_count,
    transaction_isolation_level_desc = CASE
        WHEN transaction_isolation_level = 0 THEN 'UNSPECIFIED'
        WHEN transaction_isolation_level = 1 THEN 'READ_UNCOMMITTED'
        WHEN transaction_isolation_level = 2 THEN 'READ_COMMITTED'
        WHEN transaction_isolation_level = 3 THEN 'REPEATABLE_READ'
        WHEN transaction_isolation_level = 4 THEN 'SERIALIZABLE'
        WHEN transaction_isolation_level = 5 THEN 'SNAPSHOT'
        ELSE 'UNKNOWN'
    END,
    login_time,
    last_request_start_time,
    DATEDIFF(SECOND, last_request_start_time, GETDATE()) AS idle_seconds
FROM sys.dm_exec_sessions
WHERE session_id > 50
ORDER BY open_transaction_count DESC;

-- 8. Query Locks (Show what queries are holding locks)
SELECT
    r.session_id,
    r.command,
    SUBSTRING(st.text, 1, 80) AS query,
    tl.resource_type,
    tl.request_mode,
    tl.request_status,
    OBJECT_NAME(tl.resource_associated_entity_id) AS locked_object
FROM sys.dm_exec_requests AS r
INNER JOIN sys.dm_exec_sessions AS s ON r.session_id = s.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS st
INNER JOIN sys.dm_tran_locks AS tl ON r.session_id = tl.request_session_id
WHERE r.session_id > 50
ORDER BY r.session_id, tl.resource_type;

-- 9. Lock Timeout Configuration
SELECT
    lock_timeout = @@LOCK_TIMEOUT;

-- 10. Deadlock Prevention Recommendations
SELECT
    'Isolation Level' AS recommendation_type,
    'Consider SNAPSHOT or READ_COMMITTED_SNAPSHOT isolation' AS recommendation,
    'Reduces locking conflicts by using row versioning' AS benefit,
    'ALTER DATABASE [database_name] SET ALLOW_SNAPSHOT_ISOLATION ON;' AS implementation
UNION ALL
SELECT
    'Index Design',
    'Add non-clustered indexes to avoid hotspots',
    'Reduces lock contention by enabling more parallelism',
    'CREATE NONCLUSTERED INDEX idx_name ON table_name (column) INCLUDE (other_columns);'
UNION ALL
SELECT
    'Transaction Duration',
    'Keep transactions as short as possible',
    'Reduces lock duration and chance of conflicts',
    'Move non-critical operations outside transaction boundaries'
UNION ALL
SELECT
    'Lock Ordering',
    'Access tables in the same order in all queries',
    'Prevents circular lock dependencies',
    'Document and enforce table access order in stored procedures'
UNION ALL
SELECT
    'Locking Hints',
    'Use NOLOCK for read-only queries if dirty reads acceptable',
    'Eliminates read locks for high-volume queries',
    'SELECT col FROM table WITH (NOLOCK) WHERE condition;'
UNION ALL
SELECT
    'Connection Pooling',
    'Ensure connection pooling is enabled',
    'Reduces transaction duration by reusing connections',
    'Check application connection string for pooling=true';

-- 11. Deadlock History (From error log)
-- Note: Requires SQL Server Agent and error log reading
-- SELECT * FROM sys.xp_readerrorlog (last N hours of deadlocks)

-- 12. Database Statistics for Deadlock Prevention
SELECT
    'Last Cleared' = GETDATE(),
    'Trace Flags Enabled' = CASE WHEN (SELECT @@OPTIONS & 4) = 4 THEN 'Yes' ELSE 'No' END,
    'Version' = @@VERSION,
    'Isolation Snapshot Enabled' = CASE WHEN (SELECT is_read_committed_snapshot_on FROM sys.databases WHERE database_id = DB_ID()) = 1 THEN 'Yes' ELSE 'No' END;

-- 13. Kill Blocking Session (If necessary - use with caution!)
-- KILL <session_id>;  -- Replace <session_id> with actual session ID

-- 14. Rollback Long Transaction (If necessary)
-- KILL <session_id> WITH STATUSONLY;  -- Check status before rollback

-- 15. Monitor Deadlock Spins (System-wide)
SELECT
    (SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = 'Number of Deadlocks/sec') AS deadlocks_per_second,
    (SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = 'Processes blocked') AS processes_blocked
