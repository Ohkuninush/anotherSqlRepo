---
name: etl-incremental-patterns
description: Incremental data loading strategies — CDC (Change Data Capture), timestamp-based detection, watermark approach, full vs incremental trade-offs
---

# ETL Incremental Load Patterns — Change Detection

## Overview

**Why incremental loading matters:**
- Full load every time = slow (hours, not minutes)
- Only changed data = fast (seconds)
- Reduces database load (CPU, I/O, network)
- Enables real-time data synchronization

**Cost of full reloads:**
- 1M rows full load = 5 minutes
- 1K new rows incremental = 5 seconds
- If load every hour = 300 mins/day wasted
- Over a year = 125 hours of unnecessary loading

**Three approaches:**
1. **CDC (Change Data Capture)** — SQL Server tracks changes automatically
2. **Timestamp-based** — Check LastModified column
3. **Watermark** — Track highest ID loaded

---

## Anti-Pattern: Full Load Every Time (❌ Don't Do This)

### The Problem
```sql
-- Every night, reload ENTIRE dataset
DELETE FROM DataWarehouse_Orders
INSERT INTO DataWarehouse_Orders
SELECT * FROM TransactionalDB.Orders

-- Problem:
-- • 10M rows = 30 minutes
-- • Only 100 rows changed
-- • 29.9 minutes wasted
-- • Locks table entire time
-- • Network overloaded
```

### Real-World Incident
```
Timeline (DataWarehouse):
  ETL schedule: Every hour full load
  Source tables: 50M rows
  Changed rows per hour: ~100
  
  Hour 1-10: Load works fine
  Hour 11: Network congestion
  Hour 12: Load takes 45 mins (longer than interval!)
  Hour 13: Two loads run simultaneously (DEADLOCK)
  Hour 14: Job fails, previous load still running
  
  Result:
    - DataWarehouse stale for 3 hours
    - Reports wrong data
    - Dashboard shows "Stale"
    - Business decisions delayed
    
Root cause: No incremental logic
```

---

## Pattern 1: Timestamp-Based Incremental Load

### Use Case
- Source table has LastModified column
- Changes are frequent but not HUGE volumes
- Simplest approach (no extra infrastructure)
- Works with any database

### ✅ Correct Implementation

#### Schema
```sql
-- Source system (transactional DB)
CREATE TABLE Orders (
    OrderID INT PRIMARY KEY,
    CustomerID INT NOT NULL,
    Amount DECIMAL(10, 2),
    OrderDate DATETIME2,
    LastModified DATETIME2 NOT NULL DEFAULT GETDATE(),  -- ← Key column
    INDEX IX_Orders_LastModified (LastModified)
)

-- Target system (data warehouse)
CREATE TABLE Orders_DW (
    OrderID INT PRIMARY KEY,
    CustomerID INT NOT NULL,
    Amount DECIMAL(10, 2),
    OrderDate DATETIME2,
    LoadDate DATETIME2  -- When it was loaded
)

-- Track checkpoint
CREATE TABLE ETL_Checkpoint (
    LoadName NVARCHAR(100) PRIMARY KEY,
    LastLoadTime DATETIME2,
    LastLoadID INT,
    LoadStatus NVARCHAR(20)
)
```

#### ETL Procedure
```sql
CREATE OR ALTER PROCEDURE sp_IncrementalLoadOrders
AS
BEGIN
    SET NOCOUNT ON
    SET XACT_ABORT ON
    
    BEGIN TRY
        -- Step 1: Get last checkpoint
        DECLARE @LastLoadTime DATETIME2 = GETDATE() - 365  -- Default: load all
        SELECT @LastLoadTime = LastLoadTime
        FROM ETL_Checkpoint
        WHERE LoadName = 'Orders'
        
        DECLARE @CurrentLoadTime DATETIME2 = GETDATE()
        
        -- Step 2: Identify changed rows
        DECLARE @ChangedCount INT
        SELECT @ChangedCount = COUNT(*)
        FROM Orders
        WHERE LastModified > @LastLoadTime
        
        BEGIN TRANSACTION
        
        -- Step 3: New rows (not in DW yet)
        INSERT INTO Orders_DW (OrderID, CustomerID, Amount, OrderDate, LoadDate)
        SELECT OrderID, CustomerID, Amount, OrderDate, @CurrentLoadTime
        FROM Orders o
        WHERE LastModified > @LastLoadTime
          AND NOT EXISTS (SELECT 1 FROM Orders_DW WHERE OrderID = o.OrderID)
        
        DECLARE @NewCount INT = @@ROWCOUNT
        
        -- Step 4: Updated rows (already in DW but changed in source)
        UPDATE dw
        SET dw.CustomerID = o.CustomerID,
            dw.Amount = o.Amount,
            dw.OrderDate = o.OrderDate,
            dw.LoadDate = @CurrentLoadTime
        FROM Orders_DW dw
        INNER JOIN Orders o ON dw.OrderID = o.OrderID
        WHERE o.LastModified > @LastLoadTime
          AND (dw.CustomerID != o.CustomerID 
               OR dw.Amount != o.Amount 
               OR dw.OrderDate != o.OrderDate)
        
        DECLARE @UpdateCount INT = @@ROWCOUNT
        
        -- Step 5: Update checkpoint
        UPDATE ETL_Checkpoint
        SET LastLoadTime = @CurrentLoadTime,
            LoadStatus = 'SUCCESS'
        WHERE LoadName = 'Orders'
        
        IF @@ROWCOUNT = 0
            INSERT INTO ETL_Checkpoint (LoadName, LastLoadTime, LoadStatus)
            VALUES ('Orders', @CurrentLoadTime, 'SUCCESS')
        
        COMMIT TRANSACTION
        
        -- Return summary
        SELECT 
            'Orders' AS TableName,
            @NewCount AS NewRows,
            @UpdateCount AS UpdatedRows,
            @NewCount + @UpdateCount AS TotalChanged,
            @CurrentLoadTime AS LoadTime
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION
        
        UPDATE ETL_Checkpoint
        SET LoadStatus = 'FAILED'
        WHERE LoadName = 'Orders'
        
        THROW
    END CATCH
END

-- Usage
EXEC sp_IncrementalLoadOrders
```

#### Advantages
```
✅ Simple (just compare LastModified)
✅ Fast (index on timestamp)
✅ Works across databases
✅ Can handle soft deletes (check DeletedDate)
```

#### Important: Clock Skew Problem
```sql
-- ⚠️ Issue: Server clocks not perfectly synchronized
-- Source server: 2026-06-02 14:00:05
-- DW server:     2026-06-02 14:00:02 (3 seconds behind!)

-- Solution: Add buffer
DECLARE @LastLoadTime DATETIME2 = GETDATE() - 365
SET @LastLoadTime = DATEADD(MINUTE, -5, @LastLoadTime)  -- ← 5 min buffer

-- This ensures we don't miss rows due to clock skew
```

---

## Pattern 2: Watermark-Based Loading (ID Tracking)

### Use Case
- No LastModified column in source
- Only track INSERT (not UPDATE)
- Know max primary key loaded
- Very fast (just check ID >= last_id)

### ✅ Correct Implementation

#### Schema
```sql
-- Source table (no timestamp needed)
CREATE TABLE Inventory (
    ProductID INT PRIMARY KEY IDENTITY(1, 1),  -- ← We track this
    ProductName NVARCHAR(100),
    QuantityOnHand INT
)

-- DW table
CREATE TABLE Inventory_DW (
    ProductID INT PRIMARY KEY,
    ProductName NVARCHAR(100),
    QuantityOnHand INT,
    LoadDate DATETIME2
)

-- Watermark checkpoint
CREATE TABLE ETL_Watermark (
    LoadName NVARCHAR(100) PRIMARY KEY,
    MaxIDLoaded INT DEFAULT 0,
    LoadDate DATETIME2
)
```

#### ETL Procedure
```sql
CREATE OR ALTER PROCEDURE sp_LoadNewProducts
AS
BEGIN
    SET NOCOUNT ON
    SET XACT_ABORT ON
    
    BEGIN TRY
        -- Step 1: Get last watermark (highest ID we've seen)
        DECLARE @MaxIDLoaded INT = 0
        SELECT @MaxIDLoaded = ISNULL(MaxIDLoaded, 0)
        FROM ETL_Watermark
        WHERE LoadName = 'Inventory'
        
        DECLARE @CurrentLoadTime DATETIME2 = GETDATE()
        
        BEGIN TRANSACTION
        
        -- Step 2: Load only new rows (ID > last watermark)
        INSERT INTO Inventory_DW (ProductID, ProductName, QuantityOnHand, LoadDate)
        SELECT ProductID, ProductName, QuantityOnHand, @CurrentLoadTime
        FROM Inventory
        WHERE ProductID > @MaxIDLoaded  -- ← Only new rows
        ORDER BY ProductID
        
        DECLARE @RowsLoaded INT = @@ROWCOUNT
        
        -- Step 3: Update watermark to highest ID loaded
        DECLARE @MaxIDInSource INT
        SELECT @MaxIDInSource = MAX(ProductID) FROM Inventory
        
        UPDATE ETL_Watermark
        SET MaxIDLoaded = @MaxIDInSource,
            LoadDate = @CurrentLoadTime
        WHERE LoadName = 'Inventory'
        
        IF @@ROWCOUNT = 0
            INSERT INTO ETL_Watermark (LoadName, MaxIDLoaded, LoadDate)
            VALUES ('Inventory', @MaxIDInSource, @CurrentLoadTime)
        
        COMMIT TRANSACTION
        
        SELECT 'Inventory' AS Table, @RowsLoaded AS RowsLoaded, @CurrentLoadTime AS LoadTime
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION
        THROW
    END CATCH
END
```

#### Advantages
```
✅ Extremely fast (just MAX(ID) check)
✅ No timestamp column needed
✅ Can't miss rows (ordered by ID)
✅ Works great for append-only data
```

#### Limitation
```
❌ Can't detect UPDATES (only sees new rows)
❌ Requires identity/sequential ID
❌ Won't catch deletions (unless soft-deleted)
```

---

## Pattern 3: CDC (Change Data Capture) — SQL Server 2016+

### Use Case
- Need to track INSERT, UPDATE, DELETE
- Source database is SQL Server 2016+
- Enterprise: audit trail required
- Can afford CDC overhead (~10% CPU)

### ✅ Correct Implementation

#### Enable CDC on Source Table
```sql
-- Enable CDC on database
EXEC sys.sp_cdc_enable_db

-- Enable CDC on specific table
EXEC sys.sp_cdc_enable_table
    @source_schema = N'dbo',
    @source_name = N'Orders',
    @role_name = NULL,
    @supports_net_changes = 1  -- Allow net changes (final state)
```

#### Query Changes
```sql
CREATE OR ALTER PROCEDURE sp_LoadChangedOrders
AS
BEGIN
    SET NOCOUNT ON
    SET XACT_ABORT ON
    
    BEGIN TRY
        -- Get last LSN (Log Sequence Number) we processed
        DECLARE @FromLSN BINARY(10), @ToLSN BINARY(10)
        
        SELECT @FromLSN = ISNULL(LastProcessedLSN, 0x00000000000000000000)
        FROM ETL_CDC_Checkpoint
        WHERE TableName = 'Orders'
        
        -- Get current max LSN
        SET @ToLSN = sys.fn_cdc_get_max_lsn()
        
        BEGIN TRANSACTION
        
        -- Get all changes since last load
        -- __$operation: 1=DELETE, 2=INSERT, 3=UPDATE (before), 4=UPDATE (after)
        INSERT INTO Orders_DW (OrderID, CustomerID, Amount, OrderDate, LoadDate, Operation)
        SELECT 
            ct.OrderID,
            ct.CustomerID,
            ct.Amount,
            ct.OrderDate,
            GETDATE(),
            CASE ct.__$operation
                WHEN 1 THEN 'DELETE'
                WHEN 2 THEN 'INSERT'
                WHEN 4 THEN 'UPDATE'
            END
        FROM cdc.fn_cdc_get_net_changes_dbo_Orders(@FromLSN, @ToLSN, 'all update old') ct
        WHERE ct.__$operation IN (2, 4)  -- INSERT and UPDATE (not DELETE)
        
        -- Update checkpoint
        UPDATE ETL_CDC_Checkpoint
        SET LastProcessedLSN = @ToLSN,
            LastProcessedTime = GETDATE()
        WHERE TableName = 'Orders'
        
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION
        THROW
    END CATCH
END
```

#### Advantages
```
✅ Captures all changes (INSERT, UPDATE, DELETE)
✅ Built-in to SQL Server (no extra tool)
✅ Reliable (SQL Agent job handles it)
✅ Can get exact operation (not just "changed")
```

#### Trade-offs
```
⚠️ ~10% CPU overhead on source database
⚠️ Requires enterprise database
⚠️ Must enable SQL Agent
⚠️ More complex to manage
```

---

## Pattern 4: Hybrid Approach (Timestamp + ID)

### Use Case
- Handle both inserts and updates efficiently
- Fast for new rows (ID watermark)
- Catches updates (timestamp check)
- Best performance/features balance

### ✅ Correct Implementation

```sql
CREATE OR ALTER PROCEDURE sp_HybridIncrementalLoad
    @TableName NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON
    SET XACT_ABORT ON
    
    BEGIN TRY
        DECLARE @MaxIDLoaded INT, @LastModTime DATETIME2
        DECLARE @CurrentTime DATETIME2 = GETDATE()
        
        -- Get checkpoints
        SELECT @MaxIDLoaded = MaxIDLoaded,
               @LastModTime = LastModTime
        FROM ETL_Checkpoint
        WHERE LoadName = @TableName
        
        SET @MaxIDLoaded = ISNULL(@MaxIDLoaded, 0)
        SET @LastModTime = ISNULL(@LastModTime, GETDATE() - 365)
        
        BEGIN TRANSACTION
        
        -- Strategy 1: New rows (ID-based, super fast)
        INSERT INTO Orders_DW (OrderID, CustomerID, Amount, OrderDate, LoadDate)
        SELECT OrderID, CustomerID, Amount, OrderDate, @CurrentTime
        FROM Orders
        WHERE OrderID > @MaxIDLoaded
        
        DECLARE @NewCount INT = @@ROWCOUNT
        
        -- Strategy 2: Updated rows (timestamp-based)
        -- Check only up to the highest ID we've seen before
        UPDATE dw
        SET dw.CustomerID = o.CustomerID,
            dw.Amount = o.Amount,
            dw.OrderDate = o.OrderDate,
            dw.LoadDate = @CurrentTime
        FROM Orders_DW dw
        INNER JOIN Orders o ON dw.OrderID = o.OrderID
        WHERE o.OrderID <= @MaxIDLoaded  -- Only rows we've seen before
          AND o.LastModified > @LastModTime  -- That have changed
        
        DECLARE @UpdateCount INT = @@ROWCOUNT
        
        -- Update checkpoints
        UPDATE ETL_Checkpoint
        SET MaxIDLoaded = (SELECT MAX(OrderID) FROM Orders),
            LastModTime = @CurrentTime
        WHERE LoadName = @TableName
        
        COMMIT TRANSACTION
        
        SELECT @NewCount AS NewRows, @UpdateCount AS UpdatedRows
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION
        THROW
    END CATCH
END
```

---

## Performance Comparison

| Approach | Speed | Completeness | Complexity | CDC Cost |
|----------|-------|--------------|-----------|----------|
| Full Load | Slow | 100% | Low | None |
| Timestamp | Fast | 100% | Low | None |
| Watermark (ID) | Very Fast | Inserts only | Low | None |
| CDC | Very Fast | 100% | High | ~10% CPU |
| Hybrid | Very Fast | 100% | Medium | None |

**Recommendation:**
- **Start with:** Timestamp-based (simplest)
- **Scale to:** Hybrid (best performance/features)
- **Enterprise:** CDC (if you can afford CPU)

---

## Best Practices

### 1. Always Have a Checkpoint
```sql
-- Never rely on system time
-- Always track what you've loaded
INSERT INTO ETL_Checkpoint (LoadName, LastLoadTime, LoadStatus)
VALUES ('Orders', GETDATE(), 'IN_PROGRESS')
```

### 2. Handle Clock Skew
```sql
-- Add buffer for server clock differences
DECLARE @LastLoadTime DATETIME2 = GETDATE() - 365
SET @LastLoadTime = DATEADD(MINUTE, -5, @LastLoadTime)
```

### 3. Idempotency
```sql
-- Make procedure safe to re-run
-- Use MERGE or conditional INSERT
MERGE INTO Orders_DW dw
USING Orders o
ON dw.OrderID = o.OrderID
WHEN MATCHED THEN UPDATE SET dw.Amount = o.Amount
WHEN NOT MATCHED THEN INSERT VALUES (...)
```

### 4. Error Recovery
```sql
-- Only update checkpoint on SUCCESS
BEGIN TRANSACTION
    -- Load data
    COMMIT TRANSACTION
-- Only then:
UPDATE ETL_Checkpoint SET LastLoadTime = @CurrentTime
```

---

## References
- `[[upsert_patterns]]` — MERGE for incremental loads
- `[[audit_trail_patterns]]` — Change tracking
- `references/etl_migration_patterns.md` — Advanced ETL
- `references/transaction_management.md` — Checkpoint safety

