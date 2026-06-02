-- ============================================================================
-- LAB-01: OPTIMIZE YOUR FIRST QUERY
-- STEP 02: HINTS AND GUIDANCE
-- ============================================================================
-- Use these hints to help diagnose and fix the slow query
-- ============================================================================

USE SampleEcommerce
GO

PRINT '🔍 ANALYZING THE SLOW QUERY...'
PRINT ''
GO

-- ============================================================================
-- HINT #1: Check Current Indexes
-- ============================================================================
PRINT '╔════════════════════════════════════════════════════════════════╗'
PRINT '║ HINT #1: Current Indexes on CustomerSalesReport               ║'
PRINT '╚════════════════════════════════════════════════════════════════╝'
PRINT ''
PRINT 'What indexes exist on the table?'
PRINT ''

SELECT
    i.name AS IndexName,
    i.type_desc AS IndexType,
    ic.name AS ColumnName,
    ic.key_ordinal AS ColumnOrder
FROM sys.indexes i
INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
WHERE OBJECT_NAME(i.object_id) = 'CustomerSalesReport'
ORDER BY i.name, ic.key_ordinal

PRINT ''
PRINT '⚠️ OBSERVATION: Notice which columns DON''T have indexes?'
PRINT '   The WHERE clause filters on: Country, TotalSpent, TotalOrders'
PRINT '   But we only have indexes on: ReportID, CustomerID'
PRINT ''
GO

-- ============================================================================
-- HINT #2: Execution Plan Analysis
-- ============================================================================
PRINT '╔════════════════════════════════════════════════════════════════╗'
PRINT '║ HINT #2: To See Execution Plan                                ║'
PRINT '╚════════════════════════════════════════════════════════════════╝'
PRINT ''
PRINT 'In SSMS:'
PRINT '1. Open 01-problema.sql'
PRINT '2. Press Ctrl+L (Display Estimated Plan)'
PRINT '3. Look for:'
PRINT '   ❌ "Table Scan" = Reading ALL rows (bad!)'
PRINT '   ✅ "Index Seek" = Reading only needed rows (good!)'
PRINT ''
PRINT 'In the execution plan, look for:'
PRINT '- Where''s the bottleneck? (highest % cost)'
PRINT '- Is there a Table Scan? (that''s the problem!)'
PRINT '- What operation comes before the sort?'
PRINT ''
GO

-- ============================================================================
-- HINT #3: What Index Would Help?
-- ============================================================================
PRINT '╔════════════════════════════════════════════════════════════════╗'
PRINT '║ HINT #3: The Solution - What Index?                           ║'
PRINT '╚════════════════════════════════════════════════════════════════╝'
PRINT ''
PRINT 'Think about the WHERE clause:'
PRINT '  WHERE r.Country IN (''USA'', ''Canada'', ''UK'')'
PRINT '    AND r.TotalSpent > 500'
PRINT '    AND r.TotalOrders > 3'
PRINT ''
PRINT 'And the ORDER BY:'
PRINT '  ORDER BY r.TotalSpent DESC'
PRINT ''
PRINT 'Question: Which column should be in the index key?'
PRINT 'Answer: The most selective column (filters out most rows)'
PRINT ''
PRINT 'Hint order:'
PRINT '1. Country (filters to 3 countries)'
PRINT '2. TotalSpent (filters > 500)'
PRINT '3. TotalOrders (filters > 3)'
PRINT ''
PRINT 'So try: CREATE NONCLUSTERED INDEX on (Country, ...)'
PRINT ''
GO

-- ============================================================================
-- HINT #4: Check How Many Rows Match
-- ============================================================================
PRINT '╔════════════════════════════════════════════════════════════════╗'
PRINT '║ HINT #4: Expected Result Set Size                             ║'
PRINT '╚════════════════════════════════════════════════════════════════╝'
PRINT ''
PRINT 'How many rows will the query return?'
PRINT ''

SELECT
    COUNT(*) AS TotalMatches,
    COUNT(CASE WHEN Country IN ('USA', 'Canada', 'UK') THEN 1 END) AS ByCountry,
    COUNT(CASE WHEN TotalSpent > 500 THEN 1 END) AS BySpending,
    COUNT(CASE WHEN TotalOrders > 3 THEN 1 END) AS ByOrderCount
FROM CustomerSalesReport

PRINT ''
PRINT 'Your optimized query should return the same number of rows!'
PRINT ''
GO

-- ============================================================================
-- HINT #5: The Fix Preview (Don't look if you want to solve it!)
-- ============================================================================
PRINT '╔════════════════════════════════════════════════════════════════╗'
PRINT '║ HINT #5: The Fix (Hidden - Don''t peek!)                       ║'
PRINT '╚════════════════════════════════════════════════════════════════╝'
PRINT ''
PRINT 'If you''re really stuck, see 03-solucion.sql'
PRINT ''
PRINT 'But first, try to figure it out yourself!'
PRINT 'Hints:'
PRINT '  - Create a composite index'
PRINT '  - Include all columns needed in WHERE and ORDER BY'
PRINT '  - Consider: (Country, TotalSpent, TotalOrders) with INCLUDE (CustomerID, ...)'
PRINT ''
GO

-- ============================================================================
-- SUMMARY OF ANALYSIS HINTS
-- ============================================================================
PRINT '╔════════════════════════════════════════════════════════════════╗'
PRINT '║ ANALYSIS SUMMARY                                               ║'
PRINT '╠════════════════════════════════════════════════════════════════╣'
PRINT '║ Problem:  Table Scan (slow) instead of Index Seek (fast)      ║'
PRINT '║ Cause:    No index on (Country, TotalSpent, TotalOrders)      ║'
PRINT '║ Solution: Create composite nonclustered index                 ║'
PRINT '║ Benefit:  10-20x performance improvement                      ║'
PRINT '╚════════════════════════════════════════════════════════════════╝'
PRINT ''
GO

-- ============================================================================
-- NEXT STEPS
-- ============================================================================
PRINT 'NEXT STEPS:'
PRINT '1. Close this file'
PRINT '2. Open 03-solucion.sql to see the answer'
PRINT '3. Or try to write it yourself first!'
PRINT '4. Test with 04-verificacion.sql'
PRINT ''
