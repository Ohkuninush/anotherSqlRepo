# 🚀 SQL Server Expert Skill - Enterprise Edition

A comprehensive enterprise-grade SQL Server expertise system with 25 advanced capabilities, production code patterns, and testing frameworks.

## 📋 Overview

This repository contains a complete SQL Server knowledge base designed to support:
- **Query Optimization** - Performance analysis and tuning
- **Concurrency Control** - Locking, blocking, and deadlock resolution
- **Data Management** - ETL, auditing, and compliance patterns
- **Architecture Design** - High availability, security, and data modeling
- **Testing & Quality** - Performance baselines and regression testing

## 🏗️ Project Structure

```
.
├── MASTER-INDEX.md                          # 🎯 Start here - Navigation guide
├── sql-server-expert-SKILL-CORRECTED.md     # 📘 Main skill definition (25 capabilities)
├── QUICK-START-GUIDE.md                     # ⚡ Quick reference
│
├── 📚 REFERENCES/ (14 guides)
│   ├── query_patterns.md                    # Optimization patterns & anti-patterns
│   ├── index_design_guidelines.md           # Index strategy
│   ├── concurrency_blocking.md              # Locking & deadlock analysis
│   ├── transaction_management.md            # Transaction patterns & isolation levels
│   ├── etl_migration_patterns.md            # Data pipeline patterns
│   ├── partitioning_strategy.md             # Large table management
│   ├── sql_server_2019_features.md          # JSON, Temporal Tables, Graph Tables
│   ├── data_modeling.md                     # OLTP vs OLAP design
│   ├── auditing_guide.md                    # Change tracking & compliance
│   ├── ha_disaster_recovery.md              # Always On, Log Shipping
│   ├── observability_diagnostics.md         # Extended Events, wait stats
│   ├── dynamic_sql_patterns.md              # SQL injection prevention
│   ├── architecture_review.md               # Database design reviews
│   └── best_practices.md                    # General SQL Server best practices
│
├── 🎨 PATTERNS/ (8 enterprise patterns)
│   ├── soft_delete_patterns.md              # GDPR-compliant deletion
│   ├── audit_trail_patterns.md              # Immutable audit trails
│   ├── upsert_patterns.md                   # MERGE vs UPDATE+INSERT
│   ├── inventory_patterns.md                # Stock management
│   ├── financial_integrity.md               # Double-entry bookkeeping
│   ├── etl_incremental.md                   # CDC & incremental loads
│   ├── multi_tenant_isolation.md            # Row-level security
│   └── hierarchical_data.md                 # Trees & graphs
│
├── 🧪 TESTING/ (4 testing frameworks)
│   ├── data_validation_tests.md             # Constraint & integrity testing
│   ├── unit_testing_tsqlt.md                # tSQLt framework
│   ├── performance_baseline_testing.md      # Performance benchmarking
│   └── regression_testing.md                # Change validation
│
├── 🔧 SCRIPTS/ (5 diagnostic utilities)
│   ├── analyze_execution_plan.sql           # 10 performance diagnosis queries
│   ├── find_missing_indexes.sql             # Index analysis
│   ├── generate_table_documentation.sql     # Schema documentation
│   ├── performance_baseline.sql             # Performance metrics
│   └── deadlock_analyzer.sql                # Concurrency troubleshooting
│
├── 📊 REPORTS/ (Completion reports)
│   ├── PHASE-1-COMPLETION-REPORT.md         # Phase 1 deliverables
│   ├── PHASE-2-COMPLETION-REPORT.md         # Phase 2 deliverables
│   └── HANDOFF-SQL-SERVER-SKILL-SESSION2.md # Transition documentation
│
└── .gitignore                               # Git configuration
```

## 🚀 Quick Start

### 1. Find Your Problem
Open **[`MASTER-INDEX.md`](MASTER-INDEX.md)** - it maps every common SQL Server problem to solutions:
- 🚀 Performance issues
- 🔒 Concurrency problems
- 📊 Data management needs
- 🏗️ Architecture decisions
- 🧪 Testing requirements

### 2. Get Guided
The MASTER-INDEX shows you exactly:
- Which **Skill Capability** applies
- Which **Reference** documents explain it
- Which **Scripts** diagnose the issue
- Which **Patterns** implement the solution
- Which **Testing** validates it

### 3. Implement & Validate
Follow the references in order:
1. **References** - Understand the what/why
2. **Scripts** - Diagnose the current state
3. **Patterns** - Implement best practices
4. **Testing** - Validate the solution

## 📚 Documentation

### Main Skill
- **[`sql-server-expert-SKILL-CORRECTED.md`](sql-server-expert-SKILL-CORRECTED.md)**
  - 25 advanced capabilities
  - Production code standards
  - Common workflows
  - 567 lines of comprehensive guidance

### Navigation Guides
- **[`MASTER-INDEX.md`](MASTER-INDEX.md)** - Problem → Solution navigator
- **[`QUICK-START-GUIDE.md`](QUICK-START-GUIDE.md)** - Quick reference

### By Category

#### Performance & Optimization
- [Query Patterns](references-query_patterns.md) - Optimization + anti-patterns
- [Index Design Guidelines](references-index_design_guidelines.md) - Index strategy
- [SQL Server 2019+ Features](references-sql_server_2019_features.md) - Modern optimization

#### Concurrency & Locking
- [Concurrency & Blocking](references-concurrency_blocking.md) - Lock analysis
- [Transaction Management](references-transaction_management.md) - Isolation levels
- [Deadlock Analyzer Script](scripts-deadlock_analyzer.sql) - Troubleshooting

#### Data Management
- [ETL & Migration Patterns](references-etl_migration_patterns.md) - Data pipelines
- [Auditing Guide](references-auditing_guide.md) - Change tracking
- [Soft Delete Patterns](patterns-soft_delete_patterns.md) - GDPR compliance

#### Architecture & Design
- [Data Modeling](references-data_modeling.md) - OLTP/OLAP design
- [Partitioning Strategy](references-partitioning_strategy.md) - Large tables
- [HA/DR Guide](references-ha_disaster_recovery.md) - High availability
- [Architecture Review](references-architecture_review.md) - Design validation

#### Testing & Quality
- [Performance Baseline Testing](testing-performance_baseline_testing.md) - Benchmarking
- [Regression Testing](testing-regression_testing.md) - Change validation
- [Data Validation Tests](testing-data_validation_tests.md) - Constraint testing
- [Unit Testing with tSQLt](testing-unit_testing_tsqlt.md) - Automated testing

## 🎯 Use Cases

### "My Query is Slow"
1. Open [MASTER-INDEX.md](MASTER-INDEX.md) → Search "Query Lenta"
2. Follow the capability → references → scripts → patterns → testing
3. Use `analyze_execution_plan.sql` to diagnose
4. Follow `query_patterns.md` to optimize
5. Validate with `performance_baseline_testing.md`

### "Database is Blocking"
1. Open [MASTER-INDEX.md](MASTER-INDEX.md) → Search "Bloqueos"
2. Run `deadlock_analyzer.sql` for diagnosis
3. Read `concurrency_blocking.md` for analysis
4. Implement from `transaction_management.md`
5. Test with `regression_testing.md`

### "Design New Database"
1. Open [MASTER-INDEX.md](MASTER-INDEX.md) → Search "Diseñar BD"
2. Read `data_modeling.md` for OLTP/OLAP choice
3. Review `best_practices.md` for schema design
4. Use `generate_table_documentation.sql` for DDL
5. Review with `architecture_review.md`

### "Implement Auditing"
1. Open [MASTER-INDEX.md](MASTER-INDEX.md) → Search "Auditar"
2. Read `auditing_guide.md` vs `audit_trail_patterns.md`
3. Decide: Shadow tables vs Temporal Tables vs Soft delete
4. Implement from `sql_server_2019_features.md` if using Temporal
5. Test with `data_validation_tests.md`

## 🔍 Key Features

### 25 Advanced Capabilities
1. Query Optimization
2. Execution Plan Analysis
3. Index Strategy & Creation
4. DDL Generation
5. Stored Procedures & Functions
6. Query Debugging & Troubleshooting
7. Window Functions (Advanced)
8. Query Hints & Query Forcing
9. Partitioning Strategy
10. Replication & CDC
11. SQL Server Security (RBAC)
12. Tempdb Optimization
13. Dynamic SQL (Secure)
14. Query Store & Performance Analysis
15. SQL Server 2019+ Modern Features
16. Concurrency, Locking & Blocking
17. JSON Processing
18. ETL & Data Migration
19. Transaction Management
20. Auditing & Change Tracking
21. Architecture Review
22. Financial & Inventory Integrity
23. High Availability & Disaster Recovery
24. Observability & Diagnostics
25. Data Modeling (OLTP & OLAP)

### 5 Diagnostic Scripts
- **analyze_execution_plan.sql** - 10 DMV queries for performance diagnosis
- **deadlock_analyzer.sql** - 15 queries for concurrency troubleshooting
- **find_missing_indexes.sql** - 7 queries for index analysis
- **generate_table_documentation.sql** - 10 queries for schema docs
- **performance_baseline.sql** - 15 queries for performance metrics

### 8 Enterprise Patterns
Proven solutions for common business scenarios:
- Soft deletes (GDPR compliance)
- Audit trails (immutable change tracking)
- Upserts (ETL reliability)
- Inventory management (concurrent stock)
- Financial integrity (double-entry bookkeeping)
- ETL incremental loads (CDC & watermarks)
- Multi-tenant isolation (row-level security)
- Hierarchical data (trees, graphs, materializations)

### 4 Testing Frameworks
- Data validation (constraints, integrity)
- Unit testing (tSQLt framework)
- Performance baseline (benchmarking)
- Regression testing (change validation)

## 📖 SQL Server Compatibility

- **SQL Server Version:** 2019+
- **Authentication:** Windows Authentication
- **SSMS Version:** 22.6.0+
- **Features Used:** Modern T-SQL, JSON, Temporal Tables, Graph Tables, IQP

## 🤝 Contributing

This is a living document. To contribute:
1. Make changes to the relevant file
2. Update MASTER-INDEX.md if adding new content
3. Test all SQL code samples
4. Verify cross-references

## 📄 License

This project is provided as-is for educational and professional use.

## 🔗 References

- [Microsoft SQL Server Documentation](https://docs.microsoft.com/sql/)
- [SQL Server Best Practices](https://docs.microsoft.com/sql/sql-server/best-practices)
- [Query Tuning Fundamentals](https://docs.microsoft.com/sql/relational-databases/query-processing-architecture)

---

## 🎯 Navigation Tips

- **First time?** → Start with [MASTER-INDEX.md](MASTER-INDEX.md)
- **Have a problem?** → Search MASTER-INDEX for your issue
- **Need to learn?** → Follow the references in order
- **Want code?** → Look for the related pattern file
- **Need to validate?** → Use the testing guides

---

**Last Updated:** 2026-06-02  
**Status:** Complete & Production-Ready  
**Skill Capability:** 25 advanced areas covered  
**Documentation:** 40+ files with 100+ KB of guides

