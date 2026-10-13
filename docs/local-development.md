# Local development

## Purpose and scope

The local stack provides the infrastructure baseline for Aether's first end-to-end CDC slice:

- PostgreSQL 17 configured for logical replication;
- Apache Kafka in single-node KRaft combined mode, with no ZooKeeper;
- Kafka Connect with the Debezium PostgreSQL connector already installed;
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

Wait until PostgreSQL, Kafka, Kafka Connect, and MinIO all report `healthy`. The first start downloads images and initializes named volumes.

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

## Debezium readiness

PostgreSQL starts with `wal_level=logical`, `max_wal_senders=10`, and `max_replication_slots=10`. Its initialization script creates the dedicated `debezium` role with replication and read permissions. The next ingestion phase will add e-commerce tables and register a PostgreSQL connector through Kafka Connect's REST API.

Kafka Connect persists connector configurations, offsets, and statuses in the three `aether.connect.*` internal topics. Broker-side automatic topic creation is disabled; Kafka Connect creates only its configured internal topics.

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
