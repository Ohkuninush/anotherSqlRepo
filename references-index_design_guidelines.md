# SQL Server Index Design Guidelines

## Index Types & When to Use

### 1. Clustered Index
**Purpose:** Physical ordering of rows on disk  
**When to use:**
- Every table should have exactly ONE clustered index (usually the primary key)
- Choose column(s) that are frequently used in WHERE clauses
- Avoid wide columns (prefer narrow/numeric)
- Avoid columns that change frequently

**Example:**
```sql
CREATE CLUSTERED INDEX PK_Orders ON Orders(OrderID)
```

### 2. Non-Clustered Index
**Purpose:** Separate index structure that points to table data  
**When to use:**
- Support secondary search criteria
- Improve JOIN performance
- Support ORDER BY operations
- Create multiple (up to 999) per table

**Example:**
```sql
CREATE NONCLUSTERED INDEX idx_orders_customer ON Orders(CustomerID)
```

### 3. Covering Index (INCLUDE clause)
**Purpose:** Include all columns needed for query without accessing table  
**When to use:**
- Frequently executed queries that return few columns
- Avoid extra lookups to main table

**Example:**
```sql
CREATE NONCLUSTERED INDEX idx_orders_date_amount ON Orders(OrderDate)
INCLUDE (CustomerID, Amount)
-- Query can be satisfied entirely from index
SELECT CustomerID, Amount FROM Orders WHERE OrderDate > '2024-01-01'
```

### 4. Composite Index (Multiple columns)
**Purpose:** Index on multiple columns for range queries  
**When to use:**
- Support queries filtering on multiple columns
- First columns in WHERE =, later columns in WHERE > or <

**Guideline:**
```sql
-- If queries are: WHERE Category = X AND Price > Y
CREATE NONCLUSTERED INDEX idx_category_price ON Products(Category, Price)

-- This index works for:
SELECT * FROM Products WHERE Category = 'Widget' AND Price > 100  -- Good
SELECT * FROM Products WHERE Price > 100  -- Less efficient (skip first column)
SELECT * FROM Products WHERE Category = 'Widget'  -- Good (matches leading column)
```

### 5. Filtered Index
**Purpose:** Index only subset of rows (smaller, faster)  
**When to use:**
- Many NULL values that you don't search
- Status = 'Active' queries often

**Example:**
```sql
CREATE NONCLUSTERED INDEX idx_active_orders ON Orders(CustomerID)
WHERE Status = 'Active'
-- Smaller index, faster, but only used for Status='Active' filters
```

### 6. Unique Index
**Purpose:** Enforce uniqueness + optimize lookups  
**When to use:**
- Natural uniqueness (e.g., email addresses)
- Alternative keys

**Example:**
```sql
CREATE UNIQUE NONCLUSTERED INDEX idx_email ON Users(Email)
```

## Index Design Rules

### Column Selection Order
For composite indexes (A, B, C):
1. **Equality columns first** - Columns with =
2. **Inequality columns next** - Columns with >, <, >=, <=
3. **INCLUDE columns last** - Columns needed but not in WHERE

Example:
```sql
-- Query: WHERE Category = 'A' AND Price > 100 ORDER BY Amount
CREATE NONCLUSTERED INDEX idx_search ON Products
    (Category, Price)  -- WHERE and ORDER BY columns
    INCLUDE (Amount)   -- Additional columns needed
```

### Column Width Considerations
- Narrow columns = smaller index = faster seeks
- Avoid: NVARCHAR(MAX), VARCHAR(MAX), TEXT, IMAGE
- Prefer: INT, BIGINT, DATE, DECIMAL(10,2)
- For string: Use only what you need

### Width Estimation
```sql
-- Estimate index size
SELECT 
    OBJECT_NAME(p.object_id) AS table_name,
    SUM(a.total_pages) * 8 / 1024 AS index_size_mb
FROM sys.partitions p
INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
INNER JOIN sys.indexes i ON p.object_id = i.object_id AND p.index_id = i.index_id
WHERE i.name = 'your_index_name'
GROUP BY p.object_id
```

## Index Maintenance

### Fragmentation Levels
- **0-10%:** No action needed
- **10-30%:** Reorganize (REORGANIZE)
- **>30%:** Rebuild (REBUILD)

```sql
-- Check fragmentation
SELECT 
    OBJECT_NAME(ips.object_id) AS table_name,
    i.name AS index_name,
    ips.avg_fragmentation_in_percent
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
INNER JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
WHERE ips.avg_fragmentation_in_percent > 10

-- Reorganize (online)
ALTER INDEX idx_name ON table_name REORGANIZE

-- Rebuild (can be offline)
ALTER INDEX idx_name ON table_name REBUILD
```

## Anti-Patterns to Avoid

❌ **Don't:**
- Index every column
- Create indexes on low-cardinality columns (Gender, IsActive)
- Create duplicate indexes with same leading columns
- Create wide indexes (too many columns)
- Ignore write performance impact (each write updates indexes)
- Create indexes on small tables

✅ **Do:**
- Index high-cardinality columns
- Focus on most-run queries
- Monitor index usage (find unused indexes to drop)
- Balance read vs write performance
- Use covering indexes strategically
- Name indexes meaningfully: idx_[columns]

## Index Usage Monitoring

```sql
-- Find unused indexes
SELECT 
    OBJECT_NAME(i.object_id) AS table_name,
    i.name AS index_name,
    s.user_seeks + s.user_scans + s.user_lookups AS reads,
    s.user_updates AS writes
FROM sys.indexes i
LEFT JOIN sys.dm_db_index_stats s ON i.object_id = s.object_id AND i.index_id = s.index_id
WHERE OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1
    AND i.index_id > 0
    AND (s.user_seeks = 0 AND s.user_scans = 0 AND s.user_lookups = 0)  -- Never used
```
