# Transaction Management Patterns

## ACID Properties

| Property | Definition | How to Ensure |
|----------|-----------|---------------|
| **Atomicity** | All or nothing | BEGIN/COMMIT/ROLLBACK |
| **Consistency** | Valid state to valid state | Constraints + app logic |
| **Isolation** | Concurrent transactions don't interfere | Isolation levels |
| **Durability** | Committed data survives failures | Transaction log |

---

## Isolation Levels (SQL Server)

### READ UNCOMMITTED (Dirty Reads Possible) ❌
```sql
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
BEGIN TRANSACTION
    -- Can read uncommitted (dirty) data
    SELECT * FROM Orders WHERE OrderID = 123
COMMIT TRANSACTION

-- Use only for approximate counts/reports where accuracy not critical
```

### READ COMMITTED (Default) ✅
```sql
SET TRANSACTION ISOLATION LEVEL READ COMMITTED
BEGIN TRANSACTION
    -- Can only read committed data
    -- But phantom reads possible (new rows inserted between reads)
    SELECT * FROM Orders WHERE Status = 'Pending'
COMMIT TRANSACTION
```

### REPEATABLE READ
```sql
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ
BEGIN TRANSACTION
    -- Same query twice = same data (no updates by other txns)
    -- But phantom reads still possible (new rows inserted)
    SELECT * FROM Orders WHERE OrderID = 123
COMMIT TRANSACTION
```

### SERIALIZABLE (Strictest)
```sql
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE
BEGIN TRANSACTION
    -- No dirty, non-repeatable, or phantom reads
    -- But worst concurrency (most locks)
    SELECT * FROM Orders WHERE Status = 'Pending'
COMMIT TRANSACTION

-- Use only when phantom reads are unacceptable
```

### SNAPSHOT (Optimistic) ⭐
```sql
ALTER DATABASE MyDB SET ALLOW_SNAPSHOT_ISOLATION ON

SET TRANSACTION ISOLATION LEVEL SNAPSHOT
BEGIN TRANSACTION
    -- Reads consistent snapshot (no locks on reads)
    -- Other transactions can continue unblocked
    SELECT * FROM Orders WHERE OrderID = 123
    
    UPDATE Orders SET Status = 'Processed' WHERE OrderID = 123
COMMIT TRANSACTION

-- Better concurrency than SERIALIZABLE with similar protection
```

---

## Proper Transaction Structure

```sql
-- ✅ CORRECT: Short, focused transaction
CREATE PROCEDURE sp_ProcessOrder
    @OrderID INT
AS
BEGIN
    SET NOCOUNT ON
    SET XACT_ABORT ON
    
    BEGIN TRY
        -- Validation outside transaction
        IF @OrderID IS NULL OR @OrderID <= 0
            THROW 50001, 'Invalid OrderID', 1
        
        BEGIN TRANSACTION
        
        UPDATE Orders 
        SET Status = 'Processing', ProcessedDate = GETDATE()
        WHERE OrderID = @OrderID
        
        INSERT INTO OrderLog (OrderID, Action, Timestamp)
        VALUES (@OrderID, 'Processing', GETDATE())
        
        COMMIT TRANSACTION
        RETURN 0
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION
        
        INSERT INTO ErrorLog (ErrorNumber, ErrorMessage, Timestamp)
        VALUES (ERROR_NUMBER(), ERROR_MESSAGE(), GETDATE())
        
        THROW
    END CATCH
END
```

---

## Handling Nested Transactions

```sql
-- SQL Server doesn't truly support nesting, but @@TRANCOUNT tracks depth
CREATE PROCEDURE sp_OuterProc
AS
BEGIN
    BEGIN TRANSACTION  -- @@TRANCOUNT = 1
    
    -- Call nested procedure
    EXECUTE sp_InnerProc
    
    -- Only outer COMMIT actually commits
    COMMIT TRANSACTION  -- @@TRANCOUNT = 0
END

CREATE PROCEDURE sp_InnerProc
AS
BEGIN
    BEGIN TRANSACTION  -- @@TRANCOUNT = 2 (nested)
    
    UPDATE Orders SET Status = 'Processing'
    
    -- COMMIT here just decrements @@TRANCOUNT to 1 (doesn't commit)
    COMMIT TRANSACTION  -- @@TRANCOUNT = 1
    
    -- If error occurs, inner ROLLBACK rolls back ALL changes!
END

-- Better approach: Use SAVEPOINTS
CREATE PROCEDURE sp_BetterNested
AS
BEGIN
    BEGIN TRANSACTION
    
    UPDATE Orders SET Status = 'Processing'
    
    SAVE TRANSACTION savepoint1
    
    BEGIN TRY
        UPDATE OrderDetails SET ProcessedDate = GETDATE()
    END TRY
    BEGIN CATCH
        -- Rollback only to savepoint, not entire transaction
        ROLLBACK TRANSACTION savepoint1
        -- Continue processing...
    END CATCH
    
    COMMIT TRANSACTION
END
```

---

## Detecting Transaction Status (XACT_STATE)

```sql
CREATE PROCEDURE sp_TransactionAware
AS
BEGIN
    BEGIN TRY
        BEGIN TRANSACTION
        
        UPDATE Orders SET Status = 'Active'
        UPDATE Inventory SET QtyAvailable = QtyAvailable - 1
        
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        -- Check transaction status
        DECLARE @TxnState INT = XACT_STATE()
        
        IF @TxnState = -1
            -- Transaction is doomed (will rollback regardless)
            ROLLBACK TRANSACTION
        ELSE IF @TxnState = 1
            -- Transaction is active (can commit or rollback)
            ROLLBACK TRANSACTION
        -- @TxnState = 0 means no transaction
        
        THROW
    END CATCH
END
```

---

## Implicit vs Explicit Transactions

```sql
-- Implicit Transaction Mode: Auto-starts on first statement, must explicitly COMMIT
SET IMPLICIT_TRANSACTIONS ON

SELECT * FROM Orders  -- Transaction auto-starts
UPDATE Orders SET Status = 'Active'  -- Continues transaction
COMMIT TRANSACTION  -- Must commit explicitly

-- Explicit Transaction Mode (Default): COMMIT/ROLLBACK needed
SET IMPLICIT_TRANSACTIONS OFF

BEGIN TRANSACTION
    UPDATE Orders SET Status = 'Active'
COMMIT TRANSACTION  -- Must explicitly commit
```

---

## Deadlock Prevention

```sql
-- Deadlock: Transaction A locks Table1 then Table2, while Transaction B locks Table2 then Table1

-- ❌ DEADLOCK RISK: Different lock order
-- Transaction A
BEGIN TRANSACTION
    UPDATE Customers SET Balance = Balance - 100 WHERE CustomerID = 1
    UPDATE Accounts SET Balance = Balance + 100 WHERE AccountID = 1
COMMIT TRANSACTION

-- Transaction B
BEGIN TRANSACTION
    UPDATE Accounts SET Balance = Balance - 50 WHERE AccountID = 1
    UPDATE Customers SET Balance = Balance + 50 WHERE CustomerID = 1
COMMIT TRANSACTION

-- ✅ DEADLOCK PREVENTION: Consistent lock order
-- Always lock in same order (Customers first, then Accounts)
-- Transaction A
BEGIN TRANSACTION
    UPDATE Customers SET Balance = Balance - 100 WHERE CustomerID = 1
    UPDATE Accounts SET Balance = Balance + 100 WHERE AccountID = 1
COMMIT TRANSACTION

-- Transaction B
BEGIN TRANSACTION
    UPDATE Customers SET Balance = Balance + 50 WHERE CustomerID = 1
    UPDATE Accounts SET Balance = Balance - 50 WHERE AccountID = 1
COMMIT TRANSACTION
```

---

## Error Handling Best Practices

```sql
-- ✅ CORRECT: Handle all error scenarios
CREATE PROCEDURE sp_SafeUpdate
    @OrderID INT,
    @NewStatus NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON
    SET XACT_ABORT ON  -- Any error causes rollback
    
    BEGIN TRY
        -- Validate inputs
        IF @OrderID IS NULL OR @OrderID <= 0
            THROW 50001, 'Invalid OrderID', 1
        
        IF @NewStatus IS NULL OR LEN(@NewStatus) = 0
            THROW 50002, 'Status cannot be empty', 1
        
        BEGIN TRANSACTION
        
        -- Check if order exists
        IF NOT EXISTS (SELECT 1 FROM Orders WHERE OrderID = @OrderID)
            THROW 50003, 'Order not found', 1
        
        UPDATE Orders SET Status = @NewStatus, ModifiedDate = GETDATE()
        WHERE OrderID = @OrderID
        
        COMMIT TRANSACTION
        RETURN 0
    END TRY
    BEGIN CATCH
        -- Always rollback on error
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION
        
        -- Log error
        INSERT INTO ErrorLog (ErrorNumber, ErrorMessage, ProcedureName, Timestamp)
        VALUES (ERROR_NUMBER(), ERROR_MESSAGE(), 'sp_SafeUpdate', GETDATE())
        
        -- Re-throw error to caller
        THROW
    END CATCH
END
```

---

## Best Practices Checklist

- [ ] All procedures have SET XACT_ABORT ON
- [ ] Transactions are as short as possible
- [ ] No long-running operations inside transactions
- [ ] TRY-CATCH with ROLLBACK on error
- [ ] Input validation outside transaction
- [ ] Consistent lock order across procedures (deadlock prevention)
- [ ] Use SNAPSHOT isolation for high-concurrency scenarios
- [ ] Check @@TRANCOUNT on error
- [ ] Log all errors to ErrorLog table
- [ ] Test with concurrent load to catch blocking/deadlocks
- [ ] Use SAVEPOINT for complex nested logic
- [ ] THROW instead of RAISERROR for modern code
