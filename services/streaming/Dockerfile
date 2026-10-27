# Flink runtime for the Aether streaming pipeline.
#
# The base image is pinned to an exact patch version: the `1.20` tag floats, so
# a rebuild weeks later could silently change the runtime under a job whose
# savepoints and state are version-sensitive.
#
# The java17 variant is required, not a preference. Apache Iceberg moved its
# baseline to JDK 17, so iceberg-flink-runtime-1.20 carries class file version
# 61 bytecode. On a java11 image (version 55) the JAR is on the classpath but
# cannot be loaded, and SQL Client fails during service discovery with
#
#   UnsupportedClassVersionError: org/apache/iceberg/flink/FlinkDynamicTableFactory
#   has been compiled by a more recent version of the Java Runtime
#
# which surfaces as "Failed to start the embedded sql-gateway" and names neither
# the JAR nor the Java version. Flink 1.20 supports Java 17 and the official
# image already sets the required --add-exports/--add-opens flags. It also
# removes the "Unknown module: jdk.compiler" warnings, which were the JRE 11
# image lacking a module the flags referred to.
FROM flink:1.20.5-scala_2.12-java17

USER root

# Enable the S3 filesystem plugin, which ships inside the image under /opt/flink/opt
# but is inactive until it is placed in its own plugins/ subdirectory.
#
# The glob keeps this working across patch releases; the explicit test turns a
# renamed artifact into a build failure that names the problem, instead of a
# cluster that starts and then cannot resolve s3:// at the first checkpoint.
#
# RocksDB is deliberately not copied. As of Flink 1.20 the RocksDB state backend
# is bundled inside flink-dist rather than shipped as an opt-in plugin, so
# `state.backend.type: rocksdb` works with nothing to enable. (Verified against
# flink-dist/src/main/assemblies/opt.xml at tag release-1.20.5, which lists
# flink-s3-fs-hadoop but no state backend.)
RUN set -eux; \
    mkdir -p /opt/flink/plugins/s3-fs-hadoop; \
    s3_jar="$(ls /opt/flink/opt/flink-s3-fs-hadoop-*.jar 2>/dev/null | head -n 1)"; \
    test -n "${s3_jar}" || { \
      echo "flink-s3-fs-hadoop plugin JAR not found in /opt/flink/opt:" >&2; \
      ls -1 /opt/flink/opt >&2; \
      exit 1; \
    }; \
    cp "${s3_jar}" /opt/flink/plugins/s3-fs-hadoop/; \
    echo "enabled ${s3_jar}"

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
# They are not mounted onto /opt/flink/lib, because a bind mount replaces the
# directory and would hide every JAR the base image ships. Instead
# aether/prepare-runtime.sh symlinks them into lib at container start, which is
# what makes them visible to SQL Client: Flink only adds usrlib to the user-code
# classloader for `flink run` submissions, not for sql-client.

USER flink
