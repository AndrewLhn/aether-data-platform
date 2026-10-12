# ADR-002: Use Apache Flink for stateful stream processing

- **Status:** Accepted
- **Date:** 2026-10-12
- **Decision makers:** Aether project maintainers

## Context

The platform must handle event time, late data, keyed state, checkpoint-based fault recovery, and deterministic replay/reconciliation. Simple stateless consumers would not demonstrate the required reliability behavior.

## Decision

Use Apache Flink as the primary stream-processing runtime. Jobs will consume Kafka topics, validate/enrich events, maintain only explicitly bounded state, checkpoint to durable storage, and write curated data through a checkpoint-aware Iceberg sink.

## Consequences

### Positive

- Mature keyed state, event-time windows, watermarks, and checkpoint/restart model.
- A strong fit for proving failure recovery rather than treating it as a theoretical feature.
- Compatible connectors for Kafka and Iceberg support the target vertical slice.

### Negative / risks

- Stateful jobs need disciplined state schema evolution, savepoints/checkpoints, and operator training.
- Correctness depends on sink integration and configuration; Flink alone does not make every path exactly-once.
- Local development and CI require non-trivial integration testing.

## Alternatives considered

- **Kafka Streams:** simpler embedded application model, but less suitable for the intended breadth of event-time/stateful operations and lakehouse demonstration.
- **Spark Structured Streaming:** strong ecosystem option, but Flink more directly emphasizes continuous state and checkpoint recovery for this project.
- **Custom consumers:** low initial complexity but would recreate difficult state/recovery problems poorly.
