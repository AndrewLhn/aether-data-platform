# Requirements

## Measurement conventions

The thresholds below are **initial engineering targets**, not verified service-level agreements. Each must be measured in a repeatable integration or operational test before it is represented as achieved. Time-based requirements use UTC event timestamps and defined test load; data volumes are synthetic until a representative workload generator exists.

## Functional requirements

| ID | Requirement | Acceptance evidence | Priority |
|---|---|---|---|
| FR-001 | Ingest committed `orders`, `payments`, `inventory`, and `customers` PostgreSQL changes using CDC. | Integration test performs inserts, updates, and deletes; each committed change appears in its mapped Kafka topic with source metadata. | Must |
| FR-002 | Ingest configured REST API data with idempotent polling or cursor semantics. | Test repeats a poll and proves no duplicate logical records are written; cursor state is persisted. | Should |
| FR-003 | Publish data-plane events to versioned Kafka topics with an event ID, event time, source position, schema version, and correlation metadata. | Contract test rejects an event missing any required envelope field. | Must |
| FR-004 | Validate events against versioned data contracts before business transformation. | Compatibility test accepts supported evolution and rejects a documented incompatible change. | Must |
| FR-005 | Transform valid events with Flink and write curated analytical data to Iceberg. | End-to-end test traces a fixture event from Kafka to an Iceberg row with lineage fields. | Must |
| FR-006 | Preserve a stable logical event identity so re-delivery or replay does not create duplicate business facts. | Fault-injection/replay test delivers the same event more than once and asserts one logical output record. | Must |
| FR-007 | Restore stream processing from a successful checkpoint after an injected worker failure. | Test terminates a task, restores it, and verifies source positions and state against expected output. | Must |
| FR-008 | Persist raw or recoverable event history in object storage with defined retention metadata. | Test locates a source range by partition/offset or time and verifies immutable object metadata. | Should |
| FR-009 | Execute a bounded, approved replay with request ID, source range, transformation version, operator identity, and outcome. | Integration test creates a replay request and verifies all audit attributes and its deterministic target result. | Must |
| FR-010 | Reconcile configurable windows across source, Kafka, and Iceberg using counts, distinct IDs, and watermark coverage. | Seeded gap/duplicate tests yield a machine-readable mismatch report with affected scope. | Must |
| FR-011 | Quarantine invalid or non-processable events without blocking unrelated partitions. | Test sends an invalid fixture and verifies dead-letter/quarantine evidence plus continued processing of a valid fixture. | Should |
| FR-012 | Expose data-product tables through Trino and dbt models with tests for key uniqueness and accepted values. | CI runs dbt tests and a query against the target model. | Should |
| FR-013 | Produce structured audit events for deployment, schema validation, checkpoint recovery, replay, and reconciliation operations. | Test queries audit storage and finds correlated records for each lifecycle operation. | Must |

## Non-functional requirements

| ID | Requirement / target | Measurement method | Priority |
|---|---|---|---|
| NFR-001 | Under the defined baseline load, p95 source-commit-to-curated-table latency should be **≤ 60 seconds**. | Correlate synthetic source commit timestamps with visible Iceberg rows across at least 1,000 events. | Should |
| NFR-002 | A planned or injected single Flink task failure should recover within **≤ 10 minutes** and meet FR-006 after recovery. | Timed fault-injection test from failure detection to healthy checkpoint, plus output comparison. | Must |
| NFR-003 | Reconciliation should identify a seeded missing or duplicate event in a **15-minute** test window within **≤ 30 minutes** of window close. | Record window close and report creation timestamps for seeded defects. | Should |
| NFR-004 | The pipeline shall have no unbounded duplicate growth under at-least-once re-delivery. | Run fixed duplicate fixture N times; output cardinality by logical identity remains one. | Must |
| NFR-005 | Every replay and operator action must be attributable to an authenticated principal and correlated with an immutable request ID. | Authorization and audit integration test; attempt an unauthorized request. | Must |
| NFR-006 | Secrets must not be committed, logged, or placed in images; local defaults must be non-production. | Secret-scanning CI, repository review, and log fixture test. | Must |
| NFR-007 | Contracts, transformations, and infrastructure configuration must be version controlled and reproducible from a clean checkout. | CI provisions the supported local/integration environment without manual file edits. | Must |
| NFR-008 | Platform telemetry must include consumer lag, checkpoint age/duration, records in/out, error/quarantine rate, Iceberg commit failures, replay state, and reconciliation status. | Dashboard/metric-contract test asserts each named signal exists and can be labeled by pipeline. | Must |
| NFR-009 | A component failure in the Recovery Engine must not prevent normal data-plane consumption and Iceberg commits. | Disable control-plane service during integration test; verify data path continues and observations buffer or degrade explicitly. | Must |
| NFR-010 | Design documentation and ADRs must be reviewable in pull requests and checked automatically for Markdown quality and broken internal links. | GitHub Actions workflow passes on a clean checkout; deliberately broken link/lint fixture fails locally or in CI. | Must |

## Assumptions and constraints

- PostgreSQL is the initial CDC source and Kafka is the durable event backbone.
- The local environment uses SeaweedFS as an S3-compatible store; production deployments may use a managed object store. See [ADR-005](adr/ADR-005-object-store-and-iceberg-catalog.md).
- The initial implementation favours a correct, observable single-region baseline over high availability across regions.
- Data contracts will start with a repository-managed schema format; a registry may be added once the producer/consumer workflow needs it.
- Metrics become targets only after the load profile, hardware/runtime, and test evidence are recorded.
