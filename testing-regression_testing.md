# Regression Testing for SQL Server

## What is Regression Testing?

**Regression Test:** Verify that existing functionality still works after code changes
- Before/after comparisons
- Side effect detection
- Data integrity validation
- Performance regression detection

---

## Setup & Teardown Pattern

```sql
-- Test framework with setup/teardown
CREATE PROCEDURE tst_CustomerDiscount_Setup
AS
BEGIN
    -- Create test data
    DELETE FROM Customers WHERE CustomerID > 10000
    
    INSERT INTO Customers (CustomerID, CustomerName, Country) VALUES
    (10001, 'Test Customer 1', 'USA'),
    (10002, 'Test Customer 2', 'Canada'),
    (10003, 'Test Customer 3', 'USA')
    
    DELETE FROM Orders WHERE OrderID > 50000
    INSERT INTO Orders (OrderID, CustomerID, Amount, OrderDate) VALUES
    (50001, 10001, 1000.00, DATEADD(MONTH, -2, GETDATE())),
    (50002, 10001, 500.00, DATEADD(MONTH, -1, GETDATE())),
    (50003, 10002, 2000.00, DATEADD(MONTH, -3, GETDATE()))
END

CREATE PROCEDURE tst_CustomerDiscount_Teardown
AS
BEGIN
    -- Cleanup test data
    DELETE FROM Orders WHERE OrderID > 50000
    DELETE FROM Customers WHERE CustomerID > 10000
END

-- Run test
EXEC tst_CustomerDiscount_Setup

-- Test code here
SELECT * FROM Customers WHERE CustomerID IN (10001, 10002, 10003)

-- Cleanup
EXEC tst_CustomerDiscount_Teardown
```

---

## Before/After Comparison

```sql
-- Capture baseline state
CREATE TABLE #OrderBaseline (
    OrderID INT,
    CustomerID INT,
    Amount DECIMAL(10,2),
    Status NVARCHAR(50)
)

-- Baseline (before change)
INSERT INTO #OrderBaseline
SELECT OrderID, CustomerID, Amount, Status FROM Orders
WHERE OrderID IN (1000, 1001, 1002)

-- Execute change
UPDATE Orders SET Status = 'Processed' WHERE OrderID = 1000

-- Compare after change
SELECT 
    b.OrderID,
    'Amount' AS Field,
    CAST(b.Amount AS VARCHAR) AS Before,
    CAST(a.Amount AS VARCHAR) AS After,
    CASE WHEN b.Amount <> a.Amount THEN '❌ CHANGED' ELSE '✅ UNCHANGED' END AS Status
FROM #OrderBaseline b
INNER JOIN Orders a ON b.OrderID = a.OrderID
WHERE b.Amount <> a.Amount

UNION ALL

SELECT 
    b.OrderID,
    'Status' AS Field,
    b.Status AS Before,
    a.Status AS After,
    CASE WHEN b.Status <> a.Status THEN '⚠️ CHANGED (Expected)' ELSE '✅ UNCHANGED' END AS Status
FROM #OrderBaseline b
INNER JOIN Orders a ON b.OrderID = a.OrderID
WHERE b.Status <> a.Status

DROP TABLE #OrderBaseline
```

---

## Data Integrity Regression Tests

```sql
-- Test 1: Foreign Key Integrity
CREATE PROCEDURE tst_ForeignKeyIntegrity
AS
BEGIN
    -- Find orphaned orders (orders without customers)
    IF EXISTS (
        SELECT 1 FROM Orders o
        WHERE NOT EXISTS (SELECT 1 FROM Customers c WHERE c.CustomerID = o.CustomerID)
    )
    BEGIN
        PRINT '❌ FAIL: Orphaned orders found'
        RETURN 1
    END
    
    PRINT '✅ PASS: No orphaned orders'
    RETURN 0
END

-- Test 2: Unique Constraint Integrity
CREATE PROCEDURE tst_UniqueConstraints
AS
BEGIN
    -- Check for duplicate customers
    IF EXISTS (
        SELECT 1 FROM Customers
        GROUP BY CustomerEmail
        HAVING COUNT(*) > 1
    )
    BEGIN
        PRINT '❌ FAIL: Duplicate customer emails found'
        RETURN 1
    END
    
    PRINT '✅ PASS: All customer emails are unique'
    RETURN 0
END

-- Test 3: Total Balance Integrity
CREATE PROCEDURE tst_BalanceReconciliation
AS
BEGIN
    DECLARE @OrderTotal DECIMAL(10,2)
    DECLARE @DetailTotal DECIMAL(10,2)
    
    -- Orders.Total should = SUM(OrderDetails.Amount)
    SELECT @OrderTotal = SUM(Amount) FROM Orders
    SELECT @DetailTotal = SUM(Amount) FROM OrderDetails
    
    IF ABS(@OrderTotal - @DetailTotal) > 0.01
    BEGIN
        PRINT '❌ FAIL: Order total (' + CAST(@OrderTotal AS VARCHAR) + ') <> Detail total (' + CAST(@DetailTotal AS VARCHAR) + ')'
        RETURN 1
    END
    
    PRINT '✅ PASS: Balance reconciliation'
    RETURN 0
END

-- Run all tests
DECLARE @Result INT = 0
EXEC @Result = tst_ForeignKeyIntegrity
IF @Result = 1 RETURN 1

EXEC @Result = tst_UniqueConstraints
IF @Result = 1 RETURN 1

EXEC @Result = tst_BalanceReconciliation
IF @Result = 1 RETURN 1

PRINT 'All regression tests passed'
```

---

## Side Effect Detection

```sql
-- Test that procedure doesn't have unintended side effects
CREATE PROCEDURE tst_ProcessOrder_NoSideEffects
    @OrderID INT
AS
BEGIN
    -- Capture baseline
    DECLARE @BaselineOrderCount INT = (SELECT COUNT(*) FROM Orders)
    DECLARE @BaselineDetailCount INT = (SELECT COUNT(*) FROM OrderDetails)
    
    -- Execute procedure
    EXEC sp_ProcessOrder @OrderID
    
    -- Verify no unexpected changes
    IF (SELECT COUNT(*) FROM Orders) <> @BaselineOrderCount
    BEGIN
        PRINT '❌ FAIL: Order count changed unexpectedly'
        RETURN 1
    END
    
    IF (SELECT COUNT(*) FROM OrderDetails) <> @BaselineDetailCount
    BEGIN
        PRINT '❌ FAIL: OrderDetails count changed unexpectedly'
        RETURN 1
    END
    
    PRINT '✅ PASS: No side effects detected'
    RETURN 0
END
```

---

## Performance Regression Tests

```sql
-- Test that query performance hasn't degraded
CREATE PROCEDURE tst_QueryPerformance_SlowQuery_Regression
AS
BEGIN
    DECLARE @StartTime DATETIME2 = GETDATE()
    DECLARE @Duration_ms DECIMAL(10,2)
    
    -- Execute query
    SELECT * FROM Orders WHERE CustomerID = 123 AND OrderDate > GETDATE() - 30
    
    SET @Duration_ms = DATEDIFF(MILLISECOND, @StartTime, GETDATE())
    
    -- Baseline: 50ms (from previous measurement)
    -- Allow 20% variance
    IF @Duration_ms > 60  -- 50ms + 20%
    BEGIN
        PRINT '⚠️ REGRESSION: Query took ' + CAST(@Duration_ms AS VARCHAR) + 'ms (baseline: 50ms)'
        RETURN 1
    END
    
    PRINT '✅ PASS: Query performance acceptable (' + CAST(@Duration_ms AS VARCHAR) + 'ms)'
    RETURN 0
END

EXEC tst_QueryPerformance_SlowQuery_Regression
```

---

## Blocking & Lock Regression Tests

```sql
-- Test that stored procedure doesn't cause blocking
CREATE PROCEDURE tst_NoBlockingRegression
AS
BEGIN
    DECLARE @BlockingProcesses INT
    
    -- Simulate concurrent activity
    EXEC sp_ProcessOrder 123
    
    -- Check for blocking (should be none)
    SELECT @BlockingProcesses = COUNT(*) 
    FROM sys.dm_exec_requests r
    WHERE r.blocking_session_id <> 0
    
    IF @BlockingProcesses > 0
    BEGIN
        PRINT '❌ FAIL: Blocking detected after procedure execution'
        RETURN 1
    END
    
    PRINT '✅ PASS: No blocking detected'
    RETURN 0
END
```

---

## Automated Regression Test Suite

```sql
CREATE PROCEDURE sp_RegressionTestSuite
    @Verbose BIT = 0
AS
BEGIN
    DECLARE @TotalTests INT = 0
    DECLARE @PassedTests INT = 0
    DECLARE @FailedTests INT = 0
    DECLARE @Result INT
    
    IF @Verbose = 1 PRINT 'Starting regression test suite...'
    
    -- Test 1
    SET @TotalTests = @TotalTests + 1
    EXEC @Result = tst_ForeignKeyIntegrity
    IF @Result = 0 SET @PassedTests = @PassedTests + 1 ELSE SET @FailedTests = @FailedTests + 1
    
    -- Test 2
    SET @TotalTests = @TotalTests + 1
    EXEC @Result = tst_UniqueConstraints
    IF @Result = 0 SET @PassedTests = @PassedTests + 1 ELSE SET @FailedTests = @FailedTests + 1
    
    -- Test 3
    SET @TotalTests = @TotalTests + 1
    EXEC @Result = tst_BalanceReconciliation
    IF @Result = 0 SET @PassedTests = @PassedTests + 1 ELSE SET @FailedTests = @FailedTests + 1
    
    -- Report
    PRINT ''
    PRINT '═══════════════════════════════════'
    PRINT 'Regression Test Results'
    PRINT '═══════════════════════════════════'
    PRINT 'Total Tests: ' + CAST(@TotalTests AS VARCHAR)
    PRINT 'Passed: ' + CAST(@PassedTests AS VARCHAR)
    PRINT 'Failed: ' + CAST(@FailedTests AS VARCHAR)
    PRINT ''
    
    IF @FailedTests > 0
    BEGIN
        PRINT '❌ REGRESSION DETECTED'
        RETURN 1
    END
    ELSE
    BEGIN
        PRINT '✅ All tests passed'
        RETURN 0
    END
END

-- Run tests
EXEC sp_RegressionTestSuite @Verbose = 1
```

---

## Best Practices

- [ ] Always run regression tests before deployment
- [ ] Capture baseline data before making changes
- [ ] Test data integrity constraints
- [ ] Test for unintended side effects
- [ ] Measure performance before/after
- [ ] Include in CI/CD pipeline
- [ ] Document baseline expectations
- [ ] Test with production-like data
- [ ] Automated test suite for common scenarios
- [ ] Block deployment if regression tests fail
