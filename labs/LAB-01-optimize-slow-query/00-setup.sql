-- ============================================================================
-- LAB-01: OPTIMIZE YOUR FIRST QUERY
-- STEP 00: SETUP
-- ============================================================================
-- Run this script first to setup the lab environment
-- This creates additional tables/data specifically for this lab
-- ============================================================================

USE SampleEcommerce
GO

-- ============================================================================
-- VERIFY SAMPLE DATABASE EXISTS
-- ============================================================================
IF OBJECT_ID('Customers') IS NULL
BEGIN
    RAISERROR('Sample database not found! Please run examples/setup-sample-database.sql first', 16, 1)
    RETURN
END

PRINT '✅ Sample database found'
GO

-- ============================================================================
-- CREATE A REPORTING TABLE (common scenario)
-- This simulates a table used by reports that needs optimization
-- ============================================================================
IF OBJECT_ID('CustomerSalesReport') IS NOT NULL
    DROP TABLE CustomerSalesReport
GO

CREATE TABLE CustomerSalesReport (
    ReportID INT PRIMARY KEY IDENTITY(1,1),
    CustomerID INT NOT NULL,
    CustomerName NVARCHAR(100) NOT NULL,
    Country NVARCHAR(50) NOT NULL,
    TotalOrders INT,
    TotalSpent DECIMAL(12,2),
    LastOrderDate DATETIME2,
    AverageOrderValue DECIMAL(10,2),
    CreatedDate DATETIME2 DEFAULT GETDATE()
)

PRINT '✅ Created CustomerSalesReport table'
GO

-- ============================================================================
-- POPULATE THE REPORTING TABLE (simulates a data refresh)
-- This data mirrors what a real report table might have
-- ============================================================================
INSERT INTO CustomerSalesReport (CustomerID, CustomerName, Country, TotalOrders, TotalSpent, LastOrderDate, AverageOrderValue)
SELECT
    c.CustomerID,
    c.CustomerName,
    c.Country,
    COUNT(o.OrderID) AS TotalOrders,
    ISNULL(SUM(o.TotalAmount), 0) AS TotalSpent,
    MAX(o.OrderDate) AS LastOrderDate,
    CASE WHEN COUNT(o.OrderID) > 0 THEN SUM(o.TotalAmount) / COUNT(o.OrderID) ELSE 0 END
FROM Customers c
LEFT JOIN Orders o ON c.CustomerID = o.CustomerID
GROUP BY c.CustomerID, c.CustomerName, c.Country

PRINT '✅ Populated CustomerSalesReport with ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + ' rows'
GO

-- ============================================================================
-- CREATE INDEXES (we'll intentionally create a suboptimal one)
-- This simulates a real-world situation with incomplete indexing
-- ============================================================================

-- Create primary key (clustered index)
CREATE CLUSTERED INDEX PK_CustomerSalesReport
ON CustomerSalesReport(ReportID)

-- Create index on CustomerID (will be useful)
CREATE NONCLUSTERED INDEX IX_CustomerSalesReport_CustomerID
ON CustomerSalesReport(CustomerID)

-- We intentionally DON'T create an index on TotalSpent or Country
-- This will force a table scan for the lab query
PRINT '✅ Created indexes (intentionally suboptimal)'
GO

-- ============================================================================
-- VERIFY SETUP
-- ============================================================================
PRINT ''
PRINT '╔════════════════════════════════════════════════════════════════╗'
PRINT '║ LAB-01 SETUP COMPLETE                                          ║'
PRINT '╠════════════════════════════════════════════════════════════════╣'
PRINT '║ Tables Ready:                                                  ║'
PRINT '║  ✅ Customers'
PRINT '║  ✅ Orders'
PRINT '║  ✅ CustomerSalesReport (created for this lab)'
PRINT '║                                                                ║'
PRINT '║ Indexes Created:                                               ║'
PRINT '║  ✅ PK_CustomerSalesReport (ClusteredIndex on ReportID)'
PRINT '║  ✅ IX_CustomerSalesReport_CustomerID'
PRINT '║                                                                ║'
PRINT '║ Status: READY TO START LAB                                     ║'
PRINT '╚════════════════════════════════════════════════════════════════╝'
PRINT ''
PRINT 'Next step: Open and run 01-problema.sql'
GO

-- ============================================================================
-- QUICK REFERENCE: What''s in the lab
-- ============================================================================
PRINT ''
PRINT 'Lab Tables:'
EXEC sp_helpindex 'CustomerSalesReport'
GO

SELECT 'Customers' AS TableName, COUNT(*) AS RowCount FROM Customers
UNION ALL
SELECT 'Orders', COUNT(*) FROM Orders
UNION ALL
SELECT 'CustomerSalesReport', COUNT(*) FROM CustomerSalesReport
GO
