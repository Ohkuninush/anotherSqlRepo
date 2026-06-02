# 🚨 CASE STUDY 01: Query Performance Crisis

## 📊 Business Context

**Company:** OnlineStore Inc. (ecommerce platform)  
**Scale:** 1000+ daily orders, 50K+ active customers  
**Problem:** Dashboard reports take 45+ seconds to load (unacceptable)  
**Impact:** Users abandon dashboard, support tickets increasing  
**Urgency:** 🔴 Critical - revenue impact

---

## 🔍 Problem Discovery

### Timeline
- **Monday 9am:** Users report slow dashboard loading
- **Monday 10am:** Issue confirmed - reports taking 45-60 seconds
- **Monday 2pm:** Database CPU at 90%+ constantly
- **Monday 4pm:** Team assigned to investigate

### Initial Symptoms
```sql
-- This query takes 47 seconds - users are waiting!
SELECT 
    c.CustomerID,
    c.CustomerName,
    c.Country,
    COUNT(o.OrderID) AS TotalOrders,
    SUM(o.TotalAmount) AS TotalSpent,
    MAX(o.OrderDate) AS LastOrderDate
FROM Customers c
LEFT JOIN Orders o ON c.CustomerID = o.CustomerID
WHERE YEAR(o.OrderDate) = YEAR(GETDATE())  -- <-- PROBLEM HERE!
GROUP BY c.CustomerID, c.CustomerName, c.Country
ORDER BY TotalSpent DESC
```

---

## 🔎 Root Cause Analysis

### Step 1: Capture Execution Plan

```sql
-- Enable statistics
SET STATISTICS IO ON
SET STATISTICS TIME ON

-- Run problematic query
SELECT 
    c.CustomerID,
    c.CustomerName,
    c.Country,
    COUNT(o.OrderID) AS TotalOrders,
    SUM(o.TotalAmount) AS TotalSpent,
    MAX(o.OrderDate) AS LastOrderDate
FROM Customers c
LEFT JOIN Orders o ON c.CustomerID = o.CustomerID
WHERE YEAR(o.OrderDate) = YEAR(GETDATE())
GROUP BY c.CustomerID, c.CustomerName, c.Country
ORDER BY TotalSpent DESC

SET STATISTICS TIME OFF
SET STATISTICS IO OFF
```

**Output Analysis:**
```
SQL Server parse and compile time: 2 ms.
SQL Server Execution Times:
   CPU time = 47,123 ms,  Elapsed time = 47,456 ms.

Table 'Orders'. Scan count 1, logical reads 8,943, physical reads 127
Table 'Customers'. Scan count 1, logical reads 245, physical reads 0
```

**Key Issues Found:**
1. ❌ **CLUSTERED INDEX SCAN** on Orders table (should be SEEK!)
2. ❌ **YEAR() function** in WHERE clause prevents index usage
3. ❌ 8,943 logical reads (excessive)
4. ❌ CPU spike (47 seconds)

### Step 2: Why YEAR() is Bad

```
YEAR(o.OrderDate) = YEAR(GETDATE())

This executes YEAR() on EVERY ROW in Orders table!
SQL Server can't use indexes on computed values
Result: Full table scan instead of index seek
```

---

## 💡 Solution

### Fix #1: Replace YEAR() with Date Range

```sql
-- ✅ OPTIMIZED: Replace YEAR() with date range
DECLARE @StartOfYear DATETIME2 = DATEFROMPARTS(YEAR(GETDATE()), 1, 1)
DECLARE @EndOfYear DATETIME2 = DATEADD(DAY, 1, EOMONTH(GETDATE(), 11))

SELECT 
    c.CustomerID,
    c.CustomerName,
    c.Country,
    COUNT(o.OrderID) AS TotalOrders,
    SUM(o.TotalAmount) AS TotalSpent,
    MAX(o.OrderDate) AS LastOrderDate
FROM Customers c
LEFT JOIN Orders o ON c.CustomerID = o.CustomerID
WHERE o.OrderDate >= @StartOfYear 
  AND o.OrderDate < @EndOfYear
GROUP BY c.CustomerID, c.CustomerName, c.Country
ORDER BY TotalSpent DESC
```

**Impact:**
- ✅ **INDEX SEEK** instead of SCAN (uses IX_Orders_OrderDate)
- ✅ **From 8,943 reads → 245 reads** (98% reduction)
- ✅ **From 47 seconds → 1.2 seconds** (39x faster!)

### Fix #2: Add Covering Index (Optional But Powerful)

```sql
-- Create covering index for this exact query pattern
CREATE NONCLUSTERED INDEX IX_Orders_OrderDate_Covering
ON Orders(OrderDate, CustomerID)
INCLUDE (TotalAmount)
WHERE OrderDate >= DATEFROMPARTS(YEAR(GETDATE()), 1, 1)
```

**With covering index:**
- ✅ Reduces from 1.2 seconds → 0.3 seconds
- ✅ Index covers all columns needed (no key lookup)

---

## 🧪 Before & After Comparison

### Execution Plan Before
```
|-- Hash Match (INNER JOIN)
    |-- Table Scan (Orders) [8,943 reads]
    |-- Hash Match (Aggregate)
        |-- Clustered Index Scan (Customers) [245 reads]
Total: 47 seconds, 47,123 ms CPU
```

### Execution Plan After
```
|-- Hash Match (INNER JOIN)
    |-- Index Seek (IX_Orders_OrderDate) [245 reads]
    |-- Hash Match (Aggregate)
        |-- Clustered Index Scan (Customers) [245 reads]
Total: 1.2 seconds, 1,234 ms CPU
```

---

## 📈 Implementation Steps

### Step 1: Test the Fix (Development)
```sql
USE SampleEcommerce
GO

-- Test new query
DECLARE @StartOfYear DATETIME2 = DATEFROMPARTS(YEAR(GETDATE()), 1, 1)
DECLARE @EndOfYear DATETIME2 = DATEADD(DAY, 1, EOMONTH(GETDATE(), 11))

SET STATISTICS IO ON
SET STATISTICS TIME ON

SELECT 
    c.CustomerID,
    c.CustomerName,
    c.Country,
    COUNT(o.OrderID) AS TotalOrders,
    SUM(o.TotalAmount) AS TotalSpent,
    MAX(o.OrderDate) AS LastOrderDate
FROM Customers c
LEFT JOIN Orders o ON c.CustomerID = o.CustomerID
WHERE o.OrderDate >= @StartOfYear 
  AND o.OrderDate < @EndOfYear
GROUP BY c.CustomerID, c.CustomerName, c.Country
ORDER BY TotalSpent DESC

SET STATISTICS TIME OFF
SET STATISTICS IO OFF

-- Expected: < 2 seconds, < 500 reads
```

### Step 2: Verify Results
```sql
-- Compare row counts
SELECT 'Old Query' AS Method, COUNT(*) AS RowCount
FROM (
    SELECT c.CustomerID FROM Customers c
    LEFT JOIN Orders o ON c.CustomerID = o.CustomerID
    WHERE YEAR(o.OrderDate) = YEAR(GETDATE())
    GROUP BY c.CustomerID
) old_results

UNION ALL

SELECT 'New Query', COUNT(*) FROM (
    DECLARE @StartOfYear DATETIME2 = DATEFROMPARTS(YEAR(GETDATE()), 1, 1)
    DECLARE @EndOfYear DATETIME2 = DATEADD(DAY, 1, EOMONTH(GETDATE(), 11))
    
    SELECT c.CustomerID FROM Customers c
    LEFT JOIN Orders o ON c.CustomerID = o.CustomerID
    WHERE o.OrderDate >= @StartOfYear 
      AND o.OrderDate < @EndOfYear
    GROUP BY c.CustomerID
) new_results

-- Results should be identical!
```

### Step 3: Deploy to Production
```sql
-- Create procedure with optimized query
CREATE OR ALTER PROCEDURE sp_GetYearlyCustomerSummary
AS
BEGIN
    SET NOCOUNT ON
    
    DECLARE @StartOfYear DATETIME2 = DATEFROMPARTS(YEAR(GETDATE()), 1, 1)
    DECLARE @EndOfYear DATETIME2 = DATEADD(DAY, 1, EOMONTH(GETDATE(), 11))
    
    SELECT 
        c.CustomerID,
        c.CustomerName,
        c.Country,
        COUNT(o.OrderID) AS TotalOrders,
        SUM(o.TotalAmount) AS TotalSpent,
        MAX(o.OrderDate) AS LastOrderDate
    FROM Customers c
    LEFT JOIN Orders o ON c.CustomerID = o.CustomerID
    WHERE o.OrderDate >= @StartOfYear 
      AND o.OrderDate < @EndOfYear
    GROUP BY c.CustomerID, c.CustomerName, c.Country
    ORDER BY TotalSpent DESC
END

-- Update application to use: EXEC sp_GetYearlyCustomerSummary
```

---

## 📊 Results & Impact

### Performance Metrics
| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Execution Time | 47 sec | 1.2 sec | **39x faster** |
| CPU Time | 47,123 ms | 1,234 ms | **95% reduction** |
| Logical Reads | 8,943 | 245 | **97% reduction** |
| Index Usage | Scan | Seek | ✅ Optimal |

### Business Impact
- ✅ Dashboard loads in 1.2 seconds (acceptable)
- ✅ CPU usage drops from 90% to 5%
- ✅ 15 concurrent users can now run this query (before: 2-3)
- ✅ User complaints resolved
- ✅ Revenue impact reversed

### Timeline to Resolution
- Monday 4pm: Issue identified
- Monday 5pm: Fix developed and tested
- Monday 6pm: Deployed to production
- Tuesday 9am: Monitoring confirms stable performance

---

## 🎓 Key Lessons

### ❌ What Went Wrong
1. **Using functions in WHERE clause** - Prevents index usage
2. **Not monitoring query performance** - Issue cascaded
3. **Lack of indexing strategy** - No proper date range index
4. **No baseline metrics** - Couldn't detect regression early

### ✅ What Went Right
1. **Root cause analysis** - Found exact problem quickly
2. **Testing before deploy** - Verified fix worked
3. **Quick turnaround** - Fixed in under 2 hours
4. **Measurable improvement** - 39x faster = clear win

### 📝 Best Practices Applied
1. **Avoid functions on filter columns**
   ```sql
   ❌ WHERE YEAR(OrderDate) = 2024
   ✅ WHERE OrderDate >= '2024-01-01' AND OrderDate < '2025-01-01'
   ```

2. **Use parameterized date ranges**
   ```sql
   DECLARE @StartDate DATETIME2 = '2024-01-01'
   DECLARE @EndDate DATETIME2 = '2025-01-01'
   WHERE OrderDate >= @StartDate AND OrderDate < @EndDate
   ```

3. **Create covering indexes for high-traffic queries**
   ```sql
   CREATE NONCLUSTERED INDEX IX_OptimalName
   ON TableName(FilterColumns)
   INCLUDE (SelectColumns)
   ```

4. **Always test performance before deploying**
   ```sql
   SET STATISTICS IO ON
   SET STATISTICS TIME ON
   -- Run query
   SET STATISTICS TIME OFF
   SET STATISTICS IO OFF
   ```

---

## 🔧 Prevention Strategy

### Going Forward
1. **Establish baseline metrics**
   - Track execution time weekly
   - Alert on 10%+ degradation

2. **Code review process**
   - Check for functions in WHERE clause
   - Verify query execution plans

3. **Monitoring**
   - Enable Query Store
   - Monitor CPU and I/O trends
   - Set up automated alerts

4. **Documentation**
   - Document why each index exists
   - Update MASTER-INDEX with patterns

---

## 📚 Related Topics

- **Reference:** [query_patterns.md](../../references-query_patterns.md) - Functions in WHERE clause anti-pattern
- **Reference:** [index_design_guidelines.md](../../references-index_design_guidelines.md) - Covering indexes
- **Pattern:** [etl_incremental.md](../../patterns-etl_incremental.md) - Date-based filtering patterns
- **Skill:** [#1 Query Optimization](../../sql-server-expert-SKILL-CORRECTED.md#core-query--performance-1-8)
- **Skill:** [#2 Execution Plan Analysis](../../sql-server-expert-SKILL-CORRECTED.md#core-query--performance-1-8)
- **Script:** [analyze_execution_plan.sql](../../scripts-analyze_execution_plan.sql)

---

## 📝 SQL Files for This Case Study

1. **setup.sql** - Create sample database
2. **01-slow-query.sql** - Original problematic query
3. **02-root-cause-analysis.sql** - Diagnostic queries
4. **03-optimized-query.sql** - Fixed version
5. **04-verification.sql** - Proof of improvement
6. **05-final-procedure.sql** - Production code

---

**Status:** ✅ Resolved  
**Time to Fix:** 2 hours  
**Performance Gain:** 39x faster  
**Business Value:** Critical issue resolved, user satisfaction restored
