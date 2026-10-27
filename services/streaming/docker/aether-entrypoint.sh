#!/usr/bin/env bash
#
# Put the mounted connector JARs on the classpath and render the pipeline SQL
# templates, then hand over to the stock Flink entrypoint so jemalloc, plugin
# activation and FLINK_PROPERTIES handling all keep working as upstream intends.

set -euo pipefail

/opt/flink/aether/prepare-runtime.sh

exec /docker-entrypoint.sh "$@"
