# ADR-003: Use Apache Iceberg for lakehouse tables

- **Status:** Accepted
- **Date:** 2026-10-12
- **Decision makers:** Aether project maintainers

## Context

The analytical store must support large immutable files with transactional table visibility, schema/partition evolution, snapshots for audit and rollback, and interoperable access from Flink, Trino, and dbt workflows. Plain files do not provide enough table-level control for safe reprocessing.

## Decision

Use Apache Iceberg tables on MinIO/S3-compatible object storage. A catalog implementation will be selected with the local runtime design. Curated outputs and controlled replay results will use Iceberg snapshots and explicit version/promotion practices.

## Consequences

### Positive

- Snapshot isolation and atomic metadata commits support reproducible analytical reads.
- Time travel and schema/partition evolution support audits and correction workflows.
- Broad engine support enables Flink writes and Trino/dbt consumption without copying datasets.

### Negative / risks

- Catalog, object-store, and engine compatibility must be tested together.
- Snapshot/file maintenance is an operational responsibility.
- Iceberg protects table commits, but does not replace event identity or business-level reconciliation.

## Alternatives considered

- **Plain Parquet on object storage:** simple, but lacks managed transactional tables, snapshots, and safe evolution.
- **Delta Lake:** a strong alternative, but Iceberg offers broad multi-engine interoperability aligned with the selected Trino/Flink stack.
- **Warehouse-only destination:** reduces lakehouse operations but limits replay/time-travel portability and storage transparency.
