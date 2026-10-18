#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
environment_file="${AETHER_ENV_FILE:-${repository_root}/.env}"
connector_file="${repository_root}/infra/docker/connectors/aether-postgres-cdc.json"

if [[ ! -f "${environment_file}" ]]; then
  echo "Missing ${environment_file}. Copy .env.example to .env before registering CDC." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "${environment_file}"
set +a

connect_port="${KAFKA_CONNECT_PORT:-8083}"
connect_url="http://localhost:${connect_port}"
connector_name="aether-postgres-cdc"

for attempt in {1..30}; do
  if curl --fail --silent --show-error "${connect_url}/connectors" >/dev/null; then
    break
  fi

  if [[ "${attempt}" -eq 30 ]]; then
    echo "Kafka Connect did not become reachable at ${connect_url}." >&2
    exit 1
  fi

  sleep 2
done

curl --fail --silent --show-error \
  --request PUT \
  --header 'Content-Type: application/json' \
  --data "@${connector_file}" \
  "${connect_url}/connectors/${connector_name}/config" >/dev/null

echo "Registered ${connector_name}."
