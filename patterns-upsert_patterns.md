---
name: upsert-patterns
description: Enterprise upsert patterns — MERGE vs UPDATE+INSERT decision tree, reliability trade-offs, performance considerations, atomic operations
---

# Upsert Patterns — Insert or Update Strategy

## Overview

**Upsert = INSERT if new, UPDATE if exists**

**Why it's complex:**
- MERGE statement is tempting (one line = simple)
- But MERGE has subtle failure modes (atomicity, reliability)
- Explicit UPDATE+INSERT is safer, clearer, more maintainable
- Performance is actually comparable in most cases

**This pattern determines:**
- Data consistency (will all or nothing apply?)
- Code clarity (will future devs understand?)
- Debugging difficulty (when it breaks, how easy to fix?)

---

## Anti-Pattern: Naive MERGE (❌ Don't Do This)

### The Problem
```sql
-- Looks simple...
MERGE INTO TargetTable t
USING SourceTable s
ON t.ID = s.ID
WHEN MATCHED THEN UPDATE SET t.Name = s.Name
WHEN NOT MATCHED THEN INSERT (ID, Name) VALUES (s.ID, s.Name)

-- But has hidden failure modes:
-- 1. If source has duplicates, MERGE may fail mysteriously
-- 2. If UPDATE fails mid-way, no partial rollback
-- 3. If triggers exist, behavior is unpredictable
-- 4. Debugging is hard (can't single-step MERGE)
```

### Real-World Incident
```
Timeline:
  Dev: "Let's use MERGE for performance"
  Prod deployment: Works fine for 2 weeks
  New data arrives: Source table has duplicate IDs
  MERGE fails: "Violation of PRIMARY KEY constraint"
  Result: Entire batch job stops
  Investigation: "Why does MERGE care about duplicates in source?"
  
Root cause: MERGE assumes source is unique
  Explicit UPDATE+INSERT would have handled it gracefully
```

---

## Decision Tree: Which Pattern?

```
START: "I need to upsert data"
│
├─ "Do I have duplicates in source data?"
│  ├─ YES → Use UPDATE+INSERT (MERGE fails on duplicates)
│  └─ NO → Continue
│
├─ "Do I need to track what changed (for audit)?"
│  ├─ YES → Use UPDATE+INSERT (can log separately)
│  └─ NO → Continue
│
├─ "Is performance critical (millions of rows)?"
│  ├─ YES → Benchmark both, usually similar
│  └─ NO → Use UPDATE+INSERT (clarity wins)
│
├─ "Is the entire operation all-or-nothing?"
│  ├─ YES → MERGE (single statement = atomic)
│  └─ NO → UPDATE+INSERT is fine
│
└─ "Do I need ALL 3 MERGE conditions (MATCHED, NOT MATCHED, NOT MATCHED BY SOURCE)?"
   ├─ YES → MERGE is justified
   └─ NO → Use UPDATE+INSERT (simpler, more reliable)
```

---

## Pattern 1: Explicit UPDATE + INSERT (Recommended)

### Use Case
- Most upsert scenarios
- Source data quality is uncertain
- Debugging and maintainability matter
- Audit trail required

### ✅ Correct Implementation

#### Schema
```sql
CREATE TABLE Employees (
    EmployeeID INT PRIMARY KEY,
    Name NVARCHAR(100) NOT NULL,
    Department NVARCHAR(50),
    Salary DECIMAL(10, 2),
    LastUpdated DATETIME2
)

CREATE TABLE Employees_Staging (
    EmployeeID INT,
    Name NVARCHAR(100),
    Department NVARCHAR(50),
    Salary DECIMAL(10, 2)
)
```

#### Procedure: Safe Upsert
```sql
CREATE OR ALTER PROCEDURE sp_UpsertEmployee
    @EmployeeID INT,
    @Name NVARCHAR(100),
    @Department NVARCHAR(50),
    @Salary DECIMAL(10, 2)
AS
BEGIN
    SET NOCOUNT ON
    SET XACT_ABORT ON
    
    BEGIN TRY
        BEGIN TRANSACTION
        
        -- Step 1: Try to UPDATE existing record
        UPDATE Employees
        SET Name = @Name,
            Department = @Department,
            Salary = @Salary,
            LastUpdated = GETDATE()
        WHERE EmployeeID = @EmployeeID
        
        -- Step 2: If nothing was updated, INSERT instead
        IF @@ROWCOUNT = 0
        BEGIN
            INSERT INTO Employees (EmployeeID, Name, Department, Salary, LastUpdated)
            VALUES (@EmployeeID, @Name, @Department, @Salary, GETDATE())
        END
        
        COMMIT TRANSACTION
        RETURN 0
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION
        THROW
    END CATCH
END
```

#### Bulk Upsert from Staging
```sql
CREATE OR ALTER PROCEDURE sp_UpsertEmployeesFromStaging
AS
BEGIN
    SET NOCOUNT ON
    SET XACT_ABORT ON
    
    BEGIN TRY
        BEGIN TRANSACTION
        
        -- Step 1: Check for duplicates in staging
        IF EXISTS (
            SELECT 1 FROM Employees_Staging
            GROUP BY EmployeeID
            HAVING COUNT(*) > 1
        )
            THROW 50001, 'Duplicate EmployeeIDs in staging table', 1
        
        -- Step 2: Update existing employees
        UPDATE e
        SET e.Name = s.Name,
            e.Department = s.Department,
            e.Salary = s.Salary,
            e.LastUpdated = GETDATE()
        FROM Employees e
        INNER JOIN Employees_Staging s ON e.EmployeeID = s.EmployeeID
        WHERE e.Name != s.Name
           OR e.Department != s.Department
           OR e.Salary != s.Salary
        
        DECLARE @UpdateCount INT = @@ROWCOUNT
        
        -- Step 3: Insert new employees (not in main table)
        INSERT INTO Employees (EmployeeID, Name, Department, Salary, LastUpdated)
        SELECT EmployeeID, Name, Department, Salary, GETDATE()
        FROM Employees_Staging s
        WHERE NOT EXISTS (
            SELECT 1 FROM Employees e 
            WHERE e.EmployeeID = s.EmployeeID
        )
        
        DECLARE @InsertCount INT = @@ROWCOUNT
        
        -- Step 4: Log the operation
        INSERT INTO UpsertLog (TableName, RecordsUpdated, RecordsInserted, UpsertDate)
        VALUES ('Employees', @UpdateCount, @InsertCount, GETDATE())
        
        COMMIT TRANSACTION
        
        -- Return summary
        SELECT 
            'SUCCESS' AS Status,
            @UpdateCount AS RecordsUpdated,
            @InsertCount AS RecordsInserted
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION
        
        INSERT INTO ErrorLog (ErrorNumber, ErrorMessage, ProcedureName, ErrorDate)
        VALUES (ERROR_NUMBER(), ERROR_MESSAGE(), 'sp_UpsertEmployeesFromStaging', GETDATE())
        
        THROW
    END CATCH
END
```

#### Advantages
```
✅ Clear logic (everyone understands UPDATE then INSERT)
✅ Handles duplicate source data gracefully
✅ Can log separately (UPDATE log + INSERT log)
✅ Easy to debug (step through each part)
✅ Transaction integrity clear (all or nothing)
✅ @@ROWCOUNT tells us what happened
```

---

## Pattern 2: MERGE When Justified

### Use Case
- All 3 MERGE conditions are needed (MATCHED, NOT MATCHED, NOT MATCHED BY SOURCE)
- Performance is critical (rare)
- Source data guaranteed unique
- Atomicity at statement level is required

### ✅ Correct Implementation

#### Example: Inventory Sync
```sql
CREATE TABLE Inventory (
    ProductID INT PRIMARY KEY,
    QuantityOnHand INT,
    QuantityReserved INT,
    LastSyncDate DATETIME2
)

CREATE TABLE InventorySource (
    ProductID INT,
    NewQuantity INT
)

-- MERGE justified here because:
-- 1. Need to UPDATE existing (MATCHED)
-- 2. Need to INSERT new (NOT MATCHED)
-- 3. Need to DEACTIVATE discontinued (NOT MATCHED BY SOURCE)
-- All 3 conditions are critical
```

#### MERGE Procedure (Safe Version)
```sql
CREATE OR ALTER PROCEDURE sp_SyncInventory
AS
BEGIN
    SET NOCOUNT ON
    SET XACT_ABORT ON
    
    BEGIN TRY
        -- Validate source first
        IF EXISTS (
            SELECT 1 FROM InventorySource
            GROUP BY ProductID
            HAVING COUNT(*) > 1
        )
            THROW 50001, 'Duplicate ProductIDs in source', 1
        
        BEGIN TRANSACTION
        
        MERGE INTO Inventory i
        USING InventorySource s
        ON i.ProductID = s.ProductID
        WHEN MATCHED THEN 
            UPDATE SET 
                i.QuantityOnHand = s.NewQuantity,
                i.LastSyncDate = GETDATE()
        WHEN NOT MATCHED THEN 
            INSERT (ProductID, QuantityOnHand, QuantityReserved, LastSyncDate)
            VALUES (s.ProductID, s.NewQuantity, 0, GETDATE())
        WHEN NOT MATCHED BY SOURCE THEN
            UPDATE SET i.QuantityOnHand = 0  -- Or DELETE
        
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION
        THROW
    END CATCH
END

-- Output row counts
SET STATISTICS TIME ON
EXEC sp_SyncInventory
SET STATISTICS TIME OFF
```

#### Cautions with MERGE
```sql
-- ❌ MERGE pitfall #1: Duplicate source causes mysterious error
MERGE INTO Inventory i
USING (SELECT 1 ProductID UNION ALL SELECT 1 ProductID) s  -- Duplicate!
ON i.ProductID = s.ProductID
-- Error: "Violation of PRIMARY KEY constraint"
-- Why? MERGE assumes source is unique

-- ✅ Fix: Validate or deduplicate source
MERGE INTO Inventory i
USING (SELECT DISTINCT ProductID FROM InventorySource) s
ON i.ProductID = s.ProductID
WHEN MATCHED THEN UPDATE SET i.LastSyncDate = GETDATE()

-- ❌ MERGE pitfall #2: With triggers, behavior unpredictable
-- If Inventory has UPDATE trigger, MERGE UPDATE and trigger interact strangely

-- ✅ Fix: Disable triggers or avoid MERGE if triggers exist
DISABLE TRIGGER ALL ON Inventory
MERGE INTO Inventory i
USING InventorySource s
ON i.ProductID = s.ProductID
WHEN MATCHED THEN UPDATE SET i.QuantityOnHand = s.NewQuantity
ENABLE TRIGGER ALL ON Inventory
```

---

## Pattern 3: MERGE with Output Clause (Tracking Changes)

### Use Case
- Need to track what was inserted vs updated
- Audit requirement (what changed?)
- Separate handling of INSERT vs UPDATE

### ✅ Correct Implementation

#### Schema
```sql
CREATE TABLE Products (
    ProductID INT PRIMARY KEY,
    Name NVARCHAR(100),
    Price DECIMAL(10, 2)
)

CREATE TABLE ProductAudit (
    AuditID BIGINT PRIMARY KEY IDENTITY(1, 1),
    ProductID INT,
    Action NVARCHAR(10),  -- INSERT, UPDATE
    OldPrice DECIMAL(10, 2),
    NewPrice DECIMAL(10, 2),
    ActionDate DATETIME2
)
```

#### MERGE with OUTPUT
```sql
CREATE OR ALTER PROCEDURE sp_UpsertProductsWithAudit
    @SourceTableName NVARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON
    SET XACT_ABORT ON
    
    BEGIN TRY
        BEGIN TRANSACTION
        
        -- Declare output table to capture changes
        DECLARE @MergeOutput TABLE (
            Action NVARCHAR(10),
            ProductID INT,
            OldPrice DECIMAL(10, 2),
            NewPrice DECIMAL(10, 2)
        )
        
        -- MERGE with OUTPUT
        MERGE INTO Products p
        USING (SELECT ProductID, Name, Price FROM ProductSource) s
        ON p.ProductID = s.ProductID
        WHEN MATCHED THEN
            UPDATE SET 
                p.Name = s.Name,
                p.Price = s.Price
        WHEN NOT MATCHED THEN
            INSERT (ProductID, Name, Price)
            VALUES (s.ProductID, s.Name, s.Price)
        OUTPUT $action, inserted.ProductID, deleted.Price, inserted.Price
        INTO @MergeOutput
        
        -- Log changes to audit table
        INSERT INTO ProductAudit (ProductID, Action, OldPrice, NewPrice, ActionDate)
        SELECT ProductID, Action, OldPrice, NewPrice, GETDATE()
        FROM @MergeOutput
        
        COMMIT TRANSACTION
        
        -- Report what happened
        SELECT 
            Action,
            COUNT(*) AS Count
        FROM @MergeOutput
        GROUP BY Action
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION
        THROW
    END CATCH
END
```

---

## Pattern 4: Conditional Upsert (Update Only If Changed)

### Use Case
- Avoid unnecessary updates (triggers, audit bloat)
- Only update if values actually changed
- Performance optimization

### ✅ Correct Implementation

```sql
CREATE OR ALTER PROCEDURE sp_UpsertOnlyIfChanged
    @EmployeeID INT,
    @Name NVARCHAR(100),
    @Salary DECIMAL(10, 2)
AS
BEGIN
    SET NOCOUNT ON
    SET XACT_ABORT ON
    
    BEGIN TRY
        BEGIN TRANSACTION
        
        DECLARE @Exists BIT
        DECLARE @OldName NVARCHAR(100)
        DECLARE @OldSalary DECIMAL(10, 2)
        
        -- Check if exists and get current values
        SELECT @Exists = 1, @OldName = Name, @OldSalary = Salary
        FROM Employees
        WHERE EmployeeID = @EmployeeID
        
        IF @Exists IS NULL
        BEGIN
            -- Insert (new record)
            INSERT INTO Employees (EmployeeID, Name, Salary, LastUpdated)
            VALUES (@EmployeeID, @Name, @Salary, GETDATE())
            
            INSERT INTO ChangeLog (EmployeeID, ChangeType, ActionDate)
            VALUES (@EmployeeID, 'INSERT', GETDATE())
        END
        ELSE
        BEGIN
            -- Update ONLY if something changed
            IF @Name != @OldName OR @Salary != @OldSalary
            BEGIN
                UPDATE Employees
                SET Name = @Name,
                    Salary = @Salary,
                    LastUpdated = GETDATE()
                WHERE EmployeeID = @EmployeeID
                
                INSERT INTO ChangeLog (EmployeeID, ChangeType, ActionDate)
                VALUES (@EmployeeID, 'UPDATE', GETDATE())
            END
            -- If nothing changed, log it but don't update
            ELSE
            BEGIN
                INSERT INTO ChangeLog (EmployeeID, ChangeType, ActionDate)
                VALUES (@EmployeeID, 'NO_CHANGE', GETDATE())
            END
        END
        
        COMMIT TRANSACTION
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

| Approach | Source Size | Performance | Reliability | Clarity |
|----------|-------------|-------------|-----------|---------|
| UPDATE+INSERT | 10K rows | 🟢 Good | 🟢 Excellent | 🟢 Excellent |
| UPDATE+INSERT | 1M rows | 🟡 Fair | 🟢 Excellent | 🟢 Excellent |
| MERGE | 10K rows | 🟢 Good | 🟡 Fair | 🟡 Fair |
| MERGE | 1M rows | 🟢 Good | 🟡 Fair | 🟡 Fair |
| MERGE (justified) | Any | 🟢 Good | 🟢 Excellent* | 🟡 Fair |

*When all 3 conditions used + no triggers + unique source

---

## Common Mistakes

### ❌ Mistake 1: MERGE with Duplicates
```sql
-- Will fail on duplicate source
MERGE INTO Target t
USING (SELECT ID FROM Source) s
ON t.ID = s.ID
WHEN MATCHED THEN UPDATE SET t.Value = 100

-- ✅ Fix: Deduplicate source
MERGE INTO Target t
USING (SELECT DISTINCT ID FROM Source) s
ON t.ID = s.ID
WHEN MATCHED THEN UPDATE SET t.Value = 100
```

### ❌ Mistake 2: Forgetting @@ROWCOUNT
```sql
-- Don't know if we updated or inserted
UPDATE Target SET Value = 100 WHERE ID = @ID
INSERT INTO Target VALUES (@ID, 100)

-- ✅ Fix: Check @@ROWCOUNT
UPDATE Target SET Value = 100 WHERE ID = @ID
IF @@ROWCOUNT = 0
    INSERT INTO Target VALUES (@ID, 100)
```

### ❌ Mistake 3: MERGE Without Validation
```sql
-- MERGE fails mysteriously on duplicate source
MERGE INTO Inventory i
USING InventorySource s
ON i.ProductID = s.ProductID
WHEN MATCHED THEN UPDATE SET i.Quantity = s.Quantity

-- ✅ Fix: Validate first
IF EXISTS (SELECT 1 FROM InventorySource GROUP BY ProductID HAVING COUNT(*) > 1)
    THROW 50001, 'Duplicate products in source', 1

MERGE INTO Inventory i
-- ... rest of MERGE
```

---

## Best Practices

### 1. Always Validate Source Data First
```sql
IF EXISTS (SELECT 1 FROM @Source GROUP BY ID HAVING COUNT(*) > 1)
    THROW 50001, 'Source has duplicates', 1
```

### 2. Use Explicit Transactions
```sql
BEGIN TRANSACTION
    -- Upsert logic
COMMIT TRANSACTION
```

### 3. Log What Happened
```sql
INSERT INTO ChangeLog (RecordsUpdated, RecordsInserted, ActionDate)
VALUES (@UpdateCount, @InsertCount, GETDATE())
```

### 4. Default to UPDATE+INSERT
```sql
-- Unless you have ALL 3 MERGE conditions, use this pattern
UPDATE Target SET ...
IF @@ROWCOUNT = 0
    INSERT INTO Target VALUES ...
```

---

## References
- `[[soft_delete_patterns]]` — Handling updates with deletion flags
- `[[data_validation_tests]]` — Testing upsert logic
- `references/transaction_management.md` — Transaction safety in upserts
- `references/etl_migration_patterns.md` — Bulk upsert scenarios

