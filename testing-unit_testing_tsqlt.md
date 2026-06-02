---
name: unit-testing-tsqlt
description: tSQLt unit testing framework — test setup, procedures, assertions, fixtures, data isolation, and enterprise test patterns
---

# Unit Testing with tSQLt — Enterprise Framework

## Overview

**What is tSQLt?** An open-source SQL Server unit testing framework. Allows you to:
- Write tests in T-SQL (test the same language you write)
- Run tests automatically (CI/CD integration)
- Isolate tests (one test can't break another)
- Mock dependencies (test without production data)
- Generate test reports

**Why it matters:** 
- Catch bugs before production
- Confidence when refactoring
- Documentation (tests show how code should work)
- Regression prevention

---

## Anti-Pattern: Manual Testing (❌ Don't Do This)

### The Problem
```sql
-- Manual testing workflow (repeatable = unreliable)
-- 1. Developer writes procedure
-- 2. QA manually runs tests
-- 3. Tester forgets a scenario
-- 4. Bug reaches production
-- 5. Repeat forever

-- No automated tests, no confidence
```

### Real-World Incident
```
Timeline:
  Dev: "I refactored the stored procedure for performance"
  Dev: "Ran some manual tests, looks good"
  QA: Manually tests 5 scenarios (checks 5/100)
  Prod: "Why are negative values in the report?"
  Dev: "I broke the edge case handling"
  
Result: Rollback, manual revert, reputation damage
Why: Manual testing catches 5%, misses 95%
```

---

## Pattern 1: tSQLt Setup & First Test

### Installation
```sql
-- Download from github.com/tSQLt-org/tSQLt
-- Extract and run:

-- 1. Create test database
CREATE DATABASE TestDB

-- 2. Install tSQLt framework
-- SQLCMD -S . -d TestDB -i "tSQLt.class.sql"
-- (See tSQLt documentation for exact steps)

-- 3. Verify installation
SELECT * FROM tSQLt.Version  -- Shows installed version
```

### ✅ Correct Implementation: First Test

#### Schema Under Test
```sql
-- In main database or test database
CREATE FUNCTION dbo.CalculateDiscount(@OrderAmount DECIMAL(10, 2))
RETURNS DECIMAL(10, 2)
AS
BEGIN
    -- Business rule: 10% discount on orders over $100
    RETURN CASE 
        WHEN @OrderAmount > 100 THEN @OrderAmount * 0.10
        ELSE 0
    END
END
```

#### Test Class
```sql
-- Create test class (container for related tests)
EXEC tSQLt.NewTestClass @ClassName = N'TestOrderDiscount'

-- Add first test
CREATE PROCEDURE [TestOrderDiscount].[Test_SmallOrder_NoDiscount]
AS
BEGIN
    -- Arrange (setup)
    DECLARE @Amount DECIMAL(10, 2) = 50
    
    -- Act (execute)
    DECLARE @Discount DECIMAL(10, 2)
    SET @Discount = dbo.CalculateDiscount(@Amount)
    
    -- Assert (verify)
    EXEC tSQLt.AssertEquals 
        @Expected = 0,
        @Actual = @Discount,
        @Message = 'Small orders should have no discount'
END

-- Add second test
CREATE PROCEDURE [TestOrderDiscount].[Test_LargeOrder_TenPercentDiscount]
AS
BEGIN
    DECLARE @Amount DECIMAL(10, 2) = 200
    DECLARE @Discount DECIMAL(10, 2)
    
    SET @Discount = dbo.CalculateDiscount(@Amount)
    
    EXEC tSQLt.AssertEquals 
        @Expected = 20,  -- 200 * 0.10
        @Actual = @Discount,
        @Message = 'Large orders should get 10% discount'
END

-- Add edge case test
CREATE PROCEDURE [TestOrderDiscount].[Test_ExactlyHundred_NoDiscount]
AS
BEGIN
    DECLARE @Amount DECIMAL(10, 2) = 100
    DECLARE @Discount DECIMAL(10, 2)
    
    SET @Discount = dbo.CalculateDiscount(@Amount)
    
    EXEC tSQLt.AssertEquals 
        @Expected = 0,
        @Actual = @Discount,
        @Message = 'Order of exactly $100 should have no discount'
END
```

#### Run Tests
```sql
-- Run all tests
EXEC tSQLt.Run @TestName = N'[TestOrderDiscount]'

-- Run specific test
EXEC tSQLt.Run @TestName = N'[TestOrderDiscount].[Test_LargeOrder_TenPercentDiscount]'

-- Show results (summary)
-- PASSED: 3 tests
-- FAILED: 0 tests
```

---

## Pattern 2: Testing Stored Procedures with Setup/Teardown

### Use Case
- Test procedures that modify data
- Need consistent test data before each test
- Need cleanup after each test

### ✅ Correct Implementation

#### Schema Under Test
```sql
CREATE TABLE Orders (
    OrderID INT PRIMARY KEY IDENTITY(1, 1),
    CustomerID INT NOT NULL,
    Amount DECIMAL(10, 2) NOT NULL CHECK (Amount > 0),
    Status NVARCHAR(20) NOT NULL DEFAULT 'PENDING'
)

CREATE TABLE OrderHistory (
    HistoryID BIGINT PRIMARY KEY IDENTITY(1, 1),
    OrderID INT,
    OldStatus NVARCHAR(20),
    NewStatus NVARCHAR(20),
    ChangedDate DATETIME2
)

CREATE PROCEDURE sp_ShipOrder
    @OrderID INT
AS
BEGIN
    SET NOCOUNT ON
    SET XACT_ABORT ON
    
    BEGIN TRY
        BEGIN TRANSACTION
        
        IF NOT EXISTS (SELECT 1 FROM Orders WHERE OrderID = @OrderID)
            THROW 50001, 'Order not found', 1
        
        DECLARE @OldStatus NVARCHAR(20)
        SELECT @OldStatus = Status FROM Orders WHERE OrderID = @OrderID
        
        UPDATE Orders SET Status = 'SHIPPED' WHERE OrderID = @OrderID
        
        INSERT INTO OrderHistory (OrderID, OldStatus, NewStatus, ChangedDate)
        VALUES (@OrderID, @OldStatus, 'SHIPPED', GETDATE())
        
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION
        THROW
    END CATCH
END
```

#### Test Class with Setup
```sql
EXEC tSQLt.NewTestClass @ClassName = N'TestOrderShipment'

-- Setup: Runs before EVERY test
CREATE PROCEDURE [TestOrderShipment].[Setup]
AS
BEGIN
    -- Create test data
    INSERT INTO Orders (CustomerID, Amount, Status)
    VALUES (1, 100, 'PENDING'),
           (2, 200, 'PENDING'),
           (3, 300, 'CANCELLED')
END

-- Teardown: Runs after EVERY test (cleanup)
CREATE PROCEDURE [TestOrderShipment].[Teardown]
AS
BEGIN
    -- tSQLt automatically isolates each test
    -- So manual cleanup isn't required
    -- But can be used for logging/debugging
    PRINT 'Test complete'
END

-- Test 1: Happy path
CREATE PROCEDURE [TestOrderShipment].[Test_ShipOrder_UpdatesStatus]
AS
BEGIN
    -- Arrange: Setup already ran, OrderID=1 exists
    -- Act: Ship the order
    EXEC sp_ShipOrder @OrderID = 1
    
    -- Assert: Status should be SHIPPED
    DECLARE @Status NVARCHAR(20)
    SELECT @Status = Status FROM Orders WHERE OrderID = 1
    
    EXEC tSQLt.AssertEquals 
        @Expected = 'SHIPPED',
        @Actual = @Status
END

-- Test 2: Verify history logged
CREATE PROCEDURE [TestOrderShipment].[Test_ShipOrder_LogsHistory]
AS
BEGIN
    EXEC sp_ShipOrder @OrderID = 1
    
    DECLARE @HistoryCount INT
    SELECT @HistoryCount = COUNT(*) 
    FROM OrderHistory 
    WHERE OrderID = 1 AND NewStatus = 'SHIPPED'
    
    EXEC tSQLt.AssertEquals 
        @Expected = 1,
        @Actual = @HistoryCount,
        @Message = 'History should be logged'
END

-- Test 3: Error case
CREATE PROCEDURE [TestOrderShipment].[Test_ShipOrder_InvalidOrderID_ThrowsError]
AS
BEGIN
    EXEC tSQLt.ExpectException
        @ExceptionMessagePattern = 'Order not found'
    
    EXEC sp_ShipOrder @OrderID = 9999  -- Doesn't exist
END

-- Test 4: Edge case
CREATE PROCEDURE [TestOrderShipment].[Test_ShipOrder_AlreadyShipped_StillWorks]
AS
BEGIN
    -- Ship twice (should be idempotent)
    EXEC sp_ShipOrder @OrderID = 1
    EXEC sp_ShipOrder @OrderID = 1
    
    DECLARE @Status NVARCHAR(20)
    SELECT @Status = Status FROM Orders WHERE OrderID = 1
    
    EXEC tSQLt.AssertEquals @Expected = 'SHIPPED', @Actual = @Status
END
```

#### Run Test Suite
```sql
-- Run all tests (with automatic setup/teardown)
EXEC tSQLt.Run @TestName = N'[TestOrderShipment]'

-- Output:
-- Test Execution Summary
-- =====================
-- Tests run: 4
-- Passed: 4
-- Failed: 0
-- Errors: 0
```

---

## Pattern 3: Testing with Mocks & Fakes

### Use Case
- Test procedure that calls another procedure
- Don't want to call real procedure (too slow, side effects)
- Replace with mock/fake for control

### ✅ Correct Implementation

#### Procedures Under Test
```sql
-- Real procedure (calls another)
CREATE PROCEDURE sp_ProcessOrder
    @OrderID INT
AS
BEGIN
    SET NOCOUNT ON
    
    -- Perform validation
    EXEC sp_ValidateOrder @OrderID
    
    -- Update order
    UPDATE Orders SET Status = 'PROCESSING' WHERE OrderID = @OrderID
END

-- Real validation procedure
CREATE PROCEDURE sp_ValidateOrder
    @OrderID INT
AS
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Orders WHERE OrderID = @OrderID)
        THROW 50001, 'Invalid order', 1
END
```

#### Test with Mock
```sql
EXEC tSQLt.NewTestClass @ClassName = N'TestOrderProcessing'

CREATE PROCEDURE [TestOrderProcessing].[Setup]
AS
BEGIN
    INSERT INTO Orders (CustomerID, Amount, Status)
    VALUES (1, 100, 'PENDING')
END

-- Test where validation passes
CREATE PROCEDURE [TestOrderProcessing].[Test_ValidOrder_UpdatesStatus]
AS
BEGIN
    EXEC sp_ProcessOrder @OrderID = 1
    
    DECLARE @Status NVARCHAR(20)
    SELECT @Status = Status FROM Orders WHERE OrderID = 1
    
    EXEC tSQLt.AssertEquals @Expected = 'PROCESSING', @Actual = @Status
END

-- Test where validation fails
-- Create a mock version of sp_ValidateOrder
CREATE PROCEDURE sp_ValidateOrder_Mock
    @OrderID INT
AS
BEGIN
    -- Mock: Always throw error
    THROW 50001, 'Mock validation failed', 1
END

-- Spy on calls
CREATE PROCEDURE [TestOrderProcessing].[Test_CallsValidation]
AS
BEGIN
    -- Replace real procedure with mock
    EXEC tSQLt.SpyProcedure @ProcedureName = 'sp_ValidateOrder'
    
    -- Now calling sp_ProcessOrder calls the spy
    EXEC sp_ProcessOrder @OrderID = 1
    
    -- Check if sp_ValidateOrder was called
    DECLARE @CallCount INT
    SELECT @CallCount = COUNT(*) 
    FROM tSQLt.CapturedSpyCalls
    WHERE ProcedureName = 'sp_ValidateOrder'
    
    EXEC tSQLt.AssertEquals 
        @Expected = 1,
        @Actual = @CallCount,
        @Message = 'sp_ValidateOrder should be called'
END
```

---

## Pattern 4: Testing Edge Cases & Error Conditions

### Use Case
- Boundary conditions (NULL, 0, negative, max values)
- Error handling verification
- Transaction rollback on error

### ✅ Correct Implementation

#### Procedure Under Test
```sql
CREATE PROCEDURE sp_TransferFunds
    @FromAccountID INT,
    @ToAccountID INT,
    @Amount DECIMAL(10, 2)
AS
BEGIN
    SET NOCOUNT ON
    SET XACT_ABORT ON
    
    BEGIN TRY
        IF @Amount IS NULL OR @Amount <= 0
            THROW 50001, 'Amount must be positive', 1
        
        IF @FromAccountID IS NULL OR @ToAccountID IS NULL
            THROW 50002, 'Account IDs required', 1
        
        IF @FromAccountID = @ToAccountID
            THROW 50003, 'Cannot transfer to same account', 1
        
        BEGIN TRANSACTION
        
        UPDATE Accounts SET Balance = Balance - @Amount WHERE AccountID = @FromAccountID
        UPDATE Accounts SET Balance = Balance + @Amount WHERE AccountID = @ToAccountID
        
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
        THROW
    END CATCH
END
```

#### Comprehensive Test Suite
```sql
EXEC tSQLt.NewTestClass @ClassName = N'TestFundsTransfer'

CREATE PROCEDURE [TestFundsTransfer].[Setup]
AS
BEGIN
    CREATE TABLE Accounts (
        AccountID INT PRIMARY KEY,
        Balance DECIMAL(10, 2)
    )
    INSERT INTO Accounts VALUES (1, 1000), (2, 500)
END

-- Test valid transfer
CREATE PROCEDURE [TestFundsTransfer].[Test_ValidTransfer_UpdatesBoth]
AS
BEGIN
    EXEC sp_TransferFunds @FromAccountID = 1, @ToAccountID = 2, @Amount = 100
    
    DECLARE @FromBalance DECIMAL(10, 2), @ToBalance DECIMAL(10, 2)
    SELECT @FromBalance = Balance FROM Accounts WHERE AccountID = 1
    SELECT @ToBalance = Balance FROM Accounts WHERE AccountID = 2
    
    EXEC tSQLt.AssertEquals @Expected = 900, @Actual = @FromBalance
    EXEC tSQLt.AssertEquals @Expected = 600, @Actual = @ToBalance
END

-- Test negative amount
CREATE PROCEDURE [TestFundsTransfer].[Test_NegativeAmount_ThrowsError]
AS
BEGIN
    EXEC tSQLt.ExpectException @ExceptionMessagePattern = 'positive'
    EXEC sp_TransferFunds 1, 2, -100
END

-- Test NULL amount
CREATE PROCEDURE [TestFundsTransfer].[Test_NullAmount_ThrowsError]
AS
BEGIN
    EXEC tSQLt.ExpectException @ExceptionMessagePattern = 'required'
    EXEC sp_TransferFunds 1, 2, NULL
END

-- Test zero amount
CREATE PROCEDURE [TestFundsTransfer].[Test_ZeroAmount_ThrowsError]
AS
BEGIN
    EXEC tSQLt.ExpectException @ExceptionMessagePattern = 'positive'
    EXEC sp_TransferFunds 1, 2, 0
END

-- Test same account
CREATE PROCEDURE [TestFundsTransfer].[Test_SameAccount_ThrowsError]
AS
BEGIN
    EXEC tSQLt.ExpectException @ExceptionMessagePattern = 'same account'
    EXEC sp_TransferFunds 1, 1, 100
END

-- Test insufficient balance (transaction rollback)
CREATE PROCEDURE [TestFundsTransfer].[Test_InsufficientFunds_RollsBack]
AS
BEGIN
    EXEC tSQLt.ExpectException  -- Procedure will fail
    EXEC sp_TransferFunds 1, 2, 10000  -- More than available
    
    -- Verify no balance change occurred
    DECLARE @Balance DECIMAL(10, 2)
    SELECT @Balance = Balance FROM Accounts WHERE AccountID = 1
    EXEC tSQLt.AssertEquals @Expected = 1000, @Actual = @Balance
END

-- Test boundary: Exact balance transfer
CREATE PROCEDURE [TestFundsTransfer].[Test_ExactBalance_TransfersAll]
AS
BEGIN
    EXEC sp_TransferFunds 1, 2, 1000  -- Transfer exactly 1000
    
    DECLARE @FromBalance DECIMAL(10, 2)
    SELECT @FromBalance = Balance FROM Accounts WHERE AccountID = 1
    
    EXEC tSQLt.AssertEquals @Expected = 0, @Actual = @FromBalance
END
```

---

## tSQLt Assertions Reference

```sql
-- Equality assertions
EXEC tSQLt.AssertEquals @Expected = 10, @Actual = @Value
EXEC tSQLt.AssertNotEquals @Expected = 10, @Actual = @Value

-- String assertions
EXEC tSQLt.AssertEqualsString 
    @Expected = 'SHIPPED', 
    @Actual = @Status

-- NULL assertions
EXEC tSQLt.AssertIsNull @Value = @NullableColumn
EXEC tSQLt.AssertIsNotNull @Value = @RequiredValue

-- Table assertions
EXEC tSQLt.AssertEmptyTable @TableName = 'dbo.Orders'
EXEC tSQLt.AssertTableEquals 
    @Expected = 'dbo.ExpectedOrders',
    @Actual = 'dbo.ActualOrders'

-- Exception expectations
EXEC tSQLt.ExpectException 
    @ExceptionNumber = 50001,
    @ExceptionMessagePattern = 'Order not found'

-- Failure (manual assertion failure)
EXEC tSQLt.Fail @Message = 'This test should not reach here'
```

---

## Best Practices for tSQLt Tests

### 1. One Assertion Per Test (When Possible)
```sql
-- ❌ BAD: Multiple assertions (hard to debug failures)
CREATE PROCEDURE [Test].[Test_OrderProcessing]
AS
BEGIN
    EXEC sp_ProcessOrder 1
    DECLARE @Status NVARCHAR(20)
    SELECT @Status = Status FROM Orders WHERE OrderID = 1
    EXEC tSQLt.AssertEquals @Expected = 'SHIPPED', @Actual = @Status
    
    DECLARE @HistoryCount INT
    SELECT @HistoryCount = COUNT(*) FROM OrderHistory WHERE OrderID = 1
    EXEC tSQLt.AssertEquals @Expected = 1, @Actual = @HistoryCount
END

-- ✅ GOOD: Separate tests
CREATE PROCEDURE [Test].[Test_OrderProcessing_UpdatesStatus]
AS
BEGIN
    EXEC sp_ProcessOrder 1
    DECLARE @Status NVARCHAR(20)
    SELECT @Status = Status FROM Orders WHERE OrderID = 1
    EXEC tSQLt.AssertEquals @Expected = 'SHIPPED', @Actual = @Status
END

CREATE PROCEDURE [Test].[Test_OrderProcessing_LogsHistory]
AS
BEGIN
    EXEC sp_ProcessOrder 1
    DECLARE @HistoryCount INT
    SELECT @HistoryCount = COUNT(*) FROM OrderHistory WHERE OrderID = 1
    EXEC tSQLt.AssertEquals @Expected = 1, @Actual = @HistoryCount
END
```

### 2. Test Names Describe What They Test
```sql
-- ✅ GOOD: Descriptive name
CREATE PROCEDURE [TestOrders].[Test_ShipOrder_ClosedOrders_ThrowsError]

-- ❌ BAD: Vague name
CREATE PROCEDURE [TestOrders].[Test_ShipOrder_1]
```

### 3. Use Setup/Teardown for Common Data
```sql
-- Setup runs before each test
CREATE PROCEDURE [TestOrders].[Setup]
AS
BEGIN
    INSERT INTO Orders VALUES (1, 100, 'PENDING')
    INSERT INTO Orders VALUES (2, 200, 'PENDING')
    INSERT INTO Customers VALUES (1, 'Alice')
    INSERT INTO Customers VALUES (2, 'Bob')
END

-- Now each test starts with clean, consistent data
```

### 4. Test Both Happy Path and Error Cases
```sql
-- Happy path
CREATE PROCEDURE [Test].[Test_ProcessOrder_Success]
CREATE PROCEDURE [Test].[Test_ProcessOrder_InvalidID_ThrowsError]
Create PROCEDURE [Test].[Test_ProcessOrder_AlreadyProcessed_Idempotent]
```

---

## CI/CD Integration

### Run Tests in Build Pipeline
```powershell
# PowerShell script for CI/CD
sqlcmd -S DBSERVER -d TestDB -Q "EXEC tSQLt.Run" -o test_results.txt

# Check for failures
if (Select-String -Path test_results.txt -Pattern "Failed.*[1-9]") {
    Write-Host "Tests failed!"
    exit 1
}

Write-Host "All tests passed!"
exit 0
```

### Generate Test Report
```sql
-- After tests run, generate report
EXEC tSQLt.XmlResultFormatter

-- Output can be converted to JUnit XML for Jenkins/Azure Pipelines
```

---

## References
- `[[data_validation_tests]]` — Manual validation tests (foundation)
- `references/common_pitfalls.md` — Edge cases to test
- `references/transaction_management.md` — Transaction testing patterns
- tSQLt.org — Official documentation

