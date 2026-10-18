# Local development

## Purpose and scope

The local stack provides the infrastructure baseline and first end-to-end CDC slice for Aether:

- PostgreSQL 17 configured for logical replication;
- Apache Kafka in single-node KRaft combined mode, with no ZooKeeper;
- Kafka Connect with the Debezium PostgreSQL connector installed;
- MinIO as S3-compatible object storage for the future Iceberg lakehouse.

This is a single-machine development environment. It intentionally uses plaintext Kafka, unauthenticated Kafka Connect, one Kafka broker, and local development credentials. It is not a production deployment.

## Prerequisites

- Docker Desktop or Docker Engine with Docker Compose v2;
- ports `5432`, `8083`, `9000`, `9001`, and `9092` available on the host;
- at least 6 GB of Docker memory for a comfortable local experience.

## Start the stack

From the repository root:

```bash
cp .env.example .env
docker compose --env-file .env -f infra/docker/docker-compose.yml up -d
docker compose --env-file .env -f infra/docker/docker-compose.yml ps
```

Wait until PostgreSQL, Kafka, Kafka Connect, and MinIO all report `healthy`. The first start downloads images, initializes named volumes, and creates the e-commerce schema with seed data.

## Local endpoints

| Service | Host address | Purpose |
|---|---|---|
| PostgreSQL | `localhost:5432` | Transactional source database |
| Kafka | `localhost:9092` | Host-facing Kafka listener |
| Kafka Connect | `http://localhost:8083` | Connector management REST API |
| MinIO API | `http://localhost:9000` | S3-compatible object-storage API |
| MinIO Console | `http://localhost:9001` | Local object-storage console |

Use the values from `.env` for PostgreSQL and MinIO credentials. Do not reuse them outside the local stack.

## Verify the services

```bash
docker compose --env-file .env -f infra/docker/docker-compose.yml exec postgres \
  psql -U aether -d aether -c 'SHOW wal_level;'

docker compose --env-file .env -f infra/docker/docker-compose.yml exec kafka \
  /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka:19092 --list

curl --fail http://localhost:8083/connectors
curl --fail http://localhost:9000/minio/health/live
```

The PostgreSQL command must return `logical`. An empty Kafka topic list and an empty JSON array from Kafka Connect are expected before the ingestion phase registers the first connector.

## E-commerce source schema

PostgreSQL starts with `wal_level=logical`, `max_wal_senders=10`, and `max_replication_slots=10`. Its initialization scripts create a dedicated `debezium` role with replication and read permissions, then create these CDC source tables:

- `customers`
- `orders`
- `payments`
- `inventory`

The initial fixture contains two customers, two orders, one payment, and two inventory records. It is synthetic data only.

The schema also creates `aether_cdc_publication` for precisely these tables. The connector uses this existing publication instead of granting it broad DDL or publication-management privileges.

## Run and verify PostgreSQL CDC

Register the versioned connector configuration:

```bash
./scripts/register-ecommerce-cdc.sh
curl --fail http://localhost:8083/connectors/aether-postgres-cdc/status
```

Run the repeatable end-to-end verification:

```bash
./scripts/verify-ecommerce-cdc.sh
```

The verification starts the stack if needed, registers the connector idempotently, waits for its task to become `RUNNING`, starts a Kafka consumer at the latest offset, and inserts a new `orders` row. It passes only when the consumer output contains that row's unique `external_order_reference` in `aether.public.orders`.

An expected successful final line has this form:

```text
CDC verification passed: cdc-verification-20261018T120000Z was emitted to aether.public.orders.
```

The timestamp changes on every execution. The script intentionally leaves the inserted test order in PostgreSQL so the event trail remains inspectable.

Kafka Connect persists connector configurations, offsets, and statuses in the three `aether.connect.*` internal topics. Broker-side automatic topic creation is disabled; the connector defines its own one-partition, replication-factor-one topic-creation policy for this local single-broker environment.

## Stop and reset

Stop containers while preserving state:

```bash
docker compose --env-file .env -f infra/docker/docker-compose.yml down
```

Delete all local infrastructure state and start over:

```bash
docker compose --env-file .env -f infra/docker/docker-compose.yml down -v
```

The reset command permanently deletes the local PostgreSQL, Kafka, and MinIO volumes. Never use it against an environment containing data you need to keep.
