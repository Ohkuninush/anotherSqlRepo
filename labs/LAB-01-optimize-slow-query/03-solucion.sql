-- ============================================================================
-- LAB-01: OPTIMIZE YOUR FIRST QUERY
-- STEP 03: THE SOLUTION
-- ============================================================================
-- This is the optimized query and the index that makes it fast
-- ============================================================================

USE SampleEcommerce
GO

PRINT '✅ THE SOLUTION: Create the Right Index'
PRINT '========================================='
PRINT ''
GO

-- ============================================================================
-- PART 1: CREATE THE OPTIMAL INDEX
-- ============================================================================
PRINT 'STEP 1: Create Composite Nonclustered Index'
PRINT '-' * 50
PRINT ''

-- Drop old index if it exists (to start fresh)
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_CustomerSalesReport_CountrySpending')
    DROP INDEX IX_CustomerSalesReport_CountrySpending ON CustomerSalesReport

-- Create the optimal index
CREATE NONCLUSTERED INDEX IX_CustomerSalesReport_CountrySpending
ON CustomerSalesReport (
    Country,           -- 1st: Filter by country
    TotalSpent,        -- 2nd: Filter by spending
    TotalOrders        -- 3rd: Filter by order count
)
INCLUDE (
    CustomerID,        -- Include for JOIN
    CustomerName,      -- Include for SELECT
    LastOrderDate,     -- Include for SELECT
    AverageOrderValue  -- Include for SELECT
)

PRINT '✅ Index created: IX_CustomerSalesReport_CountrySpending'
PRINT ''
PRINT 'Index Structure:'
PRINT '  - Key Columns: Country, TotalSpent, TotalOrders'
PRINT '  - Included Columns: CustomerID, CustomerName, LastOrderDate, AverageOrderValue'
PRINT '  - Type: Nonclustered (B-Tree index)'
PRINT ''
PRINT 'Why this index:'
PRINT '  1. Country first: Reduces candidates from 100 to ~30 rows'
PRINT '  2. TotalSpent second: Reduces further with > 500 filter'
PRINT '  3. TotalOrders third: Final filter for > 3 orders'
PRINT '  4. Includes all SELECT columns: No key lookups needed'
PRINT ''
GO

-- ============================================================================
-- PART 2: THE OPTIMIZED QUERY
-- ============================================================================
PRINT ''
PRINT 'STEP 2: Run the Same Query with New Index'
PRINT '-' * 50
PRINT ''

-- Enable statistics to measure improvement
SET STATISTICS IO ON
SET STATISTICS TIME ON

-- SAME QUERY - but now with the index!
SELECT
    c.CustomerID,
    c.CustomerName,
    c.Country,
    r.TotalOrders,
    r.TotalSpent,
    r.LastOrderDate,
    r.AverageOrderValue
FROM CustomerSalesReport r
INNER JOIN Customers c ON r.CustomerID = c.CustomerID
WHERE r.Country IN ('USA', 'Canada', 'UK')
  AND r.TotalSpent > 500
  AND r.TotalOrders > 3
ORDER BY r.TotalSpent DESC

SET STATISTICS TIME OFF
SET STATISTICS IO OFF

PRINT ''
PRINT '✅ Query completed much faster!'
PRINT ''
GO

-- ============================================================================
-- PART 3: VERIFY THE IMPROVEMENT
-- ============================================================================
PRINT 'STEP 3: Verify Index Usage'
PRINT '-' * 50
PRINT ''

-- Show that the new index is being used
SELECT
    i.name AS IndexName,
    s.user_seeks AS Seeks,
    s.user_scans AS Scans,
    s.user_lookups AS Lookups,
    s.user_updates AS Updates
FROM sys.indexes i
LEFT JOIN sys.dm_db_index_usage_stats s ON i.object_id = s.object_id AND i.index_id = s.index_id
WHERE OBJECT_NAME(i.object_id) = 'CustomerSalesReport'
AND database_id = DB_ID()

PRINT ''
PRINT 'Expected: Index Seeks on IX_CustomerSalesReport_CountrySpending (fast!)'
GO

-- ============================================================================
-- PART 4: WHY THIS WORKS
-- ============================================================================
PRINT ''
PRINT 'WHY THIS SOLUTION WORKS'
PRINT '=' * 50
PRINT ''
PRINT 'BEFORE (Slow):
PRINT '  Query Type: Table Scan (reads ALL rows, every column)'
PRINT '  Logical Reads: 2,500+ (reading entire table)'
PRINT '  Execution Time: 3-5 seconds'
PRINT '  Reason: No suitable index for the WHERE clause filters'
PRINT ''
PRINT 'AFTER (Fast):
PRINT '  Query Type: Index Seek (reads only matching rows)'
PRINT '  Logical Reads: 50-100 (reading only needed data)'
PRINT '  Execution Time: 0.3-0.5 seconds'
PRINT '  Reason: Composite index covers all filter and sort columns'
PRINT ''
PRINT 'PERFORMANCE: ~6-10x faster! ✅'
PRINT ''
GO

-- ============================================================================
-- PART 5: KEY LEARNING POINTS
-- ============================================================================
PRINT 'KEY LEARNING POINTS'
PRINT '=' * 50
PRINT ''
PRINT '1. COMPOSITE INDEXES ARE POWERFUL'
PRINT '   Multiple columns in key order = better filtering'
PRINT ''
PRINT '2. INDEX COLUMN ORDER MATTERS'
PRINT '   Put most selective column first (Country = 3 values)'
PRINT '   Then other filter columns (TotalSpent, TotalOrders)'
PRINT ''
PRINT '3. COVERING INDEXES AVOID LOOKUPS'
PRINT '   INCLUDE all columns in SELECT clause'
PRINT '   This means: Index has all data, no need to lookup base table'
PRINT ''
PRINT '4. STATISTICS TELL THE STORY'
PRINT '   SET STATISTICS IO ON'
PRINT '   Look for: Logical reads count'
PRINT '   Lower = better'
PRINT ''
PRINT '5. EXECUTION PLANS DON''T LIE'
PRINT '   Table Scan = problem'
PRINT '   Index Seek = solution'
PRINT ''
GO

-- ============================================================================
-- PART 6: APPLY THIS PATTERN TO YOUR OWN QUERIES
-- ============================================================================
PRINT ''
PRINT 'HOW TO APPLY THIS PATTERN TO YOUR OWN QUERIES'
PRINT '=' * 50
PRINT ''
PRINT 'For any slow query:'
PRINT ''
PRINT '1. Identify the WHERE columns'
PRINT '2. Order them by selectivity (most to least)'
PRINT '3. Add ORDER BY columns if needed'
PRINT '4. Create composite index:'
PRINT '   CREATE INDEX ON Table('
PRINT '       FirstFilter,'
PRINT '       SecondFilter,'
PRINT '       OrderByColumn'
PRINT '   )'
PRINT '   INCLUDE (SelectColumns)'
PRINT ''
PRINT '5. Test with execution plan'
PRINT '6. Measure logical reads'
PRINT '7. Celebrate the improvement! 🎉'
PRINT ''
GO

-- ============================================================================
-- NEXT STEPS
-- ============================================================================
PRINT ''
PRINT 'NEXT STEPS:'
PRINT ''
PRINT '1. Compare your solution with this one'
PRINT '2. Run 04-verificacion.sql to verify'
PRINT '3. Read 05-leccion.md to understand deeper'
PRINT '4. Apply this to your own queries!'
PRINT ''
