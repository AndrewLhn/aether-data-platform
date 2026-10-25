# Aether use cases

## Domain and actors

Aether models an e-commerce company whose transactional application writes orders, payments, inventory adjustments, and customer changes to PostgreSQL. Data consumers include finance, operations, and product analytics. Platform engineers operate the pipelines; data engineers own transformations and data products.

The initial scope is a learning and portfolio environment, not a production service handling real personal or card data. Synthetic identifiers and masked payloads are mandatory in demos.

---

## UC-01 — Near-real-time order and payment analytics

**Goal:** Make completed orders, payment outcomes, and gross merchandise value available to analytics with predictable latency and guaranteed lineage.

### Workflow
1. An application transaction creates or updates an order and its payment status in PostgreSQL.
2. Debezium captures the change from the WAL (Write-Ahead Log) and emits a versioned event to a Kafka topic.
3. Flink consumes the stream, applying:
    - **Schema Validation:** Ensures the event conforms to the registered contract.
    - **Stateful Enrichment:** Joins events with reference data (e.g., customer segments) stored in Flink state.
    - **Watermarking:** Handles out-of-order events using a bounded-out-of-orderness strategy to ensure window correctness.
4. The processed stream is materialized into Apache Iceberg tables using the Iceberg Flink Sink.
5. Trino and dbt expose governed analytical models over the Iceberg snapshots.

### Technical Specifications & Guarantees
- **Delivery Semantics:** End-to-end *at-least-once* by default, upgrading to *exactly-once* for financial metrics via Flink's Two-Phase Commit (2PC) sink to Iceberg.
- **Latency Target:** Event-to-Lakehouse latency $< 5$ minutes (NFR-001).
- **Lineage:** Every record in Iceberg must carry metadata: `source_ts`, `kafka_offset`, `flink_checkpoint_id`, and `event_version`.

### Failure Modes & Edge Cases
- **Late Arrivals:** Events arriving after the watermark boundary are routed to a "late-events" side-output for manual reconciliation (UC-04).
- **Schema Mismatch:** Events failing validation are sent to a Dead Letter Queue (DLQ) to prevent pipeline stalls.

---

## UC-02 — Stream processor failure and safe continuation

**Goal:** Recover from an unexpected Flink task failure without losing or double-counting business facts.

### Workflow
1. A Flink task fails (e.g., OOM, Node failure).
2. Flink restores state (window contents, offsets) and source positions from the last successful checkpoint in the distributed storage.
3. The Iceberg sink leverages its commit protocol: only data associated with a *completed* Flink checkpoint is committed as a new snapshot in Iceberg.
4. The Recovery Engine observes the failure via Flink's JobManager API and triggers a reconciliation check for the window covered by the failed checkpoint.

### Technical Specifications & Guarantees
- **Consistency:** No partial checkpoints are visible to Trino queries.
- **Recovery Time Objective (RTO):** Job restart and state recovery $< 10$ minutes.
- **State Backend:** RocksDB for incremental checkpoints to handle large state sizes.

### Failure Modes & Edge Cases
- **Checkpoint Corruption:** If the last checkpoint is corrupted, the system rolls back to the previous valid checkpoint, triggering a re-process of the data range (idempotency required).

---

## UC-03 — Correct a transformation with a bounded historical replay

**Goal:** Recompute a derived dataset after a defect or business-rule change without disturbing unrelated data.

### Workflow
1. An operator defines a **Replay Scope**: `(source_topic, start_offset/timestamp, end_offset/timestamp, target_table, transformation_version)`.
2. The Recovery Engine creates an immutable `ReplayJob` record and validates that the target table supports versioning.
3. The replay executes into a **Shadow Table** (cloned Iceberg table) to avoid mutating production data.
4. **Deterministic Identity:** Every record is written using a composite key `(source_event_id, transformation_version)` to ensure idempotency.
5. A reconciliation process compares the Shadow Table against the Production Table for the specific scope.
6. Upon approval, a metadata swap or `REPLACE` operation promotes the corrected snapshot to production.

### Technical Specifications & Guarantees
- **Isolation:** Zero impact on the real-time data plane during replay.
- **Auditability:** Every replay is linked to a Jira/Ticket ID and an operator signature.

### Failure Modes & Edge Cases
- **Resource Contention:** Replay jobs are assigned lower priority/resources to prevent starving the real-time pipeline.

---

## UC-04 — Detect and reconcile a data gap

**Goal:** Find and fix divergences caused by connector downtime, retention pressure, or malformed events.

### Workflow
1. **Scheduled Audit:** The Recovery Engine performs a "lightweight" reconciliation:
    - Compares record counts between PostgreSQL (source) and Iceberg (sink) for a specific time bucket.
    - Validates watermark continuity in Kafka.
2. **Deep Inspection:** If a mismatch is found, the engine computes a hash-based checksum of primary keys for the affected window.
3. **Incident Creation:** A gap is logged with the exact missing `event_ids`.
4. **Resolution:** The operator chooses:
    - `REPLAY`: Trigger UC-03 for the missing range.
    - `IGNORE`: Accept the gap as a known loss (logged as an exception).

### Technical Specifications & Guarantees
- **Optimization:** Uses Trino's distributed compute to perform counts and checksums over Iceberg, minimizing data movement.
- **Coverage:** Ensures 100% of committed source transactions are accounted for in the lakehouse.

---

## UC-05 — Evolve an event contract safely

**Goal:** Allow producer evolution while protecting existing consumers and historical datasets.

### Workflow
1. **Proposal:** A producer proposes a schema change (e.g., adding `discount_code` to `orders`).
2. **Compatibility Check:** A CI gate checks the new schema against the Schema Registry using **Backward Compatibility** rules (new fields must be optional).
3. **Version Tagging:** Every Kafka message is tagged with a `schema_id`.
4. **Consumer Adaptation:** Flink uses a "Schema-on-Read" approach:
    - Known versions are mapped to the internal POJO.
    - Unknown/New versions are handled via a generic `metadata` map to prevent crashes.
5. **Migration:** Historical data is either left as-is (handled by dbt's `COALESCE`) or updated via a targeted replay (UC-03).

### Technical Specifications & Guarantees
- **Registry:** Centralized schema management (e.g., Confluent Schema Registry or similar).
- **Breaking Changes:** Any change violating backward compatibility requires a major version bump and a new Kafka topic.

---

## Out of scope for the first release

- Multi-region active-active replication.
- Processing of raw payment card data or production personal data.
- Generic workflow orchestration for arbitrary teams.
- A self-service UI beyond a minimal operator API/CLI.
- An assertion that every sink or path is exactly-once without a corresponding implementation and test.
