# 📊 Performance Dashboard - Track Metrics Over Time

A complete performance monitoring solution that captures, stores, and visualizes SQL Server metrics to identify trends and bottlenecks.

---

## 🎯 Quick Start

### 1. **First Time Setup**
```sql
-- Run this ONCE to initialize the dashboard
USE YourDatabase;
-- Execute: scripts/setup-performance-history.sql
```

### 2. **Capture Initial Metrics**
```sql
-- Run this to capture baseline
USE YourDatabase;
-- Execute: scripts/capture-performance-metrics.sql
```

### 3. **View Dashboard**
```sql
-- View your current performance metrics
USE YourDatabase;
-- Execute: scripts/performance-dashboard.sql
```

### 4. **Schedule Regular Captures** (Optional)
```
-- Run capture-performance-metrics.sql:
-- - Daily for trending analysis
-- - Hourly for frequent monitoring
-- See "Scheduling" section below
```

---

## 📋 What Gets Tracked

### Metric Snapshots
- ✅ Average query execution time
- ✅ Max query execution time
- ✅ Total query count
- ✅ Buffer pool usage (MB)
- ✅ CPU time
- ✅ Index fragmentation
- ✅ Missing indexes count
- ✅ Long-running transactions
- ✅ Blocking/deadlock counts

### Query Performance History
- ✅ Per-query execution stats
- ✅ CPU time tracking
- ✅ I/O metrics (logical/physical reads/writes)
- ✅ Execution count & timing

### Index Fragmentation
- ✅ Fragmentation percentage over time
- ✅ Page counts by index
- ✅ Trending identification

### Wait Events
- ✅ Top blocking wait types
- ✅ Wait time analysis
- ✅ Bottleneck identification

---

## 🚀 How to Use

### Scenario 1: "My Database is Getting Slow"

```
Step 1: Run setup-performance-history.sql (if not done)
        └─ Creates tracking tables

Step 2: Run capture-performance-metrics.sql
        └─ Captures current state

Step 3: Wait a few days/weeks, run capture again
        └─ Repeats capture

Step 4: Run performance-dashboard.sql
        └─ Shows trend analysis
        └─ Identifies what changed

Step 5: Review recommendations
        └─ Follow suggested fixes
```

### Scenario 2: "Did Our Optimization Help?"

```
Step 1: Run capture-performance-metrics.sql BEFORE optimization
        └─ Baseline captured

Step 2: Apply optimization (create index, tune query, etc.)

Step 3: Run capture-performance-metrics.sql AFTER optimization
        └─ New metrics captured

Step 4: Run performance-dashboard.sql
        └─ Shows comparison
        └─ Calculates improvement percentage
```

### Scenario 3: "Monitor Weekly"

```
Every Monday:
- Run: capture-performance-metrics.sql

Every Friday:
- Run: performance-dashboard.sql
- Review dashboard
- Take notes on trends
```

---

## 📊 Understanding the Dashboard Output

### Section 1: Current Snapshot
```
📊 CURRENT PERFORMANCE SNAPSHOT

Captured at              2026-06-02 14:30:45
Average Query Time       245 ms
Max Query Time          8923 ms
Total Queries           1,250
Buffer Pool (MB)        2,048 MB
Avg Index Fragmentation 12 %
Missing Indexes         3
```

**What it means:**
- **Average Query Time:** Most queries take ~245ms (good!)
- **Max Query Time:** Worst query takes 8.9 seconds (needs investigation)
- **Missing Indexes:** 3 indexes could improve performance

### Section 2: Trend Analysis
```
📈 PERFORMANCE TREND (Last 30 Days)

DayNum  Date        AvgTimeMs  MaxTimeMs  QueryCount
1       2026-06-02  245        8923       1,250
2       2026-06-01  234        7234       1,200
3       2026-05-31  223        6500       1,150
```

**What to look for:**
- ✅ **Downward trend** = Getting faster (optimization working!)
- ⚠️  **Upward trend** = Getting slower (problem developing)
- → **Flat trend** = Stable performance

### Section 3: Top Slow Queries
```
🐌 TOP 10 SLOWEST QUERIES

Rank  AvgTimeMs  ExecutionCount  TotalMinutes  QueryPreview
1     8923       125             18.5          SELECT * FROM Orders WHERE YEAR(OrderDate)...
2     4500       500             37.5          SELECT CustomerID, SUM(Amount) FROM...
3     2300       1000            38.3          SELECT * FROM Products WHERE...
```

**Action items:**
- Rank 1 query takes 8.9 seconds on average → Optimize this first
- Use `find_missing_indexes.sql` to diagnose

### Section 4: Index Fragmentation
```
🔧 INDEX FRAGMENTATION STATUS

AvgFragmentation  MaxFragmentation  IndexCount
12%              45%               25 indexes

Most Fragmented Indexes:
TableName      IndexName                    FragmentationPercent  PageCount
Orders         IX_Orders_OrderDate          45%                   15000
Customers      IX_Customers_Country_Name    32%                   8500
```

**When to act:**
- **> 30%:** REBUILD (drop and recreate)
- **10-30%:** REORGANIZE (defragment)
- **< 10%:** Monitor only

### Section 5: Wait Events
```
⏳ TOP WAIT EVENTS (Bottlenecks)

WaitType             TotalWaitMinutes  WaitCount  Percentage
PAGEIOLATCH_SH       125               5,000      35%
SOS_SCHEDULER_YIELD  89                12,000     25%
LOCK_HASH            56                8,500      15%
```

**Interpretation:**
- **PAGEIOLATCH_SH (35%):** Disk I/O is slow → Check disk performance
- **SOS_SCHEDULER_YIELD (25%):** CPU contention → Add CPU or optimize queries
- **LOCK_HASH (15%):** Locking contention → Review transaction design

### Section 6: Comparison
```
📊 COMPARISON: Current vs 7 Days Ago

Metric              Current    Previous  ChangePct  Trend
Avg Query Time      245 ms     234 ms    +4.7%      ⚠️  Worse
Max Query Time      8923 ms    7234 ms   +23.4%     ⚠️  Worse
```

**Red flags:**
- Upward trends = Performance degrading
- Large percentage changes = Significant issue

### Section 7: Health Assessment
```
🏥 HEALTH ASSESSMENT

✅ QUERY PERFORMANCE: Excellent (Avg < 100ms)
⚠️  INDEX HEALTH: Needs maintenance (Avg fragmentation 45%) - Run defrag
⚠️  MISSING INDEXES: 3 indexes could improve performance
```

---

## 🔄 Scheduling Regular Captures

### Option 1: SQL Server Agent Job
```sql
-- Create SQL Agent job to run daily at 2am
EXEC msdb.dbo.sp_add_job
    @job_name = 'DailyPerformanceCapture',
    @enabled = 1;

-- Add job step
EXEC msdb.dbo.sp_add_jobstep
    @job_name = 'DailyPerformanceCapture',
    @step_name = 'CaptureMetrics',
    @subsystem = 'TSQL',
    @command = 'EXEC capture-performance-metrics.sql',
    @database_name = 'YourDatabase';

-- Schedule for 2am daily
EXEC msdb.dbo.sp_add_schedule
    @schedule_name = 'DailyAt2AM',
    @freq_type = 4,
    @freq_interval = 1,
    @active_start_time = '020000';
```

### Option 2: Windows Task Scheduler
```batch
REM Run capture daily via Task Scheduler
sqlcmd -S (local) -d YourDatabase -i capture-performance-metrics.sql
```

### Option 3: Application Scheduler
```csharp
// Run via your application scheduler
var command = @"
    USE YourDatabase;
    EXEC PerfDashboard.sp_CaptureMetricsSnapshot;
    EXEC capture-performance-metrics.sql;
";
// Execute command on daily schedule
```

---

## 📈 Trend Analysis Tips

### How to Spot Problems Early

**Rising Average Query Time:**
```
If trend shows consistent increase over 2+ weeks:
1. Check for new missing indexes
2. Review schema changes
3. Check data volume growth
4. Run find_missing_indexes.sql
```

**Index Fragmentation Growing:**
```
If fragmentation % increases weekly:
1. Data modifications are high
2. Need more frequent maintenance
3. Consider rebuild vs reorganize strategy
4. Check for LOB fragmentation
```

**Increased Wait Events:**
```
If wait times increase suddenly:
1. Check for blocking queries
2. Review transaction isolation levels
3. Look for long-running transactions
4. Monitor concurrent connections
```

---

## 🎯 Common Dashboard Scenarios

### Scenario A: Query Degradation
```
Problem:  Avg query time went from 100ms → 500ms
Solution:
1. Review "TOP SLOWEST QUERIES" section
2. Run: find_missing_indexes.sql
3. Check if indexes were dropped/disabled
4. Try: LAB-01 for optimization technique
```

### Scenario B: Index Fragmentation
```
Problem:  Index fragmentation at 45%
Solution:
1. Review "INDEX FRAGMENTATION STATUS"
2. Run:  ALTER INDEX [IndexName] ON [TableName] REBUILD;
3. Monitor trend after rebuild
4. Schedule regular maintenance
```

### Scenario C: High Wait Events
```
Problem:  PAGEIOLATCH_SH wait = 60% of total waits
Solution:
1. Indicates I/O bottleneck
2. Check disk subsystem health
3. Review large table scans
4. Create missing indexes to reduce scans
```

---

## 🛠️ Maintenance

### Data Retention
By default, metrics are kept for **90 days**.

To change:
```sql
UPDATE PerfDashboard.DashboardConfig
SET ConfigValue = '180'
WHERE ConfigKey = 'RetentionDays';
```

### Manual Cleanup
```sql
-- Delete old metrics
DELETE FROM PerfDashboard.MetricSnapshots 
WHERE SnapshotDate < DATEADD(DAY, -180, GETDATE());

DELETE FROM PerfDashboard.QueryPerformanceHistory 
WHERE CaptureDate < DATEADD(DAY, -180, GETDATE());
```

### Check Configuration
```sql
-- View current dashboard config
SELECT ConfigKey, ConfigValue, Description
FROM PerfDashboard.DashboardConfig;
```

---

## 📊 Advanced: Exporting Data

### Export to CSV
```sql
-- Generate export query
SELECT *
FROM PerfDashboard.MetricSnapshots
WHERE SnapshotDate >= DATEADD(DAY, -30, GETDATE())
ORDER BY SnapshotDate DESC;

-- Use SSMS Export wizard or:
bcp "SELECT * FROM PerfDashboard.MetricSnapshots" queryout metrics.csv ...
```

### Create Baseline
```sql
-- Capture a named baseline
INSERT INTO PerfDashboard.PerformanceBaseline (
    BaselineName,
    Description,
    AvgQueryTimeMs,
    AvgIndexFragmentation,
    AvgCPUTimeMs,
    TotalBufferPoolMB,
    IsActive
)
SELECT TOP 1
    'Pre-Optimization-Baseline',
    'Baseline before optimization work',
    AvgExecutionTimeMs,
    TotalIndexFragmentation,
    TotalCPUTimeMs,
    TotalBufferPoolUsedMB,
    1
FROM PerfDashboard.MetricSnapshots
ORDER BY SnapshotDate DESC;
```

---

## 🔗 Related Resources

- **[references-query_patterns.md](../references-query_patterns.md)** - Query optimization patterns
- **[references-index_design_guidelines.md](../references-index_design_guidelines.md)** - Index strategy
- **[scripts-find_missing_indexes.sql](find_missing_indexes.sql)** - Detailed index recommendations
- **[scripts-analyze_execution_plan.sql](analyze_execution_plan.sql)** - Plan analysis
- **[LAB-01](../labs/LAB-01-optimize-slow-query/)** - Hands-on optimization

---

## 📞 Troubleshooting

### "No data in dashboard"
```
Solution: Run capture-performance-metrics.sql first
Then run dashboard after 1-2 captures
```

### "Out of memory during capture"
```
Solution: Run during off-peak hours
Or: Reduce sample size in capture script
```

### "Trends don't show"
```
Solution: Need at least 2 captures to compare
Wait a few days between captures
```

---

## 📈 Best Practices

1. **Daily Captures** - Most effective for trending
2. **Weekly Reviews** - Check dashboard every Friday
3. **Act on Alerts** - Don't ignore upward trends
4. **Document Changes** - Note when you apply fixes
5. **Baseline Comparison** - Always compare to baseline
6. **Automate Captures** - Use SQL Agent or scheduler

---

**Last Updated:** 2026-06-02  
**Status:** ✅ Production Ready  
**Frequency:** Run capture daily for best results
