# Resolved artifacts land here

This directory is the bind mount source for `/opt/flink/usrlib` in the Flink
containers. Its contents are produced by `scripts/download-flink-libs.sh` from
`../libs.lock` and are gitignored, so only this placeholder is tracked.

Run `make libs` to populate it.
