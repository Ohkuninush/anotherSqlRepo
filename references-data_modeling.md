# SQL Server Data Modeling (OLTP & OLAP)

## OLTP vs OLAP

### OLTP (OnLine Transaction Processing)
**Purpose:** Real-time operational data  
**Access Pattern:** Many small transactions, read + write, immediate consistency

```sql
-- OLTP Schema: Normalized, row-store focused
CREATE TABLE Orders (
    OrderID INT PRIMARY KEY IDENTITY,
    CustomerID INT NOT NULL,
    OrderDate DATETIME NOT NULL,
    Amount DECIMAL(10,2),
    Status NVARCHAR(50),
    FOREIGN KEY (CustomerID) REFERENCES Customers(CustomerID),
    INDEX idx_customer ON Orders(CustomerID),
    INDEX idx_order_date ON Orders(OrderDate)
)

-- OLTP Characteristics:
-- ✓ Normalized (reduce redundancy, enforce consistency)
-- ✓ Many indexes (support varied queries)
-- ✓ Row-store (fast for single/few row operations)
-- ✓ Small tables (3NF normalization)
-- ✓ Fast writes (INSERT/UPDATE quickly)
-- ✓ Supports concurrent access (locking, transactions)

-- Query: Get customer's latest orders
SELECT TOP 5 OrderID, OrderDate, Amount
FROM Orders
WHERE CustomerID = 123
ORDER BY OrderDate DESC
```

### OLAP (OnLine Analytical Processing)
**Purpose:** Historical aggregated data for analysis  
**Access Pattern:** Large batch reads, summarization, no updates

```sql
-- OLAP Schema: Dimensional modeling (star schema), column-store focused
CREATE TABLE FactOrders (
    OrderKey INT PRIMARY KEY,
    CustomerKey INT,
    DateKey INT,
    ProductKey INT,
    QuantitySold INT,
    OrderAmount DECIMAL(12,2),
    FOREIGN KEY (CustomerKey) REFERENCES DimCustomer(CustomerKey),
    FOREIGN KEY (DateKey) REFERENCES DimDate(DateKey),
    FOREIGN KEY (ProductKey) REFERENCES DimProduct(ProductKey)
)
CREATE NONCLUSTERED COLUMNSTORE INDEX idx_factorders_cs ON FactOrders

-- OLAP Characteristics:
-- ✓ Denormalized (aggregate data upfront)
-- ✓ Few indexes (column-store does compression)
-- ✓ Column-store (compress 10x, fast aggregations)
-- ✓ Large fact tables (years of data)
-- ✓ Slow writes (batch loads only)
-- ✓ No concurrent updates (ETL-only)

-- Query: Total sales by region, last 12 months
SELECT 
    dr.RegionName,
    SUM(fo.OrderAmount) AS TotalSales,
    COUNT(DISTINCT fo.CustomerKey) AS CustomerCount
FROM FactOrders fo
INNER JOIN DimCustomer dc ON fo.CustomerKey = dc.CustomerKey
INNER JOIN DimRegion dr ON dc.RegionKey = dr.RegionKey
INNER JOIN DimDate dd ON fo.DateKey = dd.DateKey
WHERE YEAR(dd.FullDate) = YEAR(GETDATE()) - 1
GROUP BY dr.RegionName
ORDER BY TotalSales DESC
```

## Star Schema (OLAP Design)

### Fact Table (Transactional Measures)
```sql
-- FACT: Quantitative measures at transaction granularity
CREATE TABLE FactSales (
    SalesKey INT PRIMARY KEY IDENTITY,
    ProductKey INT,
    CustomerKey INT,
    DateKey INT,
    StoreKey INT,
    Quantity INT,
    UnitPrice DECIMAL(10,2),
    DiscountAmount DECIMAL(10,2),
    SalesAmount DECIMAL(12,2),  -- Quantity * UnitPrice - Discount
    FOREIGN KEY (ProductKey) REFERENCES DimProduct(ProductKey),
    FOREIGN KEY (CustomerKey) REFERENCES DimCustomer(CustomerKey),
    FOREIGN KEY (DateKey) REFERENCES DimDate(DateKey),
    FOREIGN KEY (StoreKey) REFERENCES DimStore(StoreKey)
)

-- Fact table characteristics:
-- - One row per transaction/event
-- - Hundreds of millions to billions of rows
-- - Only numeric (measures) and foreign keys
-- - Heavily indexed, heavily accessed
-- - No descriptive text (that's in dimensions)
```

### Dimension Tables (Context)
```sql
-- DIMENSION: Descriptive attributes
CREATE TABLE DimCustomer (
    CustomerKey INT PRIMARY KEY IDENTITY,
    CustomerID INT UNIQUE,  -- Link to operational system
    CustomerName NVARCHAR(100),
    City NVARCHAR(50),
    State NVARCHAR(2),
    Country NVARCHAR(50),
    CustomerSegment NVARCHAR(50),  -- Premium, Standard, Budget
    AnnualIncome DECIMAL(12,2),
    ValidFrom DATE,
    ValidTo DATE,
    IsCurrent BIT DEFAULT 1
)

-- Dimension characteristics:
-- - Thousands to millions of rows (vs billions in fact)
-- - Denormalized (wide, many attributes)
-- - Primary key = surrogate (DimCustomer.CustomerKey)
-- - Foreign key = natural key from source (CustomerID)
-- - Slowly changing dimensions (SCD)
-- - Descriptive attributes (names, addresses, categories)
```

### Time Dimension (Critical)
```sql
CREATE TABLE DimDate (
    DateKey INT PRIMARY KEY,  -- 20240601 = 2024-06-01
    FullDate DATE UNIQUE,
    Year INT,
    Quarter INT,
    Month INT,
    MonthName NVARCHAR(10),
    DayOfMonth INT,
    DayOfWeek INT,
    WeekOfYear INT,
    IsWeekend BIT,
    IsHoliday BIT
)

-- Pre-populate dates (100 years of dates = 36,500 rows)
-- Enables fast year/month/quarter aggregations
-- No need to convert dates in queries
```

## Snowflake Schema (Normalized OLAP)

```sql
-- More normalized than star schema
-- Dimensions point to other dimensions

CREATE TABLE FactOrders (
    OrderKey INT PRIMARY KEY,
    OrderID INT,
    CustomerKey INT,
    DateKey INT,
    OrderAmount DECIMAL(12,2),
    FOREIGN KEY (CustomerKey) REFERENCES DimCustomer(CustomerKey),
    FOREIGN KEY (DateKey) REFERENCES DimDate(DateKey)
)

-- Flattened hierarchy would duplicate cities/states
-- Instead, normalize into separate dimensions

CREATE TABLE DimCustomer (
    CustomerKey INT PRIMARY KEY IDENTITY,
    CustomerID INT,
    CustomerName NVARCHAR(100),
    CityKey INT,  -- Link to separate dimension
    FOREIGN KEY (CityKey) REFERENCES DimCity(CityKey)
)

CREATE TABLE DimCity (
    CityKey INT PRIMARY KEY,
    CityName NVARCHAR(50),
    StateKey INT,
    FOREIGN KEY (StateKey) REFERENCES DimState(StateKey)
)

CREATE TABLE DimState (
    StateKey INT PRIMARY KEY,
    StateName NVARCHAR(50),
    CountryKey INT,
    FOREIGN KEY (CountryKey) REFERENCES DimCountry(CountryKey)
)

-- Snowflake pros: Less redundancy, easier maintenance
-- Snowflake cons: More joins (slower queries)

-- Star vs Snowflake: Prefer STAR for analytics (simpler queries)
```

## Slowly Changing Dimensions (SCD)

### SCD Type 1 (Overwrite)
```sql
-- Keep only current version
-- No history

UPDATE DimCustomer
SET CustomerName = 'Updated Name'
WHERE CustomerID = 123

-- Use when: Minor corrections, history not needed
```

### SCD Type 2 (New Row with Versioning)
```sql
-- Keep all versions with validity dates

-- New customer attribute triggers new row
INSERT INTO DimCustomer
SELECT 
    NULL,  -- New key
    123,   -- Same customer
    'Updated Name',
    GETDATE() AS ValidFrom,
    '9999-12-31' AS ValidTo,
    1 AS IsCurrent
    
-- Mark old version as expired
UPDATE DimCustomer
SET ValidTo = GETDATE() - 1,
    IsCurrent = 0
WHERE CustomerID = 123 AND ValidTo = '9999-12-31' AND CustomerName != 'Updated Name'

-- Query current version
SELECT * FROM DimCustomer WHERE IsCurrent = 1 AND CustomerID = 123

-- Use when: Track history (address changes, salary changes)
```

### SCD Type 3 (Previous Column)
```sql
-- Keep current and previous value
CREATE TABLE DimCustomer (
    CustomerKey INT PRIMARY KEY,
    CustomerID INT,
    CustomerNameCurrent NVARCHAR(100),
    CustomerNamePrevious NVARCHAR(100),
    CustomerNameChangeDate DATE
)

-- Simple history (only one previous version)
UPDATE DimCustomer
SET 
    CustomerNamePrevious = CustomerNameCurrent,
    CustomerNameCurrent = 'New Name',
    CustomerNameChangeDate = GETDATE()
WHERE CustomerID = 123

-- Use when: Need limited history (one version back)
```

## Bridge Tables (Many-to-Many)

```sql
-- Product can belong to multiple categories
-- Category can have multiple products

CREATE TABLE DimProduct (
    ProductKey INT PRIMARY KEY,
    ProductID INT,
    ProductName NVARCHAR(100)
)

CREATE TABLE DimCategory (
    CategoryKey INT PRIMARY KEY,
    CategoryID INT,
    CategoryName NVARCHAR(100)
)

-- Bridge table (many-to-many)
CREATE TABLE BridgeProductCategory (
    ProductKey INT,
    CategoryKey INT,
    PRIMARY KEY (ProductKey, CategoryKey),
    FOREIGN KEY (ProductKey) REFERENCES DimProduct(ProductKey),
    FOREIGN KEY (CategoryKey) REFERENCES DimCategory(CategoryKey)
)

-- Query products in multiple categories
SELECT DISTINCT p.ProductName, c.CategoryName
FROM FactSales fs
INNER JOIN DimProduct p ON fs.ProductKey = p.ProductKey
INNER JOIN BridgeProductCategory bpc ON p.ProductKey = bpc.ProductKey
INNER JOIN DimCategory c ON bpc.CategoryKey = c.CategoryKey
```

## ETL Flow (OLTP → OLAP)

```
OPERATIONAL DATABASE (OLTP)
    ↓ Extract
RAW STAGE (As-is copy)
    ↓ Transform & Load
CLEAN STAGE (Validated, deduplicated)
    ↓ Aggregate & Denormalize
DATA WAREHOUSE (OLAP)
    ↓ Aggregate
MARTS (Specialized views)
    ↓ Visualize
DASHBOARDS & REPORTS
```

### Sample ETL Procedure
```sql
CREATE PROCEDURE sp_ETL_LoadDimCustomer
AS
BEGIN
    SET NOCOUNT ON
    
    -- EXTRACT: Get new/changed customers from OLTP
    CREATE TABLE #NewCustomers AS
    SELECT 
        CustomerID,
        CustomerName,
        City,
        CustomerSegment,
        GETDATE() AS LoadDate
    FROM OLTP_Orders.dbo.Customers
    WHERE ModifiedDate > (SELECT MAX(LoadDate) FROM DW_Staging.dbo.LastLoad)
    
    -- TRANSFORM: Apply business rules
    UPDATE #NewCustomers
    SET CustomerName = UPPER(LTRIM(RTRIM(CustomerName))),
        CustomerSegment = CASE
            WHEN CustomerSegment = 'VIP' THEN 'Premium'
            WHEN CustomerSegment = 'REGULAR' THEN 'Standard'
            ELSE 'Budget'
        END
    
    -- LOAD: Merge into dimension (SCD Type 2)
    MERGE INTO DW.dbo.DimCustomer dc
    USING #NewCustomers nc ON dc.CustomerID = nc.CustomerID
    WHEN MATCHED AND dc.IsCurrent = 1 AND dc.CustomerName != nc.CustomerName THEN
        BEGIN
            UPDATE SET ValidTo = GETDATE() - 1, IsCurrent = 0
            WHERE dc.CustomerID = nc.CustomerID AND dc.IsCurrent = 1
            
            INSERT INTO DW.dbo.DimCustomer
            VALUES (NULL, nc.CustomerID, nc.CustomerName, GETDATE(), '9999-12-31', 1)
        END
    WHEN NOT MATCHED THEN
        INSERT VALUES (NULL, nc.CustomerID, nc.CustomerName, GETDATE(), '9999-12-31', 1)
    
    -- Update tracking table
    UPDATE DW_Staging.dbo.LastLoad SET LoadDate = GETDATE()
    
    DROP TABLE #NewCustomers
END
```

## Design Checklist

### OLTP Design
- [ ] All tables have primary keys
- [ ] Foreign key relationships defined
- [ ] Indexes on frequently queried columns
- [ ] Normalized to 3NF
- [ ] Constraints enforce business rules
- [ ] Audit columns (CreatedDate, ModifiedDate, CreatedBy)

### OLAP Design
- [ ] Fact table contains measures (numeric)
- [ ] Dimension tables contain attributes (descriptive)
- [ ] Surrogate keys (DimCustomerKey vs CustomerID)
- [ ] Time dimension populated for all historical dates
- [ ] SCD Type appropriate to business need
- [ ] Columnstore indexes on fact tables
- [ ] Materialized aggregates for common reports

### ETL Design
- [ ] Staging tables for data validation
- [ ] Incremental load strategy (CDC, timestamp, watermark)
- [ ] Error handling and retry logic
- [ ] Data quality checks (nulls, duplicates, referential integrity)
- [ ] Audit logging of load metrics
- [ ] Recovery procedures documented
