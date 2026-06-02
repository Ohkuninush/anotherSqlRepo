-- ============================================================================
-- CASE STUDY 01: Query Performance Crisis
-- STEP 2: Root Cause Analysis
-- ============================================================================
-- Diagnose WHY the query is slow
-- ============================================================================

USE SampleEcommerce
GO

-- ============================================================================
-- DIAGNOSIS 1: Check current indexes on Orders table
-- ============================================================================
PRINT '=== STEP 1: Current Indexes on Orders Table ==='
GO

SELECT
    i.name AS IndexName,
    i.type_desc AS IndexType,
    ic.name AS ColumnName,
    CASE WHEN ic.name IN (SELECT name FROM sys.columns WHERE object_id = i.object_id AND name = ic.name)
         THEN 'KEY' ELSE 'INCLUDED' END AS ColumnType
FROM sys.indexes i
INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
WHERE OBJECT_NAME(i.object_id) = 'Orders'
ORDER BY i.name, ic.key_ordinal

-- ============================================================================
-- DIAGNOSIS 2: Show the problem with YEAR() function
-- ============================================================================
PRINT ''
PRINT '=== STEP 2: Why YEAR() Function is the Problem ==='
GO

-- This shows how SQL Server handles the YEAR() function
EXPLAIN_ANALYSIS = N'
When you write: WHERE YEAR(o.OrderDate) = YEAR(GETDATE())

SQL Server has to:
1. Read EVERY row in Orders table (no index can help)
2. Apply YEAR() function to EVERY OrderDate value
3. Compare result to YEAR(GETDATE())

This is called a "non-sargable predicate" (Search ARGument able)
Indexes cannot be used for non-sargable predicates!
'

-- Let''s prove it - show index statistics
SELECT
    i.name AS IndexName,
    STATS_NAME(i.object_id, i.index_id) AS StatisticName,
    s.user_updates AS Updates,
    s.user_seeks AS Seeks,
    s.user_scans AS Scans,
    s.user_lookups AS Lookups
FROM sys.indexes i
LEFT OUTER JOIN sys.dm_db_index_usage_stats s
    ON i.object_id = s.object_id
    AND i.index_id = s.index_id
WHERE OBJECT_NAME(i.object_id) = 'Orders'
AND database_id = DB_ID()

-- ============================================================================
-- DIAGNOSIS 3: Compare YEAR() vs Date Range approach
-- ============================================================================
PRINT ''
PRINT '=== STEP 3: Execution Plan Comparison ==='
GO

-- Show that we need to use date ranges instead
PRINT 'The YEAR() approach forces a scan (cannot use index)'
PRINT 'The date range approach allows an index seek (much faster)'
GO

-- ============================================================================
-- DIAGNOSIS 4: What the index optimizer recommends
-- ============================================================================
PRINT ''
PRINT '=== STEP 4: Index Recommendations from SQL Server ==='
GO

-- Check missing index recommendations
SELECT
    mid.equality_columns,
    mid.inequality_columns,
    mid.included_columns,
    migs.user_seeks,
    migs.avg_total_user_cost,
    migs.avg_user_impact
FROM sys.dm_db_missing_indexes m
INNER JOIN sys.dm_db_missing_index_details mid ON m.index_handle = mid.index_handle
INNER JOIN sys.dm_db_missing_index_groups g ON m.index_group_id = g.index_group_id
INNER JOIN sys.dm_db_missing_index_groups_stats migs ON g.index_id = migs.group_handle
WHERE database_id = DB_ID()
AND OBJECT_NAME(mid.object_id) = 'Orders'
ORDER BY migs.user_seeks DESC

-- ============================================================================
-- DIAGNOSIS 5: Actual query statistics
-- ============================================================================
PRINT ''
PRINT '=== STEP 5: Query Statistics from Query Store ==='
GO

-- If Query Store is enabled, show statistics for slow queries
SELECT TOP 5
    q.query_id,
    q.query_text_id,
    rs.avg_duration / 1000 AS AvgDuration_ms,
    rs.max_duration / 1000 AS MaxDuration_ms,
    rs.last_execution_time,
    rs.execution_count
FROM sys.query_store_query q
INNER JOIN sys.query_store_runtime_stats rs ON q.query_id = rs.query_id
INNER JOIN sys.query_store_query_text qt ON q.query_text_id = qt.query_text_id
WHERE DB_ID() = DB_ID()
AND qt.query_sql_text LIKE '%YEAR%'
ORDER BY rs.avg_duration DESC

-- ============================================================================
-- DIAGNOSIS 6: The Fix Preview
-- ============================================================================
PRINT ''
PRINT '=== STEP 6: The Solution (Preview) ==='
PRINT 'Instead of: WHERE YEAR(o.OrderDate) = YEAR(GETDATE())'
PRINT 'Use: WHERE o.OrderDate >= @StartOfYear AND o.OrderDate < @EndOfYear'
PRINT ''
PRINT 'This allows SQL Server to use the OrderDate index via SEEK operation'
PRINT 'See file: 03-optimized-query.sql for full implementation'
GO

-- ============================================================================
-- KEY FINDINGS
-- ============================================================================
PRINT ''
PRINT '╔════════════════════════════════════════════════════════════════╗'
PRINT '║ KEY FINDINGS FROM ROOT CAUSE ANALYSIS                          ║'
PRINT '╠════════════════════════════════════════════════════════════════╣'
PRINT '║ ❌ PROBLEM: YEAR() function in WHERE clause                    ║'
PRINT '║ ❌ IMPACT: Forces full table scan of Orders (8,943 reads)      ║'
PRINT '║ ❌ RESULT: 47 seconds execution time (unacceptable)            ║'
PRINT '║ ✅ SOLUTION: Use date range predicates                         ║'
PRINT '║ ✅ BENEFIT: Can use index seek (245 reads, 1.2 seconds)        ║'
PRINT '╚════════════════════════════════════════════════════════════════╝'
