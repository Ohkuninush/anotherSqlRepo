# SQL Server Observability & Diagnostics

## Extended Events (Better than Profiler)

### Setup Extended Events Session
```sql
-- Create session for capturing deadlocks
CREATE EVENT SESSION Deadlock_Events ON SERVER
ADD EVENT sqlserver.xml_deadlock_report
(ACTION (sqlserver.sql_text, sqlserver.database_name))
ADD TARGET package0.event_file
(SET filename = N'D:\ExtendedEvents\deadlock.xel', max_file_size = 10)
WITH (STARTUP_STATE = ON)

-- Start session
ALTER EVENT SESSION Deadlock_Events ON SERVER STATE = START

-- View captured deadlocks
SELECT 
    event_data.value('(event/@timestamp)[1]', 'DATETIME') AS DeadlockTime,
    event_data.value('(event/data[@name="deadlock_graph"]/value)[1]', 'NVARCHAR(MAX)') AS DeadlockGraph
FROM (
    SELECT CAST(event_data AS XML) AS event_data
    FROM sys.fn_xe_file_target_read_file(
        'D:\ExtendedEvents\deadlock.xel*', NULL, NULL, NULL
    )
) AS T
```

### Performance Monitoring Session
```sql
-- Track slow queries
CREATE EVENT SESSION SlowQueries ON SERVER
ADD EVENT sqlserver.sql_statement_completed
(
    WHERE sqlserver.sql_statement_completed.cpu_time > 5000000  -- > 5 seconds CPU
)
ADD EVENT sqlserver.rpc_completed
(
    WHERE sqlserver.rpc_completed.cpu_time > 5000000
)
ADD TARGET package0.event_file
(SET filename = N'D:\ExtendedEvents\slowqueries.xel')
WITH (STARTUP_STATE = ON)

-- Read slow query data
SELECT 
    event_data.value('(event/@timestamp)[1]', 'DATETIME') AS EventTime,
    event_data.value('(event/data[@name="cpu_time"]/value)[1]', 'BIGINT') AS CPUTimeUS,
    event_data.value('(event/data[@name="duration"]/value)[1]', 'BIGINT') AS DurationUS,
    event_data.value('(event/data[@name="statement"]/value)[1]', 'NVARCHAR(MAX)') AS SQLStatement
FROM (
    SELECT CAST(event_data AS XML) AS event_data
    FROM sys.fn_xe_file_target_read_file(
        'D:\ExtendedEvents\slowqueries.xel*', NULL, NULL, NULL
    )
)
ORDER BY EventTime DESC
```

## Wait Statistics (System Bottlenecks)

### Analyze Wait Types
```sql
-- Clear waits first
DBCC SQLPERF('sys.dm_os_wait_stats', CLEAR)

-- ... wait 1-2 hours of production traffic ...

-- Analyze waits
SELECT TOP 20
    wait_type,
    wait_count,
    wait_time_ms,
    max_wait_time_ms,
    CONVERT(NUMERIC(8,2), 100.0 * wait_time_ms / SUM(wait_time_ms) OVER()) AS pct_total_wait,
    CONVERT(NUMERIC(8,2), wait_time_ms / NULLIF(wait_count, 0)) AS avg_wait_ms
FROM sys.dm_os_wait_stats
WHERE wait_type NOT IN (
    'SQLTRACE_WAIT_ENTRIES', 'LAZYWRITER_SLEEP', 'RESOURCE_QUEUE',
    'CLR_SEMAPHORE', 'SLEEP_TASK', 'BROKER_EVENTHANDLER',
    'CHECKPOINT_QUEUE', 'BROKER_RECEIVE_WAITFOR'  -- Ignore harmless waits
)
ORDER BY wait_time_ms DESC

-- Interpretation:
-- - CXPACKET: CPU parallelism bottleneck
-- - PAGEIOLATCH_*: Disk I/O bottleneck
-- - PAGELATCH_*: Memory/buffer pool contention
-- - WRITELOG: Transaction log I/O bottleneck
-- - LCK_M_*: Locking contention (blocking)
```

### Example: Diagnose PAGEIOLATCH Wait
```sql
-- PAGEIOLATCH_EX waits = Waiting for disk reads
-- Solution: 
-- 1. Add more RAM (cache more data)
-- 2. Faster disks (SSD)
-- 3. Index optimization (fewer scans)

-- Check which queries cause I/O
SELECT TOP 20
    qs.execution_count,
    qs.total_logical_reads,
    qs.total_physical_reads,
    qs.total_logical_reads / NULLIF(qs.execution_count, 0) AS avg_logical_reads,
    SUBSTRING(st.text, 1, 100) AS QueryText
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
ORDER BY qs.total_physical_reads DESC

-- High physical_reads = queries causing disk I/O
-- Solution: Add covering index, optimize query, increase buffer pool
```

## Memory Grants & Spills

### Detect Spilling Queries
```sql
-- Queries that spilled to disk (used tempdb for sort/hash)
SELECT TOP 20
    plan_handle,
    r.session_id,
    r.requested_memory_kb,
    r.granted_memory_kb,
    r.required_memory_kb,
    CASE 
        WHEN r.granted_memory_kb < r.required_memory_kb THEN 'SPILL_RISK'
        WHEN r.granted_memory_kb < r.requested_memory_kb * 0.8 THEN 'LIKELY_SPILL'
        ELSE 'OK'
    END AS SpillStatus,
    SUBSTRING(st.text, 1, 100) AS QueryText
FROM sys.dm_exec_query_memory_grants r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) st
ORDER BY r.requested_memory_kb DESC

-- Spills are SLOW (tempdb = disk storage)
-- Solutions:
-- 1. Add more RAM
-- 2. Optimize query (filter earlier, better indexes)
-- 3. Increase max memory grant (RESOURCE GOVERNOR)
-- 4. Partition large tables
```

### Monitor Memory Pressure
```sql
-- Check buffer pool usage
SELECT 
    (SELECT COUNT(*) FROM sys.dm_os_buffer_descriptors) AS total_buffer_pages,
    (SELECT COUNT(*) FROM sys.dm_os_buffer_descriptors WHERE database_id = DB_ID()) AS current_db_pages,
    (SELECT COUNT(*) FROM sys.dm_os_buffer_descriptors WHERE database_id = DB_ID()) * 8 / 1024 AS current_db_mb,
    (SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = 'Total Pages') AS total_memory_pages,
    (SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = 'Free Pages') AS free_memory_pages

-- If free_memory_pages is low: Memory pressure, queries spill
```

## Spinlocks (Lightweight Locking Contention)

### Detect Spinlock Contention
```sql
-- Spinlocks indicate CPU contention on small locks
SELECT 
    name,
    spins,
    spins_per_collision,
    sleep_count,
    backoffs
FROM sys.dm_os_spinlock_stats
ORDER BY spins DESC

-- High spins = threads waiting for lock (busy loop)
-- Remedy: 
-- - Add CPUs
-- - Balance workload
-- - Optimize queries (reduce lock time)
-- - Use SNAPSHOT isolation (reduces locking)
```

### Common Spinlock Causes
```sql
-- SOS_CACHESTORE spinlock: Query plan cache contention
-- - Many different queries (hash table collision)
-- - Solution: Parameterize queries, reduce unique plans

-- LAT spinlock: Latch contention
-- - Typically in tempdb (session management)
-- - Solution: Add tempdb files (one per 4 logical CPUs)

-- BUFFER spinlock: Buffer pool contention
-- - Many threads accessing buffer pool
-- - Solution: Add RAM, optimize query access patterns
```

## Resource Governor (Workload Management)

### Create Resource Pool
```sql
-- Limit resource consumption by workload
CREATE RESOURCE POOL DataSciencePool
WITH (
    MIN_CPU_PERCENT = 10,
    MAX_CPU_PERCENT = 30,
    CAP_CPU_PERCENT = 35,
    MIN_MEMORY_PERCENT = 20,
    MAX_MEMORY_PERCENT = 40,
    MIN_IOPS_PER_VOLUME = 100,
    MAX_IOPS_PER_VOLUME = 500
)

-- Create workload group
CREATE WORKLOAD GROUP DataScienceGroup
WITH (
    IMPORTANCE = LOW,
    REQUEST_MAX_MEMORY_GRANT_PERCENT = 10,
    REQUEST_MAX_CPU_TIME_SEC = 3600,
    REQUEST_MEMORY_GRANT_TIMEOUT_SEC = 120
)
USING DataSciencePool

-- Assign user logins to group
CREATE LOGIN DataScienceUser WITH PASSWORD = 'P@ssw0rd'
CREATE USER DataScienceUser FROM LOGIN DataScienceUser

EXEC sp_addrolemember 'DataScienceGroup', 'DataScienceUser'
```

### Monitor Resource Usage
```sql
-- Check actual resource consumption
SELECT 
    group_name,
    session_count,
    cpu_time_ms,
    memory_used_kb,
    io_reads,
    io_writes
FROM sys.dm_resource_governor_resource_pools
JOIN sys.dm_resource_governor_workload_groups ON resource_pool_id = pool_id
ORDER BY cpu_time_ms DESC
```

## Query Store (Built-in Observability)

### Enable Query Store
```sql
-- Enable on database
ALTER DATABASE MyDB SET QUERY_STORE = ON

-- Configure (30GB, hourly cleanup)
ALTER DATABASE MyDB SET QUERY_STORE (
    OPERATION_MODE = READ_WRITE,
    CLEANUP_POLICY = (BASE_CLEANUP_MODE = AUTO, STALE_QUERY_THRESHOLD_DAYS = 30),
    MAX_STORAGE_SIZE_MB = 30000,
    QUERY_CAPTURE_MODE = AUTO
)
```

### Find Regressions
```sql
-- Queries that got slower recently
WITH query_perf AS (
    SELECT 
        q.query_id,
        q.query_text_id,
        rs.plan_id,
        rs.avg_duration,
        rs.execution_count,
        LAG(rs.avg_duration) OVER (PARTITION BY q.query_id ORDER BY rs.last_execution_time) AS prior_avg_duration
    FROM sys.query_store_query q
    INNER JOIN sys.query_store_runtime_stats rs ON q.query_id = rs.query_id
)
SELECT TOP 20
    query_text_id,
    query_id,
    plan_id,
    CONVERT(NUMERIC(10,2), (avg_duration - prior_avg_duration) / NULLIF(prior_avg_duration, 0) * 100) AS pct_regression,
    CONVERT(NUMERIC(10,2), avg_duration / 1000) AS avg_duration_ms
FROM query_perf
WHERE prior_avg_duration IS NOT NULL
    AND (avg_duration - prior_avg_duration) > prior_avg_duration * 0.2  -- 20% slower
ORDER BY pct_regression DESC
```

### Force Good Plan
```sql
-- When one plan is better than another, force it
SELECT TOP 1
    plan_id,
    avg_duration
FROM sys.query_store_runtime_stats
WHERE query_id = 123
ORDER BY avg_duration ASC

-- Force this plan
EXEC sys.sp_query_store_force_plan
    @query_id = 123,
    @plan_id = 999  -- Best plan ID

-- Verify it's forcing
SELECT * FROM sys.query_store_query_hints
WHERE query_id = 123
```

## Monitoring Dashboard Queries

### Overall Health Check
```sql
-- 5-minute health dashboard
SELECT 
    'Database' AS Metric,
    CAST(SUM(size) * 8 / 1024 / 1024 AS INT) AS ValueMB,
    'Size' AS Unit
FROM sys.database_files
UNION ALL
SELECT 'Active Transactions', COUNT(*), 'Count' FROM sys.dm_tran_active_transactions
UNION ALL
SELECT 'Blocking Sessions', COUNT(*), 'Count' FROM sys.dm_exec_requests WHERE blocking_session_id > 0
UNION ALL
SELECT 'CPU Usage (%)', 
    CAST(100.0 * SUM(cpu_time) / (SELECT SUM(cpu_time) FROM sys.dm_exec_requests) AS INT),
    '%'
FROM sys.dm_exec_requests
UNION ALL
SELECT 'Memory Used (MB)',
    CAST((SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = 'Total Pages') * 8 / 1024, INT),
    'MB'
```

## Performance Troubleshooting Flowchart

```
1. Database slow?
   ↓
2. CPU or I/O bottleneck?
   → CPU: Check wait stats for CXPACKET, reduce parallelism
   → I/O: Check PAGEIOLATCH waits, add RAM or fast storage
   ↓
3. Specific query slow?
   → Check execution plan for scans/expensive operations
   → Add indexes, rewrite query
   ↓
4. Blocking/Deadlocking?
   → Check deadlock graph (deadlock_analyzer.sql)
   → Reduce transaction duration, use snapshot isolation
   ↓
5. Memory spills?
   → Check tempdb usage and memory grants
   → Add RAM, optimize large queries
   ↓
6. Still slow?
   → Run Extended Events session for detailed capture
   → Analyze query plans from production workload
   → Consider schema changes or partitioning
```
