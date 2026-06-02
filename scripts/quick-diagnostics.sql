/*
╔══════════════════════════════════════════════════════════════════════╗
║                                                                      ║
║         SQL Server Expert Skill - Quick Diagnostics                  ║
║                                                                      ║
║  Analyzes YOUR database and recommends what to read/study next.      ║
║  Run this against your database to get personalized guidance!        ║
║                                                                      ║
║  Usage:
║    USE YourDatabase;
║    EXEC sp_executesql N'<paste this script>'
║                                                                      ║
╚══════════════════════════════════════════════════════════════════════╝
*/

SET NOCOUNT ON;
DECLARE @DatabaseName NVARCHAR(255) = DB_NAME();

PRINT '╔══════════════════════════════════════════════════════════════════════╗';
PRINT '║  SQL SERVER EXPERT SKILL - QUICK DIAGNOSTICS                        ║';
PRINT '║  Database: ' + @DatabaseName;
PRINT '║  Analysis Date: ' + CONVERT(NVARCHAR(20), GETDATE(), 121);
PRINT '╚══════════════════════════════════════════════════════════════════════╝';
PRINT '';

-- ============================================================================
-- SECTION 1: PERFORMANCE DIAGNOSTICS
-- ============================================================================
PRINT '┌─────────────────────────────────────────────────────────────────────┐';
PRINT '│ 🚀 PERFORMANCE ANALYSIS';
PRINT '└─────────────────────────────────────────────────────────────────────┘';
PRINT '';

-- Check for missing indexes
DECLARE @MissingIndexCount INT = 0;
SELECT @MissingIndexCount = COUNT(*)
FROM sys.dm_db_missing_index_details AS mid
WHERE database_id = DB_ID()
AND mid.equality_columns IS NOT NULL;

IF @MissingIndexCount > 0
BEGIN
    PRINT '⚠️  FINDING: ' + CAST(@MissingIndexCount AS NVARCHAR(10)) + ' potential missing indexes detected';
    PRINT '   📚 RECOMMENDATION: Read references-index_design_guidelines.md';
    PRINT '   🔧 DIAGNOSTIC: Run scripts/find_missing_indexes.sql';
    PRINT '   🧪 LEARN: Try LAB-01 - Optimize Slow Query';
    PRINT '';
END
ELSE
BEGIN
    PRINT '✓ No obvious missing indexes detected';
    PRINT '';
END

-- Check table sizes
DECLARE @LargeTableCount INT = 0;
SELECT @LargeTableCount = COUNT(*)
FROM (
    SELECT t.NAME, SUM(s.in_row_data_page_count) AS PageCount
    FROM sys.tables t
    JOIN sys.dm_db_partition_stats s ON t.object_id = s.object_id
    WHERE s.in_row_data_page_count > 1000  -- Tables larger than 8MB
    GROUP BY t.NAME
) large_tables;

IF @LargeTableCount > 0
BEGIN
    PRINT '⚠️  FINDING: ' + CAST(@LargeTableCount AS NVARCHAR(10)) + ' tables > 8MB detected';
    PRINT '   📚 RECOMMENDATION: Read references-partitioning_strategy.md';
    PRINT '   📚 RECOMMENDATION: Read references-index_design_guidelines.md';
    PRINT '   🎯 PATTERN: See patterns-etl_incremental.md for data management';
    PRINT '';
END
ELSE
BEGIN
    PRINT '✓ All tables are reasonably sized';
    PRINT '';
END

-- ============================================================================
-- SECTION 2: CONCURRENCY DIAGNOSTICS
-- ============================================================================
PRINT '┌─────────────────────────────────────────────────────────────────────┐';
PRINT '│ 🔒 CONCURRENCY & LOCKING ANALYSIS';
PRINT '└─────────────────────────────────────────────────────────────────────┘';
PRINT '';

-- Check for long-running transactions
DECLARE @LongTransactionCount INT = 0;
SELECT @LongTransactionCount = COUNT(*)
FROM sys.dm_tran_active_transactions
WHERE transaction_begin_time < DATEADD(MINUTE, -5, GETDATE());

IF @LongTransactionCount > 0
BEGIN
    PRINT '⚠️  FINDING: Long-running transactions detected';
    PRINT '   📚 RECOMMENDATION: Read references-transaction_management.md';
    PRINT '   📚 RECOMMENDATION: Read references-concurrency_blocking.md';
    PRINT '   🔧 DIAGNOSTIC: Run scripts/deadlock_analyzer.sql';
    PRINT '';
END
ELSE
BEGIN
    PRINT '✓ No long-running transactions detected';
    PRINT '';
END

-- ============================================================================
-- SECTION 3: DATA INTEGRITY DIAGNOSTICS
-- ============================================================================
PRINT '┌─────────────────────────────────────────────────────────────────────┐';
PRINT '│ 📊 DATA INTEGRITY ANALYSIS';
PRINT '└─────────────────────────────────────────────────────────────────────┘';
PRINT '';

-- Check for tables without primary keys
DECLARE @NoPKCount INT = 0;
SELECT @NoPKCount = COUNT(*)
FROM sys.tables t
WHERE NOT EXISTS (
    SELECT 1 FROM sys.key_constraints kc
    WHERE t.object_id = kc.parent_object_id
    AND kc.type = 'PK'
);

IF @NoPKCount > 0
BEGIN
    PRINT '⚠️  FINDING: ' + CAST(@NoPKCount AS NVARCHAR(10)) + ' tables without primary keys';
    PRINT '   📚 RECOMMENDATION: Read references-data_modeling.md';
    PRINT '   📚 RECOMMENDATION: Read references-best_practices.md';
    PRINT '   🎯 PATTERN: See patterns-upsert_patterns.md for safe data operations';
    PRINT '';
END
ELSE
BEGIN
    PRINT '✓ All tables have primary keys';
    PRINT '';
END

-- Check for tables without constraints
DECLARE @NoFKCount INT = 0;
SELECT @NoFKCount = COUNT(DISTINCT t.object_id)
FROM sys.tables t
WHERE NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys fk
    WHERE t.object_id = fk.parent_object_id
);

IF @NoFKCount > 10
BEGIN
    PRINT '⚠️  FINDING: Many tables without foreign keys';
    PRINT '   📚 RECOMMENDATION: Read references-data_modeling.md';
    PRINT '   💡 INSIGHT: FK can help query optimization';
    PRINT '';
END

-- ============================================================================
-- SECTION 4: DESIGN PATTERN RECOMMENDATIONS
-- ============================================================================
PRINT '┌─────────────────────────────────────────────────────────────────────┐';
PRINT '│ 🎨 ENTERPRISE PATTERNS - RECOMMENDATIONS';
PRINT '└─────────────────────────────────────────────────────────────────────┘';
PRINT '';

-- Check for soft deletes pattern usage
DECLARE @DeletedColumnsCount INT = 0;
SELECT @DeletedColumnsCount = COUNT(*)
FROM sys.columns
WHERE name LIKE '%deleted%' OR name LIKE '%is_deleted%' OR name LIKE '%is_active%';

IF @DeletedColumnsCount > 0
BEGIN
    PRINT '✓ PATTERN DETECTED: Soft Delete pattern (is_active/is_deleted columns)';
    PRINT '   📚 REFERENCE: patterns-soft_delete_patterns.md';
    PRINT '   🧪 TESTING: See testing-data_validation_tests.md';
    PRINT '';
END

-- Check for timestamp/audit columns
DECLARE @AuditColumnsCount INT = 0;
SELECT @AuditColumnsCount = COUNT(*)
FROM sys.columns
WHERE name LIKE '%created%' OR name LIKE '%modified%' OR name LIKE '%updated%';

IF @AuditColumnsCount > 0
BEGIN
    PRINT '✓ PATTERN DETECTED: Audit Trail pattern (created/modified timestamps)';
    PRINT '   📚 REFERENCE: patterns-audit_trail_patterns.md';
    PRINT '   📚 REFERENCE: references-auditing_guide.md';
    PRINT '';
END

-- Check for multi-tenant pattern
DECLARE @TenantColumnsCount INT = 0;
SELECT @TenantColumnsCount = COUNT(*)
FROM sys.columns
WHERE name LIKE '%tenant%' OR name LIKE '%client%' OR name LIKE '%organization%';

IF @TenantColumnsCount > 0
BEGIN
    PRINT '✓ PATTERN DETECTED: Multi-tenant structure detected';
    PRINT '   📚 REFERENCE: patterns-multi_tenant_isolation.md';
    PRINT '   🔒 SECURITY: Row-level security implementation recommended';
    PRINT '';
END

-- ============================================================================
-- SECTION 5: SPECIFIC RECOMMENDATIONS
-- ============================================================================
PRINT '┌─────────────────────────────────────────────────────────────────────┐';
PRINT '│ 📖 PERSONALIZED LEARNING PATH';
PRINT '└─────────────────────────────────────────────────────────────────────┘';
PRINT '';

PRINT '🎯 START HERE (based on your database):';
PRINT '';
PRINT '1. First Time? Start with SQL Server Fundamentals:';
PRINT '   ├─ Read: QUICK-START-GUIDE.md (5 min overview)';
PRINT '   ├─ Use: MASTER-INDEX.md (find your problem)';
PRINT '   └─ Study: sql-server-expert-SKILL-CORRECTED.md (25 capabilities)';
PRINT '';

PRINT '2. Hands-On Learning:';
PRINT '   ├─ LAB-01: Optimize Slow Query (45-60 min)';
PRINT '   │          └─ Learn query optimization & index strategy';
PRINT '   └─ Case Study 01: Query Performance Crisis';
PRINT '                     └─ Real-world scenario (10x improvement)';
PRINT '';

PRINT '3. Reference Materials (by topic):';
PRINT '   ├─ 🚀 Performance: query_patterns.md, index_design_guidelines.md';
PRINT '   ├─ 🔒 Concurrency: concurrency_blocking.md, transaction_management.md';
PRINT '   ├─ 📊 Data: data_modeling.md, etl_migration_patterns.md';
PRINT '   ├─ 🏗️  Architecture: ha_disaster_recovery.md, security.md';
PRINT '   └─ 🧪 Testing: data_validation_tests.md, regression_testing.md';
PRINT '';

PRINT '4. Diagnostic Tools:';
PRINT '   ├─ analyze_execution_plan.sql (performance diagnosis)';
PRINT '   ├─ deadlock_analyzer.sql (concurrency issues)';
PRINT '   ├─ find_missing_indexes.sql (index strategy)';
PRINT '   └─ performance_baseline.sql (performance tracking)';
PRINT '';

-- ============================================================================
-- SECTION 6: QUICK STATS
-- ============================================================================
PRINT '┌─────────────────────────────────────────────────────────────────────┐';
PRINT '│ 📈 DATABASE STATISTICS';
PRINT '└─────────────────────────────────────────────────────────────────────┘';
PRINT '';

DECLARE @TableCount INT, @StoredProcCount INT, @ViewCount INT, @FKCount INT;

SELECT @TableCount = COUNT(*) FROM sys.tables;
SELECT @StoredProcCount = COUNT(*) FROM sys.procedures;
SELECT @ViewCount = COUNT(*) FROM sys.views;
SELECT @FKCount = COUNT(*) FROM sys.foreign_keys;

PRINT 'Database: ' + @DatabaseName;
PRINT 'Tables: ' + CAST(@TableCount AS NVARCHAR(10));
PRINT 'Views: ' + CAST(@ViewCount AS NVARCHAR(10));
PRINT 'Stored Procedures: ' + CAST(@StoredProcCount AS NVARCHAR(10));
PRINT 'Foreign Keys: ' + CAST(@FKCount AS NVARCHAR(10));
PRINT '';

-- ============================================================================
-- SECTION 7: NEXT STEPS
-- ============================================================================
PRINT '┌─────────────────────────────────────────────────────────────────────┐';
PRINT '│ 🚀 NEXT STEPS';
PRINT '└─────────────────────────────────────────────────────────────────────┘';
PRINT '';

PRINT '1️⃣  Navigate to MASTER-INDEX.md';
PRINT '    └─ Find your specific problem/question';
PRINT '';

PRINT '2️⃣  Follow the recommended path:';
PRINT '    ├─ Read the reference guide';
PRINT '    ├─ Run the diagnostic script';
PRINT '    ├─ Study the patterns';
PRINT '    └─ Validate with tests';
PRINT '';

PRINT '3️⃣  Get hands-on with labs:';
PRINT '    ├─ LAB-01: Query Optimization (available now)';
PRINT '    └─ LAB-02+: Coming soon (concurrency, design)';
PRINT '';

PRINT '════════════════════════════════════════════════════════════════════════';
PRINT 'Analysis complete! Start with: MASTER-INDEX.md';
PRINT '════════════════════════════════════════════════════════════════════════';
