# Query Optimization Patterns & Anti-Patterns

## ✅ Optimization Patterns

### 1. Window Functions vs Self-Joins
**Pattern:** Use window functions for ranking, running totals, and comparisons
```sql
-- ✅ GOOD: Window function
SELECT OrderID, Amount,
    LAG(Amount) OVER (ORDER BY OrderDate) AS PriorAmount
FROM Orders

-- ❌ SLOW: Self-join
SELECT o1.OrderID, o1.Amount, o2.Amount AS PriorAmount
FROM Orders o1
LEFT JOIN Orders o2 ON o1.OrderID = o2.OrderID + 1
```

### 2. CTEs for Readability
**Pattern:** Break complex logic into CTEs
```sql
WITH CustomerTotals AS (
    SELECT CustomerID, SUM(Amount) AS TotalSpent FROM Orders GROUP BY CustomerID
),
HighValue AS (
    SELECT * FROM CustomerTotals WHERE TotalSpent > 10000
)
SELECT * FROM HighValue
```

### 3. UNION vs OR (Index Awareness)
**Pattern:** Use UNION instead of OR for better index utilization
```sql
-- ✅ GOOD: Union leverages both indexes
SELECT OrderID FROM Orders WHERE Status = 'Shipped' AND OrderDate > @Date
UNION
SELECT OrderID FROM Orders WHERE CustomerID = @CustID

-- ⚠️ SLOWER: OR prevents optimization
SELECT OrderID FROM Orders 
WHERE (Status = 'Shipped' AND OrderDate > @Date) OR CustomerID = @CustID
```

### 4. Covering Indexes
**Pattern:** Create covering indexes to avoid key lookups
```sql
CREATE INDEX IX_Orders_Status_Covering 
ON Orders(Status, OrderDate) 
INCLUDE (OrderID, Amount)
```

### 5. SET-BASED Operations
**Pattern:** Use set-based instead of row-by-row (RBAR)
```sql
-- ✅ GOOD: Set-based
UPDATE Orders SET Status = 'Shipped' WHERE OrderDate < GETDATE() - 30

-- ❌ SLOW: Row-by-row RBAR
DECLARE cur CURSOR FOR SELECT OrderID FROM Orders ...
```

---

## ❌ Anti-Patterns to Avoid

### 1. SELECT * (Retrieves Unnecessary Columns)
```sql
-- ❌ AVOID
SELECT * FROM Orders

-- ✅ GOOD
SELECT OrderID, CustomerID, Amount FROM Orders
```

### 2. LIKE with Leading Wildcard
```sql
-- ❌ SLOW: Can't use index
SELECT * FROM Customers WHERE CustomerName LIKE '%Smith%'

-- ✅ GOOD: Index seek possible
SELECT * FROM Customers WHERE CustomerName LIKE 'Smith%'
```

### 3. Functions on Filter Columns
```sql
-- ❌ SLOW: Function prevents index
SELECT * FROM Orders WHERE YEAR(OrderDate) = 2026

-- ✅ GOOD: Direct date comparison
SELECT * FROM Orders 
WHERE OrderDate >= '2026-01-01' AND OrderDate < '2027-01-01'
```

### 4. NOT IN with Subquery
```sql
-- ❌ SLOW: NOT IN (NULL-sensitive)
SELECT * FROM Orders WHERE CustomerID NOT IN (SELECT CustomerID FROM Blacklist)

-- ✅ GOOD: LEFT JOIN
SELECT o.* FROM Orders o
LEFT JOIN Blacklist b ON o.CustomerID = b.CustomerID
WHERE b.CustomerID IS NULL
```

### 5. DISTINCT When GROUP BY Works
```sql
-- ❌ SLOWER: DISTINCT
SELECT DISTINCT CustomerID FROM Orders

-- ✅ FASTER: GROUP BY
SELECT CustomerID FROM Orders GROUP BY CustomerID
```

### 6. Correlated Subqueries
```sql
-- ❌ SLOW: Runs for each row
SELECT OrderID, 
    (SELECT COUNT(*) FROM OrderDetails od WHERE od.OrderID = o.OrderID) AS LineCount
FROM Orders o

-- ✅ GOOD: JOIN with aggregation
SELECT o.OrderID, COUNT(od.OrderDetailID) AS LineCount
FROM Orders o
LEFT JOIN OrderDetails od ON o.OrderID = od.OrderID
GROUP BY o.OrderID
```

---

## Performance Checklist

- [ ] Execution plan reviewed (no table scans on large tables)
- [ ] Indexes on all filter/join columns
- [ ] No functions on WHERE clause columns
- [ ] Window functions used for ranking/running totals
- [ ] UNION preferred over OR
- [ ] Covering indexes for high-volume queries
- [ ] Set-based operations (no cursors)
- [ ] NO SELECT *
- [ ] Tested with production-sized data
