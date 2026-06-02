# 🔧 Diagnostic Scripts

SQL scripts to analyze your database and provide recommendations.

---

## 📋 Available Scripts

### `quick-diagnostics.sql`

**Purpose:** Comprehensive database analysis with personalized learning recommendations.

**What it analyzes:**
- ✓ Performance issues (missing indexes, large tables)
- ✓ Concurrency problems (long transactions, blocking)
- ✓ Data integrity issues (missing PKs, constraints)
- ✓ Design patterns used (soft deletes, audit trails, multi-tenant)
- ✓ Database statistics and structure

**How to run:**
```sql
-- 1. Open SQL Server Management Studio (SSMS)
-- 2. Connect to YOUR database
-- 3. Open: scripts/quick-diagnostics.sql
-- 4. Execute (F5)
-- 5. Read the recommendations
```

**Example output:**
```
╔══════════════════════════════════════════════════════════════════════╗
║  SQL SERVER EXPERT SKILL - QUICK DIAGNOSTICS                        ║
║  Database: YourDatabase
║  Analysis Date: 2026-06-02 14:30:45
╚══════════════════════════════════════════════════════════════════════╝

┌─────────────────────────────────────────────────────────────────────┐
│ 🚀 PERFORMANCE ANALYSIS
└─────────────────────────────────────────────────────────────────────┘

⚠️  FINDING: 5 potential missing indexes detected
   📚 RECOMMENDATION: Read references-index_design_guidelines.md
   🔧 DIAGNOSTIC: Run scripts/find_missing_indexes.sql
   🧪 LEARN: Try LAB-01 - Optimize Slow Query

⚠️  FINDING: 2 tables > 8MB detected
   📚 RECOMMENDATION: Read references-partitioning_strategy.md

... (more findings)

┌─────────────────────────────────────────────────────────────────────┐
│ 📖 PERSONALIZED LEARNING PATH
└─────────────────────────────────────────────────────────────────────┘

🎯 START HERE (based on your database):

1. First Time? Start with SQL Server Fundamentals:
   ├─ Read: QUICK-START-GUIDE.md (5 min overview)
   ├─ Use: MASTER-INDEX.md (find your problem)
   └─ Study: sql-server-expert-SKILL-CORRECTED.md (25 capabilities)

2. Hands-On Learning:
   ├─ LAB-01: Optimize Slow Query (45-60 min)
   └─ Case Study 01: Query Performance Crisis

3. Reference Materials (by topic):
   ├─ 🚀 Performance: query_patterns.md, index_design_guidelines.md
   ├─ 🔒 Concurrency: concurrency_blocking.md, transaction_management.md
   ...
```

---

### `analyze_execution_plan.sql`

**Purpose:** Diagnose query performance issues by analyzing execution plans.

**Includes:**
- Query statistics (CPU, reads, execution time)
- Missing index recommendations
- Table/index scan analysis
- Query cost analysis
- Index fragmentation checks

**When to use:**
- "Why is my query slow?"
- "Is this query using the right index?"
- "How can I optimize this?"

---

### `deadlock_analyzer.sql`

**Purpose:** Identify and troubleshoot deadlock issues.

**Analyzes:**
- Long-running transactions
- Lock waits
- Blocking chains
- Deadlock history
- High contention tables

**When to use:**
- "We're getting deadlocks"
- "Why is my transaction blocking others?"
- "Which queries cause the most contention?"

---

### `find_missing_indexes.sql`

**Purpose:** Identify missing indexes that would improve performance.

**Shows:**
- Missing indexes by table
- Estimated improvement
- Column recommendations
- Impact estimates

**When to use:**
- "Which indexes should I create?"
- "Can I improve performance with indexing?"

---

### `generate_table_documentation.sql`

**Purpose:** Auto-generate schema documentation for your database.

**Generates:**
- Table structure (columns, types, constraints)
- Primary/foreign keys
- Indexes
- Statistics

**When to use:**
- "I need to document my schema"
- "What tables do we have?"
- "Create DDL for new environment"

---

### `performance_baseline.sql`

**Purpose:** Capture baseline performance metrics for monitoring.

**Tracks:**
- Query execution times
- Resource usage (CPU, memory, I/O)
- Table/index statistics
- Wait events

**When to use:**
- "I need a before/after comparison"
- "Let's establish a performance baseline"
- "Monitor performance over time"

---

## 🎯 Quick Reference

### For Performance Issues
```
1. Run: quick-diagnostics.sql
   └─ See if missing indexes are detected

2. If yes, run: find_missing_indexes.sql
   └─ Get specific index recommendations

3. Then, run: analyze_execution_plan.sql
   └─ Compare execution before/after fix

4. Learn: Read references-index_design_guidelines.md
   └─ Understand why it works

5. Practice: Try LAB-01-optimize-slow-query
   └─ Hands-on optimization practice
```

### For Concurrency Issues
```
1. Run: quick-diagnostics.sql
   └─ Check for long transactions

2. If issues found, run: deadlock_analyzer.sql
   └─ Identify blocking chains

3. Learn: Read references-concurrency_blocking.md
   └─ Understand blocking behavior

4. Reference: transaction_management.md
   └─ Best practices for transactions
```

### For Data Design
```
1. Run: quick-diagnostics.sql
   └─ Check data integrity issues

2. If issues, run: generate_table_documentation.sql
   └─ Document current schema

3. Learn: Read references-data_modeling.md
   └─ Design best practices

4. Patterns: See patterns-[your-pattern].md
   └─ Enterprise design patterns
```

---

## 🚀 Usage Examples

### Example 1: Analyze Slow Query Performance

```sql
-- Step 1: Get baseline
USE YourDatabase;
EXEC scripts.run_performance_baseline;

-- Step 2: Find what's wrong
EXEC scripts.run_quick_diagnostics;
-- Output shows: "5 missing indexes detected"

-- Step 3: Get specific recommendations
EXEC scripts.find_missing_indexes;
-- Output shows: Exact indexes to create

-- Step 4: Capture detailed analysis
EXEC scripts.analyze_execution_plan;
-- Shows: Query cost, I/O, CPU

-- Step 5: Create index and re-test
CREATE INDEX IX_NewIndex ON Table(Column);

-- Step 6: Compare performance
EXEC scripts.run_performance_baseline;
-- Compare against Step 1
```

### Example 2: Troubleshoot Deadlock

```sql
-- Step 1: Run diagnostics
USE YourDatabase;
EXEC scripts.quick_diagnostics;
-- Output: "Long-running transactions detected"

-- Step 2: Deep dive into blocking
EXEC scripts.deadlock_analyzer;
-- Shows: Blocking chains, transaction isolation

-- Step 3: Read relevant docs
-- Open: references-concurrency_blocking.md
-- Open: references-transaction_management.md

-- Step 4: Apply fix
-- Example: Change isolation level
-- See: transaction_management.md for options
```

---

## 📊 Understanding Script Output

### Color Coding
- ✓ **Green checkmark** - Good, no issues
- ⚠️ **Yellow warning** - Potential issue
- ✗ **Red X** - Problem found

### Recommendation Levels
| Level | Example | Action |
|-------|---------|--------|
| 📚 Read | "Read references-X.md" | Documentation to understand concept |
| 🔧 Diagnostic | "Run scripts/X.sql" | Another script to diagnose |
| 🎯 Pattern | "See patterns-X.md" | Implementation pattern to follow |
| 🧪 Learn | "Try LAB-01" | Hands-on learning exercise |

---

## 🔄 Running Scripts Regularly

### Weekly
- `quick-diagnostics.sql` - Catch issues early

### Monthly
- `performance_baseline.sql` - Track trends
- `analyze_execution_plan.sql` - Monitor key queries

### Before Major Changes
- All scripts - Establish baseline
- Repeat after changes - Compare impact

---

## 📞 Support

- **Script errors?** Check prerequisites
- **Output confusing?** See "Understanding Output" section
- **Need new diagnostic?** Open GitHub Issue

---

## 🔗 Related Resources

- **Learning:** [MASTER-INDEX.md](../MASTER-INDEX.md)
- **Labs:** [labs/](../labs/)
- **Patterns:** [patterns-*.md](../)
- **References:** [references-*.md](../)

---

**Last Updated:** 2026-06-02  
**Status:** ✅ Ready to use
