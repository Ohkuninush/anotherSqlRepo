# SQL Server High Availability & Disaster Recovery

## Definitions: RTO & RPO

- **RTO (Recovery Time Objective):** How long can the system be DOWN before unacceptable business impact
  - Example: "RTO = 1 hour" means must be back online within 60 minutes
  
- **RPO (Recovery Point Objective):** How much DATA LOSS is acceptable
  - Example: "RPO = 15 minutes" means losing 15 minutes of work is acceptable

## Always On Availability Groups

### Setup (Synchronous Replication - High Safety)
```sql
-- Step 1: Create availability group
CREATE AVAILABILITY GROUP HighAvailability
WITH (AUTOMATED_BACKUP_PREFERENCE = PRIMARY_REPLICA)
FOR DATABASE MyDatabase
REPLICA ON
    'SQLSERVER1' WITH (
        ENDPOINT_URL = 'TCP://SQLSERVER1.domain.com:5022',
        AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
        FAILOVER_MODE = AUTOMATIC,
        BACKUP_PRIORITY = 100
    ),
    'SQLSERVER2' WITH (
        ENDPOINT_URL = 'TCP://SQLSERVER2.domain.com:5022',
        AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
        FAILOVER_MODE = MANUAL,
        BACKUP_PRIORITY = 50
    )

-- Step 2: Join secondary to AG (run on secondary)
ALTER AVAILABILITY GROUP HighAvailability JOIN

-- Step 3: Grant backup permissions
ALTER AVAILABILITY GROUP HighAvailability GRANT CREATE ANY DATABASE

-- Step 4: Monitor health
SELECT 
    replica_server_name,
    availability_mode_desc,
    failover_mode_desc,
    operational_state_desc,
    synchronization_health_desc
FROM sys.dm_hadr_availability_replica_states
ORDER BY replica_server_name
```

### Automatic Failover
```sql
-- Always On automatically fails over when:
-- 1. Primary becomes unavailable (network, crash, service stop)
-- 2. Secondary is in SYNCHRONIZED state (RPO = 0)
-- 3. Failover mode = AUTOMATIC

-- Failover triggers:
-- - Network timeout (default 10 seconds)
-- - Database health check failure
-- - Lease timeout

-- Verify AG is healthy before failover
SELECT 
    ag.name,
    hars.replica_server_name,
    hars.operational_state_desc,
    hars.synchronization_health_desc,
    hdrs.database_state_desc,
    hdrs.synchronization_state_desc
FROM sys.availability_groups ag
INNER JOIN sys.dm_hadr_availability_replica_states hars ON ag.group_id = hars.group_id
INNER JOIN sys.dm_hadr_database_replica_states hdrs ON hars.replica_id = hdrs.replica_id
ORDER BY ag.name, replica_server_name
```

### Asynchronous Replication (For DR)
```sql
-- Secondary in different datacenter (asynchronous)
ALTER AVAILABILITY GROUP DisasterRecovery
MODIFY REPLICA ON 'SQLSERVER_DR'
WITH (AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT)

-- Risks:
-- - Failover may lose uncommitted transactions (RPO = some data loss)
-- - Manual failover only (no automatic)
-- - DR replica may not be fully synchronized

-- Use for: Low-priority databases, remote sites, cost reduction
```

## Log Shipping

### Setup (Manual Failover, Lower Cost)
```sql
-- Step 1: Full backup of primary
BACKUP DATABASE MyDatabase
TO DISK = '\\BackupShare\MyDatabase_Full.bak'
WITH INIT

-- Step 2: Restore on secondary (STANDBY mode)
RESTORE DATABASE MyDatabase
FROM DISK = '\\BackupShare\MyDatabase_Full.bak'
WITH STANDBY = '\\BackupShare\MyDatabase_Undo.ldf'

-- Step 3: Setup log shipping job (backup logs periodically)
EXEC sp_add_log_shipping_primary_database
    @database = 'MyDatabase',
    @backup_directory = '\\BackupShare\Logs',
    @backup_share = '\\BackupShare\Logs',
    @backup_job_name = 'LSBackup_MyDatabase',
    @backup_retention_period = 4320  -- 3 days in minutes

-- Step 4: Setup restore job on secondary
EXEC sp_add_log_shipping_secondary_database
    @secondary_database = 'MyDatabase',
    @primary_server = 'SQLSERVER1',
    @primary_database = 'MyDatabase',
    @restore_delay = 0,
    @restore_mode = 0,  -- STANDBY mode (can query)
    @disconnect_users = 1,
    @restore_job_name = 'LSRestore_MyDatabase'

-- Monitor log shipping
SELECT 
    primary_server,
    primary_database,
    secondary_server,
    secondary_database,
    backup_threshold,
    last_backup_date,
    last_restored_date
FROM msdb.dbo.log_shipping_monitor_primary
```

## Backup Strategy

### Full Backup (Weekly or Monthly)
```sql
-- Complete database backup
BACKUP DATABASE MyDatabase
TO DISK = 'D:\Backups\MyDatabase_Full_20240601.bak'
WITH 
    INIT,
    NAME = 'Full Backup 2024-06-01',
    DESCRIPTION = 'Complete backup of MyDatabase',
    CHECKSUM,  -- Verify backup integrity
    COMPRESSION

-- Size: ~100MB per 1GB of database
-- Time: 1-10 minutes (depends on size)
-- Retention: Keep for 4-8 weeks
```

### Differential Backup (Daily)
```sql
-- Changes since last FULL backup
BACKUP DATABASE MyDatabase
TO DISK = 'D:\Backups\MyDatabase_Diff_20240601.bak'
WITH 
    DIFFERENTIAL,
    INIT,
    CHECKSUM,
    COMPRESSION

-- Size: ~10-30% of changes since full
-- Retention: Until next full backup taken
-- Best for: Large databases (faster restores than log backups)
```

### Transaction Log Backup (Every 15-30 minutes)
```sql
-- Backup uncommitted transactions
BACKUP LOG MyDatabase
TO DISK = 'D:\Backups\MyDatabase_Log_20240601_1030.trn'
WITH 
    INIT,
    CHECKSUM,
    COMPRESSION

-- Size: Small (usually < 50MB)
-- Retention: 7-14 days (for point-in-time recovery)
-- Strategy:
--   - Every 15 minutes: High-value databases
--   - Every 60 minutes: Standard databases
--   - Every 4 hours: Low-priority databases
```

### Automated Backup Script
```sql
-- Maintenance plan (SQL Server Agent job)
-- Daily: Full backup (Sunday)
-- Daily: Differential (Mon-Sat)
-- Every 30 min: Transaction log

CREATE PROCEDURE sp_DailyBackupRoutine
AS
BEGIN
    SET NOCOUNT ON
    
    DECLARE @BackupPath NVARCHAR(256) = 'D:\Backups\'
    DECLARE @BackupDate NVARCHAR(10) = FORMAT(GETDATE(), 'yyyyMMdd')
    DECLARE @DayOfWeek INT = DATEPART(WEEKDAY, GETDATE())
    
    IF @DayOfWeek = 1  -- Sunday
    BEGIN
        -- Full backup
        BACKUP DATABASE MyDatabase
        TO DISK = @BackupPath + 'MyDatabase_Full_' + @BackupDate + '.bak'
        WITH INIT, CHECKSUM, COMPRESSION
    END
    ELSE
    BEGIN
        -- Differential backup
        BACKUP DATABASE MyDatabase
        TO DISK = @BackupPath + 'MyDatabase_Diff_' + @BackupDate + '.bak'
        WITH DIFFERENTIAL, INIT, CHECKSUM, COMPRESSION
    END
    
    -- Transaction log backup (always)
    BACKUP LOG MyDatabase
    TO DISK = @BackupPath + 'MyDatabase_Log_' + FORMAT(GETDATE(), 'yyyyMMdd_HHmm') + '.trn'
    WITH INIT, CHECKSUM, COMPRESSION
END
```

## Point-in-Time Recovery (PITR)

### Recovery to Specific Time
```sql
-- SCENARIO: Data deleted at 2:45 PM, need to recover to 2:40 PM

-- Step 1: Restore full backup (as of Sunday 11 PM)
RESTORE DATABASE MyDatabase
FROM DISK = 'D:\Backups\MyDatabase_Full_20240602.bak'
WITH NORECOVERY

-- Step 2: Restore differential (as of Monday 2 AM)
RESTORE DATABASE MyDatabase
FROM DISK = 'D:\Backups\MyDatabase_Diff_20240602.bak'
WITH NORECOVERY

-- Step 3: Restore log backups up to target time
RESTORE LOG MyDatabase
FROM DISK = 'D:\Backups\MyDatabase_Log_20240602_0200.trn'
WITH NORECOVERY

RESTORE LOG MyDatabase
FROM DISK = 'D:\Backups\MyDatabase_Log_20240602_0230.trn'
WITH NORECOVERY

-- Step 4: Restore log with STOPAT (recover to exact time)
RESTORE LOG MyDatabase
FROM DISK = 'D:\Backups\MyDatabase_Log_20240602_0245.trn'
WITH STOPAT = '2024-06-02 14:40:00',  -- 2:40 PM
RECOVERY

-- Database now contains data as of 2:40 PM (before deletion)
```

### Verify Backup Integrity
```sql
-- Check backup is valid
RESTORE VERIFYONLY
FROM DISK = 'D:\Backups\MyDatabase_Full_20240602.bak'

-- Restore to Test database to validate
RESTORE DATABASE MyDatabase_Test
FROM DISK = 'D:\Backups\MyDatabase_Full_20240602.bak'
WITH REPLACE, RECOVERY

-- Run integrity check
DBCC CHECKDB (MyDatabase_Test) WITH NO_INFOMSGS

-- If OK, backup is valid; if errors, backup is corrupted
```

## Recovery Testing

### Test RTO (How fast can we recover?)
```sql
-- Procedure:
-- 1. Record current time
-- 2. Simulate primary failure (take database offline)
-- 3. Failover to secondary or restore from backup
-- 4. Run critical queries to verify data
-- 5. Record recovery completion time
-- 6. Calculate RTO = completion - failure

DECLARE @FailoverStartTime DATETIME = GETDATE()

-- Failover to secondary
ALTER AVAILABILITY GROUP HighAvailability FAILOVER

-- Verify database is online
WHILE (SELECT state_desc FROM sys.databases WHERE name = 'MyDatabase') != 'ONLINE'
    WAITFOR DELAY '00:00:01'

-- Test critical application functionality
EXEC sp_VerifyApplicationHealth

DECLARE @RecoveryTime INT = DATEDIFF(SECOND, @FailoverStartTime, GETDATE())
INSERT INTO HA_TestLog VALUES (GETDATE(), 'Failover RTO', @RecoveryTime, 'Success')

-- RTO Target: 5 minutes, Actual: 2 minutes ✓
```

### Test RPO (How much data loss?)
```sql
-- Procedure:
-- 1. Write test data to primary
-- 2. Simulate failure immediately after
-- 3. Failover/restore
-- 4. Verify if test data exists on secondary

DECLARE @TestID INT = 99999
INSERT INTO TestRecords (ID, TestData) VALUES (@TestID, 'RPO_TEST_' + CAST(GETDATE() AS NVARCHAR(30)))
INSERT INTO HA_TestLog VALUES (GETDATE(), 'Test data written', @TestID, 'Started')

-- Wait 5 seconds (less than RPO)
WAITFOR DELAY '00:00:05'

-- Simulate failure
ALTER AVAILABILITY GROUP HighAvailability FAILOVER

-- Check if test data exists
IF EXISTS (SELECT 1 FROM TestRecords WHERE ID = @TestID)
    INSERT INTO HA_TestLog VALUES (GETDATE(), 'RPO Test', @TestID, 'PASS - Data preserved')
ELSE
    INSERT INTO HA_TestLog VALUES (GETDATE(), 'RPO Test', @TestID, 'FAIL - Data lost')

-- RPO Target: 15 minutes, Actual: 0 (zero data loss) ✓
```

## HA/DR Decision Matrix

| Solution | RTO | RPO | Cost | Setup Complexity | Use Case |
|----------|-----|-----|------|-----------------|----------|
| **Always On (Sync)** | <1 min | 0 | High | High | Mission-critical, local |
| **Always On (Async)** | 5-15 min | 0-5 min | High | High | Multi-site, some loss OK |
| **Log Shipping** | 5-30 min | 15 min | Low | Low | Standard HA, tape backup |
| **Backup/Restore** | 1-4 hours | 1 hour | Low | Low | Non-critical, cost-sensitive |
| **Managed Backup** | 24 hours | 24 hours | Very Low | Very Low | Archives, compliance only |

## Disaster Recovery Checklist

✅ **Do:**
- Test recovery procedures monthly
- Maintain offsite backups
- Document failover procedures
- Monitor HA/DR health continuously
- Encrypt backups (protect credentials in backups)
- Test backup integrity regularly
- Automate backup jobs
- Track RTO/RPO metrics

❌ **Don't:**
- Store backups only on primary server
- Ignore backup job failures
- Skip testing (untested = won't work)
- Over-design (match actual requirements)
- Forget to test failover switchback
- Store backup passwords in scripts
- Rely on manual backups alone
