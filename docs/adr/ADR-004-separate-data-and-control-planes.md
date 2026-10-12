# ADR-004: Separate the data and control planes

- **Status:** Accepted
- **Date:** 2026-10-12
- **Decision makers:** Aether project maintainers

## Context

Continuous event delivery must remain reliable during operational investigation. Recovery, replay approvals, reconciliation, incident recording, and audit queries have different latency, authorization, and failure characteristics from normal record processing. Embedding them inside a stream job would make corrective operations opaque and could turn a control-service outage into a data outage.

## Decision

Operate the Kafka-to-Flink-to-Iceberg path as a data plane. Implement the Recovery Engine as a separate control plane that observes pipeline metadata, stores immutable operational records, orchestrates bounded replay and reconciliation, and exposes operator workflows. The control plane may request actions but must not synchronously gate normal data-plane writes.

## Consequences

### Positive

- Recovery is governed, inspectable, and auditable.
- Control-plane faults do not inherently stop data delivery.
- The architecture makes ownership and security boundaries explicit.

### Negative / risks

- The system has an additional service, persistence model, and integration contracts.
- Observation is eventually consistent; dashboards cannot be mistaken for the data path itself.
- Command idempotency, authorization, and audit storage become first-class requirements.

## Alternatives considered

- **Embed replay/reconciliation inside each Flink job:** fewer services, but inconsistent operator experience and unsafe coupling to business transformation code.
- **Manual scripts only:** quick initially, but weak auditability, reproducibility, authorization, and portfolio value.
- **Fully synchronous orchestration gateway:** centralized control, but it creates an avoidable availability dependency in the data path.
