# SQL Server Auditing Guide

## Audit Table Pattern (Manual)

### Create Audit Table
```sql
CREATE TABLE OrdersAudit (
    AuditID INT PRIMARY KEY IDENTITY(1,1),
    OrderID INT,
    ColumnName NVARCHAR(100),
    OldValue NVARCHAR(MAX),
    NewValue NVARCHAR(MAX),
    ChangeType NVARCHAR(10),  -- 'INSERT', 'UPDATE', 'DELETE'
    ChangedBy NVARCHAR(100),  -- User who made change
    ChangedAt DATETIME DEFAULT GETDATE(),
    AppName NVARCHAR(100)  -- Application making change
)

CREATE INDEX idx_Orders_AuditLog ON OrdersAudit(OrderID, ChangedAt)
```

### Trigger for INSERT
```sql
CREATE OR ALTER TRIGGER tr_Orders_Insert
ON Orders
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON
    
    INSERT INTO OrdersAudit (OrderID, ColumnName, OldValue, NewValue, ChangeType, ChangedBy, AppName)
    SELECT 
        i.OrderID,
        'OrderID',
        NULL,
        CAST(i.OrderID AS NVARCHAR(MAX)),
        'INSERT',
        SUSER_NAME(),
        APP_NAME()
    FROM inserted i
    
    UNION ALL
    
    SELECT 
        i.OrderID,
        'Amount',
        NULL,
        CAST(i.Amount AS NVARCHAR(MAX)),
        'INSERT',
        SUSER_NAME(),
        APP_NAME()
    FROM inserted i
    
    UNION ALL
    
    SELECT 
        i.OrderID,
        'Status',
        NULL,
        i.Status,
        'INSERT',
        SUSER_NAME(),
        APP_NAME()
    FROM inserted i
END
```

### Trigger for UPDATE
```sql
CREATE OR ALTER TRIGGER tr_Orders_Update
ON Orders
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON
    
    -- Log changed Amount
    INSERT INTO OrdersAudit (OrderID, ColumnName, OldValue, NewValue, ChangeType, ChangedBy, AppName)
    SELECT 
        i.OrderID,
        'Amount',
        CAST(d.Amount AS NVARCHAR(MAX)),
        CAST(i.Amount AS NVARCHAR(MAX)),
        'UPDATE',
        SUSER_NAME(),
        APP_NAME()
    FROM inserted i
    INNER JOIN deleted d ON i.OrderID = d.OrderID
    WHERE i.Amount <> d.Amount
    
    -- Log changed Status
    UNION ALL
    
    SELECT 
        i.OrderID,
        'Status',
        d.Status,
        i.Status,
        'UPDATE',
        SUSER_NAME(),
        APP_NAME()
    FROM inserted i
    INNER JOIN deleted d ON i.OrderID = d.OrderID
    WHERE i.Status <> d.Status
END
```

### Query Audit Log
```sql
-- View all changes to Order 123
SELECT * FROM OrdersAudit WHERE OrderID = 123 ORDER BY ChangedAt

-- View changes by user
SELECT ChangedBy, COUNT(*) AS ChangeCount
FROM OrdersAudit
WHERE ChangedAt >= GETDATE() - 30  -- Last 30 days
GROUP BY ChangedBy

-- Find specific column changes
SELECT * FROM OrdersAudit
WHERE ColumnName = 'Amount' AND ChangedAt >= GETDATE() - 1
ORDER BY ChangedAt DESC
```

## Temporal Tables (System-Versioned)

### Create Temporal Table
```sql
CREATE TABLE Orders (
    OrderID INT PRIMARY KEY,
    CustomerID INT,
    Amount DECIMAL(10,2),
    Status NVARCHAR(50),
    ValidFrom DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN,
    ValidTo DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN,
    PERIOD FOR SYSTEM_TIME (ValidFrom, ValidTo)
)
WITH (SYSTEM_VERSIONING = ON, HISTORY_TABLE = OrdersHistory)

-- History table automatically created: OrdersHistory
-- Stores old versions of rows automatically
```

### Query Historical Data
```sql
-- Current state only
SELECT * FROM Orders

-- As of specific point in time
SELECT * FROM Orders FOR SYSTEM_TIME AS OF '2024-06-01 10:30:00'

-- All versions throughout history
SELECT * FROM Orders FOR SYSTEM_TIME ALL

-- Between two dates
SELECT * FROM Orders FOR SYSTEM_TIME BETWEEN '2024-06-01' AND '2024-06-30'

-- During time period (BETWEEN inclusive, TO exclusive)
SELECT * FROM Orders FOR SYSTEM_TIME FROM '2024-01-01' TO '2024-12-31'
```

### Compare versions
```sql
-- See how a record changed over time
WITH OrderHistory AS (
    SELECT *, ROW_NUMBER() OVER (ORDER BY ValidFrom) AS Version
    FROM Orders FOR SYSTEM_TIME ALL
    WHERE OrderID = 123
)
SELECT 
    Version,
    Amount,
    Status,
    ValidFrom,
    ValidTo
FROM OrderHistory
ORDER BY ValidFrom
```

### Query both current and history
```sql
-- Find records modified in last 7 days
SELECT 'Current' AS Source, * FROM Orders
WHERE ValidFrom >= GETDATE() - 7
UNION ALL
SELECT 'History', * FROM OrdersHistory
WHERE ValidTo >= GETDATE() - 7
ORDER BY OrderID, ValidFrom DESC
```

## Delete Patterns

### Hard Delete (Remove Completely)
```sql
DELETE FROM Orders WHERE OrderID = 123
-- Row completely removed
-- Can't recover unless from backup

-- Audit: Record deleted value in audit table first
BEGIN TRANSACTION
    INSERT INTO OrdersAudit (OrderID, ChangeType, ChangedBy, ChangedAt)
    SELECT OrderID, 'DELETED_HARD', SUSER_NAME(), GETDATE()
    FROM Orders WHERE OrderID = 123
    
    DELETE FROM Orders WHERE OrderID = 123
COMMIT TRANSACTION
```

### Soft Delete (Mark as Deleted)
```sql
-- Add IsDeleted column
ALTER TABLE Orders ADD IsDeleted BIT DEFAULT 0

-- Soft delete (marks as deleted, keeps data)
UPDATE Orders SET IsDeleted = 1, DeletedBy = SUSER_NAME(), DeletedAt = GETDATE()
WHERE OrderID = 123

-- Queries ignore soft-deleted records
SELECT * FROM Orders WHERE IsDeleted = 0

-- Can recover if needed
UPDATE Orders SET IsDeleted = 0 WHERE OrderID = 123

-- Eventually archive and hard delete
INSERT INTO OrdersArchive
SELECT * FROM Orders WHERE IsDeleted = 1 AND DeletedAt < GETDATE() - 365

DELETE FROM Orders WHERE IsDeleted = 1 AND DeletedAt < GETDATE() - 365
```

### Archive Pattern
```sql
-- Archive table (exact same schema as source)
CREATE TABLE OrdersArchive LIKE Orders

-- Periodically archive old data
BEGIN TRANSACTION
    INSERT INTO OrdersArchive
    SELECT * FROM Orders
    WHERE CreatedAt < GETDATE() - 730  -- Older than 2 years
    
    DELETE FROM Orders
    WHERE CreatedAt < GETDATE() - 730
COMMIT TRANSACTION

-- Query archive
SELECT * FROM OrdersArchive WHERE OrderID = 123
```

## SQL Server Audit Feature

### Enable Audit
```sql
-- Create audit target
CREATE SERVER AUDIT SQLServerAudit
TO FILE (FILEPATH = 'C:\AuditLogs\', MAXSIZE = 1024 MB)
WITH (QUEUE_DELAY = 1000, ON_FAILURE = CONTINUE)

-- Enable audit
ALTER SERVER AUDIT SQLServerAudit WITH (STATE = ON)

-- Create database audit specification
CREATE DATABASE AUDIT SPECIFICATION db_Orders_Audit
FOR SERVER AUDIT SQLServerAudit
ADD (SELECT ON Orders BY PUBLIC)  -- Log SELECT on Orders
ADD (INSERT ON Orders BY PUBLIC)  -- Log INSERT on Orders
ADD (UPDATE ON Orders BY PUBLIC)  -- Log UPDATE on Orders
ADD (DELETE ON Orders BY PUBLIC)  -- Log DELETE on Orders
WITH (STATE = ON)
```

### Query Audit Log
```sql
-- Read audit log
SELECT 
    event_time,
    server_principal_name,
    action_id,
    object_name,
    succeeded
FROM sys.fn_get_audit_file('C:\AuditLogs\*.sqlaudit', DEFAULT, DEFAULT)
WHERE object_name = 'Orders'
ORDER BY event_time DESC
```

## Change Tracking (Lightweight)

### Enable Change Tracking
```sql
-- Enable on database
ALTER DATABASE MyDB SET CHANGE_TRACKING = ON (CHANGE_RETENTION = 2 DAYS, AUTO_CLEANUP = ON)

-- Enable on specific table
ALTER TABLE Orders ENABLE CHANGE_TRACKING

-- Enable with column tracking
ALTER TABLE Orders ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = ON)
```

### Query Changes
```sql
-- Get changes since specific version
DECLARE @last_sync_version BIGINT = 0

SELECT 
    CT.OrderID,
    CT.SYS_CHANGE_VERSION,
    CT.SYS_CHANGE_CREATION_VERSION,
    CT.SYS_CHANGE_OPERATION,  -- 'I'=Insert, 'U'=Update, 'D'=Delete
    CT.SYS_CHANGE_COLUMNS  -- Which columns changed
FROM CHANGETABLE(CHANGES Orders, @last_sync_version) AS CT
ORDER BY CT.SYS_CHANGE_VERSION

-- Get current sync version
SELECT CHANGE_TRACKING_CURRENT_VERSION() AS CurrentVersion
```

## Audit Checklist

✅ **Audit:**
- User access to sensitive data
- Data modifications (INSERT, UPDATE, DELETE)
- Administrative actions
- Failed login attempts
- Privilege changes
- Critical reports run
- Bulk operations

❌ **Don't audit** (performance impact):
- Every SELECT statement (use change tracking instead)
- Logging tables themselves
- Staging/temp tables
- High-volume operational reads

## Compliance Scenarios

### SOX Compliance (Financial Records)
```sql
-- Immutable audit log
CREATE TABLE FinancialAudit (
    AuditID INT PRIMARY KEY IDENTITY(1,1),
    TransactionID INT NOT NULL,
    AccountNumber NVARCHAR(50),
    Amount DECIMAL(15,2),
    BeforeAmount DECIMAL(15,2),
    AfterAmount DECIMAL(15,2),
    ChangedBy NVARCHAR(100),
    ChangedAt DATETIME DEFAULT GETDATE(),
    Reason NVARCHAR(MAX),
    CONSTRAINT chk_Amount_NonNegative CHECK (AfterAmount >= 0)
)

-- Make audit read-only for production
CREATE ROLE AuditReader
GRANT SELECT ON FinancialAudit TO AuditReader

-- Deny modifications to audit table
DENY INSERT, UPDATE, DELETE ON FinancialAudit TO PUBLIC
```

### GDPR Compliance (Right to Erasure)
```sql
-- Track what personal data we have
CREATE TABLE PersonalDataInventory (
    TableName NVARCHAR(100),
    ColumnName NVARCHAR(100),
    DataType NVARCHAR(50),
    LastRemovedDate DATETIME
)

-- Document deletions (anonymize after 90 days)
UPDATE Customers
SET Email = 'deleted_' + CAST(CustomerID AS NVARCHAR(10)) + '@deleted.local'
WHERE CustomerID IN (
    SELECT CustomerID FROM DeleteRequests
    WHERE RequestDate < GETDATE() - 90
)
```
