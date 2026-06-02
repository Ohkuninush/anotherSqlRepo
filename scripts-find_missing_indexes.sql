-- ========================================
-- FIND MISSING INDEXES
-- Purpose: Identify indexes that would improve query performance
-- ========================================

-- 1. Missing Indexes (Top 30 by impact)
SELECT TOP 30
    d.equality_columns,
    d.inequality_columns,
    d.included_columns,
    s.user_seeks,
    s.user_scans,
    s.user_lookups,
    s.avg_total_user_cost,
    s.avg_user_impact,
    (s.user_seeks + s.user_scans + s.user_lookups) * s.avg_total_user_cost * (s.avg_user_impact * 0.01) AS improvement_score,
    d.statement AS table_name
FROM sys.dm_db_missing_index_details AS d
INNER JOIN sys.dm_db_missing_index_groups AS ig ON d.index_handle = ig.index_handle
INNER JOIN sys.dm_db_missing_index_groups_stats AS s ON ig.index_group_id = s.index_group_id
WHERE database_id = DB_ID()
ORDER BY improvement_score DESC;

-- 2. Generate CREATE INDEX statements for missing indexes
SELECT TOP 20
    'CREATE NONCLUSTERED INDEX idx_' +
    REPLACE(REPLACE(REPLACE(d.equality_columns, ', ', '_'), ', ', '_'), ' ', '_') +
    ' ON ' + d.statement +
    ' (' + d.equality_columns +
    CASE WHEN d.inequality_columns IS NOT NULL THEN ', ' + d.inequality_columns ELSE '' END + ')' +
    CASE WHEN d.included_columns IS NOT NULL THEN ' INCLUDE (' + d.included_columns + ')' ELSE '' END + ';' AS create_index_statement,
    (s.user_seeks + s.user_scans + s.user_lookups) * s.avg_total_user_cost * (s.avg_user_impact * 0.01) AS improvement_score
FROM sys.dm_db_missing_index_details AS d
INNER JOIN sys.dm_db_missing_index_groups AS ig ON d.index_handle = ig.index_handle
INNER JOIN sys.dm_db_missing_index_groups_stats AS s ON ig.index_group_id = s.index_group_id
WHERE database_id = DB_ID()
    AND s.avg_user_impact > 10  -- Only significant improvements
ORDER BY improvement_score DESC;

-- 3. Unused Indexes (Candidates for removal)
SELECT TOP 20
    OBJECT_NAME(i.object_id) AS table_name,
    i.name AS index_name,
    s.user_seeks,
    s.user_scans,
    s.user_lookups,
    s.user_updates,
    'DROP INDEX ' + i.name + ' ON ' + OBJECT_NAME(i.object_id) + ';' AS drop_statement
FROM sys.indexes AS i
LEFT JOIN sys.dm_db_index_stats AS s ON i.object_id = s.object_id AND i.index_id = s.index_id
WHERE OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1
    AND i.index_id > 0  -- Exclude clustered
    AND (s.user_seeks = 0 AND s.user_scans = 0 AND s.user_lookups = 0)  -- Never used
    AND i.name NOT LIKE 'PK_%'  -- Exclude primary keys
    AND i.is_disabled = 0  -- Only enabled indexes
ORDER BY s.user_updates DESC;

-- 4. Duplicate Indexes (Redundant indexes)
WITH IndexColumns AS (
    SELECT
        i.object_id,
        i.index_id,
        i.name,
        OBJECT_NAME(i.object_id) AS table_name,
        STRING_AGG(c.name, ',') AS columns,
        i.is_unique
    FROM sys.indexes AS i
    INNER JOIN sys.index_columns AS ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
    INNER JOIN sys.columns AS c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
    WHERE OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1
    GROUP BY i.object_id, i.index_id, i.name, OBJECT_NAME(i.object_id), i.is_unique
)
SELECT
    a.table_name,
    a.name AS index_name_1,
    b.name AS index_name_2,
    a.columns
FROM IndexColumns AS a
INNER JOIN IndexColumns AS b
    ON a.table_name = b.table_name
    AND a.columns = b.columns
    AND a.index_id < b.index_id
WHERE a.is_unique = b.is_unique;

-- 5. Index Size Analysis (Large indexes)
SELECT TOP 20
    OBJECT_NAME(p.object_id) AS table_name,
    i.name AS index_name,
    SUM(a.total_pages) * 8 / 1024 AS size_mb,
    s.user_seeks + s.user_scans + s.user_lookups AS reads,
    s.user_updates AS writes,
    CASE
        WHEN s.user_updates > (s.user_seeks + s.user_scans + s.user_lookups)
            THEN 'HIGH WRITE COST'
        ELSE 'OK'
    END AS status
FROM sys.partitions AS p
INNER JOIN sys.allocation_units AS a ON p.partition_id = a.container_id
INNER JOIN sys.indexes AS i ON p.object_id = i.object_id AND p.index_id = i.index_id
LEFT JOIN sys.dm_db_index_stats AS s ON p.object_id = s.object_id AND p.index_id = s.index_id
WHERE database_id = DB_ID() AND i.index_id > 0
GROUP BY p.object_id, i.name, s.user_seeks, s.user_scans, s.user_lookups, s.user_updates
ORDER BY SUM(a.total_pages) DESC;

-- 6. Composite Indexes (Check for redundancy)
SELECT
    OBJECT_NAME(i.object_id) AS table_name,
    i.name AS index_name,
    STRING_AGG(c.name, ', ') WITHIN GROUP (ORDER BY ic.key_ordinal) AS column_list,
    COUNT(*) AS column_count
FROM sys.indexes AS i
INNER JOIN sys.index_columns AS ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
INNER JOIN sys.columns AS c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
WHERE OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1 AND i.index_id > 0
GROUP BY i.object_id, i.name
HAVING COUNT(*) > 3  -- Composite indexes with many columns
ORDER BY COUNT(*) DESC;

-- 7. Index Recommendations Summary
SELECT TOP 15
    d.statement AS table_name,
    'MISSING: ' + d.equality_columns +
    CASE WHEN d.included_columns IS NOT NULL THEN ' INCLUDE: ' + d.included_columns ELSE '' END AS recommendation,
    (s.user_seeks + s.user_scans + s.user_lookups) * s.avg_total_user_cost * (s.avg_user_impact * 0.01) AS priority_score
FROM sys.dm_db_missing_index_details AS d
INNER JOIN sys.dm_db_missing_index_groups AS ig ON d.index_handle = ig.index_handle
INNER JOIN sys.dm_db_missing_index_groups_stats AS s ON ig.index_group_id = s.index_group_id
WHERE database_id = DB_ID()
UNION ALL
SELECT
    OBJECT_NAME(i.object_id),
    'UNUSED: ' + i.name,
    0
FROM sys.indexes AS i
LEFT JOIN sys.dm_db_index_stats AS s ON i.object_id = s.object_id AND i.index_id = s.index_id
WHERE OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1
    AND i.index_id > 0
    AND (s.user_seeks = 0 AND s.user_scans = 0 AND s.user_lookups = 0)
ORDER BY priority_score DESC;
