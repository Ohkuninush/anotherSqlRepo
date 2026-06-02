# 🤝 Contributing to SQL Server Expert Skill

Thank you for your interest in contributing! This document provides guidelines and instructions for contributing to the SQL Server Expert Skill repository.

---

## 📋 Table of Contents

1. [Code of Conduct](#code-of-conduct)
2. [Getting Started](#getting-started)
3. [How to Contribute](#how-to-contribute)
4. [Contribution Types](#contribution-types)
5. [Documentation Standards](#documentation-standards)
6. [SQL Code Standards](#sql-code-standards)
7. [Commit Message Guidelines](#commit-message-guidelines)
8. [Pull Request Process](#pull-request-process)
9. [Review Process](#review-process)

---

## 🤝 Code of Conduct

Be respectful, professional, and constructive in all interactions. We're here to share knowledge and improve SQL Server practices together.

---

## 🚀 Getting Started

### 1. Fork the Repository
```bash
# Fork on GitHub, then:
git clone https://github.com/YOUR-USERNAME/anotherSqlRepo.git
cd anotherSqlRepo
git remote add upstream https://github.com/Ohkuninush/anotherSqlRepo.git
```

### 2. Create a Feature Branch
```bash
git checkout -b feature/your-feature-name
# or for fixes:
git checkout -b fix/issue-description
```

### 3. Stay Updated
```bash
git fetch upstream
git rebase upstream/master
```

---

## 📝 How to Contribute

### Types of Contributions Welcome

✅ **Highly Welcome:**
- Bug fixes in documentation or examples
- Clarifications and improvements to existing guides
- Additional SQL code examples
- Testing patterns and validation improvements
- Translation improvements
- Cross-reference corrections

⚠️ **Needs Discussion First (Open an issue):**
- New capabilities beyond the 25 defined
- Architectural changes to the skill structure
- Major reorganization of content
- Removal of content

❌ **Not Accepted:**
- Proprietary code or patterns
- Content violating Microsoft's SQL Server licensing
- Unverified claims about performance/security

---

## 🎯 Contribution Types

### Type 1: Fix Documentation Issues
**Examples:** Typo fixes, incorrect SQL syntax, broken links

```bash
git checkout -b fix/typo-in-query-patterns
# Make changes
git commit -m "fix: Correct SQL syntax in window function example"
git push origin fix/typo-in-query-patterns
# Create pull request
```

### Type 2: Add/Improve Content
**Examples:** Add new pattern, expand a reference guide, add SQL examples

```bash
# For new patterns:
git checkout -b feature/add-pattern-xxx
# For improvements:
git checkout -b feature/improve-reference-xxx
```

**Requirements:**
- Test all SQL code before submitting
- Add cross-references to MASTER-INDEX.md
- Include real-world context
- Verify links work

### Type 3: Add SQL Scripts
**Examples:** New diagnostic scripts, performance analysis queries

```bash
git checkout -b feature/add-script-xxx
```

**Requirements:**
- Tested on SQL Server 2019+
- Includes comments explaining each section
- Handles edge cases
- Returns meaningful results

### Type 4: Improve Testing Frameworks
**Examples:** New test patterns, additional validation examples

```bash
git checkout -b feature/enhance-testing-xxx
```

**Requirements:**
- Real-world test scenarios
- Clear pass/fail criteria
- Examples with setup/teardown
- Integration with existing frameworks

---

## 📚 Documentation Standards

### Markdown Formatting

**Use consistent structure:**
```markdown
# Main Title (H1)

## Section (H2)

### Subsection (H3)

**Bold for important terms**
- Bullet points for lists
- Clear examples

#### Code Examples
```sql
-- SQL code with comments
SELECT * FROM Orders WHERE Status = 'Active'
```

**Best Practices:**
- Line length: Max 100 characters
- Use ✅ for good examples, ❌ for bad ones
- Include practical context
- Link to related files: `[reference-name.md](reference-name.md)`
- Use tables for comparisons

### File Naming

```
references-topic_name.md      # Reference guides
patterns-pattern_name.md      # Design patterns
testing-test_type.md          # Testing guides
scripts-script_purpose.sql    # SQL scripts
```

### Structure Template for New Guides

```markdown
# Topic Name

## Overview
Brief explanation of what this is about (2-3 sentences)

## When to Use
Scenarios where this applies

## How It Works
Explanation with examples (code blocks with ✅/❌)

## Implementation
Step-by-step instructions

## Best Practices
Checklist of important points

## Common Pitfalls
What to avoid

## Related Topics
Links to other guides
```

---

## 💾 SQL Code Standards

### Required Standards

**All SQL code MUST include:**

1. **Comments explaining purpose**
```sql
-- Calculate running total by customer
SELECT 
    OrderID,
    CustomerID,
    Amount,
    SUM(Amount) OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS RunningTotal
FROM Orders
```

2. **Error handling (in procedures)**
```sql
CREATE PROCEDURE sp_ProcessOrder
    @OrderID INT
AS
BEGIN
    SET NOCOUNT ON
    SET XACT_ABORT ON
    
    BEGIN TRY
        -- Code here
    END TRY
    BEGIN CATCH
        THROW
    END CATCH
END
```

3. **Good naming conventions**
```sql
-- ✅ GOOD: Clear, descriptive names
CREATE PROCEDURE sp_CalculateOrderTotal
    @OrderID INT

-- ❌ AVOID: Vague names
CREATE PROCEDURE sp_Process @ID INT
```

4. **Production-ready patterns**
```sql
-- ✅ GOOD: Explicit columns
INSERT INTO Orders (OrderID, CustomerID, Amount) 
VALUES (@OrderID, @CustID, @Amount)

-- ❌ AVOID: Implicit ordering
INSERT INTO Orders 
VALUES (@OrderID, @CustID, @Amount)
```

### Verification Checklist

- [ ] Code tested on SQL Server 2019+
- [ ] No hardcoded values (use parameters)
- [ ] Includes comments explaining logic
- [ ] Follows production code standards from skill
- [ ] No SELECT * (explicit columns)
- [ ] Error handling for procedures
- [ ] Performance considerations documented
- [ ] Example output or results shown

---

## 📝 Commit Message Guidelines

### Format
```
type(scope): subject

body (optional)
```

### Types
- **docs:** Documentation changes
- **feat:** New feature (new pattern, new guide)
- **fix:** Bug fixes (typos, incorrect code)
- **refactor:** Reorganization without behavior change
- **chore:** Non-code changes (scripts, tooling)
- **perf:** Performance improvements
- **test:** Testing improvements

### Scope
- `references` - Reference guides
- `patterns` - Design patterns
- `testing` - Testing frameworks
- `scripts` - SQL scripts
- `skill` - Main skill documentation
- `index` - Navigation index

### Examples

```bash
# Good commits
git commit -m "docs(references): Add JSON processing best practices"
git commit -m "feat(patterns): Add multi-tenant isolation pattern"
git commit -m "fix(scripts): Correct DMV query for index analysis"
git commit -m "docs(index): Update MASTER-INDEX with new content"
git commit -m "test(testing): Add regression testing for ETL pipeline"

# Bad commits
git commit -m "Updated stuff"
git commit -m "Fixed things"
git commit -m "Work in progress"
```

---

## 🔄 Pull Request Process

### Before Creating a PR

1. **Check MASTER-INDEX.md**
   - Does your content fit an existing capability?
   - Do you need to add cross-references?

2. **Test everything**
   - SQL code tested on SQL Server 2019+
   - Links verified (especially in markdown)
   - Examples work as shown

3. **Review content**
   - No typos or grammatical errors
   - Consistent with existing style
   - Follows documentation standards

4. **Update navigation**
   - Add to MASTER-INDEX.md if new content
   - Link to related files
   - Update table of contents if applicable

### Creating a PR

```bash
# Make sure your branch is up to date
git fetch upstream
git rebase upstream/master

# Push to your fork
git push origin your-branch-name

# Create PR on GitHub
# - Clear title
# - Describe what changed and why
# - Reference any related issues
```

### PR Title Format
```
[Type] Brief description

Examples:
[Docs] Add JSON processing guide to references
[Feature] Implement soft delete pattern
[Fix] Correct blocking analysis script
```

### PR Description Template

```markdown
## Description
Brief explanation of changes

## Type of Change
- [ ] Documentation improvement
- [ ] New pattern/guide
- [ ] SQL code fix/enhancement
- [ ] Testing framework improvement
- [ ] Navigation/cross-reference update

## Changes Made
- Specific change 1
- Specific change 2
- Specific change 3

## Related Content
- Links to related guides
- Cross-references
- Related issues/discussions

## Verification
- [ ] Tested on SQL Server 2019+
- [ ] Updated MASTER-INDEX.md
- [ ] Added cross-references
- [ ] Follows documentation standards
- [ ] No broken links
- [ ] Spell-checked

## Screenshots (if applicable)
Screenshots of any diagrams or examples
```

---

## 🔍 Review Process

### What We Look For

1. **Correctness**
   - SQL code actually works
   - Information is accurate
   - Examples are reproducible

2. **Clarity**
   - Content is understandable
   - Examples are clear
   - Structure is logical

3. **Completeness**
   - Links are working
   - Cross-references exist
   - Examples are realistic

4. **Consistency**
   - Matches existing style
   - Follows naming conventions
   - Uses established patterns

5. **Value**
   - Adds genuine value
   - Solves real problems
   - Fits the scope

### Reviewer Comments

**You may receive requests for:**
- More explanation or examples
- SQL code changes or optimization
- Link/reference additions
- Style or formatting updates
- Cross-reference additions

**Response guidance:**
- Address all comments respectfully
- Push updates to the same branch
- No need to close and reopen PR
- Ask for clarification if needed

---

## 📊 Examples of Good Contributions

### Example 1: Documentation Improvement
```markdown
# Before
Only 1 paragraph explaining the concept

# After
- Clear intro
- 3-5 code examples (with ✅/❌)
- Real-world scenario
- Links to related content
- Checklist of best practices
```

### Example 2: New Pattern
```markdown
Submitting: patterns-new_pattern_name.md

Should include:
- When to use
- Problem it solves
- Implementation example
- Edge cases handled
- Testing validation
- Links to related patterns
```

### Example 3: SQL Script Improvement
```sql
-- Before
SELECT * FROM Orders

-- After
-- Find orders with high-value customers
-- Purpose: Performance analysis of top-tier customer orders
SELECT 
    o.OrderID,
    o.CustomerID,
    c.CustomerName,
    o.Amount
FROM Orders o
INNER JOIN Customers c ON o.CustomerID = c.CustomerID
WHERE o.Amount > 10000
ORDER BY o.Amount DESC

-- Related: See references-query_patterns.md for optimization
```

---

## ❓ Questions or Issues?

### Before Opening an Issue
- Search existing issues first
- Check MASTER-INDEX.md for related content
- Check the skill documentation

### Issue Categories
- **Documentation Issue** - Unclear, incorrect, or missing info
- **SQL Code Issue** - Code doesn't work or has bugs
- **Enhancement Request** - Suggest new content/patterns
- **Question** - Ask for help understanding content

### Issue Template
```markdown
## Description
What's the issue?

## Location
File: [filename.md](link)
Section: [heading name]

## Current Behavior
What currently exists (if applicable)

## Expected Behavior
What should happen instead

## Steps to Reproduce (if bug)
1. Step 1
2. Step 2

## Additional Context
Any other relevant info
```

---

## 🎓 Learning Resources

To contribute effectively, you should understand:

1. **SQL Server Basics** - If adding SQL code
2. **Markdown Syntax** - For documentation
3. **Git & GitHub** - For contributing

**Our Docs Include:**
- `MASTER-INDEX.md` - Content navigation
- `sql-server-expert-SKILL-CORRECTED.md` - Skill overview
- Individual guides in `references/` folder

---

## 🙏 Thank You!

Your contributions help build a better SQL Server knowledge base for everyone. Whether it's a small typo fix or a comprehensive new pattern, all contributions are valued.

### What Happens After Your PR
1. Review (1-3 days)
2. Feedback (if needed)
3. Approval ✅
4. Merge to master
5. Your contribution goes live!

---

## 📞 Getting Help

- **Questions about contributing?** Open an issue labeled "question"
- **Need guidance on content?** Start a discussion
- **Found a bug?** Open an issue with details
- **Want to suggest something?** Create an enhancement issue

---

## 📜 License

By contributing, you agree that your contributions will be licensed under the same license as the project.

---

**Happy Contributing! 🚀**

Last updated: 2026-06-02
