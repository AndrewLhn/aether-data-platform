#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
environment_file="${AETHER_ENV_FILE:-${repository_root}/.env}"
compose_file="${repository_root}/infra/docker/docker-compose.yml"

if [[ ! -f "${environment_file}" ]]; then
  echo "Missing ${environment_file}. Copy .env.example to .env before running the CDC verification." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "${environment_file}"
set +a

compose=(docker compose --env-file "${environment_file}" -f "${compose_file}")
connector_name="aether-postgres-cdc"
connect_url="http://localhost:${KAFKA_CONNECT_PORT:-8083}"
topic="aether.public.orders"
marker="cdc-verification-$(date -u +%Y%m%dT%H%M%SZ)"
consumer_output="$(mktemp)"
consumer_pid=""

cleanup() {
  if [[ -n "${consumer_pid}" ]] && kill -0 "${consumer_pid}" 2>/dev/null; then
    kill "${consumer_pid}" 2>/dev/null || true
  fi
  rm -f "${consumer_output}"
}
trap cleanup EXIT

wait_for() {
  local description="$1"
  shift

  for attempt in {1..45}; do
    if "$@" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  echo "Timed out waiting for ${description}." >&2
  return 1
}

"${compose[@]}" up -d
wait_for "Kafka Connect" curl --fail --silent --show-error "${connect_url}/connectors"
"${repository_root}/scripts/register-ecommerce-cdc.sh"

connector_is_running() {
  local status
  status="$(curl --fail --silent --show-error "${connect_url}/connectors/${connector_name}/status")"
  [[ "${status}" == *'"connector":{"state":"RUNNING"'* ]] &&
    [[ "${status}" == *'"tasks":[{"id":0,"state":"RUNNING"'* ]]
}

wait_for "Debezium connector" connector_is_running

# The connector's topic-creation policy makes this a single-partition topic, so
# partition 0 is the only one. Naming it is required rather than cosmetic: Kafka
# 4.x rejects --offset without --partition with "The partition is required when
# offset is specified.", the consumer prints its usage and exits having read
# nothing, which looks like a missing CDC record rather than a bad invocation.
# --formatter-property replaces --property, deprecated and scheduled for removal.
"${compose[@]}" exec -T kafka \
  /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server kafka:19092 \
  --topic "${topic}" \
  --partition 0 \
  --offset latest \
  --max-messages 1 \
  --timeout-ms 30000 \
  --formatter-property print.key=true \
  --formatter-property key.separator=' | ' >"${consumer_output}" 2>&1 &
consumer_pid=$!

sleep 2

"${compose[@]}" exec -T postgres \
  psql \
  --username "${POSTGRES_USER}" \
  --dbname "${POSTGRES_DB}" \
  --set=ON_ERROR_STOP=1 \
  --command "INSERT INTO public.orders (customer_id, external_order_reference, order_status, currency, total_amount) VALUES (1, '${marker}', 'created', 'USD', 42.50);" >/dev/null

if ! wait "${consumer_pid}"; then
  cat "${consumer_output}" >&2
  echo "Kafka consumer did not receive a CDC record." >&2
  exit 1
fi
consumer_pid=""

if ! grep --fixed-strings --quiet "${marker}" "${consumer_output}"; then
  cat "${consumer_output}" >&2
  echo "CDC record did not contain verification reference ${marker}." >&2
  exit 1
fi

echo "CDC verification passed: ${marker} was emitted to ${topic}."
