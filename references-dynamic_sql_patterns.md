# Secure Dynamic SQL Patterns

## Safe vs Unsafe Dynamic SQL

### ❌ UNSAFE: SQL Injection Risk
```sql
-- NEVER do this!
DECLARE @SQL NVARCHAR(MAX) = 'SELECT * FROM Users WHERE UserID = ' + @UserID
EXECUTE sp_executesql @SQL
```

### ✅ SAFE: Parameterized Dynamic SQL
```sql
-- CORRECT: Use sp_executesql with parameters
DECLARE @SQL NVARCHAR(MAX) = N'SELECT * FROM Users WHERE UserID = @UserID'
EXECUTE sp_executesql @SQL, N'@UserID INT', @UserID = @UserID
```

## Pattern 1: Simple Dynamic WHERE Clause

```sql
CREATE PROCEDURE sp_SearchCustomers
    @CustomerID INT = NULL,
    @Name NVARCHAR(100) = NULL
AS
BEGIN
    DECLARE @SQL NVARCHAR(MAX) = N'SELECT * FROM Customers WHERE 1=1'
    DECLARE @Params NVARCHAR(MAX) = N''
    
    IF @CustomerID IS NOT NULL
    BEGIN
        SET @SQL += N' AND CustomerID = @CustomerID'
        SET @Params = N'@CustomerID INT, '
    END
    
    IF @Name IS NOT NULL
    BEGIN
        SET @SQL += N' AND Name LIKE @Name'
        IF @Params = N''
            SET @Params = N'@Name NVARCHAR(100)'
        ELSE
            SET @Params += N'@Name NVARCHAR(100)'
    END
    
    IF @Params != N''
        EXECUTE sp_executesql @SQL, @Params, 
            @CustomerID = @CustomerID, 
            @Name = @Name + '%'
    ELSE
        EXECUTE sp_executesql @SQL
END
```

## Pattern 2: Dynamic Table/Column Names

**Challenge:** Table and column names cannot be parameterized
**Solution:** Validate against catalog views

```sql
CREATE PROCEDURE sp_GetTableData
    @TableName NVARCHAR(128),
    @ColumnName NVARCHAR(128)
AS
BEGIN
    -- Validate table exists
    IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = @TableName)
    BEGIN
        RAISERROR('Invalid table name', 16, 1)
        RETURN
    END
    
    -- Validate column exists
    IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS 
                   WHERE TABLE_NAME = @TableName AND COLUMN_NAME = @ColumnName)
    BEGIN
        RAISERROR('Invalid column name', 16, 1)
        RETURN
    END
    
    -- Now safe to use in dynamic SQL
    DECLARE @SQL NVARCHAR(MAX) = N'SELECT ' + QUOTENAME(@ColumnName) + 
                                 N' FROM ' + QUOTENAME(@TableName)
    EXECUTE sp_executesql @SQL
END
```

## Pattern 3: Dynamic ORDER BY

```sql
CREATE PROCEDURE sp_GetOrdersOrdered
    @OrderByColumn NVARCHAR(50),
    @OrderByDirection NVARCHAR(4) = 'ASC'
AS
BEGIN
    -- Validate column
    IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS 
                   WHERE TABLE_NAME = 'Orders' AND COLUMN_NAME = @OrderByColumn)
    BEGIN
        RAISERROR('Invalid sort column', 16, 1)
        RETURN
    END
    
    -- Validate direction
    IF @OrderByDirection NOT IN ('ASC', 'DESC')
    BEGIN
        RAISERROR('Order direction must be ASC or DESC', 16, 1)
        RETURN
    END
    
    DECLARE @SQL NVARCHAR(MAX) = N'SELECT * FROM Orders ORDER BY ' + 
                                 QUOTENAME(@OrderByColumn) + ' ' + @OrderByDirection
    EXECUTE sp_executesql @SQL
END
```

## Pattern 4: String Escaping for LIKE

```sql
CREATE PROCEDURE sp_SearchProductName
    @ProductName NVARCHAR(100)
AS
BEGIN
    -- Escape special LIKE characters
    DECLARE @EscapedName NVARCHAR(100) = 
        REPLACE(REPLACE(REPLACE(@ProductName, '[', '[[]'), '%', '[%]'), '_', '[_]')
    
    DECLARE @SQL NVARCHAR(MAX) = N'SELECT * FROM Products WHERE ProductName LIKE @Pattern ESCAPE ''['''
    EXECUTE sp_executesql @SQL, N'@Pattern NVARCHAR(100)', 
        @Pattern = @EscapedName + '%'
END
```

## Pattern 5: IN Clause with Multiple Values

❌ **UNSAFE:**
```sql
DECLARE @IDs NVARCHAR(MAX) = '1,2,3'
DECLARE @SQL NVARCHAR(MAX) = 'SELECT * FROM Orders WHERE OrderID IN (' + @IDs + ')'
EXECUTE sp_executesql @SQL
```

✅ **SAFE:**
```sql
CREATE PROCEDURE sp_GetOrdersByIDs
    @IDs NVARCHAR(MAX)  -- Comma-separated list
AS
BEGIN
    -- Parse CSV into table
    DECLARE @OrderIDs TABLE (OrderID INT)
    INSERT INTO @OrderIDs (OrderID)
    SELECT CAST(value AS INT) FROM STRING_SPLIT(@IDs, ',')
    
    SELECT * FROM Orders WHERE OrderID IN (SELECT OrderID FROM @OrderIDs)
END
```

## Pattern 6: QUOTENAME for Safe Identifiers

```sql
DECLARE @TableName NVARCHAR(128) = 'Orders'
DECLARE @ColumnName NVARCHAR(128) = 'OrderID'

-- QUOTENAME handles special characters and brackets
DECLARE @SQL NVARCHAR(MAX) = N'SELECT ' + QUOTENAME(@ColumnName) + 
                             N' FROM ' + QUOTENAME(@TableName)
EXECUTE sp_executesql @SQL
-- Result: SELECT [OrderID] FROM [Orders]
```

## Security Checklist

✅ **Do:**
- Always use parameterized queries with sp_executesql
- Validate table/column names against catalog views
- Use QUOTENAME() for identifiers
- Escape LIKE wildcards when needed
- Test with malicious input: `'; DROP TABLE--`
- Log dynamic SQL for audit trails
- Restrict permissions on stored procedures

❌ **Don't:**
- Concatenate user input into SQL strings
- Trust application-layer validation alone
- Use xp_executesql (deprecated)
- Expose dynamic SQL to users directly
- Skip validation of non-parametrizable elements

## Testing Dynamic SQL Safety

```sql
-- Test injection attempt
DECLARE @UserInput NVARCHAR(100) = '''; DROP TABLE Orders;--'
DECLARE @SQL NVARCHAR(MAX) = N'SELECT * FROM Users WHERE UserID = @ID'
EXECUTE sp_executesql @SQL, N'@ID NVARCHAR(100)', @ID = @UserInput
-- Safe: Will search for literal string, not execute DROP
```
