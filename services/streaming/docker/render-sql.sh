#!/usr/bin/env bash
#
# Render every *.sql.in template under SQL_SRC_DIR into SQL_OUT_DIR.
#
# Flink SQL Client has no variable substitution, and credentials must not be
# committed inside SQL, so the templates live in git and the values come from
# the container environment. Called by prepare-runtime.sh; safe to run
# repeatedly.
#
# Substitution is done with bash parameter expansion rather than envsubst. That
# removes a dependency on gettext-base and, more importantly, restricts
# expansion to an explicit allowlist: an unrelated '$' in a SQL comment or
# string literal cannot be rewritten, and a missing variable is a hard error
# instead of an empty string silently interpolated into a catalog definition.

set -euo pipefail

SQL_SRC_DIR="${SQL_SRC_DIR:-/opt/flink/sql-src}"
SQL_OUT_DIR="${SQL_OUT_DIR:-/opt/flink/sql}"

RENDER_VARS=(
  KAFKA_BOOTSTRAP_SERVERS
  S3_ENDPOINT_INTERNAL
  S3_ACCESS_KEY_ID
  S3_SECRET_ACCESS_KEY
  S3_REGION
  S3_WAREHOUSE_BUCKET
)

if [[ ! -d "${SQL_SRC_DIR}" ]]; then
  echo "No SQL source directory at ${SQL_SRC_DIR}; nothing to render." >&2
  exit 0
fi

missing=()
for name in "${RENDER_VARS[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    missing+=("${name}")
  fi
done

if [[ "${#missing[@]}" -gt 0 ]]; then
  echo "Cannot render SQL: required variable(s) unset or empty: ${missing[*]}" >&2
  echo "They are provided by docker-compose from .env; run 'make env' and restart." >&2
  exit 1
fi

mkdir -p "${SQL_OUT_DIR}"

count=0
for template in "${SQL_SRC_DIR}"/*.sql.in; do
  [[ -e "${template}" ]] || continue

  content="$(<"${template}")"
  for name in "${RENDER_VARS[@]}"; do
    content="${content//\$\{${name}\}/${!name}}"
  done

  leftover="$(grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*\}' <<<"${content}" || true)"
  if [[ -n "${leftover}" ]]; then
    echo "Unresolved placeholder(s) in ${template}: $(tr '\n' ' ' <<<"${leftover}")" >&2
    exit 1
  fi

  rendered="${SQL_OUT_DIR}/$(basename "${template}" .in)"
  printf '%s\n' "${content}" >"${rendered}"
  chmod 0644 "${rendered}"
  count=$((count + 1))
done

echo "Rendered ${count} SQL template(s) into ${SQL_OUT_DIR}."
