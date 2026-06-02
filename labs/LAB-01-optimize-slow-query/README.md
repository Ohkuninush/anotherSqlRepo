# 🧪 LAB-01: Optimize Your First Query

## 📚 Laboratory Overview

**Difficulty:** Intermediate  
**Estimated Time:** 45-60 minutes  
**Skills You'll Gain:**
- Reading execution plans
- Identifying missing indexes
- Writing optimal queries
- Performance tuning basics

---

## 🎯 What You'll Learn

In this lab, you'll:
1. ✅ Identify a slow query
2. ✅ Analyze the execution plan
3. ✅ Find the root cause
4. ✅ Implement a fix
5. ✅ Verify the improvement
6. ✅ Understand why it works

---

## 📋 Prerequisites

**Required:**
- SQL Server 2019+ installed
- [Sample Database](../../examples/setup-sample-database.sql) created
- SSMS (SQL Server Management Studio)
- Basic SQL knowledge

**Recommended:**
- Read [Case Study 01: Query Performance Crisis](../../case-studies/CASE-STUDY-01-query-performance-crisis.md) first
- Read [query_patterns.md](../../references-query_patterns.md)

---

## 🚀 Getting Started

### Step 1: Setup (5 minutes)
```sql
-- Execute this to setup the lab
-- File: 00-setup.sql
```

### Step 2: Problem (10 minutes)
```sql
-- Find the slow query
-- File: 01-problema.sql
-- Your task: Make it faster!
```

### Step 3: Investigation (20 minutes)
```sql
-- Analyze the problem
-- Files: 
--   - Read the hints in 02-pistas.sql
--   - Compare your analysis with 03-solucion.sql
```

### Step 4: Solution (15 minutes)
```sql
-- Implement your fix
-- Test your solution
-- File: 03-solucion.sql for reference
```

### Step 5: Verification (10 minutes)
```sql
-- Verify your solution works
-- File: 04-verificacion.sql
```

### Step 6: Learning (5 minutes)
```
Read: 05-leccion.md
Understand WHY the fix works
```

---

## 💡 How to Approach This Lab

### Recommended Workflow:

1. **Don't skip the problem** 
   - Run 01-problema.sql
   - Feel the pain (slow query)
   - Time it mentally

2. **Don't peek at the solution yet**
   - Try to diagnose yourself first
   - Use the hints in 02-pistas.sql
   - Think about what could be wrong

3. **Consult references if stuck**
   - Check [query_patterns.md](../../references-query_patterns.md)
   - Check [index_design_guidelines.md](../../references-index_design_guidelines.md)
   - Think about what you know

4. **Then compare with solution**
   - Look at 03-solucion.sql
   - See if you got it right
   - Learn from differences

5. **Run verification**
   - Execute 04-verificacion.sql
   - Confirm your solution works
   - See the performance metrics

6. **Understand the lesson**
   - Read 05-leccion.md
   - Internalize the concepts
   - Think about other similar problems

---

## 📊 Expected Results

If you complete this lab successfully, you should see:

```
BEFORE (Slow):
├─ Execution Time: ~8-12 seconds
├─ Logical Reads: ~2,500+
├─ Index Operation: Scan
└─ Status: ❌ Unacceptable

AFTER (Fast):
├─ Execution Time: ~0.5-1 second
├─ Logical Reads: ~50-100
├─ Index Operation: Seek
└─ Status: ✅ Excellent
```

**Your Goal:** 10-20x performance improvement

---

## 🛠️ File Structure

```
LAB-01-optimize-slow-query/
├── README.md                    ← You are here
├── 00-setup.sql                 ← Setup (run first)
├── 01-problema.sql              ← The slow query (your challenge)
├── 02-pistas.sql                ← Hints to solve it
├── 03-solucion.sql              ← The solution (reference)
├── 04-verificacion.sql          ← Verify your solution works
├── 05-leccion.md                ← What you learned
└── SOLUTIONS-AND-NOTES.md       ← Detailed explanations (for reference)
```

---

## 🎓 Success Criteria

You've completed this lab when:

- [ ] You can explain why the original query is slow
- [ ] You understand which index would help
- [ ] You can write a faster query
- [ ] Your query returns the same results
- [ ] Your performance is > 10x better
- [ ] You understand the key lesson

---

## ⏭️ Next Steps After Lab

1. **Practice Similar Patterns**
   - Look at other queries in your codebase
   - Apply the same optimization technique
   - Check execution plans

2. **Explore Related Topics**
   - [query_patterns.md](../../references-query_patterns.md) - More optimization patterns
   - [index_design_guidelines.md](../../references-index_design_guidelines.md) - Index strategy
   - [CASE-STUDY-01](../../case-studies/CASE-STUDY-01-query-performance-crisis.md) - Real-world scenario

3. **Do LAB-02** (Coming soon)
   - Resolve a deadlock scenario
   - Learn concurrency control

---

## 🆘 Stuck? Here's Help

### "I don't know where to start"
→ Read [Case Study 01](../../case-studies/CASE-STUDY-01-query-performance-crisis.md) first

### "I don't understand execution plans"
→ Look at [analyze_execution_plan.sql](../../scripts-analyze_execution_plan.sql) script

### "My solution is still slow"
→ Check hint #3 in 02-pistas.sql

### "I want to understand deeper"
→ Read 05-leccion.md and SOLUTIONS-AND-NOTES.md

---

## 📝 Notes for Your Learning

Use this space to write notes:

```
Query Problem:
[Your notes here]

Root Cause:
[Your analysis here]

Solution Applied:
[What you did]

Performance Metrics:
Before: [time/reads]
After:  [time/reads]

Key Insight:
[What you learned]
```

---

## 🎯 Learning Objectives Summary

| Objective | Completed? |
|-----------|-----------|
| Read and understand slow query | ☐ |
| Analyze execution plan | ☐ |
| Identify missing indexes | ☐ |
| Write optimized query | ☐ |
| Verify performance improvement | ☐ |
| Explain the fix to someone else | ☐ |

---

## 🚀 Ready to Start?

1. Open **00-setup.sql** in SSMS
2. Execute it against your SampleEcommerce database
3. Then open **01-problema.sql**
4. Try to make it faster!

**Good luck! 💪**

---

**Lab Status:** Ready to use  
**Difficulty:** ⭐⭐ Intermediate  
**Time:** 45-60 minutes  
**Reward:** 10-20x performance improvement + valuable SQL skills
