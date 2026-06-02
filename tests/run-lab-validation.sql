/*
╔══════════════════════════════════════════════════════════════════════╗
║                                                                      ║
║           SQL Server Expert Skill - Lab Validation Suite             ║
║                                                                      ║
║  This script validates that all labs can run successfully.           ║
║  Run this after any changes to ensure nothing broke.                 ║
║                                                                      ║
╚══════════════════════════════════════════════════════════════════════╝
*/

SET NOCOUNT ON;
SET ANSI_WARNINGS ON;

DECLARE @TestsPassed INT = 0;
DECLARE @TestsFailed INT = 0;
DECLARE @TestResults TABLE (
    TestID INT,
    TestName NVARCHAR(255),
    Status NVARCHAR(20),
    Message NVARCHAR(MAX),
    ExecutionTimeMs INT
);

PRINT '════════════════════════════════════════════════════════════════';
PRINT '  LAB VALIDATION SUITE - Starting'
PRINT '════════════════════════════════════════════════════════════════';
PRINT '';

-- ============================================================================
-- TEST 1: Check if SampleEcommerce database exists
-- ============================================================================
PRINT '[TEST 1] Checking if SampleEcommerce database exists...';
DECLARE @StartTime DATETIME = GETDATE();

IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'SampleEcommerce')
BEGIN
    INSERT INTO @TestResults VALUES (
        1,
        'Database Exists',
        'PASS',
        'SampleEcommerce database found',
        DATEDIFF(MILLISECOND, @StartTime, GETDATE())
    );
    SET @TestsPassed = @TestsPassed + 1;
    PRINT '  ✓ PASS: SampleEcommerce database exists';
END
ELSE
BEGIN
    INSERT INTO @TestResults VALUES (
        1,
        'Database Exists',
        'FAIL',
        'SampleEcommerce database not found. Run: examples/setup-sample-database.sql',
        DATEDIFF(MILLISECOND, @StartTime, GETDATE())
    );
    SET @TestsFailed = @TestsFailed + 1;
    PRINT '  ✗ FAIL: SampleEcommerce database not found';
    PRINT '  FIX: Run examples/setup-sample-database.sql first';
END

PRINT '';

-- ============================================================================
-- TEST 2: Check if Customers table exists with required columns
-- ============================================================================
PRINT '[TEST 2] Checking Customers table structure...';
SET @StartTime = GETDATE();

IF EXISTS (
    SELECT 1 FROM SampleEcommerce.INFORMATION_SCHEMA.TABLES
    WHERE TABLE_NAME = 'Customers'
)
BEGIN
    IF EXISTS (
        SELECT 1 FROM SampleEcommerce.INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = 'Customers'
        AND COLUMN_NAME IN ('CustomerID', 'CustomerName', 'Country')
    )
    BEGIN
        INSERT INTO @TestResults VALUES (
            2,
            'Customers Table',
            'PASS',
            'Customers table with required columns found',
            DATEDIFF(MILLISECOND, @StartTime, GETDATE())
        );
        SET @TestsPassed = @TestsPassed + 1;
        PRINT '  ✓ PASS: Customers table structure is correct';
    END
    ELSE
    BEGIN
        INSERT INTO @TestResults VALUES (
            2,
            'Customers Table',
            'FAIL',
            'Customers table missing required columns',
            DATEDIFF(MILLISECOND, @StartTime, GETDATE())
        );
        SET @TestsFailed = @TestsFailed + 1;
        PRINT '  ✗ FAIL: Customers table missing columns';
    END
END
ELSE
BEGIN
    INSERT INTO @TestResults VALUES (
        2,
        'Customers Table',
        'FAIL',
        'Customers table not found',
        DATEDIFF(MILLISECOND, @StartTime, GETDATE())
    );
    SET @TestsFailed = @TestsFailed + 1;
    PRINT '  ✗ FAIL: Customers table not found';
END

PRINT '';

-- ============================================================================
-- TEST 3: Check if Orders table exists with required columns
-- ============================================================================
PRINT '[TEST 3] Checking Orders table structure...';
SET @StartTime = GETDATE();

IF EXISTS (
    SELECT 1 FROM SampleEcommerce.INFORMATION_SCHEMA.TABLES
    WHERE TABLE_NAME = 'Orders'
)
BEGIN
    IF EXISTS (
        SELECT 1 FROM SampleEcommerce.INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = 'Orders'
        AND COLUMN_NAME IN ('OrderID', 'CustomerID', 'OrderDate', 'TotalAmount')
    )
    BEGIN
        INSERT INTO @TestResults VALUES (
            3,
            'Orders Table',
            'PASS',
            'Orders table with required columns found',
            DATEDIFF(MILLISECOND, @StartTime, GETDATE())
        );
        SET @TestsPassed = @TestsPassed + 1;
        PRINT '  ✓ PASS: Orders table structure is correct';
    END
    ELSE
    BEGIN
        INSERT INTO @TestResults VALUES (
            3,
            'Orders Table',
            'FAIL',
            'Orders table missing required columns',
            DATEDIFF(MILLISECOND, @StartTime, GETDATE())
        );
        SET @TestsFailed = @TestsFailed + 1;
        PRINT '  ✗ FAIL: Orders table missing columns';
    END
END
ELSE
BEGIN
    INSERT INTO @TestResults VALUES (
        3,
        'Orders Table',
        'FAIL',
        'Orders table not found',
        DATEDIFF(MILLISECOND, @StartTime, GETDATE())
    );
    SET @TestsFailed = @TestsFailed + 1;
    PRINT '  ✗ FAIL: Orders table not found';
END

PRINT '';

-- ============================================================================
-- TEST 4: Check data integrity - No NULL in NOT NULL columns
-- ============================================================================
PRINT '[TEST 4] Checking data integrity (NULL values)...';
SET @StartTime = GETDATE();

DECLARE @NullCount INT = 0;

SELECT @NullCount = COUNT(*)
FROM SampleEcommerce.dbo.Orders
WHERE OrderID IS NULL OR CustomerID IS NULL OR OrderDate IS NULL;

IF @NullCount = 0
BEGIN
    INSERT INTO @TestResults VALUES (
        4,
        'Data Integrity',
        'PASS',
        'No NULL values in required columns',
        DATEDIFF(MILLISECOND, @StartTime, GETDATE())
    );
    SET @TestsPassed = @TestsPassed + 1;
    PRINT '  ✓ PASS: Data integrity check passed';
END
ELSE
BEGIN
    INSERT INTO @TestResults VALUES (
        4,
        'Data Integrity',
        'FAIL',
        'Found ' + CAST(@NullCount AS NVARCHAR(10)) + ' NULL values',
        DATEDIFF(MILLISECOND, @StartTime, GETDATE())
    );
    SET @TestsFailed = @TestsFailed + 1;
    PRINT '  ✗ FAIL: Found NULL values in Orders table';
END

PRINT '';

-- ============================================================================
-- TEST 5: Check if LAB-01 problem query runs without error
-- ============================================================================
PRINT '[TEST 5] Running LAB-01 problem query...';
SET @StartTime = GETDATE();

BEGIN TRY
    DECLARE @LabResults TABLE (
        CustomerID INT,
        CustomerName NVARCHAR(255),
        Country NVARCHAR(100),
        TotalOrders INT,
        TotalSpent DECIMAL(10, 2),
        LastOrderDate DATE
    );

    INSERT INTO @LabResults
    SELECT
        c.CustomerID,
        c.CustomerName,
        c.Country,
        COUNT(o.OrderID) AS TotalOrders,
        ISNULL(SUM(o.TotalAmount), 0) AS TotalSpent,
        MAX(o.OrderDate) AS LastOrderDate
    FROM SampleEcommerce.dbo.Customers c
    LEFT JOIN SampleEcommerce.dbo.Orders o ON c.CustomerID = o.CustomerID
    WHERE YEAR(o.OrderDate) = YEAR(GETDATE())
    GROUP BY c.CustomerID, c.CustomerName, c.Country
    ORDER BY TotalSpent DESC;

    INSERT INTO @TestResults VALUES (
        5,
        'LAB-01 Problem Query',
        'PASS',
        'Query executed successfully',
        DATEDIFF(MILLISECOND, @StartTime, GETDATE())
    );
    SET @TestsPassed = @TestsPassed + 1;
    PRINT '  ✓ PASS: LAB-01 problem query runs without error';
END TRY
BEGIN CATCH
    INSERT INTO @TestResults VALUES (
        5,
        'LAB-01 Problem Query',
        'FAIL',
        ERROR_MESSAGE(),
        DATEDIFF(MILLISECOND, @StartTime, GETDATE())
    );
    SET @TestsFailed = @TestsFailed + 1;
    PRINT '  ✗ FAIL: ' + ERROR_MESSAGE();
END CATCH

PRINT '';

-- ============================================================================
-- TEST 6: Check if OrderDetails table exists (for advanced labs)
-- ============================================================================
PRINT '[TEST 6] Checking OrderDetails table...';
SET @StartTime = GETDATE();

IF EXISTS (
    SELECT 1 FROM SampleEcommerce.INFORMATION_SCHEMA.TABLES
    WHERE TABLE_NAME = 'OrderDetails'
)
BEGIN
    INSERT INTO @TestResults VALUES (
        6,
        'OrderDetails Table',
        'PASS',
        'OrderDetails table exists for advanced labs',
        DATEDIFF(MILLISECOND, @StartTime, GETDATE())
    );
    SET @TestsPassed = @TestsPassed + 1;
    PRINT '  ✓ PASS: OrderDetails table exists';
END
ELSE
BEGIN
    INSERT INTO @TestResults VALUES (
        6,
        'OrderDetails Table',
        'WARN',
        'OrderDetails table not found - some advanced labs may not work',
        DATEDIFF(MILLISECOND, @StartTime, GETDATE())
    );
    PRINT '  ⚠ WARN: OrderDetails table not found';
END

PRINT '';

-- ============================================================================
-- SUMMARY REPORT
-- ============================================================================
PRINT '════════════════════════════════════════════════════════════════';
PRINT '  TEST SUMMARY';
PRINT '════════════════════════════════════════════════════════════════';
PRINT '';

SELECT
    TestID,
    TestName,
    Status,
    Message,
    ExecutionTimeMs
FROM @TestResults
ORDER BY TestID;

PRINT '';
PRINT '────────────────────────────────────────────────────────────────';
PRINT 'RESULTS: ' + CAST(@TestsPassed AS NVARCHAR(10)) + ' Passed, ' +
       CAST(@TestsFailed AS NVARCHAR(10)) + ' Failed';

IF @TestsFailed = 0
BEGIN
    PRINT '════════════════════════════════════════════════════════════════';
    PRINT '  ✓ ALL TESTS PASSED - Labs are ready to use!';
    PRINT '════════════════════════════════════════════════════════════════';
END
ELSE
BEGIN
    PRINT '════════════════════════════════════════════════════════════════';
    PRINT '  ✗ SOME TESTS FAILED - Fix issues before proceeding';
    PRINT '════════════════════════════════════════════════════════════════';
END

PRINT '';
PRINT 'Next: Run LAB-01 at labs/LAB-01-optimize-slow-query/';
