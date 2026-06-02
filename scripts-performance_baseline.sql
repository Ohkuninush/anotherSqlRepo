-- ========================================
-- PERFORMANCE BASELINE
-- Purpose: Collect performance metrics and establish baseline data
-- ========================================

-- 1. Database-wide Performance Summary
SELECT
    DB_NAME() AS database_name,
    (SELECT SUM(size) * 8 / 1024 FROM sys.database_files) AS total_size_mb,
    (SELECT SUM(used) FROM sys.dm_db_file_space_usage) / 128 AS used_space_mb,
    (SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped = 0) AS user_tables,
    (SELECT COUNT(*) FROM sys.views WHERE is_ms_shipped = 0) AS user_views,
    (SELECT COUNT(*) FROM sys.procedures WHERE is_ms_shipped = 0) AS user_procedures;

-- 2. Expensive Queries (Top 20 by total execution time)
SELECT TOP 20
    ROW_NUMBER() OVER (ORDER BY qs.total_elapsed_time DESC) AS rank,
    qs.execution_count,
    qs.total_elapsed_time / 1000000 AS total_elapsed_sec,
    qs.total_elapsed_time / qs.execution_count / 1000 AS avg_elapsed_ms,
    qs.total_logical_reads,
    qs.total_physical_reads,
    qs.creation_time,
    SUBSTRING(st.text, 1, 80) AS query_text
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
ORDER BY qs.total_elapsed_time DESC;

-- 3. CPU-Intensive Queries
SELECT TOP 20
    ROW_NUMBER() OVER (ORDER BY qs.total_worker_time DESC) AS rank,
    qs.total_worker_time / 1000 AS cpu_ms,
    qs.execution_count,
    qs.total_worker_time / qs.execution_count / 1000 AS avg_cpu_ms,
    SUBSTRING(st.text, 1, 80) AS query_text
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
ORDER BY qs.total_worker_time DESC;

-- 4. I/O-Intensive Queries
SELECT TOP 20
    ROW_NUMBER() OVER (ORDER BY qs.total_logical_reads DESC) AS rank,
    qs.total_logical_reads,
    qs.total_physical_reads,
    qs.total_logical_writes,
    qs.execution_count,
    SUBSTRING(st.text, 1, 80) AS query_text
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
ORDER BY qs.total_logical_reads DESC;

-- 5. Longest Running Queries (Currently executing)
SELECT TOP 20
    s.session_id,
    r.command,
    DATEDIFF(SECOND, r.start_time, GETDATE()) AS duration_seconds,
    r.status,
    r.wait_type,
    r.cpu_time AS cpu_ms,
    r.logical_reads,
    SUBSTRING(st.text, 1, 100) AS query_text
FROM sys.dm_exec_requests AS r
INNER JOIN sys.dm_exec_sessions AS s ON r.session_id = s.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS st
WHERE r.session_id > 50
ORDER BY r.start_time ASC;

-- 6. Wait Statistics (System bottlenecks)
SELECT TOP 20
    wait_type,
    waiting_tasks_count,
    wait_time_ms,
    max_wait_time_ms,
    CONVERT(NUMERIC(12,2), 100.0 * wait_time_ms / SUM(wait_time_ms) OVER()) AS pct_total_wait,
    CONVERT(NUMERIC(12,2), wait_time_ms / NULLIF(waiting_tasks_count, 0)) AS avg_wait_ms
FROM sys.dm_os_wait_stats
WHERE wait_type NOT IN ('CLR_SEMAPHORE', 'LAZYWRITER_SLEEP', 'RESOURCE_QUEUE', 'SLEEP_TASK', 'SP_SERVER_DIAGNOSTICS_SLEEP')
ORDER BY wait_time_ms DESC;

-- 7. Buffer Pool Usage
SELECT
    (SELECT COUNT(*) FROM sys.dm_os_buffer_descriptors) AS total_buffer_pages,
    (SELECT COUNT(*) FROM sys.dm_os_buffer_descriptors WHERE database_id = DB_ID()) AS current_db_pages,
    (SELECT COUNT(*) FROM sys.dm_os_buffer_descriptors WHERE database_id = DB_ID()) * 8 / 1024 AS current_db_mb,
    (SELECT COUNT(*) FROM sys.dm_os_buffer_descriptors WHERE is_in_bpool_extension = 1) AS buffer_pool_extension_pages;

-- 8. Procedure Execution Statistics
SELECT TOP 20
    OBJECT_NAME(ps.object_id) AS procedure_name,
    ps.execution_count,
    ps.cached_time,
    ps.last_execution_time,
    DATEDIFF(DAY, ps.cached_time, GETDATE()) AS days_cached
FROM sys.dm_exec_procedure_stats AS ps
WHERE database_id = DB_ID()
ORDER BY ps.execution_count DESC;

-- 9. Lock Waits (Current blocking)
SELECT
    session_id,
    wait_duration_ms,
    wait_type,
    last_wait_type,
    program_name,
    login_name
FROM sys.dm_exec_sessions
WHERE wait_time_ms > 0 AND session_id > 50
ORDER BY wait_time_ms DESC;

-- 10. Compilation & Recompilation Statistics
SELECT TOP 20
    OBJECT_NAME(p.object_id) AS procedure_name,
    ps.execution_count,
    (SELECT occurrences FROM sys.dm_exec_cached_plans AS cp
     WHERE cp.plan_handle = (SELECT plan_handle FROM sys.dm_exec_procedure_stats WHERE object_id = p.object_id LIMIT 1)) AS plan_count,
    SUBSTRING(
        (SELECT text FROM sys.dm_exec_sql_text(
            (SELECT plan_handle FROM sys.dm_exec_procedure_stats WHERE object_id = p.object_id LIMIT 1)
        )),
        1, 80
    ) AS query_text
FROM sys.procedures AS p
INNER JOIN sys.dm_exec_procedure_stats AS ps ON p.object_id = ps.object_id
WHERE ps.database_id = DB_ID()
ORDER BY ps.execution_count DESC;

-- 11. Memory Grant & Spill Analysis
SELECT TOP 20
    SUBSTRING(qt.text, 1, 80) AS query_text,
    rg.requested_memory_kb,
    rg.granted_memory_kb,
    rg.required_memory_kb,
    CASE WHEN rg.granted_memory_kb < rg.required_memory_kb THEN 'SPILL RISK' ELSE 'OK' END AS status
FROM sys.dm_exec_query_memory_grants AS rg
CROSS APPLY sys.dm_exec_sql_text(rg.sql_handle) AS qt
ORDER BY rg.requested_memory_kb DESC;

-- 12. Transaction & Lock Summary
SELECT
    COUNT(DISTINCT session_id) AS active_sessions,
    COUNT(*) AS active_transactions,
    MIN(transaction_begin_time) AS oldest_transaction_start,
    DATEDIFF(SECOND, MIN(transaction_begin_time), GETDATE()) AS oldest_transaction_seconds
FROM sys.dm_tran_active_transactions;

-- 13. Table Access Patterns (Hot tables)
SELECT TOP 20
    OBJECT_NAME(s.object_id) AS table_name,
    s.user_seeks + s.user_scans + s.user_lookups AS total_reads,
    s.user_updates AS total_writes,
    CASE WHEN s.user_updates > 0 THEN CONVERT(NUMERIC(5,2), (s.user_seeks + s.user_scans + s.user_lookups) / CONVERT(FLOAT, s.user_updates)) ELSE 999 END AS read_to_write_ratio
FROM sys.dm_db_index_stats AS s
WHERE s.database_id = DB_ID() AND s.object_id > 100
GROUP BY s.object_id
ORDER BY s.user_seeks + s.user_scans + s.user_lookups DESC;

-- 14. Query Store (If enabled)
SELECT
    q.query_id,
    q.query_text_id,
    SUBSTRING(qt.query_sql_text, 1, 80) AS query_text,
    COUNT(rs.plan_id) AS execution_count,
    AVG(rs.avg_duration) / 1000 AS avg_duration_ms,
    MAX(rs.last_execution_time) AS last_execution
FROM sys.query_store_query AS q
INNER JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
INNER JOIN sys.query_store_runtime_stats AS rs ON q.query_id = rs.query_id
WHERE q.context_settings_id = (SELECT TOP 1 context_settings_id FROM sys.query_store_query)
GROUP BY q.query_id, q.query_text_id, qt.query_sql_text
ORDER BY COUNT(rs.plan_id) DESC;

-- 15. Baseline Snapshot Summary
SELECT
    GETDATE() AS snapshot_time,
    DB_NAME() AS database_name,
    (SELECT COUNT(*) FROM sys.databases WHERE state_desc = 'ONLINE') AS online_databases,
    (SELECT @@VERSION) AS sql_version,
    (SELECT SUM(total_physical_memory_kb) / 1024 / 1024 FROM sys.dm_os_sys_memory) AS total_system_memory_gb
