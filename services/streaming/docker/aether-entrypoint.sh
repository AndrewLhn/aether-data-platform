#!/usr/bin/env bash
#
# Render the pipeline SQL templates, then hand over to the stock Flink
# entrypoint so jemalloc, plugin activation and FLINK_PROPERTIES handling all
# keep working exactly as upstream intends.

set -euo pipefail

/opt/flink/aether/render-sql.sh

exec /docker-entrypoint.sh "$@"
