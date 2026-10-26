# Aether Data Platform — Project Status

Working notes for anyone picking this up, human or agent. Kept honest on purpose: a status file that claims more than the repository does is worse than no status file, and this one was wrong once already.

## Current stage: Phase 1 — data plane, first slice running

### Done and verified by an actual run

- **Architecture baseline:** `docs/use-cases.md` and `docs/architecture.md` at senior+ depth — delivery semantics, 2PC, recovery patterns.
- **Local infrastructure:** PostgreSQL 17 with logical decoding, Kafka 4.2 in KRaft mode, Debezium 3.7 Connect, SeaweedFS as the S3-compatible store, Flink 1.20.5 on Java 17.
- **CDC slice:** connector registered from a versioned config; `make verify-cdc` proves PostgreSQL to Kafka with a freshly inserted order.
- **Streaming slice:** `make pipeline` submits `services/streaming/sql/pipeline.sql.in` through SQL Client. Verified end to end — job `RUNNING` with 3/3 tasks, checkpoint 1 completed, Iceberg snapshot `9046756570855116756` committed with 3 records, metadata written to `s3://aether-lakehouse`.
- **Operator surface:** `make help` lists every target. `libs`, `env`, `build`, `up`, `down`, `ps`, `verify-cdc`, `verify-stream`, `jobs`, `cancel-jobs`, `pipeline`, `sql-client`, `doctor`, `lint`, `reset`.
- **Static gates:** compose portability and env coverage, `libs.lock` structure, JVM requirement measured from bytecode, shell and JSON syntax. All wired into `make lint`.

### Not done

- **Recovery Engine and reconciliation** — Phase 2. `services/recovery/` is a placeholder.
- **`verify-lakehouse.sh`** — an assertive end-to-end test. `verify-stream` reports and always exits 0; it does not yet pass or fail on its own, so nothing in CI proves the pipeline works.
- **CI runs no integration test.** `.github/workflows/infrastructure.yml` checks syntax and `docker compose config`, neither of which would have caught any defect found while bringing this up.
- **Trino, dbt, Airflow, observability** — design only. `dbt/`, `orchestration/`, `services/ingestion/` are placeholders.
- **Schema Registry and DLQ** — described in `docs/architecture.md`, not implemented. The CDC contract is currently enforced by prose in `infra/docker/connectors/README.md`.
- **Secrets appear in the `pipeline-submit` log.** SQL Client echoes `CREATE CATALOG` before execution, including `jdbc.password` and `s3.secret-access-key`. Local-only values, still worth fixing.
- **Known benign warnings** are listed in `docs/local-development.md`. Do not "fix" the s3a credential-provider stack trace without a way to test it; checkpoints commit fine as-is.

## Decisions that are easy to undo by accident

- **JARs are resolved, never committed.** `infra/docker/flink/libs.lock` holds digest, target and URL; `scripts/download-flink-libs.sh` verifies before use. Do not add `*.jar` to git and do not relax `.gitignore` for them.
- **They are symlinked into `/opt/flink/lib` at container start** by `prepare-runtime.sh`. Mounting onto `lib` directly would hide the base image's JARs. Leaving them in `/opt/flink/usrlib` does not work: SQL Client does not put `usrlib` on its classpath, and the failure is `Could not find any factory for identifier 'iceberg'`.
- **The base image must be a `java17` variant.** Iceberg's baseline is JDK 17. Run `make verify-java` after any dependency bump.
- **`hadoop-client-api` and `hadoop-client-runtime` are both required**, at the pairing Apache Iceberg uses in its own quickstart. `hadoop-client-runtime` alone relocates everything under `org/apache/hadoop/shaded` and provides nothing Iceberg can bind to.
- **The CDC data contract is three properties**, all load-bearing: `decimal.handling.mode: string`, `tombstones.on.delete: false`, and RFC 3339 timestamps read as ISO-8601 into `TIMESTAMP_LTZ`. Changing one changes what the reader must expect, and it is not retroactive for records already in a topic.
- **`pipeline-submit` is behind a compose profile.** Removing the profile makes every `compose up` submit another writer into the same table. Two writers do not fail; they both commit.
- **ADRs are immutable.** ADR-003 still says MinIO because that was the decision at the time; ADR-005 supersedes the storage and catalog choices. Do not edit an accepted ADR's decision text.

## Environment

| Service | Host port | In-network name |
|---|---|---|
| PostgreSQL | 5432 | `postgres` |
| Kafka | 9092 | `kafka:19092` |
| Kafka Connect | 8083 | `connect` |
| Flink UI / REST | 8081 | `flink-jobmanager:8081` |
| SeaweedFS S3 | 8333 | `seaweedfs:8333` |

Pinned versions: Flink 1.20.5, Iceberg 1.12.0, Kafka 4.2.2, Debezium 3.7, PostgreSQL 17.11, SeaweedFS 4.50, PostgreSQL JDBC 42.7.14, Hadoop client 3.4.2.
