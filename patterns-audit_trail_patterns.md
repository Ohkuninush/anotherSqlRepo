---
name: audit-trail-patterns
description: Enterprise audit trail implementation — who changed what when, user traceability, Temporal Tables, compliance-ready change tracking
---

# Audit Trail Patterns — Complete Change Tracking

## Overview

**Why it matters:** You need to answer:
- "Who deleted that customer record?"
- "When did the price change from $50 to $75?"
- "What was the inventory count on 2026-05-15?"
- "Can we prove compliance with data retention rules?"

**Without audit trails:** No audit → No compliance → Legal liability → $$$

**Use cases:**
- Financial compliance (Sarbanes-Oxley, GDPR)
- Healthcare (HIPAA requires audit logs)
- eCommerce (dispute resolution)
- Security incidents (forensics)
- Data integrity verification

---

## Anti-Pattern: No Audit Trail (❌ Don't Do This)

### The Problem
```sql
-- No way to track changes
CREATE TABLE Orders (
    OrderID INT PRIMARY KEY,
    CustomerID INT,
    Amount DECIMAL(10, 2),
    Status NVARCHAR(20)
)

-- Someone updates the amount...
UPDATE Orders SET Amount = 500 WHERE OrderID = 1

-- Later: "Who changed this?" 
-- Answer: You have no idea. It's gone.
```

### Real-World Incident
```
Timeline:
  Customer: "I was charged twice for my order!"
  Support: "Let me check... Order shows $100, not $200"
  Customer: "Someone changed it after I was charged!"
  Support: "I can't prove what happened. No audit trail."
  
  Result: Refund $100 + reputation damage
  
Why it happened: No audit trail
```

---

## Pattern 1: Shadow Table with Triggers

### Use Case
- Medium-volume changes (not millions per second)
- Need detailed change history
- Compliance requirement (financial audit)
- Don't want to mess with the main table structure

### ✅ Correct Implementation

#### Schema
```sql
-- Main table (unchanged)
CREATE TABLE Customers (
    CustomerID INT PRIMARY KEY,
    Name NVARCHAR(100) NOT NULL,
    Email NVARCHAR(255),
    Phone NVARCHAR(20),
    Balance DECIMAL(10, 2)
)

-- Shadow table (tracks all changes)
CREATE TABLE Customers_Audit (
    AuditID BIGINT PRIMARY KEY IDENTITY(1, 1),
    CustomerID INT NOT NULL,
    Action NVARCHAR(10) NOT NULL,  -- INSERT, UPDATE, DELETE
    OldValue_Name NVARCHAR(100),
    NewValue_Name NVARCHAR(100),
    OldValue_Email NVARCHAR(255),
    NewValue_Email NVARCHAR(255),
    OldValue_Phone NVARCHAR(20),
    NewValue_Phone NVARCHAR(20),
    OldValue_Balance DECIMAL(10, 2),
    NewValue_Balance DECIMAL(10, 2),
    ChangedByUser NVARCHAR(128) NOT NULL,
    ChangedDate DATETIME2 NOT NULL DEFAULT GETDATE(),
    ApplicationName NVARCHAR(128)
)
```

#### Triggers for INSERT/UPDATE/DELETE
```sql
-- Trigger: Track INSERTs
CREATE TRIGGER tr_Customers_Insert
ON Customers
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON
    
    INSERT INTO Customers_Audit 
    (CustomerID, Action, 
     NewValue_Name, NewValue_Email, NewValue_Phone, NewValue_Balance,
     ChangedByUser, ChangedDate, ApplicationName)
    SELECT 
        i.CustomerID,
        'INSERT',
        i.Name, i.Email, i.Phone, i.Balance,
        SUSER_NAME(),
        GETDATE(),
        APP_NAME()
    FROM inserted i
END

-- Trigger: Track UPDATEs
CREATE TRIGGER tr_Customers_Update
ON Customers
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON
    
    -- Only log if actual values changed (not dummy updates)
    INSERT INTO Customers_Audit 
    (CustomerID, Action, 
     OldValue_Name, NewValue_Name,
     OldValue_Email, NewValue_Email,
     OldValue_Phone, NewValue_Phone,
     OldValue_Balance, NewValue_Balance,
     ChangedByUser, ChangedDate, ApplicationName)
    SELECT 
        d.CustomerID,
        'UPDATE',
        d.Name, i.Name,
        d.Email, i.Email,
        d.Phone, i.Phone,
        d.Balance, i.Balance,
        SUSER_NAME(),
        GETDATE(),
        APP_NAME()
    FROM deleted d
    INNER JOIN inserted i ON d.CustomerID = i.CustomerID
    WHERE d.Name != i.Name
       OR d.Email != i.Email
       OR d.Phone != i.Phone
       OR d.Balance != i.Balance
       -- Avoid logging unchanged columns
END

-- Trigger: Track DELETEs
CREATE TRIGGER tr_Customers_Delete
ON Customers
AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON
    
    INSERT INTO Customers_Audit 
    (CustomerID, Action,
     OldValue_Name, OldValue_Email, OldValue_Phone, OldValue_Balance,
     ChangedByUser, ChangedDate, ApplicationName)
    SELECT 
        d.CustomerID,
        'DELETE',
        d.Name, d.Email, d.Phone, d.Balance,
        SUSER_NAME(),
        GETDATE(),
        APP_NAME()
    FROM deleted d
END
```

#### Audit Queries
```sql
-- Show all changes to a customer
SELECT 
    AuditID,
    Action,
    OldValue_Name, NewValue_Name,
    OldValue_Email, NewValue_Email,
    OldValue_Balance, NewValue_Balance,
    ChangedByUser,
    ChangedDate
FROM Customers_Audit
WHERE CustomerID = @CustomerID
ORDER BY ChangedDate DESC

-- Show timeline of balance changes
SELECT 
    ChangedDate,
    OldValue_Balance,
    NewValue_Balance,
    ChangedByUser
FROM Customers_Audit
WHERE CustomerID = @CustomerID
  AND (OldValue_Balance IS NOT NULL OR NewValue_Balance IS NOT NULL)
ORDER BY ChangedDate ASC

-- Prove who changed what
SELECT 
    COUNT(*) AS TotalChanges,
    ChangedByUser,
    MIN(ChangedDate) AS FirstChange,
    MAX(ChangedDate) AS LastChange
FROM Customers_Audit
WHERE ChangedDate BETWEEN @StartDate AND @EndDate
GROUP BY ChangedByUser
ORDER BY TotalChanges DESC
```

#### Performance Considerations
```sql
-- Create clustered index on CustomerID + ChangedDate for fast queries
CREATE CLUSTERED INDEX IX_Audit_CustomerDate
ON Customers_Audit (CustomerID, ChangedDate DESC)

-- Archive old audit records (keep hot, move cold)
DECLARE @CutoffDate DATETIME2 = GETDATE() - 365
DELETE FROM Customers_Audit WHERE ChangedDate < @CutoffDate
```

---

## Pattern 2: Temporal Tables (Modern, Automatic)

### Use Case
- SQL Server 2016+ only
- Automatic versioning (no triggers needed)
- Built-in point-in-time queries
- Minimal application code changes
- Best for compliance-heavy systems

### ✅ Correct Implementation

#### Schema (SQL Server 2016+)
```sql
-- Create main table with system time tracking
CREATE TABLE Customers (
    CustomerID INT PRIMARY KEY,
    Name NVARCHAR(100) NOT NULL,
    Email NVARCHAR(255),
    Phone NVARCHAR(20),
    Balance DECIMAL(10, 2),
    -- System columns (added automatically)
    SysStartTime DATETIME2 GENERATED ALWAYS AS ROW START,
    SysEndTime DATETIME2 GENERATED ALWAYS AS ROW END,
    PERIOD FOR SYSTEM_TIME (SysStartTime, SysEndTime)
)
WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.Customers_History))

-- SQL Server automatically creates Customers_History table
-- You don't define it; the system manages it
```

#### Operations (Same as Normal Table)
```sql
-- INSERT (tracked automatically)
INSERT INTO Customers VALUES (1, 'Alice', 'alice@example.com', '555-1234', 100)

-- UPDATE (creates history entry)
UPDATE Customers SET Balance = 150 WHERE CustomerID = 1

-- DELETE (marks end time, doesn't remove)
DELETE FROM Customers WHERE CustomerID = 1

-- SELECT current state only (default behavior)
SELECT * FROM Customers  -- Shows current data only
```

#### Point-in-Time Queries
```sql
-- What was the balance on May 15, 2026 at 2pm?
SELECT CustomerID, Name, Balance, SysStartTime
FROM Customers
FOR SYSTEM_TIME AS OF '2026-05-15 14:00:00'
WHERE CustomerID = 1

-- Show all versions (current + history)
SELECT CustomerID, Name, Balance, SysStartTime, SysEndTime
FROM Customers
FOR SYSTEM_TIME ALL
WHERE CustomerID = 1
ORDER BY SysStartTime ASC

-- Show changes in a date range
SELECT CustomerID, Name, Balance, SysStartTime, SysEndTime
FROM Customers
FOR SYSTEM_TIME BETWEEN '2026-05-01' AND '2026-05-31'
WHERE CustomerID = 1
ORDER BY SysStartTime ASC

-- Show current and future (for trending)
SELECT CustomerID, Name, Balance, SysStartTime
FROM Customers
FOR SYSTEM_TIME FROM '2026-05-01' TO '2026-06-01'
WHERE CustomerID = 1
ORDER BY SysStartTime
```

#### Historical Analysis
```sql
-- Track balance over time
SELECT 
    SysStartTime AS ChangedDate,
    Name,
    LAG(Balance) OVER (ORDER BY SysStartTime) AS PriorBalance,
    Balance AS CurrentBalance,
    Balance - LAG(Balance) OVER (ORDER BY SysStartTime) AS Change
FROM Customers
FOR SYSTEM_TIME ALL
WHERE CustomerID = 1
ORDER BY SysStartTime

-- Find when status changed
SELECT 
    SysStartTime,
    SysEndTime,
    Balance
FROM Customers
FOR SYSTEM_TIME ALL
WHERE CustomerID = 1
  AND Balance > 500
ORDER BY SysStartTime
```

#### Compliance Proof
```sql
-- Show complete audit trail (immutable by default)
CREATE PROCEDURE sp_GetAuditTrail
    @CustomerID INT
AS
BEGIN
    SELECT 
        SysStartTime AS ChangedAt,
        Name,
        Email,
        Phone,
        Balance
    FROM Customers
    FOR SYSTEM_TIME ALL
    WHERE CustomerID = @CustomerID
    ORDER BY SysStartTime DESC
    
    -- Output proves: when changed, what was the state
    -- Cannot be altered (history table is read-only)
END
```

---

## Pattern 3: Audit Table with Application Logic

### Use Case
- Custom audit rules (not every change matters)
- Want to log business events + data changes
- Example: "Log price changes, but not status updates"

### ✅ Correct Implementation

#### Schema
```sql
CREATE TABLE Products (
    ProductID INT PRIMARY KEY,
    Name NVARCHAR(100),
    Price DECIMAL(10, 2),
    Status NVARCHAR(20)
)

CREATE TABLE ProductAudit (
    AuditID BIGINT PRIMARY KEY IDENTITY(1, 1),
    ProductID INT,
    ChangeType NVARCHAR(50),  -- 'PRICE_CHANGE', 'DISCONTINUED', 'RESTOCKED'
    OldValue NVARCHAR(255),
    NewValue NVARCHAR(255),
    BusinessReason NVARCHAR(500),  -- WHY it changed
    ChangedByUser NVARCHAR(128),
    ChangedDate DATETIME2,
    ApprovedByUser NVARCHAR(128),  -- For compliance
    ApprovedDate DATETIME2
)
```

#### Stored Procedure with Business Logic
```sql
CREATE OR ALTER PROCEDURE sp_UpdateProductPrice
    @ProductID INT,
    @NewPrice DECIMAL(10, 2),
    @BusinessReason NVARCHAR(500),
    @ApprovedByUser NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON
    SET XACT_ABORT ON
    
    DECLARE @OldPrice DECIMAL(10, 2)
    
    BEGIN TRY
        BEGIN TRANSACTION
        
        -- Get current price
        SELECT @OldPrice = Price FROM Products WHERE ProductID = @ProductID
        
        -- Prevent significant price drops without approval
        IF (@OldPrice - @NewPrice) > (@OldPrice * 0.20)  -- >20% discount
        BEGIN
            IF @ApprovedByUser IS NULL
                THROW 50001, 'Large discount requires manager approval', 1
        END
        
        -- Update the actual data
        UPDATE Products 
        SET Price = @NewPrice
        WHERE ProductID = @ProductID
        
        -- Log the change (business-aware)
        INSERT INTO ProductAudit 
        (ProductID, ChangeType, OldValue, NewValue, BusinessReason,
         ChangedByUser, ChangedDate, ApprovedByUser, ApprovedDate)
        VALUES 
        (@ProductID, 'PRICE_CHANGE', 
         CAST(@OldPrice AS NVARCHAR(255)), 
         CAST(@NewPrice AS NVARCHAR(255)),
         @BusinessReason,
         SUSER_NAME(), GETDATE(),
         @ApprovedByUser, GETDATE())
        
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION
        THROW
    END CATCH
END

-- Usage: Only price changes are audited, not every update
EXEC sp_UpdateProductPrice 1, 89.99, 'Clearance sale', 'Manager123'
```

---

## Pattern 4: Compliance-Ready Audit

### Use Case
- Legal/regulatory requirements (GDPR, HIPAA, SOX)
- Read-only audit (can't be tampered with)
- Immutable history with signatures

### ✅ Correct Implementation

#### Schema
```sql
CREATE TABLE FinancialTransactions (
    TransactionID BIGINT PRIMARY KEY,
    Amount DECIMAL(19, 4),
    Status NVARCHAR(20)
)

-- Immutable audit log (append-only)
CREATE TABLE FinancialAudit (
    AuditID BIGINT PRIMARY KEY IDENTITY(1, 1),
    TransactionID BIGINT,
    Action NVARCHAR(20),
    OldAmount DECIMAL(19, 4),
    NewAmount DECIMAL(19, 4),
    ChangedByUser NVARCHAR(128),
    ChangedDate DATETIME2,
    AuditHash NVARCHAR(64),  -- SHA256 hash for tamper detection
    PriorAuditHash NVARCHAR(64),  -- Chain of hashes
    CONSTRAINT UQ_AuditHash UNIQUE (AuditHash)  -- Prevent duplicates
)
```

#### Secure Audit Insertion
```sql
CREATE OR ALTER PROCEDURE sp_RecordAudit
    @TransactionID BIGINT,
    @Action NVARCHAR(20),
    @OldAmount DECIMAL(19, 4),
    @NewAmount DECIMAL(19, 4)
AS
BEGIN
    SET NOCOUNT ON
    SET XACT_ABORT ON
    
    DECLARE @CurrentHash NVARCHAR(64)
    DECLARE @PriorHash NVARCHAR(64)
    DECLARE @HashInput NVARCHAR(MAX)
    
    BEGIN TRY
        -- Get hash chain
        SELECT @PriorHash = MAX(AuditHash) 
        FROM FinancialAudit
        
        -- Create tamper-proof hash
        SELECT @HashInput = 
            CAST(@TransactionID AS VARCHAR) + '|' +
            @Action + '|' +
            CAST(@NewAmount AS VARCHAR) + '|' +
            CAST(GETDATE() AS VARCHAR) + '|' +
            ISNULL(@PriorHash, '')
        
        -- Use HASHBYTES for SHA256
        SELECT @CurrentHash = 
            CONVERT(VARCHAR(64), 
                HASHBYTES('SHA2_256', @HashInput), 2)
        
        -- Append-only insert (no updates allowed)
        INSERT INTO FinancialAudit 
        (TransactionID, Action, OldAmount, NewAmount, 
         ChangedByUser, ChangedDate, AuditHash, PriorAuditHash)
        VALUES 
        (@TransactionID, @Action, @OldAmount, @NewAmount,
         SUSER_NAME(), GETDATE(), @CurrentHash, @PriorHash)
    END TRY
    BEGIN CATCH
        THROW
    END CATCH
END
```

#### Tamper Detection
```sql
-- Verify audit trail hasn't been modified
CREATE OR ALTER PROCEDURE sp_VerifyAuditIntegrity
AS
BEGIN
    DECLARE @HashMismatch INT = 0
    
    -- Recalculate hashes and compare
    SELECT @HashMismatch = COUNT(*)
    FROM FinancialAudit fa1
    WHERE fa1.AuditHash != 
        CONVERT(VARCHAR(64), 
            HASHBYTES('SHA2_256', 
                CAST(fa1.TransactionID AS VARCHAR) + '|' +
                fa1.Action + '|' +
                CAST(fa1.NewAmount AS VARCHAR) + '|' +
                CAST(fa1.ChangedDate AS VARCHAR) + '|' +
                ISNULL(fa1.PriorAuditHash, '')), 2)
    
    IF @HashMismatch > 0
        PRINT 'WARNING: Audit trail tampering detected!'
    ELSE
        PRINT 'Audit trail integrity verified'
    
    RETURN @HashMismatch
END
```

---

## Best Practices

### 1. Audit Indexes (Critical for Performance)
```sql
-- Make audit queries fast
CREATE CLUSTERED INDEX IX_Audit_CustomerDate
ON Customers_Audit (CustomerID, ChangedDate DESC)

CREATE NONCLUSTERED INDEX IX_Audit_User
ON Customers_Audit (ChangedByUser, ChangedDate)

CREATE NONCLUSTERED INDEX IX_Audit_Action
ON Customers_Audit (Action) WHERE Action IN ('DELETE', 'UPDATE')
```

### 2. Archive Old Audit Records
```sql
-- Don't let audit tables grow unbounded
CREATE OR ALTER PROCEDURE sp_ArchiveAuditRecords
    @RetentionDays INT = 1825  -- 5 years
AS
BEGIN
    DECLARE @CutoffDate DATETIME2 = GETDATE() - @RetentionDays
    
    BEGIN TRANSACTION
        -- Move to archive table
        INSERT INTO Customers_AuditArchive
        SELECT * FROM Customers_Audit
        WHERE ChangedDate < @CutoffDate
        
        -- Delete from hot table
        DELETE FROM Customers_Audit
        WHERE ChangedDate < @CutoffDate
    COMMIT TRANSACTION
END
```

### 3. Restrict Audit Access
```sql
-- Only compliance officers can read audit tables
CREATE ROLE ComplianceOfficer
GRANT SELECT ON Customers_Audit TO ComplianceOfficer
DENY DELETE ON Customers_Audit TO ComplianceOfficer
DENY UPDATE ON Customers_Audit TO ComplianceOfficer
```

### 4. Regular Audit Review
```sql
-- Monthly compliance report
SELECT 
    ChangedByUser,
    COUNT(*) AS TotalChanges,
    COUNT(CASE WHEN Action = 'DELETE' THEN 1 END) AS Deletions,
    MIN(ChangedDate) AS FirstChange,
    MAX(ChangedDate) AS LastChange
FROM Customers_Audit
WHERE ChangedDate >= DATEADD(MONTH, -1, GETDATE())
GROUP BY ChangedByUser
ORDER BY Deletions DESC
```

---

## Choosing a Pattern

| Pattern | Complexity | Compliance | Ease of Use | Performance |
|---------|-----------|-----------|-----------|-------------|
| Shadow Table + Triggers | Medium | ⭐⭐⭐ | Easy | Good |
| Temporal Tables | Low | ⭐⭐⭐⭐⭐ | Very Easy | Excellent |
| Custom Audit | High | ⭐⭐⭐⭐ | Complex | Good |
| Immutable Audit | Very High | ⭐⭐⭐⭐⭐ | Complex | Good |

**Recommendation:**
- **New systems:** Use Temporal Tables (SQL Server 2016+)
- **Existing systems:** Add Shadow Tables with Triggers
- **Compliance-critical:** Immutable Audit with hashing
- **Custom business rules:** Application-level audit procedure

---

## References
- `[[soft_delete_patterns]]` — Integration with deletion tracking
- `[[data_validation_tests]]` — Test audit constraints
- `references/auditing_guide.md` — Detailed compliance requirements
- `references/transaction_management.md` — Transaction isolation in audits

