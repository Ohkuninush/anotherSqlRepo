# Case Study 01: Query Performance Crisis

## 🎯 Quick Overview

**Problem:** Dashboard query taking 47+ seconds (unacceptable)  
**Root Cause:** YEAR() function in WHERE clause prevents index usage  
**Solution:** Replace with date range predicates  
**Result:** 39x faster (47 sec → 1.2 sec)  

---

## 📝 How to Use This Case Study

### Step 1: Setup Sample Database
```bash
Execute: ../../examples/setup-sample-database.sql
```

### Step 2: Follow the Journey
1. **01-slow-query.sql** - See the problem in action
2. **02-root-cause-analysis.sql** - Understand why it's slow
3. **03-optimized-query.sql** - Learn the solution
4. **04-verification.sql** - Verify the fix works
5. **05-final-procedure.sql** - Production-ready code

### Step 3: Learn the Lessons
Read: **CASE-STUDY-01-query-performance-crisis.md**

---

## 🔑 Key Takeaways

| Aspect | Takeaway |
|--------|----------|
| **Problem** | Functions in WHERE clause prevent index usage |
| **Solution** | Use sargable predicates (date ranges) |
| **Performance** | 39x improvement through index seek |
| **Lesson** | Always think about indexes when writing WHERE clauses |

---

## 📊 Before vs After

```
BEFORE (Slow):
WHERE YEAR(o.OrderDate) = YEAR(GETDATE())
- Execution Time: 47 seconds
- Index Operation: Clustered Scan
- Logical Reads: 8,943

AFTER (Fast):
WHERE o.OrderDate >= @Start AND o.OrderDate < @End
- Execution Time: 1.2 seconds
- Index Operation: Index Seek
- Logical Reads: 245
```

---

## 🔗 Related Documentation

- **Reference:** [query_patterns.md](../../references-query_patterns.md#functions-on-filter-columns)
- **Skill Capability:** [#1 Query Optimization](../../sql-server-expert-SKILL-CORRECTED.md)
- **Skill Capability:** [#2 Execution Plan Analysis](../../sql-server-expert-SKILL-CORRECTED.md)
- **Script:** [analyze_execution_plan.sql](../../scripts-analyze_execution_plan.sql)

---

## 💡 What You'll Learn

✅ How to identify slow queries  
✅ How to read execution plans  
✅ Why functions prevent index usage  
✅ How to write sargable predicates  
✅ How to verify query improvements  
✅ How to deploy fixes safely  

---

## ⏱️ Time Estimate

- Reading the case study: 15 minutes
- Running the SQL scripts: 10 minutes
- Total learning time: 25 minutes

---

**Status:** ✅ Ready to learn  
**Difficulty:** Intermediate  
**Topic:** Query Optimization, Index Strategy
