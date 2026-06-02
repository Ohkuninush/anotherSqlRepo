# 🎯 MASTER INDEX - SQL Server Expert Skill Navigation

**Este archivo es tu mapa de ruta.** Encuentra tu problema → obtén solución → accede a archivos, scripts y código.

---

## 📍 NAVEGACIÓN RÁPIDA

| Categoría | Problema | Solución Rápida |
|-----------|----------|-----------------|
| 🚀 **PERFORMANCE** | Query lenta | [→ Query Optimization](#query-lenta) |
| | Tabla scan en lugar de seek | [→ Index Strategy](#tabla-scan) |
| | Memoria/CPU alto | [→ Execution Plans](#memora-cpu) |
| | Ejecución inconsistente | [→ Query Forcing](#ejecucion-inconsistente) |
| 🔒 **CONCURRENCY** | Bloqueos/Deadlocks | [→ Locking & Blocking](#bloqueos-deadlocks) |
| | Transacción larga | [→ Transaction Management](#transaccion-larga) |
| | Aislamiento de datos | [→ Isolation Levels](#aislamiento-datos) |
| 📊 **DATA** | Sincronizar datos externos | [→ ETL & Migration](#sincronizar-datos) |
| | Auditar cambios | [→ Auditing](#auditar-cambios) |
| | Eliminar datos sin perder historial | [→ Soft Deletes](#eliminar-datos) |
| | Datos jerárquicos/grafos | [→ Hierarchical Data](#datos-jerarquicos) |
| 🏗️ **ARCHITECTURE** | Diseñar base de datos | [→ Data Modeling](#disenar-bd) |
| | Tablas muy grandes | [→ Partitioning](#tablas-grandes) |
| | Alta disponibilidad | [→ HA/DR](#alta-disponibilidad) |
| | Seguridad/roles | [→ Security](#seguridad) |
| 🧪 **TESTING** | Validar datos | [→ Data Validation](#validar-datos) |
| | Detectar regresiones | [→ Regression Testing](#detectar-regresiones) |
| | Benchmark performance | [→ Performance Baseline](#benchmark) |

---

## 🚀 PERFORMANCE

### Query Lenta
**Síntomas:** Consulta tarda > 1 segundo, usuarios reportan lentitud

| Aspecto | Referencia | Script | Patrón | Testing |
|--------|-----------|--------|--------|---------|
| **Paso 1: Diagnosticar** | [query_patterns.md](#referencia-query-patterns) | [analyze_execution_plan.sql](#script-analyze) | - | - |
| **Paso 2: Optimizar** | [query_patterns.md](#referencia-query-patterns) | [find_missing_indexes.sql](#script-indexes) | - | [performance_baseline_testing.md](#test-perf) |
| **Paso 3: Implementar** | [best_practices.md](#referencia-best) | - | [etl_incremental.md](#pattern-etl) | [regression_testing.md](#test-regression) |
| **Paso 4: Validar** | - | - | - | [performance_baseline_testing.md](#test-perf) |

**Skill Capability:** #1 Query Optimization

**Acción rápida:**
```sql
-- 1. Leer el plan de ejecución
SET STATISTICS IO ON
SET STATISTICS TIME ON
SELECT * FROM Orders WHERE YEAR(OrderDate) = 2026
SET STATISTICS TIME OFF
SET STATISTICS IO OFF

-- 2. Ver scan vs seek en output
-- 3. Si hay scan, crear index en OrderDate
-- Ver: references-index_design_guidelines.md, references-query_patterns.md
```

---

### Tabla Scan en lugar de Seek
**Síntomas:** Plan de ejecución muestra "Clustered Index Scan", debería ser "Seek"

| Aspecto | Referencia | Script | Patrón |
|--------|-----------|--------|--------|
| **Diagnóstico** | [index_design_guidelines.md](#referencia-index) | [find_missing_indexes.sql](#script-indexes) | - |
| **Crear Index** | [index_design_guidelines.md](#referencia-index) | - | - |
| **Validar** | [common_pitfalls.md](#referencia-pitfalls) | - | - |

**Skill Capability:** #3 Index Strategy & Creation

**Código típico:**
```sql
-- Identificar índices faltantes
EXEC sp_helpindex 'Orders'

-- Crear covering index
CREATE INDEX IX_Orders_Status_OrderDate_Covering 
ON Orders(Status, OrderDate) 
INCLUDE (OrderID, Amount)

-- Validar con plan
SET STATISTICS IO ON
SELECT OrderID, Amount FROM Orders WHERE Status = 'Pending'
SET STATISTICS IO OFF
```

---

### Memoria/CPU Alto
**Síntomas:** Query usa mucha memoria, CPU al 100%

| Aspecto | Referencia | Script | Patrón |
|--------|-----------|--------|--------|
| **Analizar** | [observability_diagnostics.md](#referencia-obs) | [analyze_execution_plan.sql](#script-analyze) | - |
| **Optimizar** | [query_patterns.md](#referencia-query-patterns) | [performance_baseline.sql](#script-perf) | - |
| **Monitorear** | [observability_diagnostics.md](#referencia-obs) | - | - |

**Skill Capability:** #2 Execution Plan Analysis, #14 Query Store & Performance Analysis

**Checklist rápida:**
- [ ] ¿Hay SORT o HASH JOIN no esperado? → Ver plan
- [ ] ¿Spill to disk? → Increase memory grant o optimizar query
- [ ] ¿Uniones complejas? → Usar CTE y window functions
- [ ] Ver: [common_pitfalls.md](#referencia-pitfalls) - "Functions in WHERE Clause"

---

### Ejecución Inconsistente
**Síntomas:** Mismo query a veces rápido, a veces lento

| Aspecto | Referencia | Script | Patrón |
|--------|-----------|--------|--------|
| **Diagnóstico** | [common_pitfalls.md](#referencia-pitfalls) | [analyze_execution_plan.sql](#script-analyze) | - |
| **Forzar Plan** | [query_patterns.md](#referencia-query-patterns) | - | - |
| **Estadísticas** | [best_practices.md](#referencia-best) | [performance_baseline.sql](#script-perf) | - |

**Skill Capability:** #8 Query Hints & Query Forcing

**Causas comunes:**
1. Estadísticas desactualizadas → `UPDATE STATISTICS`
2. Parámetro sniffing → Use `OPTIMIZE FOR` hint
3. Multiple plans en cache → Force plan con Query Store

---

## 🔒 CONCURRENCY

### Bloqueos/Deadlocks
**Síntomas:** Error: "Deadlock victim" o queries bloqueadas esperando locks

| Aspecto | Referencia | Script | Patrón | Testing |
|--------|-----------|--------|--------|---------|
| **Diagnóstico** | [concurrency_blocking.md](#referencia-conc) | [deadlock_analyzer.sql](#script-deadlock) | - | - |
| **Análisis** | [concurrency_blocking.md](#referencia-conc) | [analyze_execution_plan.sql](#script-analyze) | - | - |
| **Solución** | [transaction_management.md](#referencia-txn) | - | - | [regression_testing.md](#test-regression) |

**Skill Capability:** #16 Concurrency, Locking & Blocking

**Acción inmediata:**
```sql
-- 1. Ver sesiones bloqueadas
SELECT * FROM sys.dm_exec_requests WHERE blocking_session_id <> 0

-- 2. Matar sesión bloqueadora (último recurso)
KILL <session_id>

-- 3. Implementar solución: Ver transaction_management.md
-- Opciones: Snapshot isolation, optimistic locking, índices mejor diseño
```

---

### Transacción Larga
**Síntomas:** BEGIN TRANSACTION...COMMIT dura varios segundos, locks acumulándose

| Aspecto | Referencia | Script |
|--------|-----------|--------|
| **Refactorizar** | [transaction_management.md](#referencia-txn) | - |
| **Validar** | [common_pitfalls.md](#referencia-pitfalls) | - |

**Skill Capability:** #19 Transaction Management

**Antipatrón → Patrón:**
```sql
-- ❌ BAD: Long transaction
BEGIN TRANSACTION
    UPDATE Orders SET Status = 'Shipped'
    EXECUTE sp_GenerateReport  -- Takes 30 seconds!
    INSERT INTO ShipmentLog VALUES (...)
COMMIT TRANSACTION

-- ✅ GOOD: Short transaction
BEGIN TRANSACTION
    UPDATE Orders SET Status = 'Shipped'
    INSERT INTO ShipmentLog VALUES (...)
COMMIT TRANSACTION
-- Then generate report separately
EXECUTE sp_GenerateReport
```

---

### Aislamiento de Datos
**Síntomas:** Necesitas SNAPSHOT isolation o READ_COMMITTED_SNAPSHOT

| Aspecto | Referencia | Script |
|--------|-----------|--------|
| **Entender Levels** | [transaction_management.md](#referencia-txn) | - |
| **Implementar** | [transaction_management.md](#referencia-txn) | - |

**Skill Capability:** #16 Concurrency, Locking & Blocking

**Habilitar SNAPSHOT:**
```sql
ALTER DATABASE MyDB SET ALLOW_SNAPSHOT_ISOLATION ON

-- Usar en procedure
SET TRANSACTION ISOLATION LEVEL SNAPSHOT
BEGIN TRANSACTION
    -- Optimistic reads (no locks)
    SELECT * FROM Orders WHERE OrderID = @ID
    UPDATE Orders SET Status = 'Active' WHERE OrderID = @ID
COMMIT TRANSACTION
```

---

## 📊 DATA

### Sincronizar Datos Externos
**Síntomas:** Necesitas ETL: API → SQL Server, archivo CSV → tabla

| Aspecto | Referencia | Script | Patrón |
|--------|-----------|--------|--------|
| **Diseñar Pipeline** | [etl_migration_patterns.md](#referencia-etl) | - | [etl_incremental.md](#pattern-etl) |
| **Implementar UPSERT** | [etl_migration_patterns.md](#referencia-etl) | - | [upsert_patterns.md](#pattern-upsert) |
| **Validar Datos** | - | - | - |

**Skill Capability:** #18 ETL & Data Migration

**Pipeline típica:**
```sql
-- 1. Staging: Cargar datos externos
CREATE TABLE Orders_Staging (...)
BULK INSERT Orders_Staging FROM 'file.csv'

-- 2. Validar
SELECT * FROM Orders_Staging WHERE OrderID IS NULL

-- 3. Merge/Upsert
MERGE INTO Orders o
USING Orders_Staging s ON o.OrderID = s.OrderID
WHEN MATCHED THEN UPDATE SET Amount = s.Amount
WHEN NOT MATCHED THEN INSERT VALUES (...)

-- Ver: references-etl_migration_patterns.md, patterns-upsert_patterns.md
```

---

### Auditar Cambios
**Síntomas:** Necesitas registrar quién cambió qué y cuándo

| Aspecto | Referencia | Patrón | Testing |
|--------|-----------|--------|---------|
| **Diseño** | [auditing_guide.md](#referencia-audit) | [audit_trail_patterns.md](#pattern-audit) | [data_validation_tests.md](#test-validation) |
| **Implementar** | [auditing_guide.md](#referencia-audit) | [soft_delete_patterns.md](#pattern-soft) | - |
| **Consultar** | [auditing_guide.md](#referencia-audit) | - | - |

**Skill Capability:** #20 Auditing & Change Tracking

**Opciones:**
- Temporal Tables (automático): Ver references-sql_server_2019_features.md
- Shadow columns (manual): Ver patterns-audit_trail_patterns.md
- Triggers: Ver references-auditing_guide.md

---

### Eliminar Datos sin Perder Historial
**Síntomas:** Compliance/GDPR requiere poder recuperar datos eliminados

| Aspecto | Referencia | Patrón |
|--------|-----------|--------|
| **Implementar** | [auditing_guide.md](#referencia-audit) | [soft_delete_patterns.md](#pattern-soft) |
| **Recuperar** | [soft_delete_patterns.md](#pattern-soft) | - |

**Skill Capability:** #20 Auditing & Change Tracking

**Patrón soft delete:**
```sql
-- En lugar de DELETE, marcar IsDeleted
UPDATE Orders SET IsDeleted = 1, DeletedDate = GETDATE() WHERE OrderID = @ID

-- Queries siempre filtran
SELECT * FROM Orders WHERE IsDeleted = 0

-- Ver: patterns-soft_delete_patterns.md
```

---

### Datos Jerárquicos/Grafos
**Síntomas:** Trees (categorías), organigramas, redes sociales

| Aspecto | Referencia | Patrón |
|--------|-----------|--------|
| **Diseño** | - | [hierarchical_data.md](#pattern-hierarchical) |
| **Queries** | [hierarchical_data.md](#pattern-hierarchical) | - |
| **Modern** | [sql_server_2019_features.md](#referencia-2019) | [hierarchical_data.md](#pattern-hierarchical) |

**Skill Capability:** #25 Data Modeling (OLTP & OLAP)

**Opciones:**
- Materialized Path: Más simple, rápido
- Nested Sets: Queries complejas
- Graph Tables (SQL Server 2019+): Relaciones M2M

---

## 🏗️ ARCHITECTURE

### Diseñar Base de Datos
**Síntomas:** Nuevo proyecto, necesitas schema desde cero

| Aspecto | Referencia | Script | Patrón |
|--------|-----------|--------|--------|
| **Normalización** | [data_modeling.md](#referencia-modeling) | [generate_table_documentation.sql](#script-gen) | - |
| **Keys & Constraints** | [best_practices.md](#referencia-best) | - | - |
| **Indexes** | [index_design_guidelines.md](#referencia-index) | - | - |
| **Review** | [architecture_review.md](#referencia-arch) | - | - |

**Skill Capability:** #4 DDL Generation, #25 Data Modeling

**Checklist:**
- [ ] ¿OLTP o OLAP? (normalized vs dimensional)
- [ ] Primary/Foreign keys definidas
- [ ] Constraints (NOT NULL, CHECK, UNIQUE)
- [ ] Indexes en filter/join columns
- [ ] Ver: references-data_modeling.md

---

### Tablas Muy Grandes
**Síntomas:** Tabla > 2GB, archivos/purgas lentas

| Aspecto | Referencia | Patrón |
|--------|-----------|--------|
| **Estrategia** | [partitioning_strategy.md](#referencia-partition) | - |
| **Implementar** | [partitioning_strategy.md](#referencia-partition) | - |
| **Mantener** | [partitioning_strategy.md](#referencia-partition) | - |

**Skill Capability:** #9 Partitioning Strategy

**Arquitectura:**
```sql
-- 1. Crear partition function (por fecha)
CREATE PARTITION FUNCTION pf_Monthly (DATETIME2) AS RANGE RIGHT FOR VALUES (...)

-- 2. Crear partition scheme
CREATE PARTITION SCHEME ps_Monthly AS PARTITION pf_Monthly TO ([PRIMARY], ...)

-- 3. Crear tabla particionada
CREATE TABLE Orders (...) ON ps_Monthly (OrderDate)

-- 4. Mantenimiento: Sliding window (agregar/remover particiones)
-- Ver: references-partitioning_strategy.md
```

---

### Alta Disponibilidad
**Síntomas:** Necesitas uptime 24/7, failover automático

| Aspecto | Referencia | Patrón |
|--------|-----------|--------|
| **RTO/RPO** | [ha_disaster_recovery.md](#referencia-ha) | - |
| **Always On** | [ha_disaster_recovery.md](#referencia-ha) | - |
| **Log Shipping** | [ha_disaster_recovery.md](#referencia-ha) | - |
| **Backup** | [ha_disaster_recovery.md](#referencia-ha) | - |

**Skill Capability:** #23 High Availability & Disaster Recovery

---

### Seguridad/Roles
**Síntomas:** RBAC, permisos por usuario/rol, encryption

| Aspecto | Referencia |
|--------|-----------|
| **RBAC Design** | [best_practices.md](#referencia-best) |
| **Usuarios/Logins** | [best_practices.md](#referencia-best) |
| **Encryption** | [best_practices.md](#referencia-best) |
| **Row-Level Security** | [multi_tenant_isolation.md](#pattern-multi) |

**Skill Capability:** #11 SQL Server Security (RBAC)

---

## 🧪 TESTING

### Validar Datos
**Síntomas:** Necesitas verificar constraints, integridad referencial

| Aspecto | Referencia | Testing |
|--------|-----------|---------|
| **Escribir Tests** | - | [data_validation_tests.md](#test-validation) |
| **Constraints** | - | [data_validation_tests.md](#test-validation) |
| **Reconciliación** | [financial_integrity.md](#pattern-financial) | [data_validation_tests.md](#test-validation) |

**Skill Capability:** No específica (transversal)

**Test típica:**
```sql
-- Test: Foreign key integrity
IF EXISTS (
    SELECT 1 FROM Orders o
    WHERE NOT EXISTS (SELECT 1 FROM Customers c WHERE c.CustomerID = o.CustomerID)
)
BEGIN
    PRINT '❌ FAIL: Orphaned orders'
    RETURN 1
END
PRINT '✅ PASS: Foreign keys valid'
```

---

### Detectar Regresiones
**Síntomas:** Después de cambios, validar que nada se rompió

| Aspecto | Referencia | Testing |
|--------|-----------|---------|
| **Setup** | - | [regression_testing.md](#test-regression) |
| **Before/After** | - | [regression_testing.md](#test-regression) |
| **Performance** | [performance_baseline_testing.md](#test-perf) | [regression_testing.md](#test-regression) |

**Skill Capability:** No específica

**Workflow:**
```sql
-- 1. Capturar baseline
SELECT * INTO #Baseline FROM Orders WHERE OrderID = @TestID

-- 2. Ejecutar cambio
UPDATE Orders SET Status = 'Active' WHERE OrderID = @TestID

-- 3. Comparar
SELECT * FROM Orders WHERE OrderID = @TestID
-- ✅ Verify: Status changed, Amount unchanged, no orphans

-- Ver: testing-regression_testing.md
```

---

### Benchmark Performance
**Síntomas:** Necesitas medir si query se aceleró/desaceleró

| Aspecto | Referencia | Testing |
|--------|-----------|---------|
| **Capturar Baseline** | - | [performance_baseline_testing.md](#test-perf) |
| **Comparar** | - | [performance_baseline_testing.md](#test-perf) |
| **Alertar** | - | [performance_baseline_testing.md](#test-perf) |

**Skill Capability:** No específica

---

## 📚 REFERENCIAS RÁPIDAS

### Por Archivo

#### `references-query_patterns.md`
- Optimization patterns (Window functions, CTEs, UNION vs OR, Covering indexes)
- Anti-patterns (SELECT *, LIKE %, Functions on columns, NOT IN, DISTINCT vs GROUP BY, Correlated subqueries)

#### `references-common_pitfalls.md`
- TRY-CATCH missing
- Implicit column ordering
- Long transactions
- NOLOCK risks
- Cursor-based processing
- Functions in WHERE
- Missing indexes
- SQL injection

#### `references-partitioning_strategy.md`
- Date-based partitioning
- Partition elimination
- Sliding window maintenance
- RANGE RIGHT/LEFT
- Monitoring

#### `references-sql_server_2019_features.md`
- JSON (OPENJSON, FOR JSON)
- Temporal Tables
- Graph Tables
- STRING_AGG
- Intelligent Query Processing
- APPROX_COUNT_DISTINCT
- DROP IF EXISTS
- UTF-8 Collation
- Resumable Index Operations

#### `references-transaction_management.md`
- ACID properties
- Isolation levels (READ UNCOMMITTED, READ COMMITTED, REPEATABLE READ, SERIALIZABLE, SNAPSHOT)
- TRY-CATCH structure
- Nested transactions + SAVEPOINT
- XACT_STATE
- Deadlock prevention
- Error handling

#### `references-concurrency_blocking.md`
- Lock types (Shared, Exclusive, Intent)
- Blocking chains
- Deadlock analysis
- Isolation levels
- Snapshot isolation
- DMV queries

#### `references-etl_migration_patterns.md`
- Incremental loads
- MERGE vs UPDATE+INSERT
- Staging tables
- Data cleansing
- BULK INSERT
- BCP

#### `references-auditing_guide.md`
- Change tracking
- Shadow columns
- Temporal Tables
- Soft delete
- User traceability
- Immutable audit

#### `references-index_design_guidelines.md`
- Clustered vs nonclustered
- Covering indexes
- Filtered indexes
- Index maintenance
- Statistics

#### `references-data_modeling.md`
- OLTP (normalized, row-store)
- OLAP (dimensional, star schema)
- Fact/Dimension tables
- Slowly Changing Dimensions
- Staging layers

#### `references-dynamic_sql_patterns.md`
- Parameterized queries (sp_executesql)
- SQL injection prevention
- Special character handling

#### `references-ha_disaster_recovery.md`
- Always On Availability Groups
- Log Shipping
- Backup strategies
- RTO/RPO planning
- Failover procedures

#### `references-architecture_review.md`
- Normalization levels
- Anti-patterns
- Scalability
- Key design
- Constraint evaluation

#### `references-best_practices.md`
- General SQL Server best practices
- Code standards
- Security guidelines

#### `references-observability_diagnostics.md`
- Extended Events
- Wait statistics
- Memory grants
- Spinlocks
- Resource Governor
- Performance monitoring

---

### Por Patrón

#### `patterns-soft_delete_patterns.md`
- IsDeleted flag
- Archival strategies
- Temporal Tables
- Compliance (GDPR, HIPAA)

#### `patterns-audit_trail_patterns.md`
- Who/when/what tracking
- User traceability
- Immutable audit
- Cryptographic signatures

#### `patterns-upsert_patterns.md`
- UPDATE + INSERT (preferred)
- MERGE (caution)
- Duplicate handling
- Source data quality

#### `patterns-inventory_patterns.md`
- Negative stock prevention
- Reservations/backorders
- Concurrent transactions
- Reconciliation

#### `patterns-financial_integrity.md`
- Double-entry bookkeeping
- Reconciliation queries
- Accounting balances
- Validation rules

#### `patterns-etl_incremental.md`
- CDC (Change Data Capture)
- Timestamp-based detection
- Watermark approaches
- Hybrid strategies

#### `patterns-multi_tenant_isolation.md`
- Row-level security
- Tenant filtering
- Billing accuracy
- Data isolation

#### `patterns-hierarchical_data.md`
- Trees (categories)
- Materialized paths
- Nested sets
- Adjacency lists
- Graph Tables

---

### Por Script

#### `scripts-analyze_execution_plan.sql`
- 10 DMV queries para diagnosticar performance
- Scan vs seek analysis
- Index statistics
- Query costs

#### `scripts-deadlock_analyzer.sql`
- 15 queries para concurrency issues
- Blocking chains
- Deadlock detection
- Lock waits

#### `scripts-find_missing_indexes.sql`
- 7 queries para index analysis
- Unused indexes
- Missing index recommendations

#### `scripts-generate_table_documentation.sql`
- 10 queries para schema documentation
- Column definitions
- Constraints
- Keys

#### `scripts-performance_baseline.sql`
- 15 queries para performance metrics
- Execution times
- I/O statistics
- CPU usage

---

### Por Testing

#### `testing-data_validation_tests.md`
- Constraint testing (NOT NULL, FK, CHECK)
- Null checks
- Referential integrity
- Data quality

#### `testing-unit_testing_tsqlt.md`
- tSQLt framework
- Test setup/teardown
- Assertions
- Fixtures
- Mocking

#### `testing-performance_baseline_testing.md`
- Captura de baselines
- Trend analysis
- Regression detection
- CI/CD integration

#### `testing-regression_testing.md`
- Setup/teardown
- Before/after comparison
- Side effect detection
- Blocking tests
- Automated suite

---

## 🔗 CÓMO USAR ESTE ÍNDICE

1. **Busca tu problema** en la tabla de navegación rápida arriba
2. **Sigue la fila** para ver: Skill Capability, References, Scripts, Patterns, Testing
3. **Lee en este orden:**
   - Referencia (qué/cómo)
   - Script (diagnosticar)
   - Patrón (implementar)
   - Testing (validar)
4. **Ten siempre a mano:** `sql-server-expert-SKILL-CORRECTED.md` para contexto completo

---

## ⚡ ACCESO DIRECTO POR CAPABILITY

| # | Capability | Problema Típico | Referencia Clave | Script |
|----|-----------|-----------------|------------------|--------|
| 1 | Query Optimization | Query lenta | query_patterns.md | analyze_execution_plan.sql |
| 2 | Execution Plan Analysis | Slow scan | analyze_execution_plan.sql | analyze_execution_plan.sql |
| 3 | Index Strategy | Missing indexes | index_design_guidelines.md | find_missing_indexes.sql |
| 4 | DDL Generation | Crear tabla | - | - |
| 5 | Stored Procedures | Escribir proc | - | - |
| 6 | Query Debugging | Query error | common_pitfalls.md | analyze_execution_plan.sql |
| 7 | Window Functions | Ranking/totals | query_patterns.md | - |
| 8 | Query Hints | Forzar plan | query_patterns.md | - |
| 9 | Partitioning | Tabla grande | partitioning_strategy.md | - |
| 10 | Replication/CDC | Sync incremental | etl_migration_patterns.md | - |
| 11 | Security RBAC | Permisos/roles | best_practices.md | - |
| 12 | Tempdb Optimization | Tempdb contention | best_practices.md | performance_baseline.sql |
| 13 | Dynamic SQL | SQL seguro | dynamic_sql_patterns.md | - |
| 14 | Query Store | Performance regression | query_patterns.md | performance_baseline.sql |
| 15 | SQL 2019+ Features | JSON/Temporal | sql_server_2019_features.md | - |
| 16 | Locking & Blocking | Deadlock | concurrency_blocking.md | deadlock_analyzer.sql |
| 17 | JSON Processing | Parse JSON | sql_server_2019_features.md | - |
| 18 | ETL & Migration | Sync datos | etl_migration_patterns.md | - |
| 19 | Transaction Management | Txn locks | transaction_management.md | - |
| 20 | Auditing | Track cambios | auditing_guide.md | - |
| 21 | Architecture Review | Review schema | architecture_review.md | generate_table_documentation.sql |
| 22 | Financial Integrity | Audit-proof | financial_integrity.md | - |
| 23 | HA/DR | 24/7 uptime | ha_disaster_recovery.md | - |
| 24 | Observability | Monitor DB | observability_diagnostics.md | - |
| 25 | Data Modeling | Diseñar DB | data_modeling.md | generate_table_documentation.sql |

---

**Última actualización:** 2026-06-02  
**Skill asociada:** `sql-server-expert-SKILL-CORRECTED.md`
