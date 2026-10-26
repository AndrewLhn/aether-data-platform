# ADR-005: Object store and Iceberg catalog for the lakehouse

- **Status:** Accepted
- **Date:** 2026-10-26
- **Decision makers:** Aether project maintainers
- **Supersedes:** the storage choice implied by [ADR-003](ADR-003-iceberg-lakehouse.md), which deferred the catalog to "the local runtime design". ADR-003 remains accepted for the table format.

## Context

ADR-003 chose Apache Iceberg and named MinIO/S3-compatible object storage, leaving the catalog implementation open. Two things changed since.

**MinIO Community Edition ended.** The `minio/minio` repository was archived on 2026-02-13 and marked "no longer maintained"; the image is no longer served by Docker Hub. Its admin console had already been reduced to an object browser in June 2025. Building a new platform on it means pinning a digest for software with no security patches, and explaining that choice to every reviewer.

**The catalog choice turned out to be constrained by the runtime, not by preference.** Implementing the streaming slice showed that `iceberg-flink-runtime` ships no `org/apache/hadoop` classes at all — Iceberg declares Hadoop as `provided` — while every catalog implementation builds a Hadoop `Configuration` during initialization. `HadoopCatalog`, `JdbcCatalog` and `RESTCatalog` all fail identically with `ClassNotFoundException: org.apache.hadoop.conf.Configuration` unless Hadoop client JARs are supplied. The catalog decision therefore could not be made on commit semantics alone; it had to be made together with a dependency decision.

Separately, `HadoopCatalog` commits by renaming a version-hint file. On an object store a rename is neither atomic nor cheap, so concurrent writers can lose commits. That rules it out for a platform whose stated subject is correctness.

## Decision

Run **SeaweedFS** as the local S3-compatible object store, and use an Iceberg **`JdbcCatalog`** backed by the PostgreSQL the stack already runs.

Both are held behind configuration rather than baked into the pipeline:

- Flink and Iceberg only ever read `S3_ENDPOINT_INTERNAL`, so the object store is swappable without touching SQL or the image;
- the catalog is declared once, in `services/streaming/sql/pipeline.sql.in`, with `catalog-impl` named explicitly.

Supporting dependency choices, recorded because each was verified rather than assumed:

- `hadoop-client-api` **and** `hadoop-client-runtime` 3.4.2, the pairing Apache Iceberg itself uses in `docker/iceberg-flink-quickstart`, at the same version. `hadoop-client-api` carries the unrelocated public classes; `hadoop-client-runtime` carries their shaded implementations. Neither is sufficient alone, and `hadoop-client-runtime` on its own is a trap: every one of its classes sits under `org/apache/hadoop/shaded` or `/thirdparty`, so it looks correct and provides nothing Iceberg can bind to.
- A Java 17 Flink base image. Iceberg moved its baseline to JDK 17, so `iceberg-flink-runtime-1.20` carries class file version 61 bytecode and cannot be loaded by a Java 11 runtime. `scripts/check-java-requirement.py` measures this from bytecode and fails if the two drift apart.

## Consequences

### Positive

- One process serves both the S3 API and the storage, so the local stack gains a lakehouse without gaining a service.
- Apache-2.0 licensed and actively released, so it can be adopted without a licensing conversation.
- Catalog commits are database transactions, which is the commit guarantee the platform claims.
- SeaweedFS also ships a built-in Iceberg REST catalog on port 8181 with OAuth2 client credentials, so migrating to a REST catalog later is a `CREATE CATALOG` change and not a pipeline change.
- Because the store is reachable only through `S3_ENDPOINT_INTERNAL`, the choice stays reversible.

### Negative / risks

- The lakehouse catalog now depends on the transactional database. Acceptable for a single-node local stack; it is the wrong shape for production, where a REST catalog is the successor.
- `JdbcCatalog` does not support views in this configuration, and says so on every start unless `jdbc.schema-version=V1` is set.
- SeaweedFS is less widely deployed than MinIO was, so fewer operators have seen it. The S3 API is the contract, which limits how much that matters.
- Hadoop client JARs add roughly 50 MB to the resolved library set, and a classpath that mixes Hadoop with Flink is a known source of conflicts. So far the only symptom is a benign credential-provider stack trace at startup.
- Millisecond precision: Debezium emits microseconds and the pipeline declares `TIMESTAMP_LTZ(3)`, so three digits are dropped. Preserving them needs `TIMESTAMP_LTZ(6)` plus `time.precision.mode=adaptive_time_microseconds`.

## Alternatives considered

### Object store

- **MinIO at a pinned digest:** instantly recognizable, and the one reviewers will not need introduced. Rejected because the archive date is public and recent; "we pinned it" answers the availability question and not the maintenance one.
- **RustFS:** actively developed, MinIO-shaped, Apache-2.0. Rejected on maturity — the published tags are pre-release (`1.0.4-preview`), which is a poor fit for a project meant to be cloned and run by a stranger.
- **LocalStack:** already in the compose file at the time, and its S3 emulation works. Rejected because it needs an auth token for current releases, the image is several times larger, and "an AWS emulator" is a weaker story than "an object store" for a lakehouse.
- **SeaweedFS:** chosen. Actively released, Apache-2.0, one process, S3 plus an optional Iceberg REST catalog.

### Catalog

- **HadoopCatalog:** no extra service, and the Iceberg quickstart uses it. Rejected on commit atomicity over object storage, and it needs the same Hadoop JARs anyway.
- **REST catalog via SeaweedFS:** the strongest production-shaped option and the likely successor. Not chosen now because it uses S3 Table Buckets and OAuth2, and Flink is absent from SeaweedFS's published integration list — an unverified path for the first slice that has to run.
- **Standalone REST server (Polaris, Lakekeeper, Gravitino):** the most production-faithful, and the most machinery. Rejected for the local stack: another service, another image, another configuration surface, before the first end-to-end write had ever succeeded.
- **JdbcCatalog:** chosen. Needs only a JDBC driver, commits transactionally, and reuses a database already in the stack.
