---
name: hierarchical-data-patterns
description: Hierarchical data patterns — trees, graphs, materialized paths, nested sets, adjacency lists, efficient querying of parent-child relationships
---

# Hierarchical Data Patterns — Trees & Graphs

## Overview

**Why hierarchical data matters:**
- Organization structures (CEO → managers → employees)
- Product categories (Electronics → Computers → Laptops)
- Bill of materials (Car → Engine → Spark Plugs)
- Geographic hierarchies (Country → Region → City)
- Comment threads (Parent comment → replies → sub-replies)

**Challenge:** Querying efficiently
- "Get all employees under this manager" = recursive search
- "Get all products in this category and subcategories" = tree traversal
- Simple queries can become slow (1000+ levels deep)

---

## Anti-Pattern: Naive Adjacency List (❌ Don't Do This)

### The Problem
```sql
-- Simple: Just store parent reference
CREATE TABLE Categories (
    CategoryID INT PRIMARY KEY,
    CategoryName NVARCHAR(100),
    ParentCategoryID INT,  -- Points to parent
    FOREIGN KEY (ParentCategoryID) REFERENCES Categories(CategoryID)
)

-- To get all products in a category and subcategories:
-- Need recursive query
WITH RECURSIVE CategoryHierarchy AS (
    SELECT CategoryID, ParentCategoryID, 0 AS Level
    FROM Categories
    WHERE CategoryID = @StartCategory
    
    UNION ALL
    
    SELECT c.CategoryID, c.ParentCategoryID, ch.Level + 1
    FROM Categories c
    INNER JOIN CategoryHierarchy ch ON c.ParentCategoryID = ch.CategoryID
    WHERE ch.Level < 50  -- ← Limit recursion depth (arbitrary!)
)
SELECT * FROM CategoryHierarchy

-- Problem:
-- • Recursive query slow on deep trees
-- • Must specify max recursion depth
-- • Gets slower as tree grows
-- • Can't easily get hierarchy level
```

### Real-World Incident
```
Timeline (Retail Company):
  Product categories: 15 levels deep
  Query: "Get all products in Electronics"
  Expected: 0.5 seconds
  Actual: 45 seconds
  
  Root cause: Naive recursive query
  Problem: Employee sees slow inventory
  Impact: "Why is search so slow?"
  
  Solution: Rewrite with Materialized Path
  Result: 0.1 seconds
```

---

## Pattern 1: Materialized Path (Recommended)

### Use Case
- Most common hierarchies (org charts, categories)
- Need fast queries for path traversal
- Simple to understand and maintain

### ✅ Correct Implementation

#### Schema
```sql
CREATE TABLE Categories (
    CategoryID INT PRIMARY KEY IDENTITY(1, 1),
    CategoryName NVARCHAR(100),
    ParentCategoryID INT NULL,
    MaterializedPath NVARCHAR(MAX),  -- '1/2/5/12/' format
    Level INT,  -- Depth in tree (0 = root)
    FOREIGN KEY (ParentCategoryID) REFERENCES Categories(CategoryID),
    INDEX IX_MaterializedPath (MaterializedPath)
)
```

#### Insert with Path Calculation
```sql
CREATE OR ALTER PROCEDURE sp_InsertCategory
    @CategoryName NVARCHAR(100),
    @ParentCategoryID INT = NULL
AS
BEGIN
    SET NOCOUNT ON
    SET XACT_ABORT ON
    
    BEGIN TRY
        DECLARE @NewCategoryID INT
        DECLARE @ParentPath NVARCHAR(MAX)
        DECLARE @NewPath NVARCHAR(MAX)
        DECLARE @ParentLevel INT
        
        BEGIN TRANSACTION
        
        -- Step 1: Get parent path
        IF @ParentCategoryID IS NOT NULL
        BEGIN
            SELECT @ParentPath = MaterializedPath,
                   @ParentLevel = Level
            FROM Categories
            WHERE CategoryID = @ParentCategoryID
            
            IF @ParentPath IS NULL
                THROW 50001, 'Parent category not found', 1
        END
        ELSE
        BEGIN
            SET @ParentPath = ''
            SET @ParentLevel = 0
        END
        
        -- Step 2: Insert new category
        INSERT INTO Categories (CategoryName, ParentCategoryID, MaterializedPath, Level)
        VALUES (@CategoryName, @ParentCategoryID, '', 0)
        
        SET @NewCategoryID = SCOPE_IDENTITY()
        SET @NewPath = @ParentPath + CAST(@NewCategoryID AS VARCHAR(10)) + '/'
        
        -- Step 3: Update with materialized path
        UPDATE Categories
        SET MaterializedPath = @NewPath,
            Level = @ParentLevel + 1
        WHERE CategoryID = @NewCategoryID
        
        COMMIT TRANSACTION
        RETURN @NewCategoryID
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION
        THROW
    END CATCH
END

-- Usage
EXEC sp_InsertCategory @CategoryName = 'Electronics', @ParentCategoryID = NULL
-- Returns: 1, Path: '1/'

EXEC sp_InsertCategory @CategoryName = 'Computers', @ParentCategoryID = 1
-- Returns: 2, Path: '1/2/'

EXEC sp_InsertCategory @CategoryName = 'Laptops', @ParentCategoryID = 2
-- Returns: 3, Path: '1/2/3/'
```

#### Fast Queries
```sql
-- Get all descendants of category 2
SELECT CategoryID, CategoryName, Level
FROM Categories
WHERE MaterializedPath LIKE '1/2/%'
ORDER BY MaterializedPath

-- Get parent path
SELECT 
    c.CategoryID,
    c.CategoryName,
    STRING_AGG(p.CategoryName, ' > ') WITHIN GROUP (ORDER BY p.Level) AS ParentPath
FROM Categories c
LEFT JOIN Categories p ON c.MaterializedPath LIKE '%' + CAST(p.CategoryID AS VARCHAR(10)) + '/%'
WHERE c.CategoryID = 3  -- Laptops
GROUP BY c.CategoryID, c.CategoryName

-- Get siblings
SELECT CategoryID, CategoryName
FROM Categories
WHERE SUBSTRING(MaterializedPath, 1, LEN(MaterializedPath) - LEN(CAST(CategoryID AS VARCHAR(10))) - 1)
    = (SELECT SUBSTRING(MaterializedPath, 1, LEN(MaterializedPath) - LEN(CAST(CategoryID AS VARCHAR(10))) - 1)
       FROM Categories WHERE CategoryID = 3)
```

#### Advantages
```
✅ Single index lookup (not recursive)
✅ Fast ancestor queries (LIKE '%')
✅ Fast descendant queries (LIKE 'path%')
✅ Can get depth easily (Level column)
✅ Simple to understand
```

---

## Pattern 2: Nested Sets (Optimized for Read-Heavy)

### Use Case
- Mostly reads (querying hierarchy)
- Few writes (building/updating tree)
- Need very fast ancestor/descendant queries

### ✅ Correct Implementation

#### Schema (Left/Right Numbers)
```sql
CREATE TABLE Categories_NestedSet (
    CategoryID INT PRIMARY KEY,
    CategoryName NVARCHAR(100),
    Left_ID INT NOT NULL,
    Right_ID INT NOT NULL,
    Level INT,
    CONSTRAINT CHK_LeftRight CHECK (Left_ID < Right_ID),
    INDEX IX_Left_Right (Left_ID, Right_ID)
)
```

#### Building the Tree
```sql
-- Nested set numbering:
-- Start from leftmost = 1, work right
-- Electronics (1-14)
--   Computers (2-7)
--     Laptops (3-4)
--     Desktops (5-6)
--   Phones (8-13)
--     Smartphones (9-10)
--     Basic (11-12)

CREATE OR ALTER PROCEDURE sp_BuildNestedSets
AS
BEGIN
    SET NOCOUNT ON
    SET XACT_ABORT ON
    
    DECLARE @Counter INT = 1
    DECLARE @Level INT = 0
    
    BEGIN TRY
        BEGIN TRANSACTION
        
        -- Add Left_ID and Right_ID columns if needed
        IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS 
                       WHERE TABLE_NAME = 'Categories_NestedSet' AND COLUMN_NAME = 'Left_ID')
            ALTER TABLE Categories_NestedSet ADD Left_ID INT, Right_ID INT
        
        -- Clear existing values
        UPDATE Categories_NestedSet SET Left_ID = NULL, Right_ID = NULL
        
        -- Recursive CTE to number the set
        ;WITH TreeNumbers AS (
            SELECT 
                CategoryID,
                ParentCategoryID,
                ROW_NUMBER() OVER (PARTITION BY ParentCategoryID ORDER BY CategoryID) AS RowNum,
                0 AS Depth
            FROM Categories
            WHERE ParentCategoryID IS NULL
            
            UNION ALL
            
            SELECT 
                c.CategoryID,
                c.ParentCategoryID,
                ROW_NUMBER() OVER (PARTITION BY c.ParentCategoryID ORDER BY c.CategoryID),
                tn.Depth + 1
            FROM Categories c
            INNER JOIN TreeNumbers tn ON c.ParentCategoryID = tn.CategoryID
        )
        SELECT * INTO #TreeWithNumbers FROM TreeNumbers
        
        -- Update with nested set numbers (left = sequential, right = end of subtree)
        -- This is complex; simplified version shown
        UPDATE cs
        SET Left_ID = ROW_NUMBER() OVER (ORDER BY CategoryID),
            Right_ID = (SELECT COUNT(*) FROM Categories)
        FROM Categories_NestedSet cs
        
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION
        THROW
    END CATCH
END
```

#### Ultra-Fast Queries
```sql
-- All descendants of category with ID 2
SELECT *
FROM Categories_NestedSet
WHERE Left_ID > (SELECT Left_ID FROM Categories_NestedSet WHERE CategoryID = 2)
  AND Right_ID < (SELECT Right_ID FROM Categories_NestedSet WHERE CategoryID = 2)

-- All ancestors
SELECT *
FROM Categories_NestedSet
WHERE Left_ID < (SELECT Left_ID FROM Categories_NestedSet WHERE CategoryID = 3)
  AND Right_ID > (SELECT Right_ID FROM Categories_NestedSet WHERE CategoryID = 3)

-- Subtree size (number of descendants)
SELECT 
    CategoryID,
    (Right_ID - Left_ID + 1) / 2 AS DescendantCount
FROM Categories_NestedSet
```

#### Trade-off
```
✅ Extremely fast queries (no recursion)
✅ Single index
✅ Get any ancestor/descendant in O(1)

❌ Slow to insert/update (must recalculate all numbers)
❌ Complex to understand
```

---

## Pattern 3: Adjacency List with Recursive CTE

### Use Case
- Simple insert/update (no path recalculation)
- Accept slower queries (queries are less frequent)
- Depth is limited (< 20 levels)

### ✅ Correct Implementation

```sql
CREATE TABLE Employees (
    EmployeeID INT PRIMARY KEY,
    EmployeeName NVARCHAR(100),
    ManagerID INT NULL,
    FOREIGN KEY (ManagerID) REFERENCES Employees(EmployeeID),
    INDEX IX_ManagerID (ManagerID)
)

-- Simple insert (no calculation needed)
INSERT INTO Employees VALUES (1, 'CEO', NULL)
INSERT INTO Employees VALUES (2, 'VP Sales', 1)
INSERT INTO Employees VALUES (3, 'Sales Rep', 2)

-- Query: All employees under VP Sales (recursion depth limited)
CREATE OR ALTER PROCEDURE sp_GetEmployeesUnder
    @ManagerID INT,
    @MaxDepth INT = 10
AS
BEGIN
    WITH EmployeeHierarchy AS (
        -- Base: Manager
        SELECT EmployeeID, EmployeeName, ManagerID, 0 AS Level
        FROM Employees
        WHERE EmployeeID = @ManagerID
        
        UNION ALL
        
        -- Recursive: Reports
        SELECT e.EmployeeID, e.EmployeeName, e.ManagerID, eh.Level + 1
        FROM Employees e
        INNER JOIN EmployeeHierarchy eh ON e.ManagerID = eh.EmployeeID
        WHERE eh.Level < @MaxDepth
    )
    SELECT EmployeeID, EmployeeName, Level
    FROM EmployeeHierarchy
    ORDER BY Level, EmployeeName
END

-- Usage
EXEC sp_GetEmployeesUnder @ManagerID = 2
```

#### Advantages
```
✅ Simple inserts (just set ManagerID)
✅ No denormalization
✅ Works for most org charts
✅ Easy to understand
```

#### Trade-off
```
❌ Queries slower (recursive)
❌ Must set max recursion depth
❌ Slower on deep trees
```

---

## Pattern 4: Graph Tables (SQL Server 2017+)

### Use Case
- Complex relationships (not just trees)
- Multiple parent nodes (graphs, not just hierarchies)
- Social networks, recommendations, knowledge graphs

### ✅ Correct Implementation

```sql
-- Create node table
CREATE TABLE Person (
    PersonID INT PRIMARY KEY,
    PersonName NVARCHAR(100)
) AS NODE

-- Create edge table (relationships)
CREATE TABLE Follows (
    -- Automatically includes $from_id and $to_id
) AS EDGE

-- Insert nodes
INSERT INTO Person VALUES (1, 'Alice')
INSERT INTO Person VALUES (2, 'Bob')
INSERT INTO Person VALUES (3, 'Charlie')

-- Insert edges (relationships)
INSERT INTO Follows ($from_id, $to_id) 
VALUES ((SELECT $node_id FROM Person WHERE PersonID = 1),
        (SELECT $node_id FROM Person WHERE PersonID = 2))

-- Query: Who does Alice follow?
SELECT p.PersonName
FROM Person p
WHERE $node_id IN (
    SELECT $to_id
    FROM Follows
    WHERE $from_id = (SELECT $node_id FROM Person WHERE PersonID = 1)
)

-- Query: Friends of friends
SELECT DISTINCT p2.PersonName
FROM Person p1
INNER JOIN Follows f1 ON p1.$node_id = f1.$from_id
INNER JOIN Person p2 ON f1.$to_id = p2.$node_id
INNER JOIN Follows f2 ON p2.$node_id = f2.$from_id
INNER JOIN Person p3 ON f2.$to_id = p3.$node_id
WHERE p1.PersonID = 1
```

#### Advantages
```
✅ Native support for graphs
✅ Can represent complex relationships
✅ Efficient path queries
✅ Built-in visualization (SQL Server Management Studio)
```

---

## Decision Tree: Which Pattern?

```
START: "I need to store hierarchy"
│
├─ "Is it a tree (single parent) or graph (multiple parents)?"
│  ├─ Graph (multiple parents) → Graph Tables (SQL Server 2017+)
│  └─ Tree (single parent) → Continue
│
├─ "How deep is the tree?"
│  ├─ Deep (> 50 levels) → Materialized Path
│  └─ Shallow (< 50 levels) → Continue
│
├─ "More reads or writes?"
│  ├─ Mostly writes → Adjacency List
│  ├─ Mostly reads → Nested Sets (complex) or Materialized Path (simple)
│  └─ Balanced → Materialized Path
│
└─ "Need path display?"
   ├─ YES → Materialized Path
   └─ NO → Nested Sets (faster queries)
```

---

## Performance Comparison

| Pattern | Insert | Ancestor Query | Descendant Query | Complexity |
|---------|--------|-----------------|-----------------|-----------|
| Adjacency List | Fast | Slow (recursive) | Slow (recursive) | Low |
| Materialized Path | Medium | Fast (index) | Fast (LIKE) | Low |
| Nested Sets | Slow | Very Fast | Very Fast | High |
| Graph Tables | Medium | Fast | Fast | Medium |

---

## Best Practices

### 1. Always Choose Based on Usage Pattern
```sql
-- Read-heavy? Materialized Path or Nested Sets
-- Write-heavy? Adjacency List
-- Balanced? Materialized Path
```

### 2. Validate Tree Integrity
```sql
-- No cycles
-- No orphans (parent must exist)
-- No self-references (unless intended)
CREATE CONSTRAINT CHECK_NoSelfReference CHECK (ParentCategoryID != CategoryID)
```

### 3. Limit Recursion Depth
```sql
-- Prevent infinite loops
WHERE Level < 50  -- Max 50 levels deep
```

### 4. Index Appropriately
```sql
-- For Materialized Path
CREATE INDEX IX_Path ON Categories(MaterializedPath)

-- For Adjacency List
CREATE INDEX IX_Parent ON Categories(ParentCategoryID)

-- For Nested Sets
CREATE INDEX IX_LeftRight ON Categories(Left_ID, Right_ID)
```

---

## References
- `[[etl_incremental]]` — Updating hierarchies incrementally
- `[[data_validation_tests]]` — Test hierarchy integrity
- `references/common_pitfalls.md` — Hierarchy mistakes

