# SQL Server Expert Skill — Quick Start Guide

**All files are in:** `C:\Users\User\claude\`

---

## 🎯 Start Here

### If you're new to the skill:
1. Read: `sql-server-expert-SKILL-CORRECTED.md` (the main skill definition)
2. Understand: 25 capabilities listed there
3. Know: It's not a prompt, it's a knowledge system

### If you're solving a specific problem:
1. Check the **problem-to-pattern map** below
2. Jump to that pattern document
3. Find your scenario (anti-pattern + correct pattern)
4. Copy the production code example

### If you're adding to the system:
1. Read: `HANDOFF-SQL-SERVER-SKILL-SESSION2.md` (architecture overview)
2. Read: `PHASE-1-COMPLETION-REPORT.md` (what Phase 1 covers)
3. Check: `patterns/` and `testing/` folders for existing patterns
4. Follow: The structure (anti-pattern, correct pattern, examples, best practices)

---

## 🗺️ Problem-to-Pattern Quick Map

### "I need to delete data but keep it recoverable"
→ `patterns/soft_delete_patterns.md`  
→ Patterns: IsDeleted flag, Temporal Tables, Archive tables

### "I need to audit who changed what when"
→ `patterns/audit_trail_patterns.md`  
→ Patterns: Shadow tables, Temporal Tables, Immutable audit

### "I need to insert or update data"
→ `patterns/upsert_patterns.md`  
→ Patterns: UPDATE+INSERT (safe), MERGE (when justified)

### "I need to prevent overselling inventory"
→ `patterns/inventory_patterns.md`  
→ Patterns: Atomic purchases, Reservations, Backorders

### "I need to test constraints work"
→ `testing/data_validation_tests.md`  
→ Patterns: NULL checks, FK validation, Range testing

### "I need automated tests for stored procedures"
→ `testing/unit_testing_tsqlt.md`  
→ Framework: tSQLt, Setup/Teardown, Assertions

---

## 📚 Document Index

### Main Skill
- **`sql-server-expert-SKILL-CORRECTED.md`** (570 lines)
  - 25 enterprise capabilities
  - Production code standards
  - Common workflows
  - When to ask clarifying questions

### Phase 1 Patterns (4 documents)

1. **`patterns/soft_delete_patterns.md`** (600+ lines)
   - Pattern 1: Simple IsDeleted flag
   - Pattern 2: Audit trail tracking
   - Pattern 3: Temporal Tables (automatic)
   - Pattern 4: Archive tables (high-volume)
   - Pattern 5: Hard delete with backup
   - Use case decision matrix

2. **`patterns/audit_trail_patterns.md`** (500+ lines)
   - Pattern 1: Shadow tables + triggers
   - Pattern 2: Temporal Tables
   - Pattern 3: Custom audit with business rules
   - Pattern 4: Immutable audit with hashing
   - Compliance guidance

3. **`patterns/upsert_patterns.md`** (480+ lines)
   - Decision tree: Which approach?
   - Pattern 1: UPDATE+INSERT (recommended)
   - Pattern 2: MERGE (when justified)
   - Pattern 3: MERGE with OUTPUT clause
   - Pattern 4: Conditional upsert
   - Performance comparison

4. **`patterns/inventory_patterns.md`** (420+ lines)
   - Pattern 1: Simple negative prevention
   - Pattern 2: Reservations (multi-step fulfillment)
   - Pattern 3: Adjustments & reconciliation
   - Pattern 4: Backorder handling
   - Pattern 5: Physical count & recount
   - Atomic operations

### Phase 1 Testing (2 documents)

1. **`testing/data_validation_tests.md`** (450+ lines)
   - Pattern 1: Constraint enforcement
   - Pattern 2: Data quality assertions
   - Pattern 3: Referential integrity
   - Pattern 4: NULL handling
   - Pattern 5: Data type & range validation
   - Pattern 6: Consistency checking
   - Best practices

2. **`testing/unit_testing_tsqlt.md`** (550+ lines)
   - Pattern 1: Setup & first test
   - Pattern 2: Stored procedure testing
   - Pattern 3: Mocking & spies
   - Pattern 4: Edge cases & error conditions
   - tSQLt assertions reference
   - CI/CD integration

### Reference Documents (17 core docs)
- `references/query_patterns.md`
- `references/index_design_guidelines.md`
- `references/dynamic_sql_patterns.md`
- `references/partitioning_strategy.md`
- `references/best_practices.md`
- `references/common_pitfalls.md`
- `references/sql_server_2019_features.md`
- `references/security_rbac_guide.md`
- `references/concurrency_blocking.md`
- `references/etl_migration_patterns.md`
- `references/transaction_management.md`
- `references/auditing_guide.md`
- `references/architecture_review.md`
- `references/ha_disaster_recovery.md`
- `references/observability_diagnostics.md`
- `references/data_modeling.md`

### Handoff & Status Documents
- **`HANDOFF-SQL-SERVER-SKILL-SESSION2.md`** — Architecture, Phase 1 overview
- **`PHASE-1-COMPLETION-REPORT.md`** — What was delivered, what you can do now
- **`QUICK-START-GUIDE.md`** — This file

---

## ⚡ Quick Decision Trees

### "Do I need to track changes?"
```
├─ YES: Do I need WHO changed it?
│  ├─ YES → audit_trail_patterns.md
│  └─ NO → soft_delete_patterns.md
└─ NO → No pattern needed
```

### "Do I need to upsert?"
```
├─ Source has duplicates?
│  ├─ YES → Use UPDATE+INSERT pattern
│  └─ NO → Consider MERGE (risky)
├─ Need to track INSERT vs UPDATE?
│  ├─ YES → Use MERGE with OUTPUT
│  └─ NO → Use UPDATE+INSERT
└─ Need all 3 MERGE conditions?
   ├─ YES → MERGE justified
   └─ NO → UPDATE+INSERT (simpler)
```

### "Do I have inventory problems?"
```
├─ Overselling?
│  ├─ YES → Pattern 1: Atomic purchases
├─ Need reservations?
│  ├─ YES → Pattern 2: Multi-step fulfillment
├─ Physical count mismatch?
│  ├─ YES → Pattern 5: Recount & reconcile
└─ Need backorders?
   └─ YES → Pattern 4: Backorder handling
```

---

## 📖 How Each Pattern is Structured

Every pattern document follows this structure:

### Overview
- Why it matters
- When to use it
- Real-world impact

### Anti-Pattern (❌ Don't Do This)
- What goes wrong
- Real incident example
- Why it fails

### Correct Pattern(s)
- Schema design
- Procedures/functions
- Decision tree
- Best practices

### Production Considerations
- Performance
- Compliance
- Security
- Maintenance

### Common Mistakes
- Edge cases
- Failure modes
- How to fix

### References
- Related patterns
- Reference documents
- Cross-links

---

## 🔧 Using Production Code Examples

Every pattern includes copy-paste-ready code:

```sql
-- These are safe to copy:
✅ All have TRY-CATCH blocks
✅ All have XACT_ABORT ON
✅ All check @@TRANCOUNT
✅ All handle errors properly
✅ All work in SQL Server 2019+
```

**Before running:**
1. Adapt table/column names to your schema
2. Review the logic for your use case
3. Test in development first
4. Add to version control

---

## 📊 Knowledge System Size

| Category | Count | Lines |
|----------|-------|-------|
| Core Capabilities | 25 | (in skill file) |
| Core References | 17 | ~3,500 |
| Phase 1 Patterns | 4 | 1,850+ |
| Phase 1 Testing | 2 | 1,200+ |
| Utility Scripts | 6 | ~800 |
| **Total** | **54** | **~7,800** |

---

## 🎓 Learning Path

### For New Developers (1-2 weeks)
1. Read: Main skill (overview)
2. Study: Each pattern document in order
3. Practice: Copy patterns, adapt to your schema
4. Test: Use testing framework on your code

### For Experienced Developers (reference)
1. Use problem-to-pattern map (jump to what you need)
2. Scan decision tree (confirm your approach)
3. Copy code example (adapt and use)
4. Reference best practices (avoid mistakes)

### For Architects (design decisions)
1. Check: Decision trees (which pattern?)
2. Consider: Trade-offs (performance vs safety)
3. Plan: Compliance needs (GDPR? HIPAA?)
4. Document: Why you chose this pattern

---

## 🚀 What's Ready Now

### Immediately Usable
- ✅ Soft delete implementation (3 levels: simple, audit, temporal)
- ✅ Audit trail systems (4 approaches)
- ✅ Safe upsert patterns (with decision tree)
- ✅ Inventory management (5 scenarios)
- ✅ Data validation testing (6 patterns)
- ✅ Automated unit testing (tSQLt framework)

### Production-Ready
- ✅ All code is tested T-SQL
- ✅ All examples include error handling
- ✅ All patterns have real-world incident examples
- ✅ All decision trees are actionable
- ✅ All best practices are enterprise-grade

---

## 🤔 Frequently Asked Questions

### "Which pattern should I use?"
→ Use the decision tree at the top of each pattern document

### "Can I copy this code directly?"
→ Yes, but adapt table/column names first

### "Is this for SQL Server 2019+ only?"
→ Mostly yes. Some patterns work in 2016+ (check notes)

### "What about Azure SQL / SQL Managed Instance?"
→ All patterns work there. No code changes needed.

### "Can I contribute to Phase 2?"
→ Read the HANDOFF document. Phase 2 patterns are listed.

### "Which pattern prevents my specific problem?"
→ Check the problem-to-pattern map above

---

## 📞 Getting Help

### If you're stuck:
1. Find the pattern for your problem
2. Read the "anti-pattern" section (to avoid mistakes)
3. Read the "correct pattern" section (to solve it)
4. Find your exact scenario in the code examples
5. Copy the pattern, adapt to your schema

### If a pattern doesn't cover your case:
1. Check the "decision tree" (might be a different pattern)
2. Check "references" section (might link to another doc)
3. Use the code as a template and adapt it

### If you find an error or omission:
- The code is production-hardened, but not perfect
- Report issues for Phase 2 improvements

---

## 🎯 One-Minute Summary

**What you have:**
- A complete SQL Server knowledge system
- Not just prompts, but production patterns
- 25+ enterprise scenarios covered
- Decision trees for every pattern
- Copy-paste ready code

**What you can do:**
- Implement soft deletes safely
- Build audit trails that comply with regulations
- Execute safe upserts without mysterious failures
- Prevent inventory overselling
- Test database code with confidence
- Integrate tests into CI/CD

**What you should do next:**
- Pick a problem you're facing
- Use the quick map to find the pattern
- Read anti-pattern section (learn why this matters)
- Copy the correct pattern code
- Adapt to your schema and test

---

**Last Updated:** 2026-06-02  
**Status:** ✅ Phase 1 Complete  
**Next:** Phase 2 (when ready)

