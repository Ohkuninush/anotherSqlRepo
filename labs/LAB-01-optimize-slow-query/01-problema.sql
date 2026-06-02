-- ============================================================================
-- LAB-01: OPTIMIZE YOUR FIRST QUERY
-- STEP 01: THE PROBLEM - YOUR CHALLENGE
-- ============================================================================
-- This is your challenge!
--
-- You have a slow query that needs optimization.
-- Your task: Make it faster without changing the results.
--
-- WHAT YOU NEED TO DO:
-- 1. Run this query as-is - notice how slow it is
-- 2. Look at the execution plan (Ctrl+L in SSMS)
-- 3. Identify what's causing the slowness
-- 4. Read the hints in 02-pistas.sql
-- 5. Write an optimized version
-- 6. Verify with 04-verificacion.sql
--
-- TIME THIS QUERY - You'll see the improvement later!
-- ============================================================================

USE SampleEcommerce
GO

PRINT 'PROBLEM QUERY: Find high-value customers by country'
PRINT '========================================================'
PRINT ''

-- Enable statistics to see actual performance metrics
SET STATISTICS IO ON
SET STATISTICS TIME ON

-- ============================================================================
-- THE SLOW QUERY (YOUR CHALLENGE TO OPTIMIZE)
-- ============================================================================
-- This query finds customers who:
-- - Are from USA, Canada, or UK
-- - Have spent more than $500 total
-- - Have made more than 3 orders
-- - And shows them sorted by spending

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

-- ============================================================================
-- EXPECTED EXECUTION PLAN ISSUES
-- ============================================================================
-- You should see:
--   ❌ Table Scan (not Index Seek)
--   ❌ Many logical reads (2000+)
--   ❌ Slow execution time (2-5 seconds)
-- ============================================================================

SET STATISTICS TIME OFF
SET STATISTICS IO OFF

PRINT ''
PRINT '╔════════════════════════════════════════════════════════════════╗'
PRINT '║ ANALYSIS QUESTIONS (Answer these):                             ║'
PRINT '╠════════════════════════════════════════════════════════════════╣'
PRINT '║ 1. What was the execution time?                                ║'
PRINT '║    Answer: ________________ seconds                            ║'
PRINT '║                                                                ║'
PRINT '║ 2. What index operation did it use?                            ║'
PRINT '║    Answer: [ ] Seek  [ ] Scan                                  ║'
PRINT '║                                                                ║'
PRINT '║ 3. How many logical reads were there?                          ║'
PRINT '║    Answer: ________________ reads                              ║'
PRINT '║                                                                ║'
PRINT '║ 4. Which columns in the WHERE clause don''t have indexes?      ║'
PRINT '║    Answer: ________________                                    ║'
PRINT '║                                                                ║'
PRINT '║ 5. What type of index could help?                              ║'
PRINT '║    Answer: ________________                                    ║'
PRINT '╚════════════════════════════════════════════════════════════════╝'
PRINT ''
PRINT 'NEXT STEPS:'
PRINT '1. Write down your answers above'
PRINT '2. Look at 02-pistas.sql for hints'
PRINT '3. Check 03-solucion.sql for reference'
PRINT '4. Create an optimized version'
PRINT '5. Run 04-verificacion.sql to verify'
GO

-- ============================================================================
-- BONUS: Try to write an optimized version below
-- ============================================================================
PRINT ''
PRINT 'YOUR OPTIMIZED QUERY (Replace the slow query above with this):'
PRINT '================================================================'
PRINT ''
PRINT '-- Write your optimized version here:'
PRINT '-- (Hint: Check 02-pistas.sql if you''re stuck)'
PRINT ''
