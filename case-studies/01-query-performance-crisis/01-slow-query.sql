-- ============================================================================
-- CASE STUDY 01: Query Performance Crisis
-- STEP 1: The Slow Query (Taking 45+ seconds)
-- ============================================================================
-- This is the ORIGINAL problematic query that's causing performance issues
-- Time to execute: ~47 seconds (UNACCEPTABLE)
-- ============================================================================

USE SampleEcommerce
GO

-- Enable statistics to see actual performance
SET STATISTICS IO ON
SET STATISTICS TIME ON

-- ============================================================================
-- THE PROBLEM QUERY
-- ============================================================================
-- This query takes forever because of YEAR() function in WHERE clause
-- YEAR() is computed for EVERY row in Orders table
-- This prevents the query optimizer from using indexes
-- Result: Full table scan instead of index seek

SELECT
    c.CustomerID,
    c.CustomerName,
    c.Country,
    COUNT(o.OrderID) AS TotalOrders,
    SUM(o.TotalAmount) AS TotalSpent,
    MAX(o.OrderDate) AS LastOrderDate
FROM Customers c
LEFT JOIN Orders o ON c.CustomerID = o.CustomerID
WHERE YEAR(o.OrderDate) = YEAR(GETDATE())  -- <-- THIS IS THE PROBLEM!
GROUP BY c.CustomerID, c.CustomerName, c.Country
ORDER BY TotalSpent DESC

-- ============================================================================
-- EXPECTED OUTPUT
-- ============================================================================
-- SQL Server parse and compile time: X ms.
-- SQL Server Execution Times:
--    CPU time = ~47,000 ms,  Elapsed time = ~47,500 ms.
--
-- Table 'Orders'. Scan count 1, logical reads 8,943, physical reads ???
-- Table 'Customers'. Scan count 1, logical reads 245, physical reads 0
--
-- Execution Plan shows: CLUSTERED INDEX SCAN (bad!)
-- ============================================================================

SET STATISTICS TIME OFF
SET STATISTICS IO OFF

-- ============================================================================
-- WHY THIS IS SLOW
-- ============================================================================
-- 1. YEAR(o.OrderDate) = YEAR(GETDATE())
--    - YEAR() function is applied to EVERY ROW
--    - SQL Server can't use index on YEAR(OrderDate)
--    - Must scan entire Orders table
--
-- 2. LEFT JOIN forces scan of Customers table too
--    - Even with LEFT JOIN, Customers needs full scan
--
-- 3. No useful index can help
--    - Index on OrderDate is useless because of YEAR() function
--
-- ============================================================================
-- SOLUTION: See "02-root-cause-analysis.sql"
-- ============================================================================
