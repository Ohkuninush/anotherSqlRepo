-- ========================================
-- GENERATE TABLE DOCUMENTATION
-- Purpose: Extract and document table structures, relationships, and constraints
-- ========================================

-- 1. Table Schema Summary (All user tables)
SELECT
    OBJECT_NAME(t.object_id) AS table_name,
    c.name AS column_name,
    tp.name AS data_type,
    c.max_length,
    c.is_nullable,
    CASE WHEN cc.definition IS NOT NULL THEN cc.definition ELSE '' END AS computed_definition,
    CASE WHEN dc.name IS NOT NULL THEN dc.definition ELSE '' END AS default_value,
    ROW_NUMBER() OVER (PARTITION BY t.object_id ORDER BY c.column_id) AS column_order
FROM sys.tables AS t
INNER JOIN sys.columns AS c ON t.object_id = c.object_id
INNER JOIN sys.types AS tp ON c.user_type_id = tp.user_type_id
LEFT JOIN sys.computed_columns AS cc ON c.object_id = cc.object_id AND c.column_id = cc.column_id
LEFT JOIN sys.default_constraints AS dc ON c.object_id = dc.parent_object_id AND c.column_id = dc.parent_column_id
WHERE is_ms_shipped = 0
ORDER BY t.name, c.column_id;

-- 2. Primary & Foreign Keys
SELECT
    OBJECT_NAME(kcu1.table_id) AS primary_table,
    c1.name AS primary_column,
    OBJECT_NAME(kcu2.table_id) AS referenced_table,
    c2.name AS referenced_column,
    fk.name AS constraint_name
FROM sys.foreign_keys AS fk
INNER JOIN sys.foreign_key_columns AS fkc ON fk.object_id = fkc.constraint_object_id
INNER JOIN sys.key_constraints AS kcu1 ON fk.parent_object_id = kcu1.parent_object_id
INNER JOIN sys.key_constraints AS kcu2 ON fk.referenced_object_id = kcu2.parent_object_id
INNER JOIN sys.columns AS c1 ON fkc.parent_object_id = c1.object_id AND fkc.parent_column_id = c1.column_id
INNER JOIN sys.columns AS c2 ON fkc.referenced_object_id = c2.object_id AND fkc.referenced_column_id = c2.column_id
WHERE OBJECTPROPERTY(fk.parent_object_id, 'IsUserTable') = 1
ORDER BY fk.name;

-- 3. Constraints (CHECK, UNIQUE, PRIMARY)
SELECT
    OBJECT_NAME(c.parent_object_id) AS table_name,
    c.name AS constraint_name,
    c.type_desc AS constraint_type,
    c.definition
FROM sys.check_constraints AS c
WHERE OBJECTPROPERTY(c.parent_object_id, 'IsUserTable') = 1
UNION ALL
SELECT
    OBJECT_NAME(i.object_id),
    i.name,
    'PRIMARY KEY',
    NULL
FROM sys.indexes AS i
WHERE OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1 AND i.is_primary_key = 1
UNION ALL
SELECT
    OBJECT_NAME(i.object_id),
    i.name,
    'UNIQUE',
    NULL
FROM sys.indexes AS i
WHERE OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1 AND i.is_unique = 1 AND i.is_primary_key = 0;

-- 4. Indexes on Table
SELECT
    OBJECT_NAME(i.object_id) AS table_name,
    i.name AS index_name,
    i.type_desc AS index_type,
    STRING_AGG(c.name, ', ') WITHIN GROUP (ORDER BY ic.key_ordinal) AS column_list,
    i.is_unique,
    i.is_primary_key,
    STATS_DATE(i.object_id, i.index_id) AS last_updated
FROM sys.indexes AS i
INNER JOIN sys.index_columns AS ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
INNER JOIN sys.columns AS c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
WHERE OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1
GROUP BY i.object_id, i.name, i.type_desc, i.is_unique, i.is_primary_key
ORDER BY OBJECT_NAME(i.object_id), i.index_id;

-- 5. Table Size & Row Count
SELECT
    OBJECT_NAME(p.object_id) AS table_name,
    SUM(a.total_pages) * 8 / 1024 AS size_mb,
    SUM(CASE WHEN a.type = 1 THEN a.used_pages ELSE 0 END) * 8 / 1024 AS data_size_mb,
    SUM(CASE WHEN a.type = 2 THEN a.used_pages ELSE 0 END) * 8 / 1024 AS index_size_mb,
    SUM(p.rows) AS row_count,
    CASE
        WHEN SUM(a.total_pages) * 8 / 1024 > 1000 THEN 'LARGE'
        WHEN SUM(a.total_pages) * 8 / 1024 > 100 THEN 'MEDIUM'
        ELSE 'SMALL'
    END AS size_category
FROM sys.partitions AS p
INNER JOIN sys.allocation_units AS a ON p.partition_id = a.container_id
WHERE database_id = DB_ID() AND p.object_id > 100
GROUP BY p.object_id
ORDER BY SUM(a.total_pages) DESC;

-- 6. Generate CREATE TABLE Statement
SELECT
    'CREATE TABLE [' + OBJECT_NAME(t.object_id) + '] (' + CHAR(13) +
    STRING_AGG(
        '  [' + c.name + '] ' + tp.name +
        CASE
            WHEN tp.name IN ('varchar', 'char', 'nvarchar', 'nchar')
                THEN '(' + CASE WHEN c.max_length = -1 THEN 'MAX' ELSE CAST(c.max_length AS VARCHAR(10)) END + ')'
            WHEN tp.name IN ('decimal', 'numeric')
                THEN '(' + CAST(c.precision AS VARCHAR(3)) + ',' + CAST(c.scale AS VARCHAR(3)) + ')'
            ELSE ''
        END +
        CASE WHEN c.is_identity = 1 THEN ' IDENTITY(1,1)' ELSE '' END +
        CASE WHEN c.is_nullable = 0 THEN ' NOT NULL' ELSE ' NULL' END +
        CASE WHEN dc.definition IS NOT NULL THEN ' DEFAULT ' + dc.definition ELSE '' END,
        ',' + CHAR(13)
    ) + CHAR(13) + ');' AS create_table_statement
FROM sys.tables AS t
INNER JOIN sys.columns AS c ON t.object_id = c.object_id
INNER JOIN sys.types AS tp ON c.user_type_id = tp.user_type_id
LEFT JOIN sys.default_constraints AS dc ON c.object_id = dc.parent_object_id AND c.column_id = dc.parent_column_id
WHERE is_ms_shipped = 0
GROUP BY t.object_id;

-- 7. Column Usage Statistics
SELECT TOP 20
    OBJECT_NAME(t.object_id) AS table_name,
    c.name AS column_name,
    tp.name AS data_type,
    CASE WHEN pk.column_id IS NOT NULL THEN 'PRIMARY KEY' ELSE '' END AS key_type,
    CASE WHEN fk.parent_object_id IS NOT NULL THEN 'FOREIGN KEY' ELSE '' END AS reference_type,
    CASE WHEN c.is_identity = 1 THEN 'IDENTITY' ELSE '' END AS special_type
FROM sys.tables AS t
INNER JOIN sys.columns AS c ON t.object_id = c.object_id
INNER JOIN sys.types AS tp ON c.user_type_id = tp.user_type_id
LEFT JOIN sys.key_constraints AS pk ON c.object_id = pk.parent_object_id AND c.column_id = pk.parent_column_id
LEFT JOIN sys.foreign_key_columns AS fk ON c.object_id = fk.parent_object_id AND c.column_id = fk.parent_column_id
WHERE is_ms_shipped = 0
ORDER BY OBJECT_NAME(t.object_id), c.column_id;

-- 8. Table Relationships (Dependency graph)
SELECT
    OBJECT_NAME(fk.parent_object_id) AS dependent_table,
    OBJECT_NAME(fk.referenced_object_id) AS referenced_table,
    fk.name AS constraint_name
FROM sys.foreign_keys AS fk
WHERE OBJECTPROPERTY(fk.parent_object_id, 'IsUserTable') = 1
ORDER BY OBJECT_NAME(fk.parent_object_id), OBJECT_NAME(fk.referenced_object_id);

-- 9. Temporal Tables (If using temporal versioning)
SELECT
    OBJECT_NAME(t.object_id) AS table_name,
    OBJECT_NAME(t.history_table_id) AS history_table,
    t.temporal_type_desc
FROM sys.tables AS t
WHERE t.temporal_type <> 0;

-- 10. Quick Reference: All Tables with Key Info
SELECT
    OBJECT_NAME(t.object_id) AS table_name,
    COUNT(DISTINCT c.column_id) AS column_count,
    SUM(CASE WHEN pk.column_id IS NOT NULL THEN 1 ELSE 0 END) AS primary_key_count,
    SUM(CASE WHEN fk.parent_object_id IS NOT NULL THEN 1 ELSE 0 END) AS foreign_key_count,
    SUM(p.rows) AS row_count
FROM sys.tables AS t
INNER JOIN sys.columns AS c ON t.object_id = c.object_id
LEFT JOIN sys.key_constraints AS pk ON c.object_id = pk.parent_object_id AND c.column_id = pk.parent_column_id
LEFT JOIN sys.foreign_key_columns AS fk ON c.object_id = fk.parent_object_id AND c.column_id = fk.parent_column_id
INNER JOIN sys.partitions AS p ON t.object_id = p.object_id AND p.index_id IN (0, 1)
WHERE t.is_ms_shipped = 0
GROUP BY t.object_id
ORDER BY SUM(p.rows) DESC;
