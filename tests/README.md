# 🧪 Testing Framework

Automated validation scripts to ensure all labs and examples work correctly.

---

## 📋 Available Tests

### `run-lab-validation.sql`

**Purpose:** Validates that LAB-01 can run start-to-finish without errors.

**What it checks:**
- ✓ SampleEcommerce database exists
- ✓ Customers table structure is correct
- ✓ Orders table structure is correct
- ✓ Data integrity (no NULL in required columns)
- ✓ LAB-01 problem query executes successfully
- ✓ OrderDetails table exists for advanced labs

**How to run:**
```sql
-- 1. Open SQL Server Management Studio (SSMS)
-- 2. Connect to your SQL Server
-- 3. Open: tests/run-lab-validation.sql
-- 4. Execute (F5)
-- 5. Check the output report
```

**Expected output:**
```
════════════════════════════════════════════════════════════════
  LAB VALIDATION SUITE - Starting
════════════════════════════════════════════════════════════════

[TEST 1] Checking if SampleEcommerce database exists...
  ✓ PASS: SampleEcommerce database exists

[TEST 2] Checking Customers table structure...
  ✓ PASS: Customers table structure is correct

... (more tests)

════════════════════════════════════════════════════════════════
  TEST SUMMARY
════════════════════════════════════════════════════════════════

TestID  TestName                  Status  Message                     ExecutionTimeMs
------  ----------------------    ------  ----------------------      ---------------
1       Database Exists           PASS    SampleEcommerce found       2
2       Customers Table           PASS    Table structure correct     1
3       Orders Table              PASS    Table structure correct     1
4       Data Integrity            PASS    No NULL values              5
5       LAB-01 Problem Query      PASS    Query executed              123
6       OrderDetails Table        WARN    Table exists                0

────────────────────────────────────────────────────────────────
RESULTS: 5 Passed, 0 Failed
════════════════════════════════════════════════════════════════
  ✓ ALL TESTS PASSED - Labs are ready to use!
════════════════════════════════════════════════════════════════
```

---

## 🚨 Troubleshooting Test Failures

### ❌ FAIL: Database Exists

**Problem:** SampleEcommerce database not found

**Solution:**
```sql
-- 1. Run the setup script
USE master;
-- 2. Execute: examples/setup-sample-database.sql
```

### ❌ FAIL: Customers Table / Orders Table

**Problem:** Table structure is incorrect

**Solution:**
1. Drop and recreate the database
2. Re-run: `examples/setup-sample-database.sql`

### ❌ FAIL: Data Integrity

**Problem:** NULL values found in required columns

**Solution:**
1. Check `examples/setup-sample-database.sql` for bugs
2. Re-run setup with fixed script
3. Report issue to: GitHub Issues

### ❌ FAIL: LAB-01 Problem Query

**Problem:** Query doesn't execute

**Solution:**
1. Check the error message in output
2. Verify Customers and Orders tables exist
3. Verify data integrity (test 4)

---

## 🔄 GitHub Actions Integration

These tests are **automatically run** on GitHub Actions when you:
- Push to `main` or `master` branch
- Create a pull request

**Check status:**
1. Go to: https://github.com/Ohkuninush/anotherSqlRepo
2. Click: Actions tab
3. Look for: "Validate SQL & Documentation" workflow
4. Click latest run to see results

---

## 📊 What Gets Tested in CI/CD

The GitHub Actions workflow runs:
1. **SQL Syntax Validation** - All `.sql` files checked
2. **Lab Validation** - `run-lab-validation.sql` executed against SQL Server 2019
3. **Markdown Validation** - All documentation checked
4. **Cross-reference Check** - All doc links verified

**Status badge:** See README.md top for live status

---

## 🎯 Adding New Tests

To add a new test:

1. **Create test file:** `tests/run-new-feature-validation.sql`

2. **Follow structure:**
```sql
-- Section: [TEST N] Description
-- 1. Try to do something
-- 2. Check if it worked
-- 3. Insert result into @TestResults
-- 4. Print user-friendly message
```

3. **Add to GitHub Actions:** Update `.github/workflows/validate-sql.yml`

4. **Run locally first:**
```sql
-- Test your script manually
-- Against SampleEcommerce database
```

5. **Commit and push:** GitHub Actions will run it

---

## 📚 Test Conventions

### Naming
- Test files: `run-[feature]-validation.sql`
- Test names: `Feature Name` (clear, concise)

### Output Format
```
[TEST N] Checking something...
  ✓ PASS: Message
  ✗ FAIL: Error message
  ⚠ WARN: Warning message
```

### Results Table
Always include:
- TestID (1, 2, 3...)
- TestName (human readable)
- Status (PASS, FAIL, WARN)
- Message (what happened)
- ExecutionTimeMs (performance tracking)

---

## 🚀 Running All Tests Locally

```sql
-- Step 1: Setup database
USE master;
-- Execute: examples/setup-sample-database.sql

-- Step 2: Run all tests
-- Test 1: Lab Validation
USE SampleEcommerce;
-- Execute: tests/run-lab-validation.sql

-- (Future) Test 2: Examples Validation
-- Execute: tests/run-examples-validation.sql

-- (Future) Test 3: Patterns Validation
-- Execute: tests/run-patterns-validation.sql
```

---

## 📞 Support

- **Tests failing?** Check troubleshooting section above
- **Need to add test?** Follow "Adding New Tests" section
- **Found bug?** Report on: GitHub Issues

---

**Last Updated:** 2026-06-02  
**Status:** ✅ Operational
