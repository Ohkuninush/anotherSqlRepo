# SQL Server Best Practices

## Naming Conventions

### Tables
```sql
-- PascalCase, singular form
CREATE TABLE Customer (...)   ✅
CREATE TABLE Customers (...)  ❌ (plural)
CREATE TABLE CUSTOMER (...)   ❌ (all caps)
CREATE TABLE cust (...)       ❌ (abbreviation)
```

### Columns
```sql
-- PascalCase, descriptive
CREATE TABLE Orders (
    OrderID INT,            ✅
    CustomerID INT,         ✅
    OrdDt DATETIME,         ❌ (abbreviated)
    Amount DECIMAL(10,2),   ✅
    amt DECIMAL(10,2)       ❌ (abbreviated)
)
```

### Indexes
```sql
-- idx_[purpose/columns]
CREATE INDEX idx_Orders_CustomerID ON Orders(CustomerID)          ✅
CREATE INDEX idx_Customer_Name ON Customers(LastName, FirstName)  ✅
CREATE INDEX IX_Order_1 ON Orders(OrderID)                        ❌ (vague)
```

### Stored Procedures & Functions
```sql
-- sp_[purpose] for procedures
CREATE PROCEDURE sp_GetOrdersByCustomer @CustomerID INT          ✅
CREATE FUNCTION fn_CalculateDiscount @Amount DECIMAL             ✅
CREATE PROC proc_get_orders @id int                              ❌ (inconsistent)
```

## Code Standards

### Formatting
```sql
-- Use consistent indentation (4 spaces or 1 tab)
-- Keep lines under 100 characters
-- Use meaningful aliases

-- Bad: Hard to read
SELECT o.OID,c.CName,od.QTY*od.Price as Tot FROM Orders o JOIN Customers c ON o.CID=c.CID JOIN OrderDetails od ON o.OID=od.OID WHERE o.OrderDate>'2024-01-01'

-- Good: Clear and readable
SELECT 
    o.OrderID,
    c.CustomerName,
    SUM(od.Quantity * od.UnitPrice) AS OrderTotal
FROM Orders o
INNER JOIN Customers c ON o.CustomerID = c.CustomerID
INNER JOIN OrderDetails od ON o.OrderID = od.OrderID
WHERE o.OrderDate >= '2024-01-01'
GROUP BY o.OrderID, c.CustomerName
```

### Comments
```sql
-- One-line comments for non-obvious logic

-- Multi-line comments only for complex sections
/*
    This calculation uses the fiscal year (Apr-Mar)
    rather than calendar year to match accounting periods.
    See ticket #1234 for business context.
*/
SELECT CASE 
    WHEN MONTH(OrderDate) >= 4 THEN YEAR(OrderDate)
    ELSE YEAR(OrderDate) - 1
END AS FiscalYear
```

## Stored Procedure Best Practices

```sql
CREATE PROCEDURE sp_ProcessOrders
    @OrderID INT,
    @Status NVARCHAR(50) = 'Pending'  -- Default value
AS
BEGIN
    SET NOCOUNT ON  -- Avoid "rows affected" messages
    
    -- Input validation
    IF @OrderID IS NULL OR @OrderID <= 0
    BEGIN
        RAISERROR('Invalid OrderID', 16, 1)
        RETURN 1
    END
    
    -- Use meaningful transaction names
    BEGIN TRANSACTION ProcessOrder
    
    BEGIN TRY
        UPDATE Orders 
        SET Status = @Status
        WHERE OrderID = @OrderID
        
        -- Log changes
        INSERT INTO OrderLog (OrderID, Action, Timestamp)
        VALUES (@OrderID, 'Status Updated: ' + @Status, GETDATE())
        
        COMMIT TRANSACTION ProcessOrder
        RETURN 0
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION ProcessOrder
        
        -- Log error
        INSERT INTO ErrorLog (ErrorNumber, ErrorMessage, Timestamp)
        VALUES (ERROR_NUMBER(), ERROR_MESSAGE(), GETDATE())
        
        RAISERROR('Order update failed', 16, 1)
        RETURN -1
    END CATCH
END
```

## Transaction Management

```sql
-- Keep transactions short
BEGIN TRANSACTION
    -- Only necessary statements inside transaction
    UPDATE Orders SET Status = 'Shipped' WHERE OrderID = 123
    INSERT INTO ShipmentLog VALUES (123, GETDATE())
COMMIT TRANSACTION

-- NOT like this (too long, locks resources):
BEGIN TRANSACTION
    -- This might run for 30 seconds...
    UPDATE Orders SET Status = 'Shipped'
    
    -- Long-running operation should be OUTSIDE transaction
    EXECUTE sp_ExpensiveReporting
    
    -- At this point locks are still held
COMMIT TRANSACTION
```

## Data Type Selection

```sql
CREATE TABLE GoodDataTypes (
    -- Use appropriate sizes
    UserID INT,                           -- ✅ For IDs
    UserID_Large BIGINT,                  -- ✅ Only if > 2B rows
    FirstName VARCHAR(100),               -- ✅ Latin characters
    FirstName_Intl NVARCHAR(100),         -- ✅ Unicode/emoji
    BirthDate DATE,                       -- ✅ Date only (no time)
    CreatedAt DATETIME2(0),               -- ✅ Timestamp with UTC
    Amount DECIMAL(10, 2),                -- ✅ Money (exact)
    Price FLOAT,                          -- ❌ Money (inexact, rounding)
    IsActive BIT,                         -- ✅ Boolean
    IsActive_Bad INT,                     -- ❌ Don't use INT for boolean
    PartialData NVARCHAR(MAX),            -- ⚠️ Last resort, expensive
)
```

## NULL Handling

```sql
-- Be explicit about NULL
CREATE TABLE GoodNULLHandling (
    CustomerID INT NOT NULL,                -- Required field
    MiddleName VARCHAR(100),                -- Optional (can be NULL)
    LastModified DATETIME2 DEFAULT GETDATE(), -- Has sensible default
    CreatedBy NVARCHAR(100) NOT NULL        -- Required
)

-- In queries
SELECT 
    CustomerID,
    COALESCE(MiddleName, '')AS MiddleName,  -- Convert NULL to empty
    ISNULL(Phone, 'Not provided') AS Phone   -- Alternative syntax
FROM Customers
```

## Performance Considerations

```sql
-- Don't retrieve unnecessary columns
SELECT OrderID, Amount FROM Orders  ✅
SELECT * FROM Orders                ❌ (If you only need 2 columns)

-- Don't convert in WHERE clause (prevents index use)
SELECT * FROM Orders WHERE YEAR(OrderDate) = 2024  ❌
SELECT * FROM Orders WHERE OrderDate >= '2024-01-01' AND OrderDate < '2025-01-01'  ✅

-- Use EXISTS instead of IN for large subqueries
SELECT * FROM Customers WHERE CustomerID IN (
    SELECT CustomerID FROM Orders WHERE Amount > 1000
)  ❌

SELECT * FROM Customers c WHERE EXISTS (
    SELECT 1 FROM Orders o WHERE o.CustomerID = c.CustomerID AND o.Amount > 1000
)  ✅
```

## Security Best Practices

```sql
-- Use parameterized queries (prevent SQL injection)
EXEC sp_executesql 
    N'SELECT * FROM Orders WHERE CustomerID = @ID',
    N'@ID INT',
    @ID = 123

-- Don't embed user input directly
-- (This is WRONG): SELECT * FROM Orders WHERE CustomerID = ' + @UserInput + '

-- Principle of least privilege
CREATE USER AppUser WITHOUT LOGIN
GRANT SELECT, INSERT ON Orders TO AppUser  -- Only needed permissions
DENY DELETE ON Orders TO AppUser

-- Don't use sa account for applications
-- Create application-specific accounts with limited permissions
```

## Backup & Recovery

```sql
-- Regular backups with verification
BACKUP DATABASE MyDatabase 
TO DISK = 'D:\Backups\MyDatabase_Full_20240601.bak'
WITH INIT, CHECKSUM

-- Full recovery model for critical databases
ALTER DATABASE MyDatabase SET RECOVERY FULL

-- Transaction log backups for point-in-time recovery
BACKUP LOG MyDatabase 
TO DISK = 'D:\Backups\MyDatabase_Log_20240601.trn'
WITH INIT
```

## Monitoring & Maintenance

```sql
-- Regular index maintenance
ALTER INDEX idx_Orders_Customer ON Orders REBUILD
-- or
ALTER INDEX idx_Orders_Customer ON Orders REORGANIZE

-- Update statistics
UPDATE STATISTICS Orders

-- Check database integrity
DBCC CHECKDB (MyDatabase) WITH NO_INFOMSGS

-- Monitor query performance
SELECT query_id, avg_duration, execution_count
FROM sys.query_store_query_runtime_stats
ORDER BY avg_duration DESC
```

## Documentation

✅ **Document:**
- Complex business logic in stored procedures
- Why indexes were created
- Data retention policies
- Known performance limitations
- ETL schedules and dependencies

❌ **Don't document:**
- Obvious code (WHERE clause on OrderID doesn't need comment)
- How to use SQL (everyone should know SELECT)
- Historical notes (use Git for that)
