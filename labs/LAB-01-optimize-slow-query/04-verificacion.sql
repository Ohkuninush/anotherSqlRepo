-- ============================================================================
-- LAB-01: OPTIMIZE YOUR FIRST QUERY
-- STEP 04: VERIFICATION
-- ============================================================================
-- Verify that your solution works correctly and improves performance
-- ============================================================================

USE SampleEcommerce
GO

PRINT '🔍 VERIFYING YOUR SOLUTION'
PRINT '============================'
PRINT ''
GO

-- ============================================================================
-- VERIFICATION #1: Check Index Exists
-- ============================================================================
PRINT '✓ VERIFICATION 1: Index Created'
PRINT '-' * 50
PRINT ''

IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_CustomerSalesReport_CountrySpending')
BEGIN
    PRINT '✅ Index IX_CustomerSalesReport_CountrySpending exists!'
    PRINT ''
    SELECT
        i.name AS IndexName,
        i.type_desc AS IndexType,
        ic.name AS ColumnName,
        ic.key_ordinal AS ColumnOrder
    FROM sys.indexes i
    INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
    WHERE i.name = 'IX_CustomerSalesReport_CountrySpending'
    ORDER BY ic.key_ordinal
    PRINT ''
END
ELSE
BEGIN
    PRINT '❌ Index not found! Create the index first using 03-solucion.sql'
    RETURN
END
GO

-- ============================================================================
-- VERIFICATION #2: Check Result Set
-- ============================================================================
PRINT ''
PRINT '✓ VERIFICATION 2: Result Set Correctness'
PRINT '-' * 50
PRINT ''

-- Get results from the slow query approach (raw data)
SELECT
    'Expected' AS Source,
    COUNT(*) AS RowCount,
    SUM(TotalSpent) AS TotalRevenue,
    AVG(TotalOrders) AS AvgOrders,
    MAX(TotalSpent) AS MaxSpent
FROM CustomerSalesReport
WHERE Country IN ('USA', 'Canada', 'UK')
  AND TotalSpent > 500
  AND TotalOrders > 3

PRINT ''
PRINT 'Your query should return these results!'
PRINT ''
GO

-- ============================================================================
-- VERIFICATION #3: Performance Metrics
-- ============================================================================
PRINT ''
PRINT '✓ VERIFICATION 3: Performance Comparison'
PRINT '-' * 50
PRINT ''

PRINT ''
PRINT 'Running query with index...'
PRINT ''

-- Run the query with performance stats
SET STATISTICS IO ON
SET STATISTICS TIME ON

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
PRINT 'Expected Performance:'
PRINT '  ✅ Execution Time: < 1 second (vs 3-5 before)'
PRINT '  ✅ Logical Reads: < 100 (vs 2,500+ before)'
PRINT '  ✅ Index Operation: Index Seek (vs Table Scan before)'
PRINT ''
GO

-- ============================================================================
-- VERIFICATION #4: Execution Plan Check
-- ============================================================================
PRINT ''
PRINT '✓ VERIFICATION 4: Execution Plan Analysis'
PRINT '-' * 50
PRINT ''

PRINT 'To verify execution plan:'
PRINT '1. In SSMS, re-run the query above'
PRINT '2. Press Ctrl+L to show execution plan'
PRINT '3. Check for:'
PRINT '   ✅ "Index Seek" on IX_CustomerSalesReport_CountrySpending'
PRINT '   ✅ No "Key Lookup" operations'
PRINT '   ✅ "Sort" operation is last'
PRINT ''
PRINT 'NOT correct if:'
PRINT '   ❌ Still shows "Table Scan"'
PRINT '   ❌ Shows "Key Lookup" operations'
PRINT '   ❌ Multiple scans on different tables'
PRINT ''
GO

-- ============================================================================
-- VERIFICATION #5: Performance Gain Calculation
-- ============================================================================
PRINT ''
PRINT '✓ VERIFICATION 5: Performance Improvement'
PRINT '-' * 50
PRINT ''

PRINT 'To calculate improvement:'
PRINT ''
PRINT 'Speedup = Time Before / Time After'
PRINT ''
PRINT 'Example:'
PRINT '  Before: 4500 ms'
PRINT '  After:  450 ms'
PRINT '  Speedup: 4500 / 450 = 10x faster ✅'
PRINT ''
PRINT 'Your goal: At least 5-10x faster'
PRINT 'Excellent: 10-20x faster'
PRINT ''
GO

-- ============================================================================
-- VERIFICATION #6: Index Statistics
-- ============================================================================
PRINT ''
PRINT '✓ VERIFICATION 6: Index Usage Statistics'
PRINT '-' * 50
PRINT ''

SELECT
    i.name AS IndexName,
    i.type_desc AS IndexType,
    ISNULL(s.user_seeks, 0) AS Seeks,
    ISNULL(s.user_scans, 0) AS Scans,
    ISNULL(s.user_lookups, 0) AS Lookups,
    ISNULL(s.user_updates, 0) AS Updates
FROM sys.indexes i
LEFT JOIN sys.dm_db_index_usage_stats s
    ON i.object_id = s.object_id
    AND i.index_id = s.index_id
    AND s.database_id = DB_ID()
WHERE OBJECT_NAME(i.object_id) = 'CustomerSalesReport'
ORDER BY i.name

PRINT ''
PRINT 'Good sign: High "Seeks" on IX_CustomerSalesReport_CountrySpending'
PRINT 'Bad sign: High "Scans" on any index'
PRINT ''
GO

-- ============================================================================
-- FINAL VERIFICATION CHECKLIST
-- ============================================================================
PRINT ''
PRINT '╔════════════════════════════════════════════════════════════════╗'
PRINT '║ FINAL VERIFICATION CHECKLIST                                   ║'
PRINT '╠════════════════════════════════════════════════════════════════╣'
PRINT '║ [ ] Index IX_CustomerSalesReport_CountrySpending exists        ║'
PRINT '║ [ ] Query returns correct results                              ║'
PRINT '║ [ ] Execution time < 1 second (was 3-5 seconds)                ║'
PRINT '║ [ ] Logical reads < 100 (was 2,500+)                           ║'
PRINT '║ [ ] Execution plan shows Index Seek (was Table Scan)           ║'
PRINT '║ [ ] No Key Lookup operations (costly)                          ║'
PRINT '║ [ ] Performance gain ≥ 5x faster                               ║'
PRINT '│                                                                │'
PRINT '║ If all checked: LAB COMPLETE! ✅                               ║'
PRINT '╚════════════════════════════════════════════════════════════════╝'
PRINT ''
GO

-- ============================================================================
-- SUCCESS!
-- ============================================================================
PRINT ''
PRINT 'CONGRATULATIONS! 🎉'
PRINT ''
PRINT 'If you completed all verifications:'
PRINT ''
PRINT '✅ You learned how to optimize a query'
PRINT '✅ You created an effective composite index'
PRINT '✅ You achieved 5-10x performance improvement'
PRINT '✅ You can now apply this to your own queries'
PRINT ''
PRINT 'Next: Read 05-leccion.md to understand the deeper concepts'
PRINT ''
