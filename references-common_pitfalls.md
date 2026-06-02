# Common SQL Server Pitfalls to Avoid

## 🔴 Critical Production Pitfalls

### 1. Ignoring TRY-CATCH in Procedures
**Pitfall:** Unhandled exceptions cause cascading failures
```sql
-- ❌ BAD: No error handling
CREATE PROCEDURE sp_ProcessOrders
    @OrderID INT
AS
BEGIN
    UPDATE Orders SET Status = 'Processing' WHERE OrderID = @OrderID
    UPDATE OrderDetails SET ProcessedDate = GETDATE() WHERE OrderID = @OrderID
    -- If second statement fails, first succeeded = data inconsistency
END

-- ✅ GOOD: Proper error handling
CREATE PROCEDURE sp_ProcessOrders
    @OrderID INT
AS
BEGIN
    SET XACT_ABORT ON
    BEGIN TRY
        BEGIN TRANSACTION
        UPDATE Orders SET Status = 'Processing' WHERE OrderID = @OrderID
        UPDATE OrderDetails SET ProcessedDate = GETDATE() WHERE OrderID = @OrderID
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
        THROW
    END CATCH
END
```

### 2. Implicit Column Ordering in INSERT
**Pitfall:** Adding columns breaks dependent code
```sql
-- ❌ BAD: Depends on column order
INSERT INTO Orders VALUES (@CustID, @Amount, @Status)

-- ✅ GOOD: Explicit columns
INSERT INTO Orders (CustomerID, Amount, Status) VALUES (@CustID, @Amount, @Status)
```

### 3. Long Running Transactions
**Pitfall:** Locks held too long = blocking cascades
```sql
-- ❌ BAD: Long transaction
BEGIN TRANSACTION
    UPDATE Orders SET Status = 'Shipped' WHERE OrderID = @OrderID
    EXECUTE sp_GenerateReport  -- Could take 30+ seconds!
    INSERT INTO ShipmentLog VALUES (@OrderID, GETDATE())
COMMIT TRANSACTION

-- ✅ GOOD: Short transaction
BEGIN TRANSACTION
    UPDATE Orders SET Status = 'Shipped' WHERE OrderID = @OrderID
    INSERT INTO ShipmentLog VALUES (@OrderID, GETDATE())
COMMIT TRANSACTION
-- Then generate report separately
EXECUTE sp_GenerateReport @OrderID
```

### 4. NOLOCK Without Understanding Risks
**Pitfall:** Dirty reads + uncommitted data
```sql
-- ❌ RISKY: Could read uncommitted data
SELECT * FROM Orders (NOLOCK) WHERE CustomerID = @CustID

-- ✅ BETTER: Use appropriate isolation level
SET TRANSACTION ISOLATION LEVEL READ_COMMITTED
SELECT * FROM Orders WHERE CustomerID = @CustID
```

### 5. Not Testing with Production Data Volume
**Pitfall:** Query/index works with 1K rows, fails at 100M
```sql
-- Works fine in dev with small data
SELECT * FROM Orders WHERE YEAR(OrderDate) = 2026

-- Fails in production due to table scan
-- Solution: Use partitioning or better index strategy
```

### 6. Cursor-Based Processing (RBAR)
**Pitfall:** Row-by-row processing is 1000x slower
```sql
-- ❌ EXTREMELY SLOW: Cursor
DECLARE cur CURSOR FOR SELECT OrderID, Amount FROM Orders
OPEN cur
FETCH NEXT FROM cur INTO @OrderID, @Amount
WHILE @@FETCH_STATUS = 0
BEGIN
    UPDATE OrderDetails SET Amount = @Amount WHERE OrderID = @OrderID
    FETCH NEXT FROM cur INTO @OrderID, @Amount
END

-- ✅ FAST: Set-based
UPDATE od
SET Amount = o.Amount
FROM OrderDetails od
INNER JOIN Orders o ON od.OrderID = o.OrderID
```

---

## 🟡 Performance Pitfalls

### 1. Functions in WHERE Clause
**Pitfall:** Prevents index seek, forces table scan
```sql
-- ❌ SLOW: YEAR() prevents index
SELECT * FROM Orders WHERE YEAR(OrderDate) = 2026

-- ✅ FAST: Date range uses index
SELECT * FROM Orders 
WHERE OrderDate >= '2026-01-01' AND OrderDate < '2027-01-01'
```

### 2. SELECT * in Application Code
**Pitfall:** Retrieves unnecessary columns = more I/O
```sql
-- ❌ BAD
SELECT * FROM Orders

-- ✅ GOOD
SELECT OrderID, CustomerID, Amount FROM Orders
```

### 3. Missing Statistics Update
**Pitfall:** Stale stats = poor query plans
```sql
-- Maintain statistics on high-activity tables
UPDATE STATISTICS Orders
UPDATE STATISTICS OrderDetails WITH FULLSCAN
```

### 4. Building SQL Strings by Concatenation
**Pitfall:** SQL Injection + no plan caching
```sql
-- ❌ CRITICAL SECURITY RISK
EXECUTE ('SELECT * FROM Orders WHERE OrderID = ' + @OrderID)

-- ✅ SAFE: Parameterized
EXECUTE sp_executesql 
    N'SELECT * FROM Orders WHERE OrderID = @ID',
    N'@ID INT',
    @ID = @OrderID
```

### 5. Implicit Conversions in JOINs
**Pitfall:** Type mismatch forces index scan
```sql
-- ❌ BAD: String to INT conversion
SELECT o.*, c.CustomerName
FROM Orders o
INNER JOIN Customers c ON o.CustomerID = CAST(c.CustomerID AS INT)

-- ✅ GOOD: Matching types
SELECT o.*, c.CustomerName
FROM Orders o
INNER JOIN Customers c ON o.CustomerID = c.CustomerID
```

---

## 🟠 Design Pitfalls

### 1. Over-Normalization
**Pitfall:** Too many JOINs = poor performance
```sql
-- Customers -> Addresses -> Cities -> Countries -> Regions
-- Query joins 5 tables just to get a customer name = slow!
-- Solution: Denormalize strategically for reporting
```

### 2. Under-Indexing
**Pitfall:** Missing indexes on filter/join columns
```sql
-- If this runs frequently, add indexes
SELECT * FROM Orders WHERE Status = 'Pending' AND CustomerID = @CustID

-- Create index
CREATE INDEX IX_Orders_Status_Customer ON Orders(Status, CustomerID)
```

### 3. Missing Primary Keys
**Pitfall:** No guaranteed uniqueness = data quality issues
```sql
-- ✅ ALWAYS define primary keys
CREATE TABLE Customers (
    CustomerID INT PRIMARY KEY,
    CustomerName NVARCHAR(100) NOT NULL
)
```

### 4. No Foreign Keys
**Pitfall:** Orphan records + data inconsistency
```sql
-- ✅ GOOD: Foreign key constraint
ALTER TABLE Orders
ADD CONSTRAINT FK_Orders_Customers 
FOREIGN KEY (CustomerID) REFERENCES Customers(CustomerID)
```

### 5. Storing Calculated Values
**Pitfall:** Data inconsistency when source changes
```sql
-- ❌ BAD: Store calculated value
CREATE TABLE Orders (
    OrderID INT,
    LineItemCount INT,  -- Could be wrong if details change!
    Amount DECIMAL
)

-- ✅ GOOD: Calculate on read
SELECT OrderID, 
       (SELECT COUNT(*) FROM OrderDetails WHERE OrderID = o.OrderID) AS LineItemCount
FROM Orders o
```

---

## Prevention Checklist

- [ ] All procedures have TRY-CATCH
- [ ] Transactions are short and focused
- [ ] INSERT/UPDATE/DELETE use explicit column lists
- [ ] Queries reviewed with actual execution plan
- [ ] No functions on filter columns
- [ ] All tables have primary keys
- [ ] Foreign key constraints in place
- [ ] Indexes analyzed for filter/join columns
- [ ] Code tested with production data volume
- [ ] No NOLOCK without careful consideration
- [ ] Statistics updated on high-activity tables
- [ ] No cursor-based row-by-row processing
