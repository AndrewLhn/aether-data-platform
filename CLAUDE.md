# Aether Data Platform - Project Status

## Current Stage: Phase 1 - Foundation & Data Plane (In Progress)

### Completed
- [x] **Architectural Blueprint**: Detailed `docs/use-cases.md` and `docs/architecture.md` to Senior+ standards (exactly-once semantics, 2PC, recovery patterns).
- [x] **Core Infrastructure**: 
    - PostgreSQL (Logical Decoding enabled)
    - Apache Kafka (KRaft mode)
    - Debezium Connect (JSON with Schemas enabled)
    - LocalStack (S3 for Lakehouse storage)
    - Apache Flink (Custom build with Kafka/Iceberg connectors)
- [x] **CDC Pipeline**: Debezium connector successfully registered; data flowing from Postgres to Kafka.
- [x] **Stream Pipeline (Code)**: PyFlink pipeline implemented in `services/streaming/pipeline.py` to move data from Kafka to Iceberg.

### Next Steps
- [ ] **Pipeline Execution**: Run `pipeline.py` and verify end-to-end flow (Postgres -> Kafka -> Flink -> Iceberg).
- [ ] **Verification**: Check Iceberg table snapshots in LocalStack S3.
- [ ] **Phase 2**: Implement the Recovery Engine and Reconciliation logic.

## Technical Debt & Notes
- **Flink Dependencies**: Resolved via local volume mapping (`infra/docker/libs`) due to Maven Central path inconsistencies.
- **LocalStack**: Used as a replacement for MinIO to avoid registry authorization issues.
- **PyFlink**: Adopted over SQL Client for better dependency management and flexibility.

## Environment Details
- **Postgres**: Port 5432
- **Kafka**: Port 9092
- **Connect**: Port 8083
- **Flink UI**: Port 8081
- **S3 (LocalStack)**: Port 4566
