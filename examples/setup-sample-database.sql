-- ============================================================================
-- SAMPLE DATABASE FOR LEARNING SQL SERVER
-- ============================================================================
-- This script creates a realistic ecommerce database with sample data
-- Use this as the foundation for all examples and labs
--
-- Database: SampleEcommerce
-- Size: ~5MB with sample data
-- Scenario: Multi-vendor ecommerce platform
--
-- WARNING: This script DROPS the database if it exists
-- ============================================================================

-- Drop existing database
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'SampleEcommerce')
BEGIN
    ALTER DATABASE SampleEcommerce SET SINGLE_USER WITH ROLLBACK IMMEDIATE
    DROP DATABASE SampleEcommerce
END
GO

-- Create database
CREATE DATABASE SampleEcommerce
GO

USE SampleEcommerce
GO

-- ============================================================================
-- 1. CUSTOMERS TABLE
-- ============================================================================
CREATE TABLE Customers (
    CustomerID INT PRIMARY KEY IDENTITY(1,1),
    CustomerName NVARCHAR(100) NOT NULL,
    Email NVARCHAR(100) UNIQUE,
    Country NVARCHAR(50) NOT NULL,
    City NVARCHAR(50),
    RegisterDate DATETIME2 NOT NULL DEFAULT GETDATE(),
    IsActive BIT NOT NULL DEFAULT 1,
    TotalSpent DECIMAL(12,2) DEFAULT 0
)

CREATE NONCLUSTERED INDEX IX_Customers_Email ON Customers(Email)
CREATE NONCLUSTERED INDEX IX_Customers_Country ON Customers(Country)
GO

-- ============================================================================
-- 2. PRODUCTS TABLE
-- ============================================================================
CREATE TABLE Products (
    ProductID INT PRIMARY KEY IDENTITY(1,1),
    ProductName NVARCHAR(100) NOT NULL,
    Category NVARCHAR(50) NOT NULL,
    Price DECIMAL(10,2) NOT NULL CHECK (Price > 0),
    Stock INT NOT NULL DEFAULT 0,
    CreatedDate DATETIME2 NOT NULL DEFAULT GETDATE(),
    IsActive BIT NOT NULL DEFAULT 1
)

CREATE NONCLUSTERED INDEX IX_Products_Category ON Products(Category)
CREATE NONCLUSTERED INDEX IX_Products_Price ON Products(Price)
GO

-- ============================================================================
-- 3. ORDERS TABLE
-- ============================================================================
CREATE TABLE Orders (
    OrderID INT PRIMARY KEY IDENTITY(1,1),
    CustomerID INT NOT NULL FOREIGN KEY REFERENCES Customers(CustomerID),
    OrderDate DATETIME2 NOT NULL DEFAULT GETDATE(),
    TotalAmount DECIMAL(12,2) NOT NULL,
    Status NVARCHAR(20) NOT NULL DEFAULT 'Pending',
    ShippedDate DATETIME2 NULL,
    DeliveredDate DATETIME2 NULL
)

CREATE NONCLUSTERED INDEX IX_Orders_CustomerID ON Orders(CustomerID)
CREATE NONCLUSTERED INDEX IX_Orders_OrderDate ON Orders(OrderDate)
CREATE NONCLUSTERED INDEX IX_Orders_Status ON Orders(Status)
GO

-- ============================================================================
-- 4. ORDER DETAILS TABLE
-- ============================================================================
CREATE TABLE OrderDetails (
    OrderDetailID INT PRIMARY KEY IDENTITY(1,1),
    OrderID INT NOT NULL FOREIGN KEY REFERENCES Orders(OrderID),
    ProductID INT NOT NULL FOREIGN KEY REFERENCES Products(ProductID),
    Quantity INT NOT NULL CHECK (Quantity > 0),
    UnitPrice DECIMAL(10,2) NOT NULL,
    LineTotal DECIMAL(12,2) NOT NULL,
    UNIQUE (OrderID, ProductID) -- One product per order
)

CREATE NONCLUSTERED INDEX IX_OrderDetails_OrderID ON OrderDetails(OrderID)
CREATE NONCLUSTERED INDEX IX_OrderDetails_ProductID ON OrderDetails(ProductID)
GO

-- ============================================================================
-- 5. PRODUCT REVIEWS TABLE
-- ============================================================================
CREATE TABLE ProductReviews (
    ReviewID INT PRIMARY KEY IDENTITY(1,1),
    ProductID INT NOT NULL FOREIGN KEY REFERENCES Products(ProductID),
    CustomerID INT NOT NULL FOREIGN KEY REFERENCES Customers(CustomerID),
    Rating INT NOT NULL CHECK (Rating BETWEEN 1 AND 5),
    ReviewText NVARCHAR(MAX),
    ReviewDate DATETIME2 NOT NULL DEFAULT GETDATE(),
    Helpful INT DEFAULT 0
)

CREATE NONCLUSTERED INDEX IX_ProductReviews_ProductID ON ProductReviews(ProductID)
CREATE NONCLUSTERED INDEX IX_ProductReviews_Rating ON ProductReviews(Rating)
GO

-- ============================================================================
-- 6. INVENTORY TRANSACTIONS TABLE (for audit trail)
-- ============================================================================
CREATE TABLE InventoryTransactions (
    TransactionID INT PRIMARY KEY IDENTITY(1,1),
    ProductID INT NOT NULL FOREIGN KEY REFERENCES Products(ProductID),
    TransactionType NVARCHAR(20) NOT NULL, -- 'Purchase', 'Return', 'Adjustment'
    Quantity INT NOT NULL,
    TransactionDate DATETIME2 NOT NULL DEFAULT GETDATE(),
    Reference NVARCHAR(100) -- e.g., OrderID or reason
)

CREATE NONCLUSTERED INDEX IX_InventoryTransactions_ProductID ON InventoryTransactions(ProductID)
CREATE NONCLUSTERED INDEX IX_InventoryTransactions_Date ON InventoryTransactions(TransactionDate)
GO

-- ============================================================================
-- SAMPLE DATA: CUSTOMERS (100 records)
-- ============================================================================
INSERT INTO Customers (CustomerName, Email, Country, City)
SELECT
    'Customer ' + CAST(ROW_NUMBER() OVER (ORDER BY @@SERVERNAME) AS VARCHAR(5)),
    'customer' + CAST(ROW_NUMBER() OVER (ORDER BY @@SERVERNAME) AS VARCHAR(5)) + '@example.com',
    CASE ROW_NUMBER() OVER (ORDER BY @@SERVERNAME) % 5
        WHEN 0 THEN 'USA'
        WHEN 1 THEN 'Canada'
        WHEN 2 THEN 'UK'
        WHEN 3 THEN 'Germany'
        ELSE 'France'
    END,
    CASE ROW_NUMBER() OVER (ORDER BY @@SERVERNAME) % 10
        WHEN 0 THEN 'New York'
        WHEN 1 THEN 'Los Angeles'
        WHEN 2 THEN 'Chicago'
        WHEN 3 THEN 'Toronto'
        WHEN 4 THEN 'London'
        WHEN 5 THEN 'Berlin'
        WHEN 6 THEN 'Paris'
        WHEN 7 THEN 'Madrid'
        WHEN 8 THEN 'Amsterdam'
        ELSE 'Brussels'
    END
FROM master..spt_values t1, master..spt_values t2
WHERE t1.number < 50 AND t2.number < 3

GO

-- ============================================================================
-- SAMPLE DATA: PRODUCTS (50 records)
-- ============================================================================
INSERT INTO Products (ProductName, Category, Price, Stock)
VALUES
-- Electronics
('Laptop Pro 15', 'Electronics', 1299.99, 45),
('Smartphone X', 'Electronics', 799.99, 120),
('Wireless Headphones', 'Electronics', 199.99, 200),
('USB-C Hub', 'Electronics', 49.99, 500),
('Mechanical Keyboard', 'Electronics', 149.99, 75),
('4K Monitor', 'Electronics', 399.99, 30),
('Webcam HD', 'Electronics', 89.99, 150),
('Mouse Pad Large', 'Electronics', 29.99, 300),

-- Books
('SQL Server Performance Tuning', 'Books', 49.99, 100),
('Database Design Mastery', 'Books', 59.99, 80),
('Advanced T-SQL', 'Books', 69.99, 60),
('Data Modeling Guide', 'Books', 54.99, 70),

-- Clothing
('Premium T-Shirt', 'Clothing', 39.99, 200),
('Jeans Slim Fit', 'Clothing', 79.99, 150),
('Winter Jacket', 'Clothing', 149.99, 80),
('Athletic Shoes', 'Clothing', 119.99, 120),
('Casual Hoodie', 'Clothing', 69.99, 100),

-- Home & Garden
('Office Chair Ergonomic', 'Home', 299.99, 50),
('Desk Lamp LED', 'Home', 59.99, 120),
('Desk Organizer', 'Home', 29.99, 200),
('Monitor Stand', 'Home', 49.99, 150),

-- Accessories
('Phone Case', 'Accessories', 19.99, 500),
('Screen Protector', 'Accessories', 9.99, 800),
('Cable Pack', 'Accessories', 24.99, 300),
('Power Bank 20000mAh', 'Accessories', 39.99, 200),

-- Additional products to reach 50
('Tablet 10inch', 'Electronics', 399.99, 60),
('Smartwatch Pro', 'Electronics', 299.99, 85),
('Portable SSD 1TB', 'Electronics', 129.99, 100),
('Graphics Card RTX 4070', 'Electronics', 599.99, 25),
('RAM Kit 32GB', 'Electronics', 159.99, 40),
('SSD NVMe 2TB', 'Electronics', 249.99, 55),
('Mechanical Keyboard RGB', 'Electronics', 179.99, 60),
('Gaming Mouse', 'Electronics', 89.99, 130),
('Notebook Set', 'Books', 24.99, 200),
('Pen Set Premium', 'Accessories', 44.99, 150),
('Backpack Pro', 'Clothing', 89.99, 90),
('Water Bottle', 'Accessories', 29.99, 400),
('Desk Pad', 'Home', 39.99, 180),
('File Cabinet', 'Home', 149.99, 35),
('Router WiFi 6', 'Electronics', 179.99, 70),
('Printer LaserJet', 'Electronics', 299.99, 20),
('External Hard Drive 4TB', 'Electronics', 99.99, 110),
('USB Flash Drive 128GB', 'Accessories', 34.99, 250),
('HDMI Cable 2M', 'Accessories', 14.99, 500)

GO

-- ============================================================================
-- SAMPLE DATA: ORDERS (~1000 orders) and ORDER DETAILS
-- ============================================================================
-- Generate orders with realistic dates (last 6 months)
DECLARE @Counter INT = 1
DECLARE @MaxOrders INT = 1000
DECLARE @CustomerID INT
DECLARE @OrderDate DATETIME2
DECLARE @Status NVARCHAR(20)
DECLARE @TotalAmount DECIMAL(12,2)
DECLARE @OrderID INT
DECLARE @ItemCount INT
DECLARE @ItemCounter INT
DECLARE @ProductID INT
DECLARE @Quantity INT
DECLARE @UnitPrice DECIMAL(10,2)
DECLARE @LineTotal DECIMAL(12,2)

WHILE @Counter <= @MaxOrders
BEGIN
    BEGIN TRY
        -- ✅ FIX #1: Initialize variables for this iteration
        SET @CustomerID = (@Counter % 100) + 1
        SET @OrderDate = DATEADD(HOUR, -(@Counter * 2), GETDATE())
        SET @Status = CASE
            WHEN @Counter % 10 = 0 THEN 'Pending'
            WHEN @Counter % 10 = 1 THEN 'Processing'
            WHEN @Counter % 10 = 2 THEN 'Shipped'
            ELSE 'Delivered'
        END
        SET @TotalAmount = 0

        -- ✅ FIX #2: Insert Order with explicit TotalAmount = 0
        INSERT INTO Orders (CustomerID, OrderDate, Status, TotalAmount)
        VALUES (@CustomerID, @OrderDate, @Status, 0)

        SET @OrderID = SCOPE_IDENTITY()

        -- ✅ FIX #3: Validate OrderID was created
        IF @OrderID IS NULL
        BEGIN
            RAISERROR ('Failed to create OrderID', 16, 1)
        END

        -- Add 1-5 items per order
        SET @ItemCount = (@Counter % 5) + 1
        SET @ItemCounter = 1

        WHILE @ItemCounter <= @ItemCount
        BEGIN
            SET @ProductID = ((@Counter + @ItemCounter) % 50) + 1
            SET @Quantity = (@ItemCounter % 3) + 1

            -- ✅ FIX #4: Get product price with NULL check
            SELECT @UnitPrice = Price FROM Products WHERE ProductID = @ProductID

            IF @UnitPrice IS NULL
            BEGIN
                SET @UnitPrice = 0  -- Skip product if not found (don't fail the entire order)
                SET @ItemCounter = @ItemCounter + 1
                CONTINUE
            END

            SET @LineTotal = @Quantity * @UnitPrice

            -- ✅ FIX #5: Insert order detail
            INSERT INTO OrderDetails (OrderID, ProductID, Quantity, UnitPrice, LineTotal)
            VALUES (@OrderID, @ProductID, @Quantity, @UnitPrice, @LineTotal)

            SET @TotalAmount = @TotalAmount + @LineTotal
            SET @ItemCounter = @ItemCounter + 1
        END

        -- ✅ FIX #6: Update TotalAmount with calculated value
        IF @TotalAmount > 0
        BEGIN
            UPDATE Orders SET TotalAmount = @TotalAmount WHERE OrderID = @OrderID
            UPDATE Customers SET TotalSpent = TotalSpent + @TotalAmount WHERE CustomerID = @CustomerID
        END

        SET @Counter = @Counter + 1
    END TRY
    BEGIN CATCH
        SET @Counter = @Counter + 1
        -- Continue processing other orders even if one fails
    END CATCH
END

GO

-- ============================================================================
-- SAMPLE DATA: PRODUCT REVIEWS
-- ============================================================================
INSERT INTO ProductReviews (ProductID, CustomerID, Rating, ReviewText, ReviewDate)
SELECT
    (ROW_NUMBER() OVER (ORDER BY @@SERVERNAME) % 50) + 1,
    (ROW_NUMBER() OVER (ORDER BY @@SERVERNAME) % 100) + 1,
    (ROW_NUMBER() OVER (ORDER BY @@SERVERNAME) % 5) + 1,
    'Great product! ' + CAST(ROW_NUMBER() OVER (ORDER BY @@SERVERNAME) AS VARCHAR(10)),
    DATEADD(DAY, -(ROW_NUMBER() OVER (ORDER BY @@SERVERNAME) % 180), GETDATE())
FROM master..spt_values t1, master..spt_values t2
WHERE t1.number < 100 AND t2.number < 2

GO

-- ============================================================================
-- SAMPLE DATA: INVENTORY TRANSACTIONS
-- ============================================================================
INSERT INTO InventoryTransactions (ProductID, TransactionType, Quantity, TransactionDate, Reference)
SELECT
    ProductID,
    CASE (ROW_NUMBER() OVER (PARTITION BY ProductID ORDER BY @@SERVERNAME) % 3)
        WHEN 0 THEN 'Purchase'
        WHEN 1 THEN 'Return'
        ELSE 'Adjustment'
    END,
    (ROW_NUMBER() OVER (PARTITION BY ProductID ORDER BY @@SERVERNAME) % 10) + 1,
    DATEADD(DAY, -(ROW_NUMBER() OVER (PARTITION BY ProductID ORDER BY @@SERVERNAME) * 2), GETDATE()),
    'Transaction ' + CAST(ROW_NUMBER() OVER (PARTITION BY ProductID ORDER BY @@SERVERNAME) AS VARCHAR(5))
FROM Products

GO

-- ============================================================================
-- VERIFY DATA
-- ============================================================================
SELECT 'Customers' AS TableName, COUNT(*) AS RecordCount FROM Customers
UNION ALL
SELECT 'Products', COUNT(*) FROM Products
UNION ALL
SELECT 'Orders', COUNT(*) FROM Orders
UNION ALL
SELECT 'OrderDetails', COUNT(*) FROM OrderDetails
UNION ALL
SELECT 'ProductReviews', COUNT(*) FROM ProductReviews
UNION ALL
SELECT 'InventoryTransactions', COUNT(*) FROM InventoryTransactions

GO

-- ============================================================================
-- SUMMARY
-- ============================================================================
-- Database: SampleEcommerce
-- Tables: 6
-- Total Records: ~3000
-- Use this database for all examples, labs, and case studies
--
-- Key Tables:
--   - Customers: 100 customers from 5 countries
--   - Products: 50 products in 5 categories
--   - Orders: ~1000 orders spanning last 6 months
--   - OrderDetails: ~3000 line items
--   - ProductReviews: ~200 reviews
--   - InventoryTransactions: ~150 transactions
--
-- Common Scenarios Available:
--   - Customer behavior analysis (repeat orders, spending patterns)
--   - Product performance (most popular, least stocked)
--   - Order processing (pending, shipped, delivered)
--   - Revenue analysis (by product, by customer, by period)
--   - Inventory management (stock levels, transaction history)
-- ============================================================================

PRINT 'Sample database created successfully!'
PRINT 'Database: SampleEcommerce'
PRINT 'Ready for examples, labs, and case studies'
