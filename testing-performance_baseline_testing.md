# Performance Baseline Testing

## Establishing Baselines

**Baseline:** Known-good performance metrics to compare against
- Execution time
- CPU usage
- I/O operations
- Memory usage
- Index seeks vs scans

```sql
-- Capture baseline metrics
CREATE TABLE PerformanceBaseline (
    TestName NVARCHAR(100),
    ExecutionTime_ms DECIMAL(10,2),
    CPU_ms DECIMAL(10,2),
    LogicalReads INT,
    PhysicalReads INT,
    CaptureDate DATETIME2,
    Notes NVARCHAR(500)
)

-- Run test and capture baseline
SET STATISTICS TIME ON
SET STATISTICS IO ON

SELECT * FROM Orders WHERE Status = 'Pending'

SET STATISTICS IO OFF
SET STATISTICS TIME OFF

-- Example output to table
INSERT INTO PerformanceBaseline VALUES (
    'Query_FindPendingOrders',
    123.45,  -- Execution time
    45.67,   -- CPU time
    1250,    -- Logical reads
    0,       -- Physical reads
    GETDATE(),
    'Initial baseline with 50K rows'
)
```

---

## Baseline Captures

### 1. Execution Time Baseline
```sql
DECLARE @StartTime DATETIME2 = GETDATE()

-- Query under test
SELECT TOP 1000 * 
FROM Orders 
WHERE CustomerID IN (SELECT CustomerID FROM Customers WHERE Country = 'USA')
ORDER BY OrderDate DESC

DECLARE @EndTime DATETIME2 = GETDATE()
DECLARE @DurationMs DECIMAL(10,2) = DATEDIFF(MILLISECOND, @StartTime, @EndTime)

SELECT 'Baseline Execution Time' AS Metric, @DurationMs AS Value_ms

-- Run multiple times for average
DECLARE @Iteration INT = 0
WHILE @Iteration < 5
BEGIN
    SET @StartTime = GETDATE()
    SELECT TOP 1000 * FROM Orders ORDER BY OrderDate DESC
    SET @EndTime = GETDATE()
    PRINT 'Run ' + CAST(@Iteration AS VARCHAR) + ': ' + CAST(DATEDIFF(MILLISECOND, @StartTime, @EndTime) AS VARCHAR) + 'ms'
    SET @Iteration = @Iteration + 1
END
```

### 2. I/O Baseline
```sql
-- Clear cache to get consistent metrics
DBCC DROPCLEANBUFFERS
DBCC FREEPROCCACHE

-- Enable I/O statistics
SET STATISTICS IO ON

SELECT * FROM Orders WHERE Status = 'Pending'

-- Output shows:
-- Table 'Orders'. Scan count 1, logical reads 245, physical reads 3

SET STATISTICS IO OFF

-- Log results
INSERT INTO PerformanceBaseline VALUES (
    'IO_FindPendingOrders',
    NULL,
    NULL,
    245,  -- Logical reads
    3,    -- Physical reads
    GETDATE(),
    'I/O baseline after cache clear'
)
```

### 3. CPU Baseline
```sql
SET STATISTICS TIME ON

SELECT * FROM Orders WHERE CustomerID = @CustID

-- Output shows:
-- SQL Server parse and compile time: 0 ms.
-- SQL Server Execution Times:
--   CPU time = 1 ms,  Elapsed time = 3 ms.

SET STATISTICS TIME OFF
```

### 4. Query Plan Baseline
```sql
-- Capture execution plan hash for later comparison
SELECT 
    @QueryHash = qs.query_hash,
    @ExecCount = qs.execution_count,
    @AvgElapsed = qs.total_elapsed_time / qs.execution_count
FROM sys.dm_exec_query_stats qs
WHERE qs.query_hash = HASHBYTES('SHA2_256', 'SELECT * FROM Orders WHERE Status = ?')

-- Store baseline plan
INSERT INTO PlanBaseline (QueryHash, AvgElapsedTime_ms, ExecutionCount, CaptureDate)
VALUES (@QueryHash, @AvgElapsed, @ExecCount, GETDATE())
```

---

## Trend Analysis

```sql
-- Compare current performance to baseline
SELECT 
    b.TestName,
    b.ExecutionTime_ms AS BaselineTime_ms,
    CAST(AVG(p.ExecutionTime_ms) AS DECIMAL(10,2)) AS CurrentAvgTime_ms,
    CAST(((AVG(p.ExecutionTime_ms) - b.ExecutionTime_ms) / b.ExecutionTime_ms * 100) AS DECIMAL(5,2)) AS PercentChange,
    CASE 
        WHEN (AVG(p.ExecutionTime_ms) - b.ExecutionTime_ms) / b.ExecutionTime_ms > 0.10 THEN '🔴 REGRESSION'
        WHEN (AVG(p.ExecutionTime_ms) - b.ExecutionTime_ms) / b.ExecutionTime_ms < -0.10 THEN '🟢 IMPROVED'
        ELSE '🟡 STABLE'
    END AS Status
FROM PerformanceBaseline b
LEFT JOIN PerformanceBaseline p ON b.TestName = p.TestName 
    AND p.CaptureDate > DATEADD(HOUR, -24, GETDATE())
    AND p.CaptureDate > b.CaptureDate
GROUP BY b.TestName, b.ExecutionTime_ms
ORDER BY PercentChange DESC
```

---

## Performance Regression Detection

```sql
-- Alert on 10%+ performance degradation
CREATE PROCEDURE sp_DetectPerformanceRegression
AS
BEGIN
    DECLARE @CurrentTime DECIMAL(10,2)
    DECLARE @BaselineTime DECIMAL(10,2)
    DECLARE @TestName NVARCHAR(100)
    
    DECLARE test_cursor CURSOR FOR
    SELECT DISTINCT TestName FROM PerformanceBaseline WHERE ExecutionTime_ms IS NOT NULL
    
    OPEN test_cursor
    FETCH NEXT FROM test_cursor INTO @TestName
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Get baseline
        SELECT @BaselineTime = ExecutionTime_ms 
        FROM PerformanceBaseline 
        WHERE TestName = @TestName 
        ORDER BY CaptureDate DESC 
        LIMIT 1
        
        -- Get current average (last 10 runs)
        SELECT @CurrentTime = AVG(ExecutionTime_ms)
        FROM PerformanceBaseline 
        WHERE TestName = @TestName 
        AND CaptureDate > DATEADD(DAY, -1, GETDATE())
        AND ExecutionTime_ms IS NOT NULL
        
        -- Alert if > 10% regression
        IF @CurrentTime > (@BaselineTime * 1.10)
        BEGIN
            -- Send alert
            PRINT '⚠️ REGRESSION DETECTED: ' + @TestName
            PRINT 'Baseline: ' + CAST(@BaselineTime AS VARCHAR) + 'ms'
            PRINT 'Current: ' + CAST(@CurrentTime AS VARCHAR) + 'ms'
            PRINT 'Change: +' + CAST((@CurrentTime - @BaselineTime) / @BaselineTime * 100 AS VARCHAR) + '%'
        END
        
        FETCH NEXT FROM test_cursor INTO @TestName
    END
    
    CLOSE test_cursor
    DEALLOCATE test_cursor
END

-- Schedule daily
EXEC sp_DetectPerformanceRegression
```

---

## CI/CD Integration

```sql
-- Test suite for automated performance validation
CREATE PROCEDURE sp_PerformanceTestSuite
    @FailOnRegression BIT = 1
AS
BEGIN
    DECLARE @TestsPassed INT = 0
    DECLARE @TestsFailed INT = 0
    
    -- Test 1: Query execution time < 100ms
    DECLARE @Duration_ms DECIMAL(10,2)
    SET @Duration_ms = (
        SELECT DATEDIFF(MILLISECOND, GETDATE(), GETDATE())  -- Dummy, replace with actual query
    )
    
    IF @Duration_ms < 100
    BEGIN
        PRINT '✅ Test 1: Fast query execution PASSED'
        SET @TestsPassed = @TestsPassed + 1
    END
    ELSE
    BEGIN
        PRINT '❌ Test 1: Fast query execution FAILED (' + CAST(@Duration_ms AS VARCHAR) + 'ms)'
        SET @TestsFailed = @TestsFailed + 1
    END
    
    -- Test 2: Index seeks (no scans)
    -- Test 3: Logical reads < baseline
    -- Test 4: No blocking detected
    
    -- Report
    PRINT ''
    PRINT 'Test Results: ' + CAST(@TestsPassed AS VARCHAR) + ' Passed, ' + CAST(@TestsFailed AS VARCHAR) + ' Failed'
    
    IF @TestsFailed > 0 AND @FailOnRegression = 1
        THROW 50001, 'Performance tests failed - regression detected', 1
END

EXEC sp_PerformanceTestSuite
```

---

## Best Practices

- [ ] Capture baselines on clean database (cache cleared)
- [ ] Run queries multiple times for average
- [ ] Document baseline conditions (data volume, hardware, load)
- [ ] Compare apples-to-apples (same data volume, index state)
- [ ] Alert on > 10% degradation
- [ ] Trending analysis (not just point-in-time comparison)
- [ ] Include baseline tests in CI/CD pipeline
- [ ] Regular baseline refreshes as data grows
- [ ] Test with production-sized data
- [ ] Use execution plans, not just timings
