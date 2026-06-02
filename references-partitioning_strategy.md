# Partitioning Strategy for Large Tables

## When to Partition

**Partition when:**
- Table exceeds 2-5 GB
- Need to archive/remove old data efficiently
- Query performance benefits from partition elimination
- Maintenance windows block queries

**Don't partition when:**
- Table < 1 GB
- No clear partitioning key
- Queries always scan entire table

---

## Date-Based Partitioning (Preferred)

**Best for:** Orders, Transactions, Logs, Events
```sql
-- 1. Create Partition Function (Monthly)
CREATE PARTITION FUNCTION pf_OrdersByMonth (DATETIME2)
AS RANGE RIGHT FOR VALUES (
    '2025-02-01', '2025-03-01', '2025-04-01', '2025-05-01', '2025-06-01',
    '2026-01-01', '2026-02-01', '2026-03-01', '2026-04-01', '2026-05-01', '2026-06-01'
)

-- 2. Create Partition Scheme
CREATE PARTITION SCHEME ps_OrdersByMonth
AS PARTITION pf_OrdersByMonth 
TO ([PRIMARY], [PRIMARY], [PRIMARY], [PRIMARY], [PRIMARY], [PRIMARY], [PRIMARY], [PRIMARY], [PRIMARY], [PRIMARY], [PRIMARY], [PRIMARY])

-- 3. Create Partitioned Table
CREATE TABLE Orders (
    OrderID INT,
    CustomerID INT,
    OrderDate DATETIME2,
    Amount DECIMAL(10,2)
) ON ps_OrdersByMonth (OrderDate)

-- 4. Create Clustered Index on Partition Key
CREATE CLUSTERED INDEX CIX_Orders_OrderDate 
ON Orders(OrderDate) 
ON ps_OrdersByMonth (OrderDate)
```

---

## Partition Elimination (Query Benefits)

```sql
-- ✅ GOOD: Partition eliminated by WHERE clause
SELECT * FROM Orders WHERE OrderDate >= '2026-05-01' AND OrderDate < '2026-06-01'
-- Execution plan shows "Partition (1:1)" = 1 partition scanned

-- ❌ BAD: Function prevents partition elimination
SELECT * FROM Orders WHERE YEAR(OrderDate) = 2026
-- Execution plan shows "Partition (1:12)" = all 12 partitions scanned!
```

---

## Sliding Window Maintenance

**Strategy:** Keep current month + rolling 12 months, archive older data

```sql
-- Monthly procedure to add new partition and remove old one
CREATE PROCEDURE sp_MaintainOrdersPartition
AS
BEGIN
    DECLARE @NewBoundary DATETIME2 = EOMONTH(GETDATE(), 1)
    DECLARE @OldBoundary DATETIME2 = EOMONTH(GETDATE(), -12)
    
    -- 1. Add new partition boundary
    ALTER PARTITION SCHEME ps_OrdersByMonth 
    NEXT USED [PRIMARY]
    
    ALTER PARTITION FUNCTION pf_OrdersByMonth() 
    SPLIT RANGE (@NewBoundary)
    
    -- 2. Archive old data (switch out to archive table)
    -- Create staging table with same structure
    CREATE TABLE Orders_Archive_202505 (
        OrderID INT, CustomerID INT, OrderDate DATETIME2, Amount DECIMAL(10,2)
    ) ON [PRIMARY]
    
    -- Switch partition out to archive table
    ALTER TABLE Orders SWITCH PARTITION 1 TO Orders_Archive_202505
    
    -- 3. Merge old boundary
    ALTER PARTITION FUNCTION pf_OrdersByMonth() 
    MERGE RANGE (@OldBoundary)
    
    PRINT 'Partition maintenance completed'
END

-- Schedule this monthly
EXEC sp_MaintainOrdersPartition
```

---

## Range Types

### RANGE RIGHT (Most Common)
- Boundary value goes to RIGHT (upper) partition
```sql
CREATE PARTITION FUNCTION pf_Test (INT)
AS RANGE RIGHT FOR VALUES (100, 200, 300)
-- Partition 1: < 100
-- Partition 2: >= 100 AND < 200
-- Partition 3: >= 200 AND < 300
-- Partition 4: >= 300
```

### RANGE LEFT
- Boundary value goes to LEFT (lower) partition
```sql
CREATE PARTITION FUNCTION pf_Test (INT)
AS RANGE LEFT FOR VALUES (100, 200, 300)
-- Partition 1: <= 100
-- Partition 2: > 100 AND <= 200
-- Partition 3: > 200 AND <= 300
-- Partition 4: > 300
```

---

## Monitoring Partitions

```sql
-- Check partition distribution
SELECT 
    ps.name AS SchemaName,
    t.name AS TableName,
    i.name AS IndexName,
    p.partition_number,
    p.rows
FROM sys.partitions p
INNER JOIN sys.tables t ON p.object_id = t.object_id
INNER JOIN sys.partition_schemes ps ON t.data_space_id = ps.data_space_id
INNER JOIN sys.indexes i ON p.object_id = i.object_id AND p.index_id = i.index_id
WHERE t.name = 'Orders'
ORDER BY p.partition_number

-- Check boundary values
SELECT 
    pf.name AS PartitionFunction,
    prv.boundary_id,
    prv.value
FROM sys.partition_range_values prv
INNER JOIN sys.partition_functions pf ON prv.function_id = pf.function_id
WHERE pf.name = 'pf_OrdersByMonth'
ORDER BY prv.boundary_id
```

---

## Best Practices

- [ ] Use date-based partitioning (most intuitive)
- [ ] Partition key should be NOT NULL
- [ ] Clustered index should include partition key
- [ ] Include partition key in WHERE clauses for partition elimination
- [ ] Avoid functions on partition key (prevents elimination)
- [ ] Plan for sliding window maintenance
- [ ] Test partition switching before production
- [ ] Monitor partition sizes
- [ ] Archive old partitions to cheaper storage
- [ ] Test queries with OPTION (RECOMPILE) to ensure correct partition elimination
