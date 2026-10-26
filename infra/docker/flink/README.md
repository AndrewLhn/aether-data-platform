# Resolved Flink libraries

`libs.lock` declares every connector and catalog JAR this stack needs as a
`digest, target, url` triple. `scripts/download-flink-libs.sh` resolves it into
`lib/`, verifying each SHA-512 before the artifact is used, and
`infra/docker/docker-compose.yml` bind mounts `lib/` into the Flink containers.

Binaries are deliberately not committed: they are irreversible in history,
bloat every clone, cannot be reviewed in a diff, and cannot be bumped by
dependency tooling. Digests give the same reproducibility without those costs.

Related targets:

```bash
make libs          # resolve the lock file
make verify-libs   # re-download and re-check every digest
make verify-java   # report the JVM each artifact requires, from its bytecode
```
