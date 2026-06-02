# SQL Server 2019+ Modern Features

## JSON Support

### Parsing JSON with OPENJSON
```sql
DECLARE @json NVARCHAR(MAX) = '{"OrderID":123,"Lines":[{"ProductID":1,"Qty":5},{"ProductID":2,"Qty":3}]}'

-- Parse top-level properties
SELECT 
    OrderID = JSON_VALUE(@json, '$.OrderID'),
    CustomerID = JSON_VALUE(@json, '$.CustomerID')

-- Parse array elements
SELECT 
    ProductID = JSON_VALUE(value, '$.ProductID'),
    Qty = JSON_VALUE(value, '$.Qty')
FROM OPENJSON(@json, '$.Lines') WITH (
    ProductID INT,
    Qty INT
)
```

### Generating JSON with FOR JSON
```sql
-- PATH mode (nested)
SELECT 
    OrderID,
    (SELECT ProductID, Qty FROM OrderDetails WHERE OrderID = o.OrderID FOR JSON PATH) AS Lines
FROM Orders o
FOR JSON PATH

-- Result: {"OrderID":123,"Lines":[{"ProductID":1,"Qty":5}]}

-- AUTO mode (inferred structure)
SELECT CustomerID, CustomerName, OrderID, Amount
FROM Orders
FOR JSON AUTO

-- ROOT option
SELECT * FROM Orders FOR JSON PATH, ROOT('Orders')
```

### JSON Validation
```sql
DECLARE @json NVARCHAR(MAX) = '{"OrderID":123}'

-- Validate JSON before processing
IF ISJSON(@json) = 1
    SELECT JSON_VALUE(@json, '$.OrderID') AS OrderID
ELSE
    THROW 50001, 'Invalid JSON format', 1
```

---

## Temporal Tables (System-Versioned)

**Track all changes automatically with SYSTEM_TIME**

```sql
-- 1. Create with temporal columns
CREATE TABLE Orders (
    OrderID INT PRIMARY KEY,
    CustomerID INT,
    Amount DECIMAL(10,2),
    OrderDate DATETIME2,
    SysStartTime DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN,
    SysEndTime DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN,
    PERIOD FOR SYSTEM_TIME (SysStartTime, SysEndTime)
)
WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.Orders_History))

-- 2. Query current version
SELECT * FROM Orders WHERE OrderID = 123

-- 3. Query historical versions
SELECT * FROM Orders FOR SYSTEM_TIME AS OF '2026-05-01' WHERE OrderID = 123

-- 4. View all changes for an order
SELECT 
    OrderID, Amount,
    SysStartTime, SysEndTime,
    CASE WHEN SysEndTime = '9999-12-31' THEN 'Current' ELSE 'Historical' END AS Version
FROM Orders FOR SYSTEM_TIME ALL
WHERE OrderID = 123
ORDER BY SysStartTime DESC

-- 5. Get changes between dates
SELECT * FROM Orders 
FOR SYSTEM_TIME BETWEEN '2026-01-01' AND '2026-06-02'
WHERE OrderID = 123
```

---

## Graph Tables

**Model relationships as graphs instead of foreign keys**

```sql
-- Create node tables
CREATE TABLE Customers AS NODE
(
    CustomerID INT PRIMARY KEY,
    CustomerName NVARCHAR(100)
)

CREATE TABLE Products AS NODE
(
    ProductID INT PRIMARY KEY,
    ProductName NVARCHAR(100)
)

-- Create edge table for "Purchased" relationship
CREATE TABLE Purchased AS EDGE
(
    PurchaseDate DATETIME2
)

-- Insert data
INSERT INTO Customers VALUES (1, 'Alice')
INSERT INTO Products VALUES (1, 'Laptop')
INSERT INTO Purchased ($from_id, $to_id, PurchaseDate)
SELECT CustomerID, ProductID, GETDATE()
FROM Customers, Products

-- Query graph (find products purchased by customer)
SELECT p.ProductName, e.PurchaseDate
FROM Customers c, Purchased e, Products p
WHERE c.CustomerID = 1 
  AND MATCH(c-(e)->p)
```

---

## STRING_AGG (Concatenation)

**Aggregate strings without XMLAGG hacks**

```sql
-- Old way (ugly)
SELECT CustomerID,
    STUFF((SELECT ', ' + ProductName FROM OrderDetails od 
           WHERE od.OrderID = o.OrderID FOR XML PATH('')), 1, 2, '')
FROM Orders o

-- New way (clean)
SELECT 
    OrderID,
    STRING_AGG(ProductName, ', ') AS ProductList
FROM OrderDetails
GROUP BY OrderID
```

---

## Intelligent Query Processing (IQP)

**Automatic optimization without hints**

### Batch Mode on Rowstore
```sql
-- Queries automatically use batch-mode processing (vectorized)
-- Better performance on aggregations/joins without columnstore indexes
ALTER DATABASE MyDB SET COMPATIBILITY_LEVEL = 150  -- SQL Server 2019

-- Monitor batch mode usage
SELECT 
    qs.query_hash,
    qs.execution_count,
    deqs.last_execution_mode
FROM sys.dm_exec_query_stats qs
INNER JOIN sys.dm_exec_requests er ON qs.query_handle = er.sql_handle
CROSS APPLY sys.dm_exec_query_plan_stats(qs.plan_handle) deqs
WHERE deqs.last_execution_mode = 'Batch'
```

---

## Approximate Query Processing

**Fast approximate results for large datasets**

```sql
-- Get approximate distinct count (fast)
SELECT APPROX_COUNT_DISTINCT(CustomerID) AS ApproxCustomers
FROM Orders

-- vs exact count (slow)
SELECT COUNT(DISTINCT CustomerID) AS ExactCustomers
FROM Orders

-- Useful for dashboards where exact count not critical
```

---

## Enhanced Datetime Support

### DATETIME2 (Default for New Code)
```sql
-- DATETIME2 has higher precision (100 nanoseconds vs 3.33 milliseconds)
DECLARE @Now DATETIME2 = GETDATE()  -- Use for new tables
DECLARE @OldStyle DATETIME = GETDATE()  -- Legacy, less precise

-- DATEFROMPARTS, DATETIMEFROMPARTS
SELECT DATEFROMPARTS(2026, 6, 2)  -- Cleaner than '2026-06-02'
SELECT DATETIMEFROMPARTS(2026, 6, 2, 14, 30, 45, 123)
```

---

## DROP IF EXISTS

**Cleaner DDL**

```sql
-- Modern (SQL Server 2016+)
DROP TABLE IF EXISTS Orders
DROP PROCEDURE IF EXISTS sp_ProcessOrders
DROP INDEX IF EXISTS IX_Orders_CustomerID ON Orders

-- Legacy
IF OBJECT_ID('dbo.Orders') IS NOT NULL DROP TABLE dbo.Orders
IF OBJECT_ID('dbo.sp_ProcessOrders', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_ProcessOrders
```

---

## UTF-8 Collation

**Native UTF-8 support without doubling storage**

```sql
-- SQL Server 2019+ supports UTF8 collation
CREATE DATABASE MyDB COLLATE Latin1_General_100_CI_AS_SC_UTF8

-- Compare: NVARCHAR(100) stores UTF-16 (doubles space)
-- vs VARCHAR(100) with UTF8 collation (native UTF-8)
```

---

## Resumable Index Operations

**Resume long-running index rebuilds**

```sql
-- Start rebuild (can pause if needed)
ALTER INDEX IX_Orders_OrderDate ON Orders
REBUILD WITH (RESUMABLE = ON, MAX_DURATION = 10 MINUTES)

-- Pause if needed
ALTER INDEX IX_Orders_OrderDate ON Orders PAUSE

-- Resume later
ALTER INDEX IX_Orders_OrderDate ON Orders RESUME

-- Check status
SELECT object_name(object_id), name, state_desc
FROM sys.index_resumable_operations
```

---

## Best Practices

- [ ] Use DATETIME2 for all new datetime columns
- [ ] Use JSON for semi-structured data
- [ ] Use Temporal Tables for audit trails
- [ ] Use STRING_AGG instead of XML PATH hacks
- [ ] Use OPENJSON for parsing external JSON
- [ ] Use Graph Tables for relationship modeling
- [ ] Enable IQP for automatic optimizations
- [ ] Use UTF8 collation for international data
- [ ] Use DROP IF EXISTS in deployment scripts
- [ ] Use APPROX_COUNT_DISTINCT for dashboard queries
