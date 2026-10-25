# Flink runtime for the Aether streaming pipeline.
#
# The base image is pinned to an exact patch version: the `1.20` tag floats, so
# a rebuild weeks later could silently change the runtime under a job whose
# savepoints and state are version-sensitive.
FROM flink:1.20.5-scala_2.12-java11

USER root

# Enable the plugins that ship inside the image but are inactive by default.
# Copying is used instead of ENABLE_BUILT_IN_PLUGINS so that a renamed or
# missing JAR fails this build loudly rather than at cluster start-up.
#
#   s3-fs-hadoop   s3:// FileSystem for checkpoints, savepoints and the
#                  HadoopCatalog warehouse metadata
#   rocksdb        incremental checkpointing with state larger than heap
RUN set -eux; \
    mkdir -p /opt/flink/plugins/s3-fs-hadoop /opt/flink/plugins/rocksdb; \
    cp /opt/flink/opt/flink-s3-fs-hadoop-1.20.5.jar /opt/flink/plugins/s3-fs-hadoop/; \
    cp /opt/flink/opt/flink-statebackend-rocksdb-1.20.5.jar /opt/flink/plugins/rocksdb/

# Operator scripts and the SQL templates they render. Execute bits are set here
# as well as in git, because a checkout on a filesystem without mode bits would
# otherwise produce a container that cannot start.
COPY docker/ /opt/flink/aether/
RUN set -eux; \
    chmod 0755 /opt/flink/aether/*.sh; \
    mkdir -p /opt/flink/sql; \
    chown -R flink:flink /opt/flink/sql /opt/flink/aether

# Connector and Iceberg JARs are NOT baked in. They are resolved on the host by
# scripts/download-flink-libs.sh from infra/docker/flink/libs.lock and bind
# mounted to /opt/flink/usrlib, which keeps the image small and makes a version
# bump a lock-file change instead of an image rebuild.
#
# /opt/flink/lib is deliberately left alone: mounting over it would shadow the
# JARs the base image ships.

USER flink
