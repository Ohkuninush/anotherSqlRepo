# SQL Server Concurrency, Locking & Blocking

## Lock Types

### Shared (S) Locks
```sql
-- Reader locks (SELECT)
SET TRANSACTION ISOLATION LEVEL READ_COMMITTED
SELECT * FROM Orders WHERE OrderID = 1
-- Acquires S lock, released immediately after read
```

### Exclusive (X) Locks
```sql
-- Writer locks (INSERT, UPDATE, DELETE)
UPDATE Orders SET Status = 'Shipped' WHERE OrderID = 1
-- Acquires X lock, held until transaction ends
```

### Intent Locks (IS, IX, SIX)
```sql
-- Table-level locks indicating row/page locks coming
BEGIN TRANSACTION
    UPDATE Orders SET Amount = Amount + 100 WHERE OrderID = 1
    -- Acquires IX on table, X on row
```

### Deadlocks Example
```sql
-- Session 1
BEGIN TRANSACTION
    UPDATE Orders SET Status = 'Shipped' WHERE OrderID = 5
    -- Holds X lock on Orders[5]
    
    -- Now waiting for Customers lock
    UPDATE Customers SET LastOrderDate = GETDATE() WHERE CustomerID = 10
    -- WAITING for Session 2 to release Customers[10]

-- Session 2 (in parallel)
BEGIN TRANSACTION
    UPDATE Customers SET LastOrderDate = GETDATE() WHERE CustomerID = 10
    -- Holds X lock on Customers[10]
    
    -- Now waiting for Orders lock
    UPDATE Orders SET Status = 'Shipped' WHERE OrderID = 5
    -- WAITING for Session 1 to release Orders[5]

-- RESULT: DEADLOCK (circular wait)
-- SQL Server detects and kills one session
```

## Isolation Levels

### READ_UNCOMMITTED (Dirty Reads)
```sql
SET TRANSACTION ISOLATION LEVEL READ_UNCOMMITTED

-- Can read uncommitted data (very fast, risky)
SELECT * FROM Orders WHERE OrderID = 1
-- If Session 2 rolls back, this data is invalid
-- Use only for approximate reporting

-- No shared locks acquired
```

### READ_COMMITTED (Default, No Dirty Reads)
```sql
SET TRANSACTION ISOLATION LEVEL READ_COMMITTED

-- Read only committed data (safe)
SELECT * FROM Orders WHERE OrderID = 1
-- Safe: won't read dirty data
-- Shared locks acquired and released quickly

-- Issues: Non-repeatable read possible
SELECT * FROM Orders WHERE Status = 'Pending'
-- Another session could UPDATE between your two SELECTs
```

### REPEATABLE_READ
```sql
SET TRANSACTION ISOLATION LEVEL REPEATABLE_READ

-- Read is stable (same data throughout transaction)
BEGIN TRANSACTION
    SELECT * FROM Orders WHERE OrderID = 1  -- Gets X lock
    -- ... later
    SELECT * FROM Orders WHERE OrderID = 1  -- Same data guaranteed
COMMIT

-- Issues: Phantom reads possible
SELECT * FROM Orders WHERE Status = 'Pending'
-- Another session could INSERT/DELETE rows matching this condition
```

### SERIALIZABLE
```sql
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE

-- Completely isolated (slowest, safest)
BEGIN TRANSACTION
    SELECT * FROM Orders WHERE Status = 'Pending'  -- Range lock
    -- No other transactions can INSERT/DELETE matching rows
    
    INSERT INTO Orders VALUES (...)  -- Proceeds safely
COMMIT

-- Most restrictive, use carefully
```

### SNAPSHOT (Row Versioning)
```sql
ALTER DATABASE MyDB SET ALLOW_SNAPSHOT_ISOLATION ON

SET TRANSACTION ISOLATION LEVEL SNAPSHOT

-- Reader sees consistent version of data
-- Readers don't block writers (and vice versa)
BEGIN TRANSACTION
    SELECT * FROM Orders  -- Sees version as of transaction start
    -- If other sessions UPDATE Orders, we still see old version
    -- NO BLOCKING
COMMIT

-- Best for mixed read/write workloads
```

## Blocking Analysis

### Detect Blocking
```sql
-- Running query showing current blocks
SELECT 
    r.session_id,
    r.blocking_session_id,
    r.command,
    SUBSTRING(st.text, 1, 100) AS query,
    r.wait_time_ms
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) st
WHERE r.blocking_session_id > 0

-- If result set is empty, no blocking occurring
```

### Blocking Chain (Multi-level)
```sql
-- Session 1 -> Session 2 -> Session 3
-- Session 3 waiting for Session 2, who's waiting for Session 1

-- Find the HEAD BLOCKER (root cause)
WITH BlockingTree AS (
    SELECT 
        session_id,
        blocking_session_id,
        1 AS level
    FROM sys.dm_exec_requests
    WHERE blocking_session_id = 0 AND session_id IN (
        SELECT DISTINCT r.session_id 
        FROM sys.dm_exec_requests r
        WHERE r.blocking_session_id > 0
    )
    UNION ALL
    SELECT 
        r.session_id,
        r.blocking_session_id,
        bt.level + 1
    FROM sys.dm_exec_requests r
    INNER JOIN BlockingTree bt ON r.blocking_session_id = bt.session_id
)
SELECT * FROM BlockingTree ORDER BY level DESC

-- Level 1 = Head blocker (kill this one)
```

### What's Blocking What
```sql
-- Find blocking locks
SELECT 
    blocker.session_id AS blocking_session,
    waiter.session_id AS waiting_session,
    SUBSTRING(st_blocker.text, 1, 100) AS blocking_query,
    SUBSTRING(st_waiter.text, 1, 100) AS waiting_query
FROM sys.dm_exec_requests blocker
INNER JOIN sys.dm_exec_requests waiter 
    ON blocker.session_id = waiter.blocking_session_id
CROSS APPLY sys.dm_exec_sql_text(blocker.sql_handle) st_blocker
CROSS APPLY sys.dm_exec_sql_text(waiter.sql_handle) st_waiter
```

## Preventing Deadlocks

### 1. Order Access Consistently
```sql
-- ✅ GOOD: Always access Tables in same order
BEGIN TRANSACTION
    UPDATE Orders SET Status = 'Shipped'
    UPDATE Customers SET LastOrder = GETDATE()  -- Orders BEFORE Customers
COMMIT

-- ❌ BAD: Different order in different sessions
-- Session 1: Orders, then Customers
-- Session 2: Customers, then Orders
-- = DEADLOCK
```

### 2. Keep Transactions Short
```sql
-- ✅ GOOD: Short transaction window
BEGIN TRANSACTION
    UPDATE Orders SET Status = 'Shipped' WHERE OrderID = @ID
COMMIT
-- Locks released quickly, less chance of blocking

-- ❌ BAD: Long transaction
BEGIN TRANSACTION
    UPDATE Orders SET Status = 'Shipped'  -- All rows
    WAITFOR DELAY '00:01:00'  -- Hold locks for 1 minute!
    INSERT INTO OrderLog VALUES (...)
COMMIT
```

### 3. Use Appropriate Isolation Level
```sql
-- ✅ For read-heavy workloads
ALTER DATABASE MyDB SET ALLOW_SNAPSHOT_ISOLATION ON

SET TRANSACTION ISOLATION LEVEL SNAPSHOT
-- Readers don't block writers

-- ❌ AVOID: SERIALIZABLE for high-volume (high contention)
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE
```

### 4. Index Design
```sql
-- ✅ GOOD: Specific index prevents large scans
CREATE INDEX idx_orders_customer ON Orders(CustomerID)

-- Then UPDATE against specific rows
UPDATE Orders SET Status = 'Shipped' 
WHERE CustomerID = @ID  -- Affects few rows

-- ❌ BAD: No index forces table scan
UPDATE Orders SET Amount = 0 WHERE Status = 'Pending'
-- Locks many rows unnecessarily
```

### 5. Use Row-Level Locking
```sql
-- ✅ GOOD: Page/row locks (more concurrency)
UPDATE Orders SET Status = 'Shipped' WHERE OrderID = 5
-- X lock on just this row

-- Less ideal: Escalates to page/table locks
UPDATE Orders SET Amount = Amount + 100
-- Might lock entire page or table
```

## Deadlock Recovery

### Automatic Retry Pattern
```sql
CREATE PROCEDURE sp_UpdateWithRetry
    @OrderID INT,
    @MaxRetries INT = 3
AS
BEGIN
    DECLARE @RetryCount INT = 0
    
    WHILE @RetryCount < @MaxRetries
    BEGIN
        BEGIN TRY
            BEGIN TRANSACTION
                UPDATE Orders SET Status = 'Shipped' WHERE OrderID = @OrderID
            COMMIT TRANSACTION
            RETURN 0  -- Success
        END TRY
        BEGIN CATCH
            IF ERROR_NUMBER() = 1205  -- Deadlock error
            BEGIN
                SET @RetryCount += 1
                WAITFOR DELAY '00:00:00.1'  -- Brief wait before retry
                IF @RetryCount = @MaxRetries
                    THROW  -- Give up after max retries
            END
            ELSE
                THROW  -- Non-deadlock error, don't retry
        END CATCH
    END
END
```

## Latch Contention

### Tempdb Latch Contention
```sql
-- Monitor latch wait times
SELECT 
    latch_class,
    wait_count,
    wait_time_ms,
    CONVERT(NUMERIC(5,2), 100.0 * wait_time_ms / SUM(wait_time_ms) OVER()) AS pct_wait
FROM sys.dm_os_latch_stats
WHERE latch_class IN ('PAGEIOLATCH_EX', 'PAGEIOLATCH_SH', 'PAGELATCH_EX')
ORDER BY wait_time_ms DESC

-- High contention on tempdb:
-- - Multiple threads creating temp tables
-- - Solution: Add tempdb files (one per logical CPU core)
```

## Isolation Level Decision Matrix

| Isolation | Dirty Reads | Non-Repeatable | Phantom | Performance | Use Case |
|-----------|------------|---|---------|-----------|----------|
| READ_UNCOMMITTED | ✅ Yes | ✅ | ✅ | 🚀 Fastest | Approximate reports only |
| READ_COMMITTED | ❌ | ✅ | ✅ | ⚡ Fast | Default, most scenarios |
| REPEATABLE_READ | ❌ | ❌ | ✅ | 🟡 Medium | Strict consistency |
| SERIALIZABLE | ❌ | ❌ | ❌ | 🐢 Slow | Critical data (rare) |
| SNAPSHOT | ❌ | ❌ | ❌ | ⚡ Fast | Mixed read/write workloads |

## Tools for Diagnosis

```sql
-- Extended Events (better than Profiler)
CREATE EVENT SESSION deadlock_events ON SERVER
ADD EVENT sqlserver.xml_deadlock_report
ADD TARGET package0.event_file(SET filename=N'deadlock.xel')
WITH (STARTUP_STATE = ON)

-- Run and check error log for deadlock graphs
```
