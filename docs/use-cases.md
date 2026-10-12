# Aether use cases

## Domain and actors

Aether models an e-commerce company whose transactional application writes orders, payments, inventory adjustments, and customer changes to PostgreSQL. Data consumers include finance, operations, and product analytics. Platform engineers operate the pipelines; data engineers own transformations and data products.

The initial scope is a learning and portfolio environment, not a production service handling real personal or card data. Synthetic identifiers and masked payloads are mandatory in demos.

## UC-01 — Near-real-time order and payment analytics

**Goal:** make completed orders, payment outcomes, and gross merchandise value available to analytics with predictable latency.

1. An application transaction creates or updates an order and its payment status in PostgreSQL.
2. Debezium emits the committed database change to a versioned Kafka topic.
3. Flink validates the event, enriches it with reference data, and materializes an Iceberg fact table.
4. Trino and dbt expose governed analytical models.

**Success criteria:** a committed valid source change is traceable through source position, Kafka offset, Flink checkpoint, and Iceberg snapshot; the latency target is evaluated against NFR-001.

## UC-02 — Stream processor failure and safe continuation

**Goal:** recover from an unexpected Flink task failure without losing or double-counting business facts.

1. A Flink task fails after consuming records.
2. Flink restores state and source positions from its latest successful checkpoint.
3. The job resumes; the Iceberg sink commits only consistent checkpoints.
4. The Recovery Engine records the incident and runs a reconciliation window.

**Success criteria:** the final Iceberg result contains one logical record per source event identity and the reconciliation report is retained. A user-facing metric is not assumed to be exactly-once until the relevant end-to-end test proves it.

## UC-03 — Correct a transformation with a bounded historical replay

**Goal:** recompute a derived dataset after a defect or business-rule change without disturbing unrelated data.

1. An operator declares the source topic/table range, target data product, transformation version, and reason.
2. The Recovery Engine validates authorization and records an immutable replay request.
3. The replay executes into a staging or versioned target, using deterministic event identities.
4. Reconciliation compares the replayed range with the source-of-record expectations.
5. An approved promotion makes the new Iceberg snapshot or table version available.

**Success criteria:** the operation has a stable run ID, bounded scope, audit trail, and verifiable comparison result. It never mutates production data silently.

## UC-04 — Detect and reconcile a data gap

**Goal:** find a divergence caused by connector downtime, retention pressure, malformed events, or a downstream incident.

1. Scheduled reconciliation computes counts, distinct event identities, and watermark coverage for a time window.
2. A mismatch creates an incident with the affected topic partitions and target table snapshots.
3. An operator inspects evidence and chooses retry, replay, quarantine, or an accepted exception.
4. A follow-up reconciliation verifies the resolution.

**Success criteria:** every mismatch is actionable and queryable; a resolved incident links to the corrective run and post-resolution evidence.

## UC-05 — Evolve an event contract safely

**Goal:** allow producer evolution while protecting existing consumers and historical datasets.

1. A producer proposes a versioned schema and compatibility declaration.
2. CI validates structural compatibility and required metadata.
3. Consumers are upgraded or a compatibility path is explicitly approved.
4. The schema version travels with every event and is available in lineage metadata.

**Success criteria:** incompatible changes are rejected before deployment, and supported versions have a documented deprecation window.

## Out of scope for the first release

- Multi-region active-active replication.
- Processing of raw payment card data or production personal data.
- Generic workflow orchestration for arbitrary teams.
- A self-service UI beyond a minimal operator API/CLI.
- An assertion that every sink or path is exactly-once without a corresponding implementation and test.
