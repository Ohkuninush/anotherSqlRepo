---
name: soft-delete-patterns
description: Enterprise soft delete implementation patterns — IsDeleted flag, archival strategies, recovery workflows, and compliance considerations
---

# Soft Delete Patterns — Enterprise Implementation Guide

## Overview

**When to use:** Systems where deleted data must be recoverable for compliance, auditing, customer service, or historical analysis.

**Why it matters:** Hard deletes (permanent removal) make recovery impossible. Soft deletes preserve data while logically removing it from active queries.

**Common use cases:**
- Financial records (audit trails, regulatory retention)
- Customer data (GDPR right-to-be-forgotten with compliance holds)
- Multi-tenant systems (one tenant deletes, doesn't affect others)
- eCommerce orders (customers request deletion, but finance needs historical records)
- Healthcare data (HIPAA requires audit logs of deletions)

---

## Anti-Pattern: Hard Delete (❌ Don't Do This)

### The Problem
```sql
-- ❌ ANTI-PATTERN: Permanent deletion
DELETE FROM Orders WHERE OrderID = @OrderID
```

**Why this fails:**
1. **No recovery** — Data is gone forever
2. **Audit trail broken** — No proof deletion occurred
3. **Compliance violations** — Can't satisfy legal holds
4. **Cascading deletes** — Foreign keys delete dependent records unexpectedly
5. **Accidental loss** — A typo in WHERE clause = mass data loss
6. **Customer complaints** — "I deleted by mistake, can you restore?"

### Real-World Incident
```
Scenario: Finance deletes Q1 orders to "clean up"
Result: 
  - Customer service can't answer "What did I order?"
  - Auditor asks for deleted order details → NOT FOUND
  - CEO receives notice: "$500K in deleted financial records"
  - Compliance: FAILED
```

---

## Pattern 1: Simple IsDeleted Flag

### Use Case
- Basic applications without complex retention rules
- Single deletion reason ("deleted by user")
- No need to track *who* deleted or *when*

### ✅ Correct Implementation

#### Schema
```sql
CREATE TABLE Orders (
    OrderID INT PRIMARY KEY,
    CustomerID INT NOT NULL,
    Amount DECIMAL(10, 2),
    OrderDate DATETIME2,
    IsDeleted BIT NOT NULL DEFAULT 0,  -- ← Soft delete flag
    INDEX IX_Orders_IsDeleted (IsDeleted) WHERE IsDeleted = 0  -- ← Filtered index
)
```

**Why filtered index:** Queries typically filter `WHERE IsDeleted = 0`, so we only index active records. Saves space, improves performance.

#### Delete Operation
```sql
-- Soft delete (logical removal)
UPDATE Orders
SET IsDeleted = 1
WHERE OrderID = @OrderID
```

#### Active Data Queries
```sql
-- Standard: Always filter for active records
SELECT OrderID, CustomerID, Amount, OrderDate
FROM Orders
WHERE IsDeleted = 0
  AND CustomerID = @CustomerID
ORDER BY OrderDate DESC
```

#### Recovery
```sql
-- Restore deleted record
UPDATE Orders
SET IsDeleted = 0
WHERE OrderID = @OrderID
```

---

## Pattern 2: Soft Delete with Audit Trail

### Use Case
- Compliance-heavy systems (finance, healthcare, government)
- Need to track WHO deleted and WHEN
- Multiple deletion reasons (user request, fraud, compliance, expiration)

### ✅ Correct Implementation

#### Schema
```sql
CREATE TABLE Orders (
    OrderID INT PRIMARY KEY,
    CustomerID INT NOT NULL,
    Amount DECIMAL(10, 2),
    OrderDate DATETIME2,
    IsDeleted BIT NOT NULL DEFAULT 0,
    DeletedByUser NVARCHAR(128) NULL,           -- ← Who deleted
    DeletedReason NVARCHAR(50) NULL,            -- ← Why deleted
    DeletedDate DATETIME2 NULL,                 -- ← When deleted
    INDEX IX_Orders_IsDeleted (IsDeleted) WHERE IsDeleted = 0
)
```

#### Delete Operation
```sql
CREATE OR ALTER PROCEDURE sp_DeleteOrder
    @OrderID INT,
    @Reason NVARCHAR(50) = 'USER_REQUEST'      -- user_request | fraud | compliance | expiration
AS
BEGIN
    SET NOCOUNT ON
    SET XACT_ABORT ON
    
    IF @OrderID IS NULL OR @OrderID <= 0
        THROW 50001, 'Invalid OrderID', 1
    
    BEGIN TRY
        BEGIN TRANSACTION
        
        -- Check if already deleted
        IF EXISTS (SELECT 1 FROM Orders WHERE OrderID = @OrderID AND IsDeleted = 1)
            THROW 50002, 'Order already deleted', 1
        
        -- Soft delete with audit
        UPDATE Orders
        SET IsDeleted = 1,
            DeletedByUser = SUSER_NAME(),
            DeletedReason = @Reason,
            DeletedDate = GETDATE()
        WHERE OrderID = @OrderID
        
        -- Log the deletion
        INSERT INTO DeletionAuditLog (OrderID, DeletedByUser, DeletedReason, DeletedDate)
        VALUES (@OrderID, SUSER_NAME(), @Reason, GETDATE())
        
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION
        THROW
    END CATCH
END
```

#### Recovery with Audit
```sql
CREATE OR ALTER PROCEDURE sp_RestoreOrder
    @OrderID INT,
    @RestoreReason NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON
    SET XACT_ABORT ON
    
    BEGIN TRY
        BEGIN TRANSACTION
        
        UPDATE Orders
        SET IsDeleted = 0,
            DeletedByUser = NULL,
            DeletedReason = NULL,
            DeletedDate = NULL
        WHERE OrderID = @OrderID
        
        -- Log restoration
        INSERT INTO RestorationAuditLog (OrderID, RestoredByUser, RestoredReason, RestoredDate)
        VALUES (@OrderID, SUSER_NAME(), @RestoreReason, GETDATE())
        
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION
        THROW
    END CATCH
END
```

#### Compliance Query
```sql
-- Show all deletions in date range (audit trail)
SELECT 
    OrderID,
    DeletedByUser,
    DeletedReason,
    DeletedDate
FROM Orders
WHERE IsDeleted = 1
  AND DeletedDate >= @StartDate
  AND DeletedDate < @EndDate
ORDER BY DeletedDate DESC
```

---

## Pattern 3: Temporal Tables (Modern Approach)

### Use Case
- Automatic version history (no manual audit triggers)
- GDPR compliance with automatic timestamping
- Point-in-time queries ("what was the balance on 2026-05-15?")
- Minimal application code changes

### ✅ Correct Implementation

#### Schema (SQL Server 2016+)
```sql
CREATE TABLE Orders (
    OrderID INT PRIMARY KEY,
    CustomerID INT NOT NULL,
    Amount DECIMAL(10, 2),
    OrderDate DATETIME2,
    IsDeleted BIT NOT NULL DEFAULT 0,
    SysStartTime DATETIME2 GENERATED ALWAYS AS ROW START,
    SysEndTime DATETIME2 GENERATED ALWAYS AS ROW END,
    PERIOD FOR SYSTEM_TIME (SysStartTime, SysEndTime)
)
WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.Orders_History))
```

**What it does:**
- Every UPDATE/DELETE creates a historical record automatically
- `Orders` = current state
- `Orders_History` = all previous versions
- No application code needed for auditing

#### Delete Operation
```sql
-- Soft delete (looks same to application)
UPDATE Orders
SET IsDeleted = 1
WHERE OrderID = @OrderID
-- SQL Server automatically versioning the change
```

#### Point-in-Time Query
```sql
-- What was the order state on June 1, 2026 at 2pm?
SELECT OrderID, Amount, IsDeleted
FROM Orders
FOR SYSTEM_TIME AS OF '2026-06-01 14:00:00'
WHERE OrderID = @OrderID
```

#### Full Audit Trail
```sql
-- All versions of this order
SELECT 
    OrderID,
    Amount,
    IsDeleted,
    SysStartTime AS ChangedAt,
    SysEndTime AS UntilTime
FROM Orders
UNION ALL
SELECT 
    OrderID,
    Amount,
    IsDeleted,
    SysStartTime AS ChangedAt,
    SysEndTime AS UntilTime
FROM Orders_History
WHERE OrderID = @OrderID
ORDER BY SysStartTime DESC
```

---

## Pattern 4: Archive Table (High-Volume Deletion)

### Use Case
- Need to delete millions of old records (performance)
- Want to preserve data in separate archive
- Compliance requires keeping deleted data accessible but separate

### ✅ Correct Implementation

#### Schema
```sql
-- Active table (hot)
CREATE TABLE Orders (
    OrderID INT PRIMARY KEY,
    CustomerID INT NOT NULL,
    Amount DECIMAL(10, 2),
    OrderDate DATETIME2,
    IsDeleted BIT NOT NULL DEFAULT 0
)

-- Archive table (cold storage)
CREATE TABLE Orders_Archive (
    OrderID INT PRIMARY KEY,
    CustomerID INT NOT NULL,
    Amount DECIMAL(10, 2),
    OrderDate DATETIME2,
    IsDeleted BIT NOT NULL DEFAULT 0,
    ArchivedDate DATETIME2 NOT NULL,
    INDEX IX_Archive_ArchivedDate (ArchivedDate)
)
```

#### Bulk Delete with Archive
```sql
CREATE OR ALTER PROCEDURE sp_ArchiveOldOrders
    @CutoffDate DATETIME2  -- Delete orders before this date
AS
BEGIN
    SET NOCOUNT ON
    SET XACT_ABORT ON
    
    BEGIN TRY
        BEGIN TRANSACTION
        
        -- Move old orders to archive
        INSERT INTO Orders_Archive (OrderID, CustomerID, Amount, OrderDate, IsDeleted, ArchivedDate)
        SELECT OrderID, CustomerID, Amount, OrderDate, IsDeleted, GETDATE()
        FROM Orders
        WHERE OrderDate < @CutoffDate
          AND IsDeleted = 0
        
        -- Mark as archived in active table
        UPDATE Orders
        SET IsDeleted = 1
        WHERE OrderDate < @CutoffDate
          AND IsDeleted = 0
        
        -- Or physically remove from hot table (optional)
        DELETE FROM Orders
        WHERE OrderDate < @CutoffDate
          AND IsDeleted = 1
        
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION
        THROW
    END CATCH
END
```

#### Query Archive
```sql
-- Search in archive
SELECT OrderID, CustomerID, Amount, ArchivedDate
FROM Orders_Archive
WHERE CustomerID = @CustomerID
ORDER BY ArchivedDate DESC
```

---

## Pattern 5: Hard Delete with Backup (Safest Approach)

### Use Case
- Absolute compliance requirement to remove data (GDPR right-to-be-forgotten)
- But still need proof it was deleted
- Need to recover if deletion was a mistake

### ✅ Correct Implementation

#### Schema
```sql
CREATE TABLE Orders (
    OrderID INT PRIMARY KEY,
    CustomerID INT NOT NULL,
    Amount DECIMAL(10, 2),
    OrderDate DATETIME2
)

-- Backup before hard delete
CREATE TABLE Orders_DeletedBackup (
    OrderID INT PRIMARY KEY,
    CustomerID INT NOT NULL,
    Amount DECIMAL(10, 2),
    OrderDate DATETIME2,
    DeletedDate DATETIME2,
    DeletedByUser NVARCHAR(128),
    DeletedReason NVARCHAR(100)
)
```

#### Safe Hard Delete
```sql
CREATE OR ALTER PROCEDURE sp_PermanentlyDeleteOrder
    @OrderID INT,
    @Reason NVARCHAR(100)  -- Legal hold reason, GDPR request, fraud, etc.
AS
BEGIN
    SET NOCOUNT ON
    SET XACT_ABORT ON
    
    BEGIN TRY
        BEGIN TRANSACTION
        
        -- 1. Backup the record FIRST
        INSERT INTO Orders_DeletedBackup
        SELECT OrderID, CustomerID, Amount, OrderDate,
               GETDATE(), SUSER_NAME(), @Reason
        FROM Orders
        WHERE OrderID = @OrderID
        
        -- 2. Verify backup worked
        IF @@ROWCOUNT = 0
            THROW 50001, 'No record to delete', 1
        
        -- 3. Now delete (with verification)
        DELETE FROM Orders
        WHERE OrderID = @OrderID
        
        -- 4. Log the deletion
        INSERT INTO DeletionLog (OrderID, Action, DeletedDate, Reason)
        VALUES (@OrderID, 'HARD_DELETE', GETDATE(), @Reason)
        
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION
        THROW
    END CATCH
END
```

#### Proof of Deletion (Compliance)
```sql
-- Show deleted records with proof
SELECT OrderID, DeletedDate, DeletedByUser, DeletedReason
FROM Orders_DeletedBackup
WHERE DeletedDate >= @DateRequested
ORDER BY DeletedDate DESC
```

---

## Production Considerations

### Performance
| Pattern | Read Performance | Storage | Compliance |
|---------|-----------------|---------|-----------|
| IsDeleted | Excellent (filtered index) | Minimal overhead | ⭐⭐ |
| IsDeleted + Audit | Excellent | +audit table | ⭐⭐⭐⭐ |
| Temporal Tables | Excellent | +history table (automatic) | ⭐⭐⭐⭐⭐ |
| Archive Table | Excellent (hot/cold separation) | Separate storage | ⭐⭐⭐ |
| Hard Delete + Backup | Good | Backup overhead | ⭐⭐⭐⭐⭐ |

### Compliance & Recovery
- **GDPR:** Use Temporal Tables or Hard Delete + Backup (proof required)
- **Financial:** Temporal Tables (automatic audit trail)
- **Healthcare:** Temporal Tables (HIPAA requires timestamped changes)
- **eCommerce:** IsDeleted + Audit (customer service recovery)

### Index Maintenance
```sql
-- Critical: Filtered indexes on IsDeleted = 0
-- Saves 40-60% space for soft-deleted systems

CREATE INDEX IX_Orders_Active 
ON Orders(CustomerID, OrderDate) 
WHERE IsDeleted = 0
```

### Query Filter Discipline
```sql
-- ❌ ANTI-PATTERN: Forgetting IsDeleted filter
SELECT * FROM Orders WHERE CustomerID = 1

-- ✅ CORRECT: Always filter in views
CREATE VIEW dbo.vw_ActiveOrders AS
SELECT * FROM Orders WHERE IsDeleted = 0

-- Application uses views, not tables directly
SELECT * FROM dbo.vw_ActiveOrders WHERE CustomerID = 1
```

---

## Common Mistakes

### ❌ Mistake 1: Forgetting to Filter in Reports
```sql
-- Wrong: Shows deleted orders too
SELECT COUNT(*) AS TotalOrders FROM Orders

-- Correct: Only active
SELECT COUNT(*) AS ActiveOrders FROM Orders WHERE IsDeleted = 0
```

### ❌ Mistake 2: No Filtered Index
```sql
-- Creates index on 95% deleted records = wasteful
CREATE INDEX IX_Orders_IsDeleted ON Orders(IsDeleted)

-- Correct: Only index active records
CREATE INDEX IX_Orders_IsDeleted ON Orders(IsDeleted) WHERE IsDeleted = 0
```

### ❌ Mistake 3: Losing Deletion Reason
```sql
-- Hard to know *why* it was deleted later
UPDATE Orders SET IsDeleted = 1 WHERE OrderID = @ID

-- Always capture context
UPDATE Orders 
SET IsDeleted = 1, DeletedReason = 'USER_REQUEST', DeletedDate = GETDATE()
WHERE OrderID = @ID
```

### ❌ Mistake 4: Temporal Table Without Understanding
```sql
-- Creates history but doesn't check if user has permission to view it
SELECT * FROM Orders FOR SYSTEM_TIME ALL WHERE OrderID = @ID

-- Secure historical access
CREATE VIEW vw_OrderHistory AS
SELECT * FROM Orders 
FOR SYSTEM_TIME BETWEEN @StartDate AND @EndDate
WHERE OrderID IN (
    SELECT OrderID FROM Orders 
    WHERE CustomerID = @AuthorizedCustomerID
)
```

---

## Decision Tree: Which Pattern?

```
START: "I need to delete data"
│
├─ "Do I need to comply with regulations (GDPR, HIPAA, SOX)?"
│  ├─ YES → Use Temporal Tables (automatic audit)
│  └─ NO → Continue
│
├─ "Do I need to track WHO deleted and WHEN?"
│  ├─ YES → IsDeleted + Audit Trail
│  └─ NO → Continue
│
├─ "Do I have millions of old records to archive?"
│  ├─ YES → Archive Table pattern
│  └─ NO → Simple IsDeleted flag
│
└─ "Do I need legal proof of hard deletion (GDPR right-to-be-forgotten)?"
   ├─ YES → Hard Delete + Backup
   └─ NO → Soft delete (IsDeleted)
```

---

## References
- `[[audit_trail_patterns]]` — Advanced tracking with Temporal Tables
- `[[transaction_management]]` — Transaction safety during deletion
- `references/auditing_guide.md` — Compliance and audit strategies
- `references/common_pitfalls.md` — Deletion mistakes to avoid

