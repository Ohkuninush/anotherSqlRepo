-- ========================================
-- ANALYZE EXECUTION PLAN
-- Purpose: DMV queries to diagnose query performance issues
-- ========================================

-- 1. Find expensive queries (Last 50)
SELECT TOP 50
    qs.execution_count,
    qs.total_elapsed_time / 1000000 AS total_elapsed_sec,
    qs.total_elapsed_time / qs.execution_count / 1000 AS avg_elapsed_ms,
    qs.creation_time,
    qs.last_execution_time,
    SUBSTRING(st.text, 1, 100) AS query_text
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
ORDER BY qs.total_elapsed_time DESC;

-- 2. Identify Missing Indexes (Next section has dedicated script)
-- Use find_missing_indexes.sql for this

-- 3. Find Scans vs Seeks (Inefficient table access)
SELECT TOP 20
    OBJECT_NAME(i.object_id) AS table_name,
    i.name AS index_name,
    s.user_seeks,
    s.user_scans,
    s.user_lookups,
    s.user_updates
FROM sys.dm_db_index_stats AS s
INNER JOIN sys.indexes AS i ON s.object_id = i.object_id AND s.index_id = i.index_id
WHERE database_id = DB_ID()
    AND s.user_scans > s.user_seeks * 10  -- More scans than seeks
ORDER BY s.user_scans DESC;

-- 4. Index Fragmentation Analysis
SELECT TOP 20
    OBJECT_NAME(ips.object_id) AS table_name,
    i.name AS index_name,
    ips.avg_fragmentation_in_percent,
    ips.page_count
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') AS ips
INNER JOIN sys.indexes AS i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
WHERE ips.avg_fragmentation_in_percent > 10  -- Fragmented indexes
    AND ips.page_count > 1000  -- Only large indexes
ORDER BY ips.avg_fragmentation_in_percent DESC;

-- 5. Wait Statistics (Identify bottlenecks)
SELECT TOP 10
    wait_type,
    wait_time_ms,
    waiting_tasks_count,
    CONVERT(NUMERIC(12,2), wait_time_ms * 100.0 / SUM(wait_time_ms) OVER()) AS pct_total_wait
FROM sys.dm_os_wait_stats
WHERE wait_type NOT IN ('CLR_SEMAPHORE', 'LAZYWRITER_SLEEP', 'RESOURCE_QUEUE', 'SLEEP_TASK')
ORDER BY wait_time_ms DESC;

-- 6. Long Running Queries (Currently executing)
SELECT TOP 10
    s.session_id,
    r.command,
    DATEDIFF(SECOND, r.start_time, GETDATE()) AS duration_seconds,
    SUBSTRING(st.text, 1, 100) AS query_text,
    r.status
FROM sys.dm_exec_requests AS r
INNER JOIN sys.dm_exec_sessions AS s ON r.session_id = s.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS st
WHERE r.session_id > 50  -- Exclude system sessions
ORDER BY r.start_time ASC;

-- 7. Memory Pressure (Check for spills)
SELECT
    db_name = DB_NAME(),
    object_name = OBJECT_NAME(s.object_id),
    type_desc = i.type_desc,
    index_name = i.name,
    seeks = s.user_seeks,
    scans = s.user_scans,
    lookups = s.user_lookups,
    updates = s.user_updates,
    writes = s.user_updates + s.user_deletes + s.user_inserts
FROM sys.dm_db_index_stats AS s
INNER JOIN sys.indexes AS i ON s.object_id = i.object_id AND s.index_id = i.index_id
WHERE database_id = DB_ID() AND writes > 0
ORDER BY writes DESC;

-- 8. Execution Plan Cache (Current plans)
SELECT TOP 20
    qs.execution_count,
    qs.total_elapsed_time / 1000000 AS total_elapsed_sec,
    cp.cacheobjtype,
    cp.objtype,
    SUBSTRING(st.text, 1, 50) AS query
FROM sys.dm_exec_cached_plans AS cp
INNER JOIN sys.dm_exec_query_stats AS qs ON cp.plan_handle = qs.plan_handle
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) AS st
ORDER BY qs.execution_count DESC;

-- 9. Index Usage Summary
SELECT TOP 30
    OBJECT_NAME(i.object_id) AS table_name,
    i.name AS index_name,
    s.user_seeks + s.user_scans + s.user_lookups AS total_reads,
    s.user_updates AS writes,
    ips.avg_fragmentation_in_percent AS fragmentation_pct
FROM sys.dm_db_index_stats AS s
INNER JOIN sys.indexes AS i ON s.object_id = i.object_id AND s.index_id = i.index_id
LEFT JOIN sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') AS ips
    ON s.object_id = ips.object_id AND s.index_id = ips.index_id
WHERE database_id = DB_ID() AND i.index_id > 0  -- Exclude heaps
ORDER BY total_reads DESC;

-- 10. Object Space Usage
SELECT TOP 20
    OBJECT_NAME(p.object_id) AS table_name,
    i.name AS index_name,
    SUM(a.total_pages) * 8 / 1024 AS size_mb
FROM sys.partitions AS p
INNER JOIN sys.allocation_units AS a ON p.partition_id = a.container_id
INNER JOIN sys.indexes AS i ON p.object_id = i.object_id AND p.index_id = i.index_id
WHERE database_id = DB_ID() AND p.object_id > 100  -- User objects only
GROUP BY p.object_id, i.name
ORDER BY SUM(a.total_pages) DESC;
