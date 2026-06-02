# SQL Server ETL & Data Migration Patterns

## Incremental Load Strategies

### Strategy 1: Timestamp-Based (Most Common)
```sql
-- Source table has ModifiedDate column
-- Load only changed records since last run

CREATE TABLE StageOrders AS
SELECT *
FROM SourceSystem.Orders
WHERE ModifiedDate > (SELECT MAX(LastLoadTime) FROM ETLControlTable)

-- Merge into target
MERGE INTO TargetOrders AS target
USING StageOrders AS source
ON target.OrderID = source.OrderID
WHEN MATCHED THEN
    UPDATE SET *
WHEN NOT MATCHED THEN
    INSERT *

-- Update control table
UPDATE ETLControlTable SET LastLoadTime = GETDATE()
```

### Strategy 2: CDC (Change Data Capture)
```sql
-- Enable CDC on source table
EXEC sys.sp_cdc_enable_table
    @source_schema = N'dbo',
    @source_name = N'Orders',
    @role_name = NULL,
    @filegroup_name = N'PRIMARY',
    @supports_net_changes = 1

-- Query changes since last run
SELECT 
    OrderID,
    Amount,
    __$operation,  -- 1=Delete, 2=Insert, 4=Before Update, 5=After Update
    __$update_mask
FROM cdc.dbo_Orders_CT
WHERE __$start_lsn > @last_lsn

-- Operations: 1=Delete, 2=Insert, 4/5=Update
```

### Strategy 3: Watermark Pattern
```sql
-- Track last loaded ID/key
SELECT MAX(OrderID) AS LastLoadedID FROM TargetOrders

-- Load only newer records
INSERT INTO TargetOrders
SELECT * FROM SourceOrders
WHERE OrderID > (SELECT COALESCE(MAX(OrderID), 0) FROM TargetOrders)

-- Update watermark
UPDATE WatermarkTable SET LastOrderID = (SELECT MAX(OrderID) FROM TargetOrders)
```

## MERGE (Upsert) Pattern

### Complete Merge Example
```sql
MERGE INTO TargetTable AS target
USING SourceTable AS source
ON target.OrderID = source.OrderID AND target.OrderDate = source.OrderDate
-- Multiple key columns for matching
WHEN MATCHED AND target.Amount <> source.Amount THEN
    -- Update if values changed
    UPDATE SET 
        Amount = source.Amount,
        Status = source.Status,
        ModifiedDate = GETDATE()
WHEN MATCHED AND source.IsDeleted = 1 THEN
    -- Soft delete (mark as deleted instead of removing)
    UPDATE SET 
        IsDeleted = 1,
        DeletedDate = GETDATE()
WHEN NOT MATCHED THEN
    -- Insert new records
    INSERT (OrderID, OrderDate, Amount, Status, CreatedDate)
    VALUES (source.OrderID, source.OrderDate, source.Amount, source.Status, GETDATE())
WHEN NOT MATCHED BY SOURCE AND target.ModifiedDate < GETDATE() - 365 THEN
    -- Remove records not in source (optional: archive old)
    DELETE;

-- Capture merge statistics
IF @@ROWCOUNT > 0
    INSERT INTO ETLLog (TableName, RowsAffected, LoadTime)
    VALUES ('TargetTable', @@ROWCOUNT, GETDATE())
```

## Staging Table Pattern

### 3-Tier ETL Architecture
```
1. RAW STAGE (Load as-is)
    ↓
2. CLEAN STAGE (Validate, transform)
    ↓
3. PRODUCTION (Merge into target)
```

### Implementation
```sql
-- STEP 1: Load RAW data from source
TRUNCATE TABLE Stage_Orders_Raw
BULK INSERT Stage_Orders_Raw
FROM 'C:\Data\orders.csv'
WITH (
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n',
    FIRSTROW = 2  -- Skip header
)

-- STEP 2: Transform and validate
INSERT INTO Stage_Orders_Clean
SELECT 
    CAST(OrderID AS INT) AS OrderID,
    CAST(OrderDate AS DATETIME) AS OrderDate,
    CAST(Amount AS DECIMAL(10,2)) AS Amount,
    UPPER(Status) AS Status,
    CAST(NULL AS DATETIME) AS ModifiedDate
FROM Stage_Orders_Raw
WHERE 
    OrderID IS NOT NULL  -- Reject nulls
    AND ISNUMERIC(Amount) = 1  -- Validate numeric
    AND ISNUMERIC(OrderID) = 1  -- Validate numeric
    AND OrderDate IS NOT NULL

-- Check for duplicates before loading
SELECT OrderID, COUNT(*)
FROM Stage_Orders_Clean
GROUP BY OrderID
HAVING COUNT(*) > 1  -- Flag duplicates

-- STEP 3: Merge into production
MERGE INTO Orders AS target
USING Stage_Orders_Clean AS source
ON target.OrderID = source.OrderID
WHEN MATCHED THEN
    UPDATE SET Amount = source.Amount, Status = source.Status
WHEN NOT MATCHED THEN
    INSERT (OrderID, OrderDate, Amount, Status)
    VALUES (source.OrderID, source.OrderDate, source.Amount, source.Status)

-- Log results
INSERT INTO ETLAudit (StepName, RowsProcessed, Status, ExecutionTime)
VALUES ('Orders Merge', @@ROWCOUNT, 'Success', GETDATE())
```

## Data Cleansing Patterns

### Handle Duplicates
```sql
-- Find duplicates
SELECT OrderID, COUNT(*) AS DuplicateCount
FROM Orders
GROUP BY OrderID
HAVING COUNT(*) > 1

-- Remove duplicates (keep oldest)
DELETE FROM Orders
WHERE OrderID IN (
    SELECT OrderID
    FROM Orders
    WHERE ROW_NUMBER() OVER (PARTITION BY OrderID ORDER BY CreatedDate DESC) > 1
)
```

### Handle NULLs
```sql
-- Identify null columns
SELECT 
    column_name,
    SUM(CASE WHEN value IS NULL THEN 1 ELSE 0 END) AS null_count,
    COUNT(*) AS total_rows
FROM (
    SELECT OrderID, Amount, NULL AS CustomerID -- Demo null
    FROM Orders
)
UNPIVOT (value FOR column_name IN (OrderID, Amount, CustomerID)) AS unpvt
GROUP BY column_name

-- Handle nulls with defaults
UPDATE Orders
SET CustomerID = -1 WHERE CustomerID IS NULL  -- Unknown customer
SET Amount = 0 WHERE Amount IS NULL

-- Or reject rows with required nulls
DELETE FROM Stage_Orders
WHERE OrderID IS NULL OR OrderDate IS NULL
```

### Standardize Data
```sql
-- Standardize status values
UPDATE Orders
SET Status = CASE UPPER(Status)
    WHEN 'COMPLETE' THEN 'Completed'
    WHEN 'PEND' THEN 'Pending'
    WHEN 'SHIPPED' THEN 'Shipped'
    ELSE 'Unknown'
END

-- Remove extra spaces
UPDATE Customers
SET Name = LTRIM(RTRIM(Name))

-- Standardize dates
UPDATE Orders
SET OrderDate = CAST(CAST(OrderDate AS DATE) AS DATETIME)  -- Remove time portion
```

## Bulk Operations

### BULK INSERT
```sql
-- Fast bulk load from file
BULK INSERT Orders
FROM 'C:\Data\orders.csv'
WITH (
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n',
    FIRSTROW = 2,
    ERRORFILE = 'C:\Data\error_rows.txt',
    MAXERRORS = 100,
    BATCHSIZE = 10000
)

-- BCP command line (fastest for large files)
-- bcp MyDB.dbo.Orders in orders.csv -c -t, -S ServerName -U username -P password
```

### Fast Insert with Minimal Logging
```sql
-- Disable triggers and constraints temporarily
ALTER TABLE Orders DISABLE TRIGGER ALL
ALTER TABLE Orders NOCHECK CONSTRAINT ALL

-- Bulk insert
BULK INSERT Orders FROM 'orders.csv' WITH (TABLOCK)

-- Re-enable
ALTER TABLE Orders ENABLE TRIGGER ALL
ALTER TABLE Orders CHECK CONSTRAINT ALL

-- Update statistics
UPDATE STATISTICS Orders
```

## Error Handling & Recovery

### Transaction with Rollback
```sql
BEGIN TRANSACTION ETLLoad
BEGIN TRY
    INSERT INTO TargetOrders SELECT * FROM StageOrders
    
    -- Validation
    IF (SELECT COUNT(*) FROM StageOrders) <> (SELECT COUNT(*) FROM TargetOrders WHERE LoadDate = CAST(GETDATE() AS DATE))
    BEGIN
        THROW 50001, 'Row count mismatch - Load failed', 1
    END
    
    COMMIT TRANSACTION ETLLoad
    INSERT INTO ETLLog VALUES ('Success', GETDATE())
END TRY
BEGIN CATCH
    ROLLBACK TRANSACTION ETLLoad
    INSERT INTO ETLLog VALUES ('Failed: ' + ERROR_MESSAGE(), GETDATE())
    THROW
END CATCH
```

## Data Validation

### Pre-Load Validation
```sql
-- Check source data quality before load
SELECT 
    'Null Orders' AS CheckName,
    COUNT(*) AS FailCount
FROM StageOrders
WHERE OrderID IS NULL

UNION ALL

SELECT 
    'Duplicate Orders',
    COUNT(*)
FROM StageOrders
GROUP BY OrderID
HAVING COUNT(*) > 1

UNION ALL

SELECT 
    'Invalid Amounts',
    COUNT(*)
FROM StageOrders
WHERE Amount < 0
```

### Post-Load Validation
```sql
-- Compare source vs target counts
IF (SELECT COUNT(*) FROM SourceOrders) <>
   (SELECT COUNT(*) FROM TargetOrders WHERE LoadDate = CAST(GETDATE() AS DATE))
BEGIN
    RAISERROR('Row count mismatch', 16, 1)
END

-- Check key relationships
IF EXISTS (SELECT 1 FROM TargetOrders o 
           WHERE NOT EXISTS (SELECT 1 FROM Customers c WHERE c.CustomerID = o.CustomerID))
BEGIN
    RAISERROR('Orphan order records found', 16, 1)
END
```

## ETL Control Table

```sql
CREATE TABLE ETLControlTable (
    ETLName NVARCHAR(100) PRIMARY KEY,
    LastLoadTime DATETIME,
    LastLoadStatus NVARCHAR(50),
    RowsLoaded INT,
    NextLoadTime DATETIME
)

-- Log each run
INSERT INTO ETLControlTable (ETLName, LastLoadTime, LastLoadStatus, RowsLoaded)
VALUES ('OrdersETL', GETDATE(), 'Success', @@ROWCOUNT)

-- Check status before running (prevent concurrent runs)
IF EXISTS (SELECT 1 FROM ETLControlTable 
           WHERE ETLName = 'OrdersETL' 
           AND LastLoadStatus = 'Running'
           AND DATEDIFF(MINUTE, LastLoadTime, GETDATE()) < 30)
BEGIN
    THROW 50002, 'ETL already running', 1
END
```
