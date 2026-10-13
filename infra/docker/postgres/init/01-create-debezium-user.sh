#!/usr/bin/env sh
set -eu

psql \
  --username "$POSTGRES_USER" \
  --dbname "$POSTGRES_DB" \
  --set=debezium_user="$DEBEZIUM_USER" \
  --set=debezium_password="$DEBEZIUM_PASSWORD" \
  --set=postgres_user="$POSTGRES_USER" \
  --set=postgres_db="$POSTGRES_DB" \
  --set=ON_ERROR_STOP=1 <<'SQL'
CREATE ROLE :"debezium_user" WITH LOGIN REPLICATION PASSWORD :'debezium_password';

GRANT CONNECT ON DATABASE :"postgres_db" TO :"debezium_user";
GRANT USAGE ON SCHEMA public TO :"debezium_user";
GRANT SELECT ON ALL TABLES IN SCHEMA public TO :"debezium_user";
ALTER DEFAULT PRIVILEGES FOR ROLE :"postgres_user" IN SCHEMA public
  GRANT SELECT ON TABLES TO :"debezium_user";
SQL
