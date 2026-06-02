---
name: inventory-patterns
description: Enterprise inventory management patterns — stock tracking, negative prevention, reservation systems, atomicity, oversell protection, and financial integrity
---

# Inventory Patterns — Stock Tracking & Control

## Overview

**Why inventory patterns matter:**
- Negative inventory = chaos (can't fulfill orders, accounting breaks)
- Double-selling = angry customers (oversold)
- Reservation confusion = phantom stock (shows available but reserved)
- Lost updates = silent data corruption (concurrency bugs)

**Cost of getting this wrong:**
- Lost revenue (can't fulfill orders)
- Excess costs (buy too much)
- Customer dissatisfaction (wrong fulfillment)
- Audit failures (stock doesn't match records)

---

## Anti-Pattern: No Reservation System (❌ Don't Do This)

### The Problem
```sql
-- Dangerous: Inventory with no reservation concept
CREATE TABLE Inventory (
    ProductID INT PRIMARY KEY,
    QuantityOnHand INT NOT NULL
)

-- Race condition: Two orders can over-sell the same stock
-- Transaction 1: Check stock (100 available)
-- Transaction 2: Check stock (100 available) ← Same value!
-- Transaction 1: Sell 80 (20 left)
-- Transaction 2: Sell 80 (20 left) ← Should fail!
-- But both succeed because no locking
```

### Real-World Incident
```
Timeline (High-Traffic Sale):
  Black Friday: Everyone ordering same hot item
  10:00 AM: Stock = 100 units
  10:00:01 AM: Order 1 checks: 100 available → Buys 100
  10:00:01 AM: Order 2 checks: 100 available → Buys 100
  10:00:02 AM: Stock = -100 (we owe customers 100 units!)
  
Result: 
  - Can't fulfill Order 2
  - Customer refund + angry review
  - Email: "Can't believe you oversold"
  - Accounting: Manual inventory adjustment
  
Root cause: No atomic reservation system
```

---

## Pattern 1: Simple Inventory with Negative Prevention

### Use Case
- Basic eCommerce (prevent oversell)
- Moderate transaction volume
- Simple product portfolio (no variants, no reservations)

### ✅ Correct Implementation

#### Schema
```sql
CREATE TABLE Inventory (
    ProductID INT PRIMARY KEY,
    QuantityOnHand INT NOT NULL CHECK (QuantityOnHand >= 0),
    LastUpdated DATETIME2,
    INDEX IX_Quantity (QuantityOnHand) WHERE QuantityOnHand > 0
)
```

#### Atomic Purchase
```sql
CREATE OR ALTER PROCEDURE sp_PurchaseInventory
    @ProductID INT,
    @QuantityToPurchase INT,
    @OrderID INT
AS
BEGIN
    SET NOCOUNT ON
    SET XACT_ABORT ON
    
    BEGIN TRY
        BEGIN TRANSACTION
        
        -- Step 1: Lock the row to prevent race conditions
        DECLARE @CurrentQty INT
        SELECT @CurrentQty = QuantityOnHand
        FROM Inventory WITH (UPDLOCK, READCOMMITTED)
        WHERE ProductID = @ProductID
        
        -- Step 2: Check if enough stock available
        IF @CurrentQty IS NULL
            THROW 50001, 'Product not found', 1
        
        IF @CurrentQty < @QuantityToPurchase
            THROW 50002, 'Insufficient inventory', 1
        
        -- Step 3: Deduct atomically
        UPDATE Inventory
        SET QuantityOnHand = QuantityOnHand - @QuantityToPurchase,
            LastUpdated = GETDATE()
        WHERE ProductID = @ProductID
        
        -- Step 4: Log the transaction
        INSERT INTO InventoryLog (ProductID, OrderID, QuantityChange, ActionType, ActionDate)
        VALUES (@ProductID, @OrderID, -@QuantityToPurchase, 'SOLD', GETDATE())
        
        COMMIT TRANSACTION
        RETURN 0  -- Success
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION
        THROW
    END CATCH
END

-- Usage
EXEC sp_PurchaseInventory @ProductID = 1, @QuantityToPurchase = 5, @OrderID = 101
```

#### Key Elements
```
✅ CHECK constraint (QuantityOnHand >= 0) prevents negative
✅ UPDLOCK prevents other transactions from reading stale value
✅ Atomic operation (UPDATE in transaction)
✅ @@TRANCOUNT check (proper error handling)
✅ Logging (audit trail)
```

---

## Pattern 2: Inventory with Reservations

### Use Case
- Multi-step fulfillment (order → pack → ship)
- Shopping carts (temporary holds)
- Backorders (reserve for customer)
- Prevent oversell during packing

### ✅ Correct Implementation

#### Schema
```sql
CREATE TABLE Inventory (
    ProductID INT PRIMARY KEY,
    QuantityOnHand INT NOT NULL CHECK (QuantityOnHand >= 0),
    QuantityReserved INT NOT NULL DEFAULT 0 CHECK (QuantityReserved >= 0),
    AvailableQuantity AS (QuantityOnHand - QuantityReserved) PERSISTED,
    LastUpdated DATETIME2
)

-- Tracks what's reserved and for whom
CREATE TABLE InventoryReservations (
    ReservationID BIGINT PRIMARY KEY IDENTITY(1, 1),
    ProductID INT NOT NULL,
    OrderID INT NOT NULL,
    ReservedQuantity INT NOT NULL CHECK (ReservedQuantity > 0),
    ReservationStatus NVARCHAR(20) DEFAULT 'ACTIVE',  -- ACTIVE, FULFILLED, CANCELLED
    ReservedDate DATETIME2,
    FulfilledDate DATETIME2,
    FOREIGN KEY (ProductID) REFERENCES Inventory(ProductID)
)
```

#### Reserve Inventory
```sql
CREATE OR ALTER PROCEDURE sp_ReserveInventory
    @ProductID INT,
    @OrderID INT,
    @QuantityToReserve INT
AS
BEGIN
    SET NOCOUNT ON
    SET XACT_ABORT ON
    
    BEGIN TRY
        BEGIN TRANSACTION
        
        -- Step 1: Check available (on-hand minus already-reserved)
        DECLARE @AvailableQty INT
        SELECT @AvailableQty = AvailableQuantity
        FROM Inventory WITH (UPDLOCK)
        WHERE ProductID = @ProductID
        
        IF @AvailableQty < @QuantityToReserve
            THROW 50001, 'Insufficient available inventory', 1
        
        -- Step 2: Increment reserved
        UPDATE Inventory
        SET QuantityReserved = QuantityReserved + @QuantityToReserve,
            LastUpdated = GETDATE()
        WHERE ProductID = @ProductID
        
        -- Step 3: Log the reservation
        INSERT INTO InventoryReservations 
        (ProductID, OrderID, ReservedQuantity, ReservationStatus, ReservedDate)
        VALUES (@ProductID, @OrderID, @QuantityToReserve, 'ACTIVE', GETDATE())
        
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION
        THROW
    END CATCH
END
```

#### Fulfill Reservation (Deduct from On-Hand)
```sql
CREATE OR ALTER PROCEDURE sp_FulfillReservation
    @ProductID INT,
    @OrderID INT,
    @ReservationID BIGINT
AS
BEGIN
    SET NOCOUNT ON
    SET XACT_ABORT ON
    
    BEGIN TRY
        BEGIN TRANSACTION
        
        DECLARE @ReservedQty INT
        
        -- Step 1: Get reservation details
        SELECT @ReservedQty = ReservedQuantity
        FROM InventoryReservations
        WHERE ReservationID = @ReservationID
          AND ProductID = @ProductID
          AND OrderID = @OrderID
          AND ReservationStatus = 'ACTIVE'
        
        IF @ReservedQty IS NULL
            THROW 50001, 'Reservation not found or already fulfilled', 1
        
        -- Step 2: Deduct from on-hand and release from reserved
        UPDATE Inventory
        SET QuantityOnHand = QuantityOnHand - @ReservedQty,
            QuantityReserved = QuantityReserved - @ReservedQty,
            LastUpdated = GETDATE()
        WHERE ProductID = @ProductID
        
        -- Step 3: Mark reservation as fulfilled
        UPDATE InventoryReservations
        SET ReservationStatus = 'FULFILLED',
            FulfilledDate = GETDATE()
        WHERE ReservationID = @ReservationID
        
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION
        THROW
    END CATCH
END
```

#### Cancel Reservation
```sql
CREATE OR ALTER PROCEDURE sp_CancelReservation
    @ReservationID BIGINT
AS
BEGIN
    SET NOCOUNT ON
    SET XACT_ABORT ON
    
    BEGIN TRY
        BEGIN TRANSACTION
        
        DECLARE @ProductID INT, @ReservedQty INT
        
        SELECT @ProductID = ProductID, @ReservedQty = ReservedQuantity
        FROM InventoryReservations
        WHERE ReservationID = @ReservationID
          AND ReservationStatus = 'ACTIVE'
        
        IF @ReservedQty IS NULL
            THROW 50001, 'Reservation not found or already processed', 1
        
        -- Release the reservation
        UPDATE Inventory
        SET QuantityReserved = QuantityReserved - @ReservedQty,
            LastUpdated = GETDATE()
        WHERE ProductID = @ProductID
        
        -- Mark as cancelled
        UPDATE InventoryReservations
        SET ReservationStatus = 'CANCELLED'
        WHERE ReservationID = @ReservationID
        
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION
        THROW
    END CATCH
END
```

#### Status Queries
```sql
-- What inventory is available?
SELECT 
    ProductID,
    QuantityOnHand,
    QuantityReserved,
    AvailableQuantity
FROM Inventory
WHERE ProductID = @ProductID

-- What's reserved for a specific order?
SELECT 
    r.ReservationID,
    r.ProductID,
    r.ReservedQuantity,
    r.ReservationStatus,
    r.ReservedDate
FROM InventoryReservations r
WHERE r.OrderID = @OrderID
  AND r.ReservationStatus = 'ACTIVE'
```

---

## Pattern 3: Inventory Adjustments (Reconciliation)

### Use Case
- Physical inventory count (stock-take)
- Damage/waste recording
- Correction of errors
- Compliance reporting

### ✅ Correct Implementation

```sql
CREATE TABLE InventoryAdjustments (
    AdjustmentID BIGINT PRIMARY KEY IDENTITY(1, 1),
    ProductID INT,
    AdjustmentQuantity INT,  -- Can be negative
    AdjustmentReason NVARCHAR(100),  -- DAMAGE, LOSS, ERROR, PHYSICAL_COUNT
    AdjustedByUser NVARCHAR(128),
    AdjustmentDate DATETIME2,
    ApprovedByUser NVARCHAR(128),
    ApprovedDate DATETIME2
)

CREATE OR ALTER PROCEDURE sp_AdjustInventory
    @ProductID INT,
    @AdjustmentQuantity INT,  -- Positive or negative
    @Reason NVARCHAR(100),
    @ApprovedByUser NVARCHAR(128) = NULL
AS
BEGIN
    SET NOCOUNT ON
    SET XACT_ABORT ON
    
    BEGIN TRY
        BEGIN TRANSACTION
        
        -- Prevent large adjustments without approval
        IF ABS(@AdjustmentQuantity) > 100 AND @ApprovedByUser IS NULL
            THROW 50001, 'Large adjustments require approval', 1
        
        -- Update inventory
        UPDATE Inventory
        SET QuantityOnHand = QuantityOnHand + @AdjustmentQuantity,
            LastUpdated = GETDATE()
        WHERE ProductID = @ProductID
        
        -- Verify didn't go negative (even with this adjustment)
        IF (SELECT QuantityOnHand FROM Inventory WHERE ProductID = @ProductID) < 0
            THROW 50002, 'Adjustment would result in negative inventory', 1
        
        -- Log adjustment
        INSERT INTO InventoryAdjustments 
        (ProductID, AdjustmentQuantity, AdjustmentReason, AdjustedByUser, 
         AdjustmentDate, ApprovedByUser, ApprovedDate)
        VALUES (@ProductID, @AdjustmentQuantity, @Reason, SUSER_NAME(),
                GETDATE(), @ApprovedByUser, 
                CASE WHEN @ApprovedByUser IS NOT NULL THEN GETDATE() END)
        
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

## Pattern 4: Backorder Handling

### Use Case
- Allow oversell if customer accepts backorder
- Track backorder separately
- Fulfill when stock available

### ✅ Correct Implementation

```sql
CREATE TABLE Backorders (
    BackorderID BIGINT PRIMARY KEY IDENTITY(1, 1),
    ProductID INT,
    OrderID INT,
    BackorderedQuantity INT,
    BackorderStatus NVARCHAR(20) DEFAULT 'PENDING',  -- PENDING, FULFILLED, CANCELLED
    BackorderedDate DATETIME2,
    FulfilledDate DATETIME2
)

CREATE OR ALTER PROCEDURE sp_PurchaseWithBackorder
    @ProductID INT,
    @OrderID INT,
    @QuantityRequested INT
AS
BEGIN
    SET NOCOUNT ON
    SET XACT_ABORT ON
    
    BEGIN TRY
        BEGIN TRANSACTION
        
        DECLARE @AvailableQty INT
        SELECT @AvailableQty = AvailableQuantity
        FROM Inventory WITH (UPDLOCK)
        WHERE ProductID = @ProductID
        
        IF @AvailableQty >= @QuantityRequested
        BEGIN
            -- Enough stock: normal purchase
            UPDATE Inventory
            SET QuantityOnHand = QuantityOnHand - @QuantityRequested
            WHERE ProductID = @ProductID
            
            INSERT INTO InventoryLog VALUES (@ProductID, @OrderID, -@QuantityRequested, 'SOLD', GETDATE())
        END
        ELSE
        BEGIN
            -- Partial stock: fulfill what we can, backorder the rest
            IF @AvailableQty > 0
            BEGIN
                UPDATE Inventory
                SET QuantityOnHand = 0
                WHERE ProductID = @ProductID
                
                INSERT INTO InventoryLog VALUES (@ProductID, @OrderID, -@AvailableQty, 'SOLD', GETDATE())
            END
            
            -- Create backorder for remainder
            DECLARE @BackorderQty INT = @QuantityRequested - @AvailableQty
            INSERT INTO Backorders (ProductID, OrderID, BackorderedQuantity, BackorderedDate)
            VALUES (@ProductID, @OrderID, @BackorderQty, GETDATE())
        END
        
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

## Pattern 5: Inventory Recount & Reconciliation

### Use Case
- Physical inventory count doesn't match system
- Find discrepancies
- Adjust records

### ✅ Correct Implementation

```sql
CREATE TABLE PhysicalInventoryCount (
    CountID BIGINT PRIMARY KEY IDENTITY(1, 1),
    ProductID INT,
    PhysicalCount INT,
    SystemCount INT,
    Variance INT,
    CountedByUser NVARCHAR(128),
    CountDate DATETIME2
)

CREATE OR ALTER PROCEDURE sp_ReconcileInventory
    @ProductID INT,
    @PhysicalCount INT
AS
BEGIN
    SET NOCOUNT ON
    SET XACT_ABORT ON
    
    BEGIN TRY
        BEGIN TRANSACTION
        
        DECLARE @SystemCount INT
        SELECT @SystemCount = QuantityOnHand
        FROM Inventory
        WHERE ProductID = @ProductID
        
        DECLARE @Variance INT = @PhysicalCount - @SystemCount
        
        -- Log the count
        INSERT INTO PhysicalInventoryCount 
        (ProductID, PhysicalCount, SystemCount, Variance, CountedByUser, CountDate)
        VALUES (@ProductID, @PhysicalCount, @SystemCount, @Variance, SUSER_NAME(), GETDATE())
        
        -- Adjust if variance exists
        IF @Variance != 0
        BEGIN
            UPDATE Inventory
            SET QuantityOnHand = @PhysicalCount,
                LastUpdated = GETDATE()
            WHERE ProductID = @ProductID
            
            -- Log adjustment with variance reason
            INSERT INTO InventoryAdjustments 
            (ProductID, AdjustmentQuantity, AdjustmentReason, AdjustedByUser, AdjustmentDate)
            VALUES (@ProductID, @Variance, 'RECOUNT_VARIANCE', SUSER_NAME(), GETDATE())
        END
        
        COMMIT TRANSACTION
        
        -- Report variance
        SELECT 
            @ProductID AS ProductID,
            @SystemCount AS SystemCount,
            @PhysicalCount AS PhysicalCount,
            @Variance AS Variance,
            CAST(ABS(@Variance) * 100.0 / NULLIF(@SystemCount, 0) AS DECIMAL(5, 2)) AS VariancePercent
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION
        THROW
    END CATCH
END
```

---

## Best Practices

### 1. Always Lock During Check-and-Act
```sql
-- ❌ WRONG: Time gap between SELECT and UPDATE
SELECT @Qty = QuantityOnHand FROM Inventory WHERE ProductID = @ID
IF @Qty >= 10
    UPDATE Inventory SET QuantityOnHand -= 10 WHERE ProductID = @ID

-- ✅ CORRECT: Lock during SELECT
SELECT @Qty = QuantityOnHand 
FROM Inventory WITH (UPDLOCK)
WHERE ProductID = @ID
IF @Qty >= 10
    UPDATE Inventory SET QuantityOnHand -= 10 WHERE ProductID = @ID
```

### 2. Calculated Columns for Available Quantity
```sql
-- Always derive AvailableQuantity
AvailableQuantity AS (QuantityOnHand - QuantityReserved) PERSISTED

-- Prevents inconsistency
```

### 3. Log Everything
```sql
-- Every change to inventory must be logged
INSERT INTO InventoryLog (ProductID, QuantityChange, Action, ActionDate)
VALUES (@ProductID, @Change, 'SOLD', GETDATE())
```

### 4. Regular Audits
```sql
-- Monthly reconciliation query
SELECT 
    ProductID,
    SUM(CASE WHEN ActionType = 'SOLD' THEN QuantityChange ELSE 0 END) AS TotalSold,
    SUM(CASE WHEN ActionType = 'RECEIVED' THEN QuantityChange ELSE 0 END) AS TotalReceived,
    (SELECT QuantityOnHand FROM Inventory i WHERE i.ProductID = l.ProductID) AS CurrentStock
FROM InventoryLog l
WHERE ActionDate >= DATEADD(MONTH, -1, GETDATE())
GROUP BY ProductID
```

---

## References
- `[[soft_delete_patterns]]` — Handling product discontinuation
- `[[data_validation_tests]]` — Testing inventory constraints
- `references/transaction_management.md` — Transaction isolation in inventory
- `references/concurrency_blocking.md` — Locking strategies

