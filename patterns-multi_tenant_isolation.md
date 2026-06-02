---
name: multi-tenant-isolation
description: Multi-tenant data isolation patterns — row-level security, tenant filtering, billing accuracy, preventing cross-tenant data leaks
---

# Multi-Tenant Data Isolation — Complete Isolation

## Overview

**Why multi-tenant isolation matters:**
- Company A sees Company B's data = lawsuit
- Billing mixes tenants = revenue nightmare
- One tenant crashes database = all tenants affected
- Performance: One tenant's heavy load hits others

**Costs of data leaks:**
- GDPR fine: €20M or 4% of revenue
- Trust lost: Customers leave
- Incident response: $1M+ per hour
- Regulatory investigation: 6-12 months

**Examples:**
- SaaS platform (each customer is a tenant)
- Healthcare (each hospital is a tenant)
- Financial services (each client is a tenant)

---

## Anti-Pattern: No Isolation (❌ Don't Do This)

### The Problem
```sql
-- Tenant data mixed in same table
CREATE TABLE Documents (
    DocumentID INT PRIMARY KEY,
    TenantID INT,  -- Easy to forget!
    DocumentName NVARCHAR(255),
    Content NVARCHAR(MAX)
)

-- Developer forgets WHERE clause
SELECT * FROM Documents WHERE DocumentName = 'Invoice'
-- Result: Returns EVERY tenant's invoices!

-- Later:
-- Customer A sees Customer B's confidential data
-- Lawsuit. Reputation destroyed.
```

### Real-World Incident
```
Timeline (SaaS Incident):
  2 customers: CompanyA and CompanyB
  CompanyA queries: SELECT * FROM Contracts
  Developer forgot: WHERE TenantID = @CurrentTenantID
  
  CompanyA gets: All contracts from all tenants
  CompanyB's board contracts exposed
  
  Result:
    - GDPR fine: €10M
    - Customer B leaves: $500K/year loss
    - Reputation: Never recovered
    - Root cause: Single WHERE clause missing
```

---

## Pattern 1: Tenant Filtering (Row-Level Security)

### Use Case
- Every query must filter by tenant
- Application enforces tenant context
- Prevents accidental data leaks

### ✅ Correct Implementation

#### Schema with TenantID
```sql
CREATE TABLE Tenants (
    TenantID INT PRIMARY KEY,
    TenantName NVARCHAR(255),
    SubscriptionLevel NVARCHAR(20),
    CreatedDate DATETIME2
)

-- EVERY table has TenantID
CREATE TABLE Documents (
    DocumentID INT PRIMARY KEY,
    TenantID INT NOT NULL,  -- ← ALWAYS required
    DocumentName NVARCHAR(255),
    Content NVARCHAR(MAX),
    CreatedDate DATETIME2,
    FOREIGN KEY (TenantID) REFERENCES Tenants(TenantID),
    INDEX IX_Documents_Tenant (TenantID, CreatedDate DESC)
)

CREATE TABLE Users (
    UserID INT PRIMARY KEY,
    TenantID INT NOT NULL,
    UserName NVARCHAR(100),
    Email NVARCHAR(255),
    FOREIGN KEY (TenantID) REFERENCES Tenants(TenantID),
    INDEX IX_Users_Tenant (TenantID)
)
```

#### Safe Query Pattern
```sql
-- ✅ ALWAYS filter by tenant
CREATE OR ALTER PROCEDURE sp_GetDocuments
    @TenantID INT,
    @DocumentName NVARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON
    
    -- Validate tenant authorization (application should verify this)
    IF @TenantID IS NULL OR @TenantID <= 0
        THROW 50001, 'Invalid tenant', 1
    
    -- REQUIRED: Filter by TenantID
    SELECT DocumentID, DocumentName, Content, CreatedDate
    FROM Documents
    WHERE TenantID = @TenantID  -- ← MANDATORY
      AND DocumentName = @DocumentName
    ORDER BY CreatedDate DESC
END

-- Usage
EXEC sp_GetDocuments @TenantID = 123, @DocumentName = 'Invoice'
```

#### View-Based Enforcement
```sql
-- Use views to force tenant filtering
CREATE VIEW vw_Documents_SafeAccess
AS
SELECT DocumentID, DocumentName, Content, CreatedDate, TenantID
FROM Documents
-- View itself doesn't filter (application provides tenant)
-- But it DOCUMENTS that TenantID exists

-- Create procedure that REQUIRES tenant
CREATE OR ALTER PROCEDURE sp_GetDocumentsSafe
    @TenantID INT,
    @DocumentID INT
AS
BEGIN
    -- Explicit validation
    IF @TenantID IS NULL
        THROW 50001, 'TenantID required', 1
    
    SELECT DocumentID, DocumentName, Content
    FROM vw_Documents_SafeAccess
    WHERE TenantID = @TenantID
      AND DocumentID = @DocumentID
END
```

#### Testing Tenant Isolation
```sql
-- Test 1: Verify tenant cannot see other tenant's data
DECLARE @TenantA INT = 1, @TenantB INT = 2

-- Insert test data
INSERT INTO Documents VALUES (1, @TenantA, 'Secret A', 'Content A', GETDATE())
INSERT INTO Documents VALUES (2, @TenantB, 'Secret B', 'Content B', GETDATE())

-- TenantA queries
DECLARE @ResultCount INT
SELECT @ResultCount = COUNT(*)
FROM Documents
WHERE TenantID = @TenantA

-- Result should be 1, not 2
IF @ResultCount != 1
    THROW 50001, 'ISOLATION VIOLATION: TenantA can see other data', 1

-- Test 2: Stored procedure isolation
EXEC sp_GetDocuments @TenantID = @TenantA, @DocumentName = 'Secret A'
-- Should return 1 row

EXEC sp_GetDocuments @TenantID = @TenantB, @DocumentName = 'Secret A'
-- Should return 0 rows (not found in TenantB)
```

---

## Pattern 2: Row-Level Security (RLS) — SQL Server 2016+

### Use Case
- Automatic filtering (no WHERE clause needed)
- Prevents developer mistakes
- Enterprise security requirement

### ✅ Correct Implementation

#### Enable RLS
```sql
-- Step 1: Create security policy function
CREATE FUNCTION Security.TenantAccessPredicate(@TenantID INT)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
SELECT 1 AS AccessAllowed
WHERE @TenantID = CAST(SESSION_CONTEXT(N'TenantID') AS INT)

-- Step 2: Create security policy on table
CREATE SECURITY POLICY TenantSecurityPolicy
ADD FILTER PREDICATE Security.TenantAccessPredicate(TenantID) ON dbo.Documents,
ADD BLOCK PREDICATE Security.TenantAccessPredicate(TenantID) ON dbo.Documents
AFTER INSERT, AFTER UPDATE

-- Step 3: Enable for select users
ALTER SECURITY POLICY TenantSecurityPolicy
WITH (STATE = ON)
```

#### Set Tenant Context
```sql
-- Application sets tenant before queries
EXEC sp_set_session_context @key = N'TenantID', @value = 123

-- Now all queries automatically filtered
SELECT * FROM Documents
-- WHERE TenantID = 123 (applied automatically!)
```

#### Query Protection
```sql
-- With RLS enabled, this query:
SELECT * FROM Documents WHERE DocumentName = 'Invoice'

-- Becomes (automatically):
SELECT * FROM Documents 
WHERE DocumentName = 'Invoice'
  AND TenantID = 123  -- ← Added by RLS, can't be bypassed
```

#### Advantages
```
✅ Automatic (no developer forgot WHERE)
✅ Can't bypass (enforced at table level)
✅ Consistent (same rule everywhere)
✅ Simple (RLS handles filtering)
```

---

## Pattern 3: Billing Accuracy (Tenant Metering)

### Use Case
- Track usage per tenant
- Prevent billing mixing
- Ensure accuracy for audit

### ✅ Correct Implementation

#### Schema
```sql
CREATE TABLE UsageMetrics (
    MetricID BIGINT PRIMARY KEY IDENTITY(1, 1),
    TenantID INT NOT NULL,
    MetricType NVARCHAR(50) NOT NULL,  -- API_CALLS, STORAGE_GB, USERS, etc
    MetricValue DECIMAL(19, 4) NOT NULL,
    UsageDate DATE NOT NULL,
    RecordedTime DATETIME2 NOT NULL,
    FOREIGN KEY (TenantID) REFERENCES Tenants(TenantID),
    INDEX IX_Usage_Tenant_Date (TenantID, UsageDate)
)

CREATE TABLE BillingLog (
    BillingID BIGINT PRIMARY KEY IDENTITY(1, 1),
    TenantID INT NOT NULL,
    BillingPeriodStart DATE NOT NULL,
    BillingPeriodEnd DATE NOT NULL,
    TotalUsage DECIMAL(19, 4),
    BillingAmount DECIMAL(19, 4),
    BilledDate DATETIME2,
    Status NVARCHAR(20),  -- DRAFT, FINALIZED, PAID
    FOREIGN KEY (TenantID) REFERENCES Tenants(TenantID)
)
```

#### Billing Procedure
```sql
CREATE OR ALTER PROCEDURE sp_GenerateBillingForTenant
    @TenantID INT,
    @BillingPeriodStart DATE,
    @BillingPeriodEnd DATE
AS
BEGIN
    SET NOCOUNT ON
    SET XACT_ABORT ON
    
    BEGIN TRY
        DECLARE @TotalUsage DECIMAL(19, 4)
        DECLARE @RatePerUnit DECIMAL(19, 4) = 0.10
        DECLARE @BillingAmount DECIMAL(19, 4)
        
        BEGIN TRANSACTION
        
        -- Step 1: Verify tenant exists
        IF NOT EXISTS (SELECT 1 FROM Tenants WHERE TenantID = @TenantID)
            THROW 50001, 'Invalid tenant', 1
        
        -- Step 2: Summarize usage for this tenant ONLY
        SELECT @TotalUsage = SUM(MetricValue)
        FROM UsageMetrics
        WHERE TenantID = @TenantID  -- ← TENANT FILTERED
          AND UsageDate BETWEEN @BillingPeriodStart AND @BillingPeriodEnd
        
        SET @TotalUsage = ISNULL(@TotalUsage, 0)
        SET @BillingAmount = @TotalUsage * @RatePerUnit
        
        -- Step 3: Create billing record
        INSERT INTO BillingLog 
        (TenantID, BillingPeriodStart, BillingPeriodEnd, TotalUsage, BillingAmount, BilledDate, Status)
        VALUES (@TenantID, @BillingPeriodStart, @BillingPeriodEnd, @TotalUsage, @BillingAmount, GETDATE(), 'DRAFT')
        
        -- Step 4: Verify isolation (no cross-tenant mixing)
        DECLARE @BillingID BIGINT = SCOPE_IDENTITY()
        DECLARE @VerifyTenant INT
        SELECT @VerifyTenant = TenantID FROM BillingLog WHERE BillingID = @BillingID
        
        IF @VerifyTenant != @TenantID
            THROW 50002, 'Billing isolation violation', 1
        
        COMMIT TRANSACTION
        
        RETURN 0
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION
        THROW
    END CATCH
END

-- Usage
EXEC sp_GenerateBillingForTenant @TenantID = 123, @BillingPeriodStart = '2026-06-01', @BillingPeriodEnd = '2026-06-30'
```

#### Reconciliation
```sql
-- Verify: Billing matches usage (no mixing)
SELECT 
    b.TenantID,
    b.TotalUsage AS BilledUsage,
    SUM(u.MetricValue) AS ActualUsage,
    b.TotalUsage - SUM(u.MetricValue) AS Variance
FROM BillingLog b
LEFT JOIN UsageMetrics u ON b.TenantID = u.TenantID
    AND u.UsageDate BETWEEN b.BillingPeriodStart AND b.BillingPeriodEnd
GROUP BY b.TenantID, b.BilledUsage
HAVING b.TotalUsage != SUM(u.MetricValue)

-- Result: Should be empty (all bills match usage)
```

---

## Pattern 4: Tenant Isolation Testing

### Use Case
- Verify no data leaks between tenants
- Regular compliance testing
- Regression detection

### ✅ Correct Implementation

```sql
CREATE OR ALTER PROCEDURE sp_TestTenantIsolation
    @TenantA INT = 1,
    @TenantB INT = 2
AS
BEGIN
    SET NOCOUNT ON
    DECLARE @FailCount INT = 0
    
    BEGIN TRY
        -- Test 1: TenantA cannot see TenantB documents
        DECLARE @TenantA_CountFromB INT
        SELECT @TenantA_CountFromB = COUNT(*)
        FROM Documents d
        WHERE TenantID = @TenantA
          AND OWNER_ID = @TenantB  -- Would only happen if isolation broken
        
        IF @TenantA_CountFromB > 0
        BEGIN
            PRINT 'FAIL: TenantA can see TenantB data'
            SET @FailCount += 1
        END
        
        -- Test 2: Query filtering works
        DECLARE @DocCount INT
        SELECT @DocCount = COUNT(*)
        FROM Documents
        WHERE TenantID = @TenantA
        
        -- Run proc as TenantB, should get 0 results for TenantA docs
        EXEC sp_set_session_context @key = N'TenantID', @value = @TenantB
        DECLARE @DocCountFromB INT
        SELECT @DocCountFromB = COUNT(*)
        FROM Documents
        WHERE TenantID = @TenantA
        
        IF @DocCountFromB > 0
        BEGIN
            PRINT 'FAIL: RLS not filtering correctly'
            SET @FailCount += 1
        END
        
        -- Test 3: Billing isolation
        DECLARE @TenantA_Bill DECIMAL(19, 4)
        DECLARE @TenantB_Bill DECIMAL(19, 4)
        
        SELECT @TenantA_Bill = SUM(BillingAmount)
        FROM BillingLog WHERE TenantID = @TenantA
        
        SELECT @TenantB_Bill = SUM(BillingAmount)
        FROM BillingLog WHERE TenantID = @TenantB
        
        -- Verify no mixing (they should be separate)
        IF @TenantA_Bill = @TenantB_Bill AND @TenantA_Bill > 0
        BEGIN
            PRINT 'WARNING: Identical bills (possible mixing)'
            SET @FailCount += 1
        END
        
        -- Summary
        IF @FailCount = 0
            PRINT 'Tenant isolation: PASS'
        ELSE
            PRINT 'Tenant isolation: FAIL (' + CAST(@FailCount AS VARCHAR(3)) + ' tests failed)'
        
        RETURN @FailCount
    END TRY
    BEGIN CATCH
        THROW
    END CATCH
END

-- Usage
EXEC sp_TestTenantIsolation @TenantA = 1, @TenantB = 2
```

---

## Best Practices

### 1. Every Table Has TenantID
```sql
-- NEVER forget TenantID
CREATE TABLE Anything (
    ID INT,
    TenantID INT NOT NULL,  -- ← ALWAYS
    ...
)
```

### 2. Every Procedure Validates Tenant
```sql
-- Required first line in any proc touching data
IF @TenantID IS NULL OR @TenantID <= 0
    THROW 50001, 'Invalid tenant', 1
```

### 3. Every Index Includes TenantID
```sql
-- For performance, always filter by tenant
CREATE INDEX IX_Documents_Tenant 
ON Documents(TenantID, CreatedDate)
```

### 4. Regular Isolation Testing
```sql
-- Monthly: Verify no cross-tenant leaks
EXEC sp_TestTenantIsolation
```

### 5. RLS When Possible
```sql
-- SQL Server 2016+: Use RLS for automatic filtering
CREATE SECURITY POLICY TenantSecurityPolicy
ADD FILTER PREDICATE Security.TenantAccessPredicate(TenantID)
```

---

## References
- `[[data_validation_tests]]` — Test isolation constraints
- `[[audit_trail_patterns]]` — Log cross-tenant attempts
- `references/security_rbac_guide.md` — Security model
- `testing/regression_testing.md` — Detect isolation breaks

