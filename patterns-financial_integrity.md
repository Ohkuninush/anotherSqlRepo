---
name: financial-integrity-patterns
description: Enterprise financial integrity patterns — balanced transactions, reconciliation, audit-proof accounting, double-entry bookkeeping, prevent fraud
---

# Financial Integrity Patterns — Audit-Proof Accounting

## Overview

**Why financial integrity matters:**
- Wrong math = auditor fails you
- Data inconsistency = cash missing
- Fraud = criminal liability
- Regulatory violations = fines + jail

**Costs of getting this wrong:**
- Lost revenue (can't track money)
- Accounting nightmare (manual corrections)
- Audit failure (can't explain discrepancies)
- Legal liability (fraud prosecution)

**Examples:**
- Airline revenue accounting ($1B+ per airline)
- Banking (debits ≠ credits = big problem)
- eCommerce (order total ≠ line items)
- Payroll (employees not paid correctly)

---

## Anti-Pattern: No Validation (❌ Don't Do This)

### The Problem
```sql
-- Insert order with no validation
INSERT INTO Orders (OrderID, CustomerID, TotalAmount)
VALUES (1, 100, 500)

-- Insert line items (maybe they don't add up?)
INSERT INTO OrderDetails (OrderDetailID, OrderID, ProductID, Quantity, UnitPrice, LineTotal)
VALUES 
    (1, 1, 10, 5, 100),  -- 5 * 100 = 500 (correct)
    (2, 1, 20, 2, 100),  -- 2 * 100 = 200 (order total now = 700!)

-- Later: Auditor asks "Why is $500 order showing $700 in details?"
-- Answer: "Uh... we don't check"
```

### Real-World Incident
```
Timeline (SaaS Billing):
  Company: Usage-based billing (per API call)
  Customer orders: $10,000 worth
  System records: Customer Account = -$10,000 balance
  System records: Revenue = +$10,000
  
  But: LineItem details = only $8,000 (system bug)
  
  Result:
    - Accounts Receivable ≠ LineItems
    - Revenue ≠ actual usage (missing $2K)
    - Customer disputes: "We were overcharged!"
    - Accountant: "Ledger doesn't match orders"
    - External audit: FAILED
    - Cost to fix: 3 weeks + manual corrections
    - Reputation: Damaged (customer trust)
```

---

## Pattern 1: Double-Entry Bookkeeping

### Use Case
- Financial systems (banking, accounting software)
- Must track BOTH debit and credit
- Every transaction has two sides
- Audit trail is non-negotiable

### ✅ Correct Implementation

#### Schema (Accounting Fundamentals)
```sql
-- Every financial transaction has two sides: debit and credit
CREATE TABLE GeneralLedger (
    LedgerID BIGINT PRIMARY KEY IDENTITY(1, 1),
    TransactionID BIGINT NOT NULL,
    AccountID INT NOT NULL,
    DebitAmount DECIMAL(19, 4) NOT NULL DEFAULT 0,  -- Money in
    CreditAmount DECIMAL(19, 4) NOT NULL DEFAULT 0, -- Money out
    TransactionDate DATETIME2 NOT NULL,
    Description NVARCHAR(500),
    
    -- Constraint: Either debit OR credit, not both
    CONSTRAINT CHK_OnlySideNotNull 
        CHECK ((DebitAmount = 0 AND CreditAmount > 0) OR (CreditAmount = 0 AND DebitAmount > 0)),
    
    FOREIGN KEY (AccountID) REFERENCES ChartOfAccounts(AccountID),
    INDEX IX_GL_Account_Date (AccountID, TransactionDate)
)

CREATE TABLE ChartOfAccounts (
    AccountID INT PRIMARY KEY,
    AccountCode NVARCHAR(20) NOT NULL,
    AccountName NVARCHAR(100) NOT NULL,
    AccountType NVARCHAR(20) NOT NULL,  -- ASSET, LIABILITY, EQUITY, REVENUE, EXPENSE
    NormalBalance NVARCHAR(10) NOT NULL -- DEBIT or CREDIT
)

CREATE TABLE Transactions (
    TransactionID BIGINT PRIMARY KEY IDENTITY(1, 1),
    TransactionType NVARCHAR(20) NOT NULL,  -- SALE, REFUND, ADJUSTMENT, etc
    TransactionDate DATETIME2 NOT NULL,
    Status NVARCHAR(20) NOT NULL DEFAULT 'POSTED'
)
```

#### Posting Transaction (Both Sides)
```sql
CREATE OR ALTER PROCEDURE sp_PostSaleTransaction
    @SaleID BIGINT,
    @Amount DECIMAL(19, 4),
    @CustomerAccountID INT,
    @RevenueAccountID INT
AS
BEGIN
    SET NOCOUNT ON
    SET XACT_ABORT ON
    
    BEGIN TRY
        BEGIN TRANSACTION
        
        DECLARE @TransactionID BIGINT
        
        -- Create parent transaction
        INSERT INTO Transactions (TransactionType, TransactionDate, Status)
        VALUES ('SALE', GETDATE(), 'PENDING')
        
        SET @TransactionID = SCOPE_IDENTITY()
        
        -- Debit: Accounts Receivable (customer owes us)
        INSERT INTO GeneralLedger (TransactionID, AccountID, DebitAmount, TransactionDate, Description)
        VALUES (@TransactionID, @CustomerAccountID, @Amount, GETDATE(), 'Sale to customer')
        
        -- Credit: Revenue (we earned money)
        INSERT INTO GeneralLedger (TransactionID, AccountID, CreditAmount, TransactionDate, Description)
        VALUES (@TransactionID, @RevenueAccountID, @Amount, GETDATE(), 'Revenue from sale')
        
        -- Update transaction status
        UPDATE Transactions SET Status = 'POSTED' WHERE TransactionID = @TransactionID
        
        COMMIT TRANSACTION
        RETURN 0
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION
        THROW
    END CATCH
END
```

#### Verification Query
```sql
-- Verify: All transactions balance (debits = credits)
SELECT 
    TransactionID,
    SUM(CASE WHEN DebitAmount > 0 THEN DebitAmount ELSE 0 END) AS TotalDebits,
    SUM(CASE WHEN CreditAmount > 0 THEN CreditAmount ELSE 0 END) AS TotalCredits,
    SUM(CASE WHEN DebitAmount > 0 THEN DebitAmount ELSE 0 END) - 
    SUM(CASE WHEN CreditAmount > 0 THEN CreditAmount ELSE 0 END) AS Imbalance
FROM GeneralLedger
GROUP BY TransactionID
HAVING SUM(CASE WHEN DebitAmount > 0 THEN DebitAmount ELSE 0 END) != 
       SUM(CASE WHEN CreditAmount > 0 THEN CreditAmount ELSE 0 END)

-- Result: Should be ZERO rows (all balanced)
-- If any rows appear: DATA CORRUPTION
```

---

## Pattern 2: Order Total Validation

### Use Case
- eCommerce (orders must total correctly)
- Invoicing (total must match line items)
- Billing (charges must match usage)

### ✅ Correct Implementation

#### Schema
```sql
CREATE TABLE Orders (
    OrderID INT PRIMARY KEY,
    CustomerID INT NOT NULL,
    OrderDate DATETIME2,
    OrderTotal DECIMAL(10, 2) NOT NULL,
    INDEX IX_Orders_CustomerDate (CustomerID, OrderDate)
)

CREATE TABLE OrderDetails (
    OrderDetailID INT PRIMARY KEY,
    OrderID INT NOT NULL,
    ProductID INT NOT NULL,
    Quantity INT NOT NULL CHECK (Quantity > 0),
    UnitPrice DECIMAL(10, 2) NOT NULL CHECK (UnitPrice > 0),
    LineTotal AS (Quantity * UnitPrice) PERSISTED,
    FOREIGN KEY (OrderID) REFERENCES Orders(OrderID),
    INDEX IX_Details_OrderID (OrderID)
)
```

#### Insert with Validation
```sql
CREATE OR ALTER PROCEDURE sp_CreateOrderWithValidation
    @OrderID INT,
    @CustomerID INT,
    @OrderDetails OrderDetailTable READONLY,  -- Table-valued parameter
    @ExpectedTotal DECIMAL(10, 2)
AS
BEGIN
    SET NOCOUNT ON
    SET XACT_ABORT ON
    
    BEGIN TRY
        -- Step 1: Calculate what total SHOULD be
        DECLARE @CalculatedTotal DECIMAL(10, 2)
        SELECT @CalculatedTotal = SUM(Quantity * UnitPrice)
        FROM @OrderDetails
        
        -- Step 2: Verify it matches what customer expects
        IF ABS(@CalculatedTotal - @ExpectedTotal) > 0.01
            THROW 50001, 'Order total mismatch: expected ' + CAST(@ExpectedTotal AS VARCHAR(10)) 
                         + ', calculated ' + CAST(@CalculatedTotal AS VARCHAR(10)), 1
        
        BEGIN TRANSACTION
        
        -- Step 3: Insert order with verified total
        INSERT INTO Orders (OrderID, CustomerID, OrderDate, OrderTotal)
        VALUES (@OrderID, @CustomerID, GETDATE(), @CalculatedTotal)
        
        -- Step 4: Insert line items
        INSERT INTO OrderDetails (OrderDetailID, OrderID, ProductID, Quantity, UnitPrice)
        SELECT ROW_NUMBER() OVER (ORDER BY ProductID), @OrderID, ProductID, Quantity, UnitPrice
        FROM @OrderDetails
        
        -- Step 5: Verify order total still matches line items
        DECLARE @VerifyTotal DECIMAL(10, 2)
        SELECT @VerifyTotal = SUM(LineTotal)
        FROM OrderDetails
        WHERE OrderID = @OrderID
        
        IF ABS(@VerifyTotal - @CalculatedTotal) > 0.01
            THROW 50002, 'Post-insert verification failed', 1
        
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION
        THROW
    END CATCH
END
```

#### Audit Query
```sql
-- Find orders where total doesn't match line items (CORRUPTION)
SELECT 
    o.OrderID,
    o.OrderTotal AS RecordedTotal,
    SUM(d.LineTotal) AS CalculatedTotal,
    o.OrderTotal - SUM(d.LineTotal) AS Discrepancy
FROM Orders o
LEFT JOIN OrderDetails d ON o.OrderID = d.OrderID
GROUP BY o.OrderID, o.OrderTotal
HAVING o.OrderTotal != SUM(d.LineTotal)

-- Result: Should be ZERO rows (all orders correct)
-- If any rows appear: DATA ERROR
```

---

## Pattern 3: Reconciliation Procedure

### Use Case
- End-of-day reconciliation (cash + cards = register)
- Monthly reconciliation (bank statement vs ledger)
- Customer account reconciliation (what we say they owe vs what they say)

### ✅ Correct Implementation

#### Schema
```sql
CREATE TABLE AccountBalances (
    AccountID INT PRIMARY KEY,
    CurrentBalance DECIMAL(19, 4),
    ReconciliationDate DATETIME2
)

CREATE TABLE ReconciliationLog (
    ReconciliationID BIGINT PRIMARY KEY IDENTITY(1, 1),
    AccountID INT,
    ExpectedBalance DECIMAL(19, 4),
    ActualBalance DECIMAL(19, 4),
    Variance DECIMAL(19, 4),
    ReconciliationDate DATETIME2,
    ReconciledByUser NVARCHAR(128),
    Status NVARCHAR(20) -- MATCHED, VARIANCE, ADJUSTMENT
)
```

#### Reconciliation Process
```sql
CREATE OR ALTER PROCEDURE sp_ReconcileAccount
    @AccountID INT,
    @ExpectedBalance DECIMAL(19, 4),
    @AllowAutoAdjust BIT = 0  -- Auto-adjust if variance < 1 cent
AS
BEGIN
    SET NOCOUNT ON
    SET XACT_ABORT ON
    
    BEGIN TRY
        BEGIN TRANSACTION
        
        -- Calculate actual balance from ledger
        DECLARE @ActualBalance DECIMAL(19, 4)
        SELECT @ActualBalance = 
            SUM(CASE WHEN DebitAmount > 0 THEN DebitAmount ELSE -CreditAmount END)
        FROM GeneralLedger
        WHERE AccountID = @AccountID
        
        DECLARE @Variance DECIMAL(19, 4) = @ExpectedBalance - @ActualBalance
        
        -- Log reconciliation
        INSERT INTO ReconciliationLog 
        (AccountID, ExpectedBalance, ActualBalance, Variance, ReconciliationDate, ReconciledByUser, Status)
        VALUES (@AccountID, @ExpectedBalance, @ActualBalance, @Variance, GETDATE(), SUSER_NAME(),
                CASE WHEN @Variance = 0 THEN 'MATCHED'
                     WHEN ABS(@Variance) <= 0.01 THEN 'VARIANCE'
                     ELSE 'VARIANCE' END)
        
        -- If matched, update balance
        IF @Variance = 0
        BEGIN
            UPDATE AccountBalances
            SET CurrentBalance = @ActualBalance,
                ReconciliationDate = GETDATE()
            WHERE AccountID = @AccountID
        END
        -- If small variance and auto-adjust enabled, make correction
        ELSE IF ABS(@Variance) <= 0.01 AND @AllowAutoAdjust = 1
        BEGIN
            -- Create adjustment entry to balance the account
            INSERT INTO GeneralLedger (TransactionID, AccountID, DebitAmount, CreditAmount, TransactionDate, Description)
            VALUES (
                (SELECT MAX(TransactionID) FROM GeneralLedger) + 1,
                @AccountID,
                CASE WHEN @Variance > 0 THEN @Variance ELSE 0 END,
                CASE WHEN @Variance < 0 THEN ABS(@Variance) ELSE 0 END,
                GETDATE(),
                'Reconciliation adjustment: ' + CAST(@Variance AS VARCHAR(20))
            )
            
            UPDATE ReconciliationLog
            SET Status = 'ADJUSTMENT'
            WHERE ReconciliationID = SCOPE_IDENTITY()
        END
        -- If large variance, raise alert
        ELSE IF ABS(@Variance) > 0.01
        BEGIN
            THROW 50001, 'Large reconciliation variance: ' + CAST(@Variance AS VARCHAR(20)), 1
        END
        
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION
        
        INSERT INTO ErrorLog (ErrorNumber, ErrorMessage, ProcedureName, ErrorDate)
        VALUES (ERROR_NUMBER(), ERROR_MESSAGE(), 'sp_ReconcileAccount', GETDATE())
        
        THROW
    END CATCH
END
```

---

## Pattern 4: Refund Processing (Reverse Transaction)

### Use Case
- Customer refunds (reverse the sale)
- Returns processing (undo charges)
- Corrections (fix overcharges)

### ✅ Correct Implementation

```sql
CREATE OR ALTER PROCEDURE sp_ProcessRefund
    @OriginalOrderID INT,
    @RefundAmount DECIMAL(10, 2),
    @RefundReason NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON
    SET XACT_ABORT ON
    
    BEGIN TRY
        DECLARE @OriginalTotal DECIMAL(10, 2)
        DECLARE @CustomerAccountID INT
        DECLARE @RevenueAccountID INT
        DECLARE @RefundTransactionID BIGINT
        
        BEGIN TRANSACTION
        
        -- Get original order details
        SELECT @OriginalTotal = o.OrderTotal,
               @CustomerAccountID = (SELECT AccountID FROM ChartOfAccounts WHERE AccountCode = 'AR001'),
               @RevenueAccountID = (SELECT AccountID FROM ChartOfAccounts WHERE AccountCode = 'REV001')
        FROM Orders o
        WHERE o.OrderID = @OriginalOrderID
        
        IF @RefundAmount > @OriginalTotal
            THROW 50001, 'Refund cannot exceed original order total', 1
        
        -- Create refund transaction
        INSERT INTO Transactions (TransactionType, TransactionDate, Status)
        VALUES ('REFUND', GETDATE(), 'PENDING')
        
        SET @RefundTransactionID = SCOPE_IDENTITY()
        
        -- REVERSE: Credit Accounts Receivable (reduce what customer owes)
        INSERT INTO GeneralLedger (TransactionID, AccountID, CreditAmount, TransactionDate, Description)
        VALUES (@RefundTransactionID, @CustomerAccountID, @RefundAmount, GETDATE(), 
                'Refund for order ' + CAST(@OriginalOrderID AS VARCHAR(10)) + ': ' + @RefundReason)
        
        -- REVERSE: Debit Revenue (reduce revenue recognized)
        INSERT INTO GeneralLedger (TransactionID, AccountID, DebitAmount, TransactionDate, Description)
        VALUES (@RefundTransactionID, @RevenueAccountID, @RefundAmount, GETDATE(),
                'Refund reversal for order ' + CAST(@OriginalOrderID AS VARCHAR(10)))
        
        -- Verify balance
        DECLARE @Debits DECIMAL(19, 4), @Credits DECIMAL(19, 4)
        SELECT @Debits = SUM(CASE WHEN DebitAmount > 0 THEN DebitAmount ELSE 0 END),
               @Credits = SUM(CASE WHEN CreditAmount > 0 THEN CreditAmount ELSE 0 END)
        FROM GeneralLedger
        WHERE TransactionID = @RefundTransactionID
        
        IF @Debits != @Credits
            THROW 50002, 'Refund transaction imbalance detected', 1
        
        -- Update transaction status
        UPDATE Transactions SET Status = 'POSTED' WHERE TransactionID = @RefundTransactionID
        
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION
        THROW
    END CATCH
END
```

---

## Pattern 5: Fraud Detection (Unusual Activity)

### Use Case
- Detect unusual transactions
- Alert on suspicious patterns
- Prevent fraud before it happens

### ✅ Correct Implementation

```sql
CREATE OR ALTER PROCEDURE sp_DetectFraud
    @CustomerID INT,
    @LookbackDays INT = 30
AS
BEGIN
    SET NOCOUNT ON
    
    DECLARE @FraudScore INT = 0
    DECLARE @AverageOrderValue DECIMAL(10, 2)
    DECLARE @RecentOrderValue DECIMAL(10, 2)
    DECLARE @FrequencyToday INT
    
    -- Get metrics
    SELECT @AverageOrderValue = AVG(OrderTotal),
           @FrequencyToday = COUNT(*)
    FROM Orders
    WHERE CustomerID = @CustomerID
      AND OrderDate >= DATEADD(DAY, -@LookbackDays, GETDATE())
    
    SELECT @RecentOrderValue = OrderTotal
    FROM Orders
    WHERE CustomerID = @CustomerID
    ORDER BY OrderDate DESC
    OFFSET 0 ROWS FETCH NEXT 1 ROWS ONLY
    
    -- Check 1: Order much larger than normal
    IF @RecentOrderValue > (@AverageOrderValue * 3)
        SELECT @FraudScore += 20
    
    -- Check 2: Unusual frequency (many orders today)
    SELECT @FrequencyToday = COUNT(*)
    FROM Orders
    WHERE CustomerID = @CustomerID
      AND CAST(OrderDate AS DATE) = CAST(GETDATE() AS DATE)
    
    IF @FrequencyToday > 5
        SELECT @FraudScore += 30
    
    -- Check 3: Unusually large refund
    DECLARE @RecentRefund DECIMAL(10, 2)
    SELECT @RecentRefund = ABS(MIN(LedgerAmount))
    FROM (
        SELECT SUM(CASE WHEN CreditAmount > 0 THEN CreditAmount ELSE -DebitAmount END) AS LedgerAmount
        FROM GeneralLedger
        WHERE TransactionID IN (SELECT TransactionID FROM Transactions WHERE TransactionType = 'REFUND')
          AND TransactionDate >= DATEADD(HOUR, -24, GETDATE())
    ) sub
    
    IF @RecentRefund > (@AverageOrderValue * 2)
        SELECT @FraudScore += 25
    
    -- Return fraud risk assessment
    SELECT 
        @CustomerID AS CustomerID,
        @FraudScore AS FraudScore,
        CASE 
            WHEN @FraudScore >= 50 THEN 'HIGH RISK - INVESTIGATE'
            WHEN @FraudScore >= 25 THEN 'MEDIUM RISK - REVIEW'
            ELSE 'LOW RISK - OK'
        END AS RiskLevel,
        @AverageOrderValue AS AverageOrderValue,
        @RecentOrderValue AS RecentOrderValue,
        @FrequencyToday AS OrdersToday
END
```

---

## Best Practices

### 1. Always Verify Totals
```sql
-- After every transaction
IF (SELECT SUM(DebitAmount) FROM GeneralLedger WHERE TransactionID = @TxnID) !=
   (SELECT SUM(CreditAmount) FROM GeneralLedger WHERE TransactionID = @TxnID)
    THROW 50001, 'Transaction imbalance', 1
```

### 2. Log Everything
```sql
INSERT INTO AuditLog (TableName, Action, OldValue, NewValue, ChangedByUser, ChangedDate)
VALUES ('Orders', 'UPDATE', @OldTotal, @NewTotal, SUSER_NAME(), GETDATE())
```

### 3. Regular Reconciliation
```sql
-- Daily end-of-day
EXEC sp_ReconcileAccount @AccountID = 1001, @ExpectedBalance = @CashRegisterTotal

-- Monthly reconciliation
EXEC sp_ReconcileAccount @AccountID = 1001, @ExpectedBalance = @BankStatement
```

### 4. Prevent Negative Balances
```sql
-- CHECK constraint on account balance
ALTER TABLE AccountBalances
ADD CONSTRAINT CHK_NonNegativeBalance CHECK (CurrentBalance >= 0)
```

---

## References
- `[[inventory_patterns]]` — Order total validation
- `[[audit_trail_patterns]]` — Immutable audit trail
- `testing/data_validation_tests.md` — Verify constraint enforcement
- `references/transaction_management.md` — Transaction atomicity

