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

/opt/flink/aether/render-sql.sh

if [[ ! -f "${PIPELINE_SQL}" ]]; then
  echo "Rendered pipeline not found at ${PIPELINE_SQL}." >&2
  echo "Is services/streaming/sql mounted at /opt/flink/sql-src?" >&2
  exit 1
fi

echo "Submitting ${PIPELINE_SQL}"
exec /opt/flink/bin/sql-client.sh -f "${PIPELINE_SQL}"
