#!/usr/bin/env bash
#
# Submit the streaming pipeline to the running session cluster.
#
# `sql-client -f` executes the statements and returns once the INSERT has been
# submitted as a detached job, so this container exits 0 and the job keeps
# running on the TaskManager. A non-zero exit means the job was rejected, which
# is exactly what CI needs to see.

set -euo pipefail

SQL_OUT_DIR="${SQL_OUT_DIR:-/opt/flink/sql}"
PIPELINE_SQL="${PIPELINE_SQL:-${SQL_OUT_DIR}/pipeline.sql}"
REST_ADDRESS="${FLINK_REST_ADDRESS:-flink-jobmanager}"
REST_PORT="${FLINK_REST_PORT:-8081}"

/opt/flink/aether/prepare-runtime.sh

if [[ ! -f "${PIPELINE_SQL}" ]]; then
  echo "Rendered pipeline not found at ${PIPELINE_SQL}." >&2
  echo "Is services/streaming/sql mounted at /opt/flink/sql-src?" >&2
  exit 1
fi

# SQL Client runs embedded by default and reads the cluster address from the
# Flink configuration, where rest.address is 0.0.0.0 because the official image
# entrypoint rewrites it for binding. A client cannot connect to that, and the
# resulting failure is a bare "java.net.ConnectException: Connection refused" at
# the first statement that needs the cluster. Point the client at the JobManager
# by hostname instead of changing the cluster's own advertised address.
echo "Submitting ${PIPELINE_SQL} to ${REST_ADDRESS}:${REST_PORT}"
exec /opt/flink/bin/sql-client.sh \
  -Drest.address="${REST_ADDRESS}" \
  -Drest.port="${REST_PORT}" \
  -f "${PIPELINE_SQL}"
