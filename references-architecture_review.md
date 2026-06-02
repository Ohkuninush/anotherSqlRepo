# SQL Server Database Architecture Review

## Normalization Levels

### 1NF (First Normal Form) - Atomic Values
```sql
-- ❌ NOT 1NF: Phone contains multiple values
CREATE TABLE Customers_Bad (
    CustomerID INT,
    Name NVARCHAR(100),
    Phones NVARCHAR(100)  -- '555-1111, 555-2222'
)

-- ✅ 1NF: Separate table for phones
CREATE TABLE Customers (
    CustomerID INT PRIMARY KEY,
    Name NVARCHAR(100)
)

CREATE TABLE CustomerPhones (
    PhoneID INT PRIMARY KEY,
    CustomerID INT,
    Phone NVARCHAR(20),
    FOREIGN KEY (CustomerID) REFERENCES Customers(CustomerID)
)
```

### 2NF (Second Normal Form) - No Partial Dependencies
```sql
-- ❌ NOT 2NF: StudentCourse table has non-key dependency
CREATE TABLE StudentCourse_Bad (
    StudentID INT,
    CourseID INT,
    StudentName NVARCHAR(100),  -- Depends only on StudentID, not key
    PRIMARY KEY (StudentID, CourseID)
)

-- ✅ 2NF: Separate tables
CREATE TABLE Students (
    StudentID INT PRIMARY KEY,
    StudentName NVARCHAR(100)
)

CREATE TABLE StudentCourse (
    StudentID INT,
    CourseID INT,
    PRIMARY KEY (StudentID, CourseID),
    FOREIGN KEY (StudentID) REFERENCES Students(StudentID)
)
```

### 3NF (Third Normal Form) - No Transitive Dependencies
```sql
-- ❌ NOT 3NF: Orders depends on Customer, which depends on City
CREATE TABLE Orders_Bad (
    OrderID INT PRIMARY KEY,
    CustomerID INT,
    CustomerName NVARCHAR(100),
    CityName NVARCHAR(100),
    CountryName NVARCHAR(100)  -- Transitive dependency
)

-- ✅ 3NF: Separate dimension tables
CREATE TABLE Customers (
    CustomerID INT PRIMARY KEY,
    CustomerName NVARCHAR(100),
    CityID INT,
    FOREIGN KEY (CityID) REFERENCES Cities(CityID)
)

CREATE TABLE Cities (
    CityID INT PRIMARY KEY,
    CityName NVARCHAR(100),
    CountryID INT,
    FOREIGN KEY (CountryID) REFERENCES Countries(CountryID)
)

CREATE TABLE Countries (
    CountryID INT PRIMARY KEY,
    CountryName NVARCHAR(100)
)
```

### BCNF (Boyce-Codd Normal Form) - All Determinants are Keys
```sql
-- Ensures every determinant is a candidate key
-- Advanced, rarely needed for OLTP systems

-- ✅ BCNF: Professor-Course relationship
CREATE TABLE ProfessorCourse (
    ProfessorID INT,
    CourseID INT,
    Time TIME,
    UNIQUE (ProfessorID, Time),  -- Professor can't teach two courses at once
    PRIMARY KEY (CourseID, ProfessorID)
)
```

## Common Anti-Patterns & Fixes

### Anti-Pattern 1: Wide Tables (EAV Model)
```sql
-- ❌ BAD: Entity-Attribute-Value (causes joins hell)
CREATE TABLE ProductProperties (
    ProductID INT,
    PropertyName NVARCHAR(100),
    PropertyValue NVARCHAR(MAX)
)
-- Query: SELECT price, color, size FROM... 3+ self-joins

-- ✅ GOOD: Proper columns
CREATE TABLE Products (
    ProductID INT PRIMARY KEY,
    ProductName NVARCHAR(100),
    Price DECIMAL(10,2),
    Color NVARCHAR(50),
    Size NVARCHAR(10)
)
-- Query: SELECT price, color, size (one table scan)
```

### Anti-Pattern 2: Missing Keys
```sql
-- ❌ BAD: No primary key
CREATE TABLE Orders (
    OrderID INT,
    CustomerID INT,
    Amount DECIMAL(10,2)
    -- Heap table, slower queries, no enforcement
)

-- ✅ GOOD: Proper key design
CREATE TABLE Orders (
    OrderID INT PRIMARY KEY CLUSTERED,
    CustomerID INT NOT NULL,
    Amount DECIMAL(10,2),
    FOREIGN KEY (CustomerID) REFERENCES Customers(CustomerID),
    INDEX idx_Customer (CustomerID)
)
```

### Anti-Pattern 3: Surrogate vs Natural Keys
```sql
-- ❌ QUESTIONABLE: Using GUID as primary key (wide, unsortable)
CREATE TABLE Orders (
    OrderGUID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    OrderDate DATETIME,
    Amount DECIMAL(10,2)
)

-- ✅ BETTER: Sequential surrogate + natural key
CREATE TABLE Orders (
    OrderID INT PRIMARY KEY IDENTITY(1,1),
    OrderNumber NVARCHAR(50) UNIQUE,  -- Natural key (user-facing)
    OrderDate DATETIME,
    Amount DECIMAL(10,2),
    INDEX idx_OrderNumber (OrderNumber)
)
```

### Anti-Pattern 4: Over-Normalization
```sql
-- ❌ EXCESSIVE: Too many joins for simple queries
CREATE TABLE Customer_Name_First (CustomerID INT, FirstName NVARCHAR(50))
CREATE TABLE Customer_Name_Last (CustomerID INT, LastName NVARCHAR(50))
CREATE TABLE Customer_Email (CustomerID INT, Email NVARCHAR(100))
-- SELECT REQUIRES 4 JOINS!

-- ✅ PRAGMATIC: Balance normalization
CREATE TABLE Customers (
    CustomerID INT PRIMARY KEY,
    FirstName NVARCHAR(50),
    LastName NVARCHAR(50),
    Email NVARCHAR(100)
)
```

## Index Design Review

### Review Checklist
```sql
-- Find unused indexes (maintenance overhead)
SELECT 
    OBJECT_NAME(i.object_id) AS TableName,
    i.name AS IndexName,
    s.user_seeks,
    s.user_scans,
    s.user_lookups,
    s.user_updates,
    SUM(a.total_pages) * 8 / 1024 AS SizeMB
FROM sys.indexes i
LEFT JOIN sys.dm_db_index_stats s ON i.object_id = s.object_id AND i.index_id = s.index_id
LEFT JOIN sys.allocation_units a ON i.object_id = a.container_id
WHERE (s.user_seeks = 0 AND s.user_scans = 0 AND s.user_lookups = 0)
    AND i.index_id > 0  -- Skip heaps
GROUP BY i.object_id, i.name, s.user_seeks, s.user_scans, s.user_lookups, s.user_updates
ORDER BY SUM(a.total_pages) DESC

-- Find missing indexes that would help
SELECT 
    d.equality_columns,
    (s.user_seeks + s.user_scans) * s.avg_total_user_cost * s.avg_user_impact AS ImpactScore
FROM sys.dm_db_missing_index_details d
INNER JOIN sys.dm_db_missing_index_groups g ON d.index_handle = g.index_handle
INNER JOIN sys.dm_db_missing_index_groups_stats s ON g.index_group_id = s.index_group_id
ORDER BY ImpactScore DESC
```

## Scalability Review

### Data Volume Assessment
```sql
-- Estimate current and projected size
SELECT 
    OBJECT_NAME(p.object_id) AS TableName,
    COUNT(DISTINCT p.partition_id) AS PartitionCount,
    SUM(a.total_pages) * 8 / 1024 / 1024 AS SizeMB,
    SUM(p.rows) AS RowCount,
    CAST(SUM(p.rows) * 0.1 AS BIGINT) AS ProjectedRowsX1000  -- 10x growth
FROM sys.partitions p
INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
WHERE p.object_id > 100
GROUP BY p.object_id
ORDER BY SUM(a.total_pages) DESC

-- Tables > 10GB likely need partitioning
-- Tables > 1B rows need careful indexing
```

### Query Performance Baseline
```sql
-- Establish performance baseline
SELECT TOP 20
    qs.execution_count,
    qs.total_elapsed_time / 1000000 AS TotalElapsedSec,
    qs.total_elapsed_time / qs.execution_count / 1000 AS AvgElapsedMS,
    SUBSTRING(st.text, 1, 80) AS QueryText
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
ORDER BY qs.total_elapsed_time DESC

-- Identify queries needing optimization
-- Establish SLA: "99% queries < 100ms"
```

## Partitioning Strategy Review

### When Partitioning is Needed
```sql
-- Table > 10GB typically needs partitioning
-- Query access patterns should partition naturally (by date, region, etc.)

-- ✅ GOOD CANDIDATE: Orders by OrderDate
-- - Queries often filter by date range
-- - Old data can be archived
-- - Table is large

CREATE PARTITION FUNCTION pf_OrderDate (DATE)
AS RANGE LEFT FOR VALUES ('2023-01-01', '2024-01-01', '2025-01-01')

-- ❌ POOR CANDIDATE: Small lookup table (States, Cities)
-- - Partitioning adds complexity with no benefit
-- - Table < 100MB
```

## Constraint Review

### Identify Missing Constraints
```sql
-- Find nullable columns that probably shouldn't be
SELECT 
    OBJECT_NAME(c.object_id) AS TableName,
    c.name AS ColumnName,
    c.is_nullable,
    TYPE_NAME(c.user_type_id) AS DataType
FROM sys.columns c
WHERE c.is_nullable = 1
    AND OBJECT_NAME(c.object_id) NOT IN ('Exceptions', 'AuditLog')
    -- Excluding tables that expect nulls

-- Review foreign key relationships
SELECT 
    OBJECT_NAME(fk.parent_object_id) AS ChildTable,
    OBJECT_NAME(fk.referenced_object_id) AS ParentTable,
    fk.name AS ConstraintName
FROM sys.foreign_keys fk
WHERE delete_referential_action = 0  -- No cascade delete
ORDER BY OBJECT_NAME(fk.parent_object_id)

-- ⚠️ NO CASCADE DELETE by default (safer)
-- ⚠️ Use explicit DELETE to remove parent + children
```

## Hierarchy Design Review

### Adjacency List (Parent-Child)
```sql
-- ✅ GOOD: Simple parent-child relationships (reporting structure)
CREATE TABLE Employees (
    EmployeeID INT PRIMARY KEY,
    Name NVARCHAR(100),
    ManagerID INT,
    FOREIGN KEY (ManagerID) REFERENCES Employees(EmployeeID)
)

-- Query direct reports: SELECT * WHERE ManagerID = @EmpID
-- Query hierarchy: Requires recursive CTE or application logic
```

### Nested Sets (Hierarchical)
```sql
-- ✅ GOOD: Complex hierarchies (organizational structure, categories)
CREATE TABLE Categories (
    CategoryID INT PRIMARY KEY,
    Name NVARCHAR(100),
    LeftValue INT,
    RightValue INT
)

-- Fast queries: SELECT * WHERE LeftValue BETWEEN @Left AND @Right
-- Slow updates: Requires renumbering descendants
```

### Path Enumeration (Materialized Path)
```sql
-- ✅ GOOD: Balance of performance and updates
CREATE TABLE Categories (
    CategoryID INT PRIMARY KEY,
    Name NVARCHAR(100),
    Path NVARCHAR(MAX)  -- '/1/5/23/' = Root > Category1 > Category5 > Category23
)

-- Query path: SELECT * WHERE Path LIKE '/1/5/%'
-- Easy updates: Just append to path
```

## Overall Assessment Checklist

| Area | Questions | Status |
|------|-----------|--------|
| **Normalization** | Are tables properly normalized (3NF+)? | ✓/✗ |
| **Keys** | Are PKs and FKs defined? Any missing? | ✓/✗ |
| **Constraints** | Are business rules enforced (CHECK, FK)? | ✓/✗ |
| **Indexes** | Are high-query tables indexed? Any unused? | ✓/✗ |
| **Size** | Any tables > 10GB needing partitioning? | ✓/✗ |
| **Performance** | Are slow queries identified? Baseline established? | ✓/✗ |
| **Scalability** | Can design support 10x data growth? | ✓/✗ |
| **Security** | Are sensitive columns encrypted? RBAC in place? | ✓/✗ |
| **Audit** | Are changes tracked (Temporal/Triggers)? | ✓/✗ |
| **Consistency** | Are data types and naming conventions consistent? | ✓/✗ |

## Sample Assessment Report

```
DATABASE ARCHITECTURE REVIEW SUMMARY
====================================

Overall Grade: B+ (Good, some improvements needed)

STRENGTHS:
✓ Proper normalization (mostly 3NF)
✓ All tables have primary keys
✓ Foreign key relationships defined
✓ Core indexes in place

AREAS FOR IMPROVEMENT:
⚠ Orders table missing index on OrderDate (top query filter)
⚠ OrderHistory table > 50GB, needs partitioning
⚠ No audit trail on sensitive financial tables
⚠ Some redundant indexes (consolidate)

RECOMMENDATIONS (Priority Order):
1. Create index on Orders(OrderDate) + coverage columns
2. Partition OrderHistory by date, archive pre-2020
3. Implement audit triggers on financial transactions
4. Remove unused indexes (detailed list attached)

ESTIMATED EFFORT:
- Quick wins: 1-2 weeks
- Medium: 1-2 months
- Long-term: Ongoing optimization

EXPECTED BENEFITS:
- 30-50% query performance improvement
- 20% reduction in storage cost
- Better compliance/audit capability
```
