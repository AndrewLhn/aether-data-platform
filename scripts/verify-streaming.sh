#!/usr/bin/env bash
#
# Check whether the streaming pipeline is actually working, as opposed to merely
# having been submitted. Submission succeeding proves the planner accepted the
# SQL; it says nothing about slots, checkpoints, object storage or data.
#
# Usage: scripts/verify-streaming.sh

set -uo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
environment_file="${AETHER_ENV_FILE:-${repository_root}/.env}"
compose_file="${repository_root}/infra/docker/docker-compose.yml"

if [[ ! -f "${environment_file}" ]]; then
  echo "Missing ${environment_file}. Run 'make env' first." >&2
  exit 1
fi

compose=(docker compose --env-file "${environment_file}" -f "${compose_file}")
rest="http://localhost:${FLINK_REST_PORT:-8081}"

# Read from .env without exporting anything into this shell.
env_value() {
  sed -n "s/^$1=//p" "${environment_file}" | head -n 1
}

section() {
  echo
  echo "=================================================================="
  echo "== $*"
  echo "=================================================================="
}

section "1. Cluster: registered TaskManagers and slots"
curl --fail --silent --show-error "${rest}/overview" || {
  echo "JobManager REST is not reachable at ${rest}." >&2
  exit 1
}
echo

section "2. Jobs"
curl --fail --silent --show-error "${rest}/jobs/overview"
echo

section "3. Checkpoints of each job (this is where S3 and RocksDB show up)"
jobs_json="$(curl --fail --silent --show-error "${rest}/jobs/overview")"
for job in $(printf '%s' "${jobs_json}" | grep -oE '"jid":"[0-9a-f]+"' | cut -d'"' -f4); do
  [[ -n "${job}" ]] || continue
  echo
  echo "--- job ${job}"
  curl --fail --silent --show-error "${rest}/jobs/${job}/checkpoints" \
    | head -c 2000
  echo
  echo "    exceptions:"
  curl --fail --silent --show-error "${rest}/jobs/${job}/exceptions" \
    | head -c 1500
  echo
done

section "4. Debezium connector state"
connector="$(curl --fail --silent --show-error \
  "http://localhost:$(env_value KAFKA_CONNECT_PORT)/connectors/aether-postgres-cdc/status" 2>&1)"
if [[ "${connector}" == *"Could not resolve host"* || "${connector}" == *"Failed to connect"* ]]; then
  echo "  connector is NOT registered. Run: ./scripts/register-ecommerce-cdc.sh"
else
  echo "${connector}" | head -c 800
  echo
fi

section "5. Kafka topic and its end offset"
topic="aether.public.orders"
"${compose[@]}" exec -T kafka /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server kafka:19092 --list 2>/dev/null | sed 's/^/  /'
echo "  --- offsets for ${topic}"
"${compose[@]}" exec -T kafka /opt/kafka/bin/kafka-get-offsets.sh \
  --bootstrap-server kafka:19092 --topic "${topic}" 2>&1 | sed 's/^/  /'

section "6. SeaweedFS: did the warehouse bucket receive anything?"
echo "  expected buckets: $(env_value S3_WAREHOUSE_BUCKET), $(env_value S3_CHECKPOINT_BUCKET)"
"${compose[@]}" exec -T seaweedfs sh -c \
  "echo 's3.bucket.list' | weed shell -master=localhost:9333 2>/dev/null" | sed 's/^/    /'
echo "  --- objects under the warehouse prefix"
"${compose[@]}" exec -T seaweedfs sh -c \
  "echo 's3.bucket.list -v' | weed shell -master=localhost:9333 2>/dev/null" | head -30 | sed 's/^/    /' 

section "7. Iceberg catalog rows recorded in PostgreSQL"
# Columns are listed rather than hardcoded: JdbcCatalog owns this table's schema
# and it differs between Iceberg versions, so a fixed column list fails with
# "column ... does not exist" instead of reporting anything.
"${compose[@]}" exec -T postgres psql \
  --username "$(env_value POSTGRES_USER)" \
  --dbname "$(env_value POSTGRES_DB)" \
  --command "SELECT column_name FROM information_schema.columns WHERE table_name = 'iceberg_tables' ORDER BY ordinal_position;" \
  --command "SELECT * FROM iceberg_tables;" 2>&1 | sed 's/^/  /'

section "8. TaskManager log: errors and checkpoint activity"
"${compose[@]}" logs --tail 400 flink-taskmanager 2>&1 \
  | grep -Ei "error|exception|caused by|checkpoint|rocksdb|s3|iceberg|snapshot" \
  | tail -60 | sed 's/^/  /'

echo
echo "Done. Paste everything above when asking for help."
