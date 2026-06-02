---
name: data-validation-tests
description: SQL Server data validation testing strategies — null checks, referential integrity, constraint enforcement, and data quality assertions
---

# Data Validation Testing — Enterprise Quality Assurance

## Overview

**Why it matters:** Most bugs in data systems aren't syntax errors (SQL Server catches those). They're *logic* errors:
- Missing NOT NULL constraint → NULLs slip in → CASE expressions fail
- Foreign key missing → Orphan records → Reports sum wrong amounts
- CHECK constraint not enforced → Negative inventory → Accounting broken
- Duplicate entries → Double billing → Customer complaints

**What we're testing:** Data rules, not T-SQL syntax.

---

## Anti-Pattern: No Testing (❌ Don't Do This)

### The Problem
```sql
-- Deploy code with "looks right" logic
CREATE TABLE Orders (
    OrderID INT PRIMARY KEY,
    CustomerID INT,
    Amount DECIMAL(10, 2)
    -- Missing: FK, CHECK, NOT NULL constraints
)

-- Insert data hoping it's valid
INSERT INTO Orders VALUES (1, NULL, -50)  -- ← This will cause problems!

-- Report queries return wrong results
SELECT SUM(Amount) FROM Orders  -- Negatives shouldn't exist
```

### Real-World Incident
```
Timeline:
  Monday: New Orders table deployed (no constraints)
  Tuesday: Overnight batch accidentally inserts 10K orphan records
  Wednesday: Reports show $2M revenue spike (wrong!)
  Thursday: Finance notices discrepancy
  Friday: 3-day investigation + manual data cleanup
  Cost: ~$50K + reputation damage

Root cause: No validation tests before deployment
```

---

## Test Pattern 1: Constraint Enforcement Testing

### Use Case
- Verify that table constraints actually work
- Catch missing NOT NULL, PRIMARY KEY, FK definitions
- Foundation before writing application logic

### ✅ Correct Implementation

#### Schema Under Test
```sql
CREATE TABLE Customers (
    CustomerID INT PRIMARY KEY,
    Name NVARCHAR(100) NOT NULL,
    Email NVARCHAR(255) UNIQUE NOT NULL,
    Balance DECIMAL(10, 2) NOT NULL CHECK (Balance >= 0)
)

CREATE TABLE Orders (
    OrderID INT PRIMARY KEY,
    CustomerID INT NOT NULL,
    Amount DECIMAL(10, 2) NOT NULL CHECK (Amount > 0),
    OrderDate DATETIME2 NOT NULL,
    FOREIGN KEY (CustomerID) REFERENCES Customers(CustomerID)
)
```

#### Test Suite: Constraint Violations
```sql
-- Test 1: PRIMARY KEY Enforcement
-- ❌ Duplicate primary key should fail
BEGIN TRY
    INSERT INTO Customers VALUES (1, 'Alice', 'alice@example.com', 0)
    INSERT INTO Customers VALUES (1, 'Bob', 'bob@example.com', 0)  -- Duplicate!
    PRINT 'FAIL: PK constraint not enforced'
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 2627  -- PK violation
        PRINT 'PASS: PK constraint enforced'
    ELSE
        PRINT 'UNEXPECTED: ' + ERROR_MESSAGE()
END CATCH

-- Cleanup
DELETE FROM Customers WHERE CustomerID = 1

-- Test 2: NOT NULL Enforcement
BEGIN TRY
    INSERT INTO Customers (CustomerID, Email, Balance)  -- Missing Name
    VALUES (2, 'test@example.com', 0)
    PRINT 'FAIL: NOT NULL not enforced'
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 515  -- NULL in NOT NULL column
        PRINT 'PASS: NOT NULL enforced'
    ELSE
        PRINT 'UNEXPECTED: ' + ERROR_MESSAGE()
END CATCH

-- Test 3: UNIQUE Constraint
BEGIN TRY
    INSERT INTO Customers VALUES (3, 'Charlie', 'duplicate@example.com', 0)
    INSERT INTO Customers VALUES (4, 'David', 'duplicate@example.com', 0)  -- Duplicate email!
    PRINT 'FAIL: UNIQUE constraint not enforced'
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 2627  -- UNIQUE violation
        PRINT 'PASS: UNIQUE constraint enforced'
END CATCH

-- Test 4: CHECK Constraint
BEGIN TRY
    INSERT INTO Customers VALUES (5, 'Eve', 'eve@example.com', -100)  -- Negative balance!
    PRINT 'FAIL: CHECK constraint not enforced'
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 547  -- CHECK violation
        PRINT 'PASS: CHECK constraint enforced'
END CATCH

-- Test 5: FOREIGN KEY Enforcement
BEGIN TRY
    INSERT INTO Orders VALUES (1, 999, 100, GETDATE())  -- FK doesn't exist!
    PRINT 'FAIL: FK constraint not enforced'
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 547  -- FK violation
        PRINT 'PASS: FK constraint enforced'
END CATCH
```

---

## Test Pattern 2: Data Quality Assertions

### Use Case
- Verify business logic constraints (e.g., negative inventory shouldn't exist)
- Check calculated fields are correct
- Validate relationships between tables

### ✅ Correct Implementation

#### Schema
```sql
CREATE TABLE Inventory (
    ProductID INT PRIMARY KEY,
    QuantityOnHand INT NOT NULL CHECK (QuantityOnHand >= 0),
    ReservedQuantity INT NOT NULL CHECK (ReservedQuantity >= 0),
    AvailableQuantity AS (QuantityOnHand - ReservedQuantity) PERSISTED
)

CREATE TABLE OrderDetails (
    OrderDetailID INT PRIMARY KEY,
    ProductID INT NOT NULL,
    Quantity INT NOT NULL CHECK (Quantity > 0),
    UnitPrice DECIMAL(10, 2) NOT NULL CHECK (UnitPrice > 0),
    LineTotal AS (Quantity * UnitPrice) PERSISTED,
    FOREIGN KEY (ProductID) REFERENCES Inventory(ProductID)
)

CREATE TABLE Orders (
    OrderID INT PRIMARY KEY,
    OrderTotal AS (
        SELECT SUM(LineTotal) 
        FROM OrderDetails 
        WHERE OrderDetails.OrderID = Orders.OrderID
    ) PERSISTED
)
```

#### Test Suite: Data Quality
```sql
-- Setup test data
INSERT INTO Inventory VALUES (1, 100, 0)  -- 100 in stock, 0 reserved
INSERT INTO OrderDetails VALUES (1, 1, 50, 10)  -- Order 50 @ $10

-- Test 1: Calculated column correctness
DECLARE @LineTotal DECIMAL(10, 2)
SELECT @LineTotal = LineTotal FROM OrderDetails WHERE OrderDetailID = 1

IF @LineTotal = 500
    PRINT 'PASS: LineTotal (50 * 10) = 500'
ELSE
    PRINT 'FAIL: LineTotal should be 500, got ' + CAST(@LineTotal AS VARCHAR(10))

-- Test 2: Inventory never goes negative
BEGIN TRY
    UPDATE Inventory 
    SET ReservedQuantity = 150  -- More than available!
    WHERE ProductID = 1
    
    IF (SELECT ReservedQuantity FROM Inventory WHERE ProductID = 1) > 100
        PRINT 'FAIL: ReservedQuantity exceeds QuantityOnHand'
    ELSE
        PRINT 'PASS: Inventory validation passed'
END TRY
BEGIN CATCH
    PRINT 'PASS: CHECK constraint prevented negative inventory'
END CATCH

-- Reset
UPDATE Inventory SET ReservedQuantity = 0 WHERE ProductID = 1

-- Test 3: Available quantity calculation
DECLARE @Available INT
SELECT @Available = AvailableQuantity FROM Inventory WHERE ProductID = 1

IF @Available = 100
    PRINT 'PASS: Available (100 - 0) = 100'
ELSE
    PRINT 'FAIL: Available should be 100, got ' + CAST(@Available AS VARCHAR(10))

-- Test 4: No orphan order details
INSERT INTO OrderDetails VALUES (2, 999, 10, 15)  -- ProductID 999 doesn't exist
PRINT 'FAIL: FK constraint not enforced (orphan created)'

-- Reset
DELETE FROM OrderDetails WHERE OrderDetailID = 2
```

---

## Test Pattern 3: Referential Integrity Testing

### Use Case
- Verify foreign key relationships
- Check CASCADE behavior (UPDATE, DELETE cascades)
- Validate orphan prevention

### ✅ Correct Implementation

#### Schema with CASCADE
```sql
CREATE TABLE Customers (
    CustomerID INT PRIMARY KEY,
    Name NVARCHAR(100) NOT NULL
)

CREATE TABLE Orders (
    OrderID INT PRIMARY KEY,
    CustomerID INT NOT NULL,
    OrderDate DATETIME2,
    FOREIGN KEY (CustomerID) REFERENCES Customers(CustomerID) ON DELETE CASCADE
)

CREATE TABLE OrderDetails (
    OrderDetailID INT PRIMARY KEY,
    OrderID INT NOT NULL,
    ProductID INT NOT NULL,
    Quantity INT,
    FOREIGN KEY (OrderID) REFERENCES Orders(OrderID) ON DELETE CASCADE
)
```

#### Test Suite: Referential Integrity
```sql
-- Setup
INSERT INTO Customers VALUES (1, 'Alice')
INSERT INTO Orders VALUES (1, 1, GETDATE())
INSERT INTO OrderDetails VALUES (1, 1, 10, 5)

-- Test 1: Verify FK relationship exists
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS
    WHERE TABLE_NAME = 'Orders' AND CONSTRAINT_NAME LIKE 'FK%'
)
    PRINT 'FAIL: Foreign key not defined on Orders.CustomerID'
ELSE
    PRINT 'PASS: Foreign key defined on Orders.CustomerID'

-- Test 2: Orphan prevention
BEGIN TRY
    INSERT INTO Orders VALUES (2, 999, GETDATE())  -- FK 999 doesn't exist
    PRINT 'FAIL: FK constraint not enforced'
END TRY
BEGIN CATCH
    PRINT 'PASS: FK constraint prevented orphan'
END CATCH

-- Test 3: CASCADE DELETE behavior
DELETE FROM Customers WHERE CustomerID = 1

DECLARE @OrderCount INT, @DetailCount INT
SELECT @OrderCount = COUNT(*) FROM Orders WHERE CustomerID = 1
SELECT @DetailCount = COUNT(*) FROM OrderDetails WHERE OrderID = 1

IF @OrderCount = 0 AND @DetailCount = 0
    PRINT 'PASS: CASCADE DELETE removed all dependent records'
ELSE
    PRINT 'FAIL: Orphan records remain after CASCADE'

-- Cleanup
DELETE FROM Customers WHERE CustomerID = 1
DELETE FROM Orders WHERE OrderID = 1
DELETE FROM OrderDetails WHERE OrderDetailID = 1
```

---

## Test Pattern 4: Null Handling Testing

### Use Case
- Verify NULL handling doesn't break aggregations
- Test ISNULL/COALESCE behavior
- Catch unexpected NULLs in calculations

### ✅ Correct Implementation

#### Schema
```sql
CREATE TABLE Sales (
    SaleID INT PRIMARY KEY,
    Amount DECIMAL(10, 2),  -- Can be NULL for unknown amounts
    Commission DECIMAL(10, 2),  -- NULL if no commission
    Notes NVARCHAR(MAX)  -- NULL if no notes
)
```

#### Test Suite: NULL Handling
```sql
-- Setup
INSERT INTO Sales VALUES (1, 100, 10, 'Standard sale')
INSERT INTO Sales VALUES (2, 50, NULL, NULL)  -- No commission, no notes
INSERT INTO Sales VALUES (3, NULL, 5, 'Commission-only')  -- Amount unknown

-- Test 1: NULL in aggregation
DECLARE @TotalAmount DECIMAL(10, 2)
SELECT @TotalAmount = SUM(Amount) FROM Sales

-- NULL in SUM() is ignored, not treated as 0
IF @TotalAmount = 150  -- 100 + 50, NULL excluded
    PRINT 'PASS: SUM() correctly ignores NULLs'
ELSE
    PRINT 'FAIL: SUM() returned ' + CAST(@TotalAmount AS VARCHAR(20))

-- Test 2: COALESCE handles NULLs safely
DECLARE @Commission DECIMAL(10, 2)
SELECT @Commission = COALESCE(Commission, 0) FROM Sales WHERE SaleID = 2

IF @Commission = 0
    PRINT 'PASS: COALESCE(NULL, 0) = 0'
ELSE
    PRINT 'FAIL: COALESCE returned ' + CAST(@Commission AS VARCHAR(10))

-- Test 3: NULLs in WHERE clause
DECLARE @CountWithNotes INT
SELECT @CountWithNotes = COUNT(*) FROM Sales WHERE Notes IS NOT NULL

IF @CountWithNotes = 2
    PRINT 'PASS: IS NOT NULL correctly filters NULLs'
ELSE
    PRINT 'FAIL: Expected 2 non-null notes, got ' + CAST(@CountWithNotes AS VARCHAR(3))

-- Test 4: NULL <> NULL (important!)
IF (NULL = NULL)
    PRINT 'FAIL: NULL = NULL is true (shouldn''t be)'
ELSE
    PRINT 'PASS: NULL = NULL is unknown (correct)'

-- Cleanup
DELETE FROM Sales
```

---

## Test Pattern 5: Data Type & Range Testing

### Use Case
- Verify column types match expected ranges
- Test boundary conditions (min/max values)
- Catch silent truncation issues

### ✅ Correct Implementation

#### Schema
```sql
CREATE TABLE Products (
    ProductID INT PRIMARY KEY,
    Name NVARCHAR(100) NOT NULL,
    Price DECIMAL(10, 2) NOT NULL,
    StockQuantity TINYINT NOT NULL,  -- 0-255 max
    Rating DECIMAL(3, 1) CHECK (Rating >= 0 AND Rating <= 5)
)
```

#### Test Suite: Data Types
```sql
-- Test 1: DECIMAL precision (10,2 means max 99999999.99)
BEGIN TRY
    INSERT INTO Products VALUES (1, 'Expensive', 999999999.99, 1, 5)  -- Too large!
    PRINT 'FAIL: Decimal overflow not caught'
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 8115
        PRINT 'PASS: Decimal overflow caught'
END CATCH

-- Test 2: TINYINT range (0-255)
BEGIN TRY
    INSERT INTO Products VALUES (1, 'Product', 100, 256, 5)  -- 256 > 255!
    PRINT 'FAIL: TINYINT overflow not caught'
END TRY
BEGIN CATCH
    PRINT 'PASS: TINYINT overflow caught'
END CATCH

-- Test 3: NVARCHAR truncation warning
INSERT INTO Products VALUES (2, 'X', 50, 10, 4.5)
DECLARE @Name NVARCHAR(100)
SELECT @Name = Name FROM Products WHERE ProductID = 2
IF LEN(@Name) <= 100
    PRINT 'PASS: NVARCHAR(100) correctly limits length'
ELSE
    PRINT 'FAIL: NVARCHAR exceeded limit'

-- Test 4: CHECK constraint on range
BEGIN TRY
    INSERT INTO Products VALUES (3, 'Bad Rating', 50, 10, 6.0)  -- Rating > 5!
    PRINT 'FAIL: Rating CHECK constraint not enforced'
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 547
        PRINT 'PASS: Rating CHECK constraint enforced'
END CATCH

-- Cleanup
DELETE FROM Products
```

---

## Test Pattern 6: Data Consistency Testing

### Use Case
- Verify calculated fields stay in sync
- Check denormalized data consistency
- Validate totals match detail

### ✅ Correct Implementation

#### Schema
```sql
CREATE TABLE Orders (
    OrderID INT PRIMARY KEY,
    CustomerID INT NOT NULL,
    OrderDate DATETIME2,
    OrderTotal DECIMAL(10, 2) NOT NULL  -- Denormalized
)

CREATE TABLE OrderDetails (
    OrderDetailID INT PRIMARY KEY,
    OrderID INT NOT NULL,
    ProductID INT NOT NULL,
    Quantity INT NOT NULL CHECK (Quantity > 0),
    UnitPrice DECIMAL(10, 2) NOT NULL CHECK (UnitPrice > 0),
    LineTotal AS (Quantity * UnitPrice) PERSISTED,
    FOREIGN KEY (OrderID) REFERENCES Orders(OrderID)
)
```

#### Test Suite: Consistency
```sql
-- Setup
INSERT INTO Orders VALUES (1, 1, GETDATE(), 0)  -- Will update
INSERT INTO OrderDetails VALUES (1, 1, 10, 50, 10)
INSERT INTO OrderDetails VALUES (2, 1, 20, 25, 10)

-- Test: OrderTotal = SUM(LineTotal)
DECLARE @CalculatedTotal DECIMAL(10, 2)
SELECT @CalculatedTotal = SUM(LineTotal) FROM OrderDetails WHERE OrderID = 1

DECLARE @StoredTotal DECIMAL(10, 2)
SELECT @StoredTotal = OrderTotal FROM Orders WHERE OrderID = 1

IF @CalculatedTotal = @StoredTotal
    PRINT 'PASS: OrderTotal matches SUM(LineTotal)'
ELSE
    PRINT 'FAIL: Totals mismatch: stored=' + CAST(@StoredTotal AS VARCHAR(10)) 
          + ' calculated=' + CAST(@CalculatedTotal AS VARCHAR(10))

-- Additional check: Account for rounding
IF ABS(@CalculatedTotal - @StoredTotal) <= 0.01
    PRINT 'PASS: Totals consistent (within rounding)'
ELSE
    PRINT 'FAIL: Totals diverge by more than penny'

-- Cleanup
DELETE FROM OrderDetails
DELETE FROM Orders
```

---

## Best Practices for Data Validation Tests

### 1. Test Before Production
```sql
-- Every constraint should have a test
-- Run tests in development/staging, not production
EXEC tSQLt.Run @TestName = N'[Test].[Test_PrimaryKeyEnforced]'
```

### 2. Test Both Success and Failure Paths
```sql
-- ✅ DO: Test that valid data succeeds
INSERT INTO Orders VALUES (1, 1, 100, GETDATE())
PRINT 'PASS: Valid order inserted'

-- ✅ DO: Test that invalid data fails
BEGIN TRY
    INSERT INTO Orders VALUES (1, 1, -50, GETDATE())  -- Negative!
    PRINT 'FAIL: Negative amount not rejected'
END TRY
BEGIN CATCH
    PRINT 'PASS: Negative amount correctly rejected'
END CATCH
```

### 3. Clean Up Test Data
```sql
-- IMPORTANT: Leave database clean for next test
BEGIN
    DELETE FROM Orders WHERE OrderID = 1
    DELETE FROM OrderDetails WHERE OrderID = 1
    DELETE FROM Customers WHERE CustomerID = 1
END
```

### 4. Document Expected vs Actual
```sql
DECLARE @Expected INT = 100
DECLARE @Actual INT = 99

IF @Expected = @Actual
    PRINT 'PASS'
ELSE
    PRINT 'FAIL: Expected ' + CAST(@Expected AS VARCHAR(5)) 
          + ', got ' + CAST(@Actual AS VARCHAR(5))
```

---

## Common Test Failures & Solutions

| Failure | Cause | Fix |
|---------|-------|-----|
| "Cannot INSERT NULL into NOT NULL column" | Test data wrong | Add constraint to schema |
| "FK violation" | Orphan record | Add FK constraint |
| "Arithmetic overflow" | TINYINT too small | Use bigger type (INT, BIGINT) |
| "String truncation" | NVARCHAR too short | Check length or increase size |
| "Unique constraint violation" | Duplicate in test data | Reset test data properly |

---

## Integration with tSQLt (Later Pattern)

Once you add `testing/unit_testing_tsqlt.md`, these manual tests convert to:

```sql
-- Manual test (what we wrote above)
BEGIN TRY
    INSERT INTO Orders VALUES (1, 1, -50, GETDATE())
    PRINT 'FAIL: Negative amount not rejected'
END TRY
BEGIN CATCH
    PRINT 'PASS: Negative amount correctly rejected'
END CATCH

-- Becomes tSQLt test (automated)
CREATE PROCEDURE [TestOrders].[Test_RejectNegativeAmount]
AS
BEGIN
    EXEC tSQLt.ExpectException
    
    INSERT INTO Orders VALUES (1, 1, -50, GETDATE())
END
```

---

## References
- `[[unit_testing_tsqlt]]` — Automate these tests with tSQLt framework
- `references/common_pitfalls.md` — Data quality mistakes to avoid
- `references/transaction_management.md` — Transaction isolation in tests
- `[[audit_trail_patterns]]` — Test audit constraints

