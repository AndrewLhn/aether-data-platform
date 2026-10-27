#!/usr/bin/env bash
#
# Prepare the Flink runtime for this container: put the mounted connector JARs
# on the classpath, then render the SQL templates.
#
# Called by aether-entrypoint.sh (jobmanager, taskmanager) and by
# submit-pipeline.sh, so every role sees the same runtime.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LIB_EXT_DIR="${LIB_EXT_DIR:-/opt/flink/usrlib}"
FLINK_LIB_DIR="${FLINK_LIB_DIR:-/opt/flink/lib}"

# Connector and catalog JARs are bind mounted read-only rather than baked into
# the image, so a version bump is a change to infra/docker/flink/libs.lock and
# not an image rebuild.
#
# They cannot be mounted straight onto /opt/flink/lib: a bind mount replaces the
# directory, which would hide every JAR the base image ships and stop Flink from
# starting. They also cannot simply be left in /opt/flink/usrlib, because Flink
# only adds usrlib to the user-code classloader for `flink run` and
# `run-application` submissions. SQL Client builds its classpath from
# /opt/flink/lib and /opt/flink/opt, so a catalog factory living in usrlib is
# invisible to it and CREATE CATALOG fails with
# "Could not find any factory for identifier 'iceberg'".
#
# Symlinking each JAR into lib keeps the base JARs in place and puts the mounted
# ones where every entry point looks for them.
link_extension_jars() {
  if [[ ! -d "${LIB_EXT_DIR}" ]]; then
    echo "No extension directory at ${LIB_EXT_DIR}; skipping JAR linking." >&2
    return 0
  fi

  mkdir -p "${FLINK_LIB_DIR}"

  local jar linked=0
  for jar in "${LIB_EXT_DIR}"/*.jar; do
    [[ -e "${jar}" ]] || continue
    ln -sfn "${jar}" "${FLINK_LIB_DIR}/$(basename "${jar}")"
    linked=$((linked + 1))
  done

  echo "Linked ${linked} extension JAR(s) into ${FLINK_LIB_DIR}."
}

link_extension_jars

"${script_dir}/render-sql.sh"
