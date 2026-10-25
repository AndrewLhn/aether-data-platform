#!/usr/bin/env bash
#
# Render every *.sql.in template under SQL_SRC_DIR into SQL_OUT_DIR.
#
# Flink SQL Client has no variable substitution, and credentials must not be
# committed inside SQL, so the templates live in git and the values come from
# the container environment. Called by both aether-entrypoint.sh and
# submit-pipeline.sh; safe to run repeatedly.

set -euo pipefail

SQL_SRC_DIR="${SQL_SRC_DIR:-/opt/flink/sql-src}"
SQL_OUT_DIR="${SQL_OUT_DIR:-/opt/flink/sql}"

# Restricting envsubst to an explicit variable list means an unrelated '$' in a
# SQL comment or string literal cannot be silently rewritten.
RENDER_VARS='${KAFKA_BOOTSTRAP_SERVERS}'
RENDER_VARS="${RENDER_VARS},\${S3_ENDPOINT_INTERNAL}"
RENDER_VARS="${RENDER_VARS},\${S3_ACCESS_KEY_ID}"
RENDER_VARS="${RENDER_VARS},\${S3_SECRET_ACCESS_KEY}"
RENDER_VARS="${RENDER_VARS},\${S3_REGION}"
RENDER_VARS="${RENDER_VARS},\${S3_WAREHOUSE_BUCKET}"

if [[ ! -d "${SQL_SRC_DIR}" ]]; then
  echo "No SQL source directory at ${SQL_SRC_DIR}; nothing to render." >&2
  exit 0
fi

mkdir -p "${SQL_OUT_DIR}"

count=0
for template in "${SQL_SRC_DIR}"/*.sql.in; do
  [[ -e "${template}" ]] || continue
  rendered="${SQL_OUT_DIR}/$(basename "${template}" .in)"
  envsubst "${RENDER_VARS}" <"${template}" >"${rendered}"
  chmod 0644 "${rendered}"
  count=$((count + 1))
done

echo "Rendered ${count} SQL template(s) into ${SQL_OUT_DIR}."
