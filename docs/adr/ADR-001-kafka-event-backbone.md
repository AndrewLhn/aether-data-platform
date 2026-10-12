# ADR-001: Use Apache Kafka as the event backbone

- **Status:** Accepted
- **Date:** 2026-10-12
- **Decision makers:** Aether project maintainers

## Context

Aether needs a durable buffer between operational producers and consumers, partition-local ordering, consumer decoupling, a bounded replay window, and observable delivery positions. CDC events may burst; the lakehouse and stream processor must not directly dictate availability of the source database.

## Decision

Use Apache Kafka as the central event backbone. Debezium and API ingestion adapters publish versioned event topics. Partition keys will be chosen by ordering domain (for example, `order_id` for order lifecycle records). Retention, compaction, partition counts, and topic ACLs will be configured explicitly as implementation proceeds.

## Consequences

### Positive

- Consumers evolve independently and can recover from stored offsets.
- Kafka provides durable backpressure isolation and topic-level observability.
- Partition offsets give a concrete unit for audit and bounded replay.

### Negative / risks

- Kafka adds cluster, topic, and schema-governance operations.
- It does not provide a global order, cross-topic transaction semantics, or automatic business deduplication.
- Replay is limited by retention; longer-term recovery requires object-store archives or source re-extraction.

## Alternatives considered

- **Direct PostgreSQL-to-Iceberg ingestion:** fewer components, but no durable decoupling/replay boundary and poor support for multiple consumers.
- **Managed queue only:** may reduce operations, but the project seeks explicit partition, offset, and streaming semantics; deployment portability would also narrow.
- **Pulsar:** viable architecture, but Kafka has stronger alignment with Debezium/Flink ecosystem familiarity for this portfolio project.
