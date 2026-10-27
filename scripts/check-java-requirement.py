#!/usr/bin/env python3
"""Report the JVM each pinned Flink library requires, from its own bytecode.

Iceberg 1.12 moved its baseline to JDK 17. On the java11 base image the JARs
were on the classpath and still could not be loaded, and SQL Client reported it
as "Failed to start the embedded sql-gateway" with the UnsupportedClassVersionError
four frames down, naming neither the artifact nor the version. This script
answers the question directly, before a cluster is started.

For every artifact in libs.lock it reads the class file major version of each
entry and reports the highest one that the JVM would actually load.
META-INF/versions/N entries are excluded unless the runtime is at least N: a
multi-release JAR falls back to the base entry below that version, so counting
them overstates the requirement. iceberg-flink-runtime-1.20-1.12.0 is a concrete
case — it carries four Java 21 classes under META-INF/versions/21 while its real
requirement is Java 17.

Pass --base-image-java to compare against the runtime declared in
services/streaming/Dockerfile and fail if any artifact needs more.

Usage:
    scripts/check-java-requirement.py [--base-image-java N] [--lock PATH]
"""

from __future__ import annotations

import argparse
import io
import os
import re
import sys
import urllib.request
import zipfile
from collections import Counter

DEFAULT_LOCK = "infra/docker/flink/libs.lock"
DOCKERFILE = "services/streaming/Dockerfile"
CLASS_MAGIC = b"\xca\xfe\xba\xbe"
MULTI_RELEASE_RE = re.compile(r"^META-INF/versions/(\d+)/")
FROM_RE = re.compile(r"^FROM\s+\S+?(?:-java|:.*-java)(\d+)", re.MULTILINE)


def parse_lock(path: str) -> list[tuple[str, str]]:
    entries = []
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            fields = line.split()
            if len(fields) == 3:
                entries.append((fields[1], fields[2]))
    return entries


def load_jar(target: str, url: str) -> bytes:
    """Read the artifact from the resolved local path, or download it."""
    if os.path.isfile(target):
        with open(target, "rb") as handle:
            return handle.read()
    sys.stderr.write(f"  {target} not resolved locally, downloading...\n")
    with urllib.request.urlopen(url, timeout=900) as response:
        return response.read()


def scan(payload: bytes, runtime_java: int | None) -> tuple[Counter, int, str | None]:
    """Return (version histogram, required java, an example class at that level)."""
    versions: Counter = Counter()
    example: dict[int, str] = {}

    with zipfile.ZipFile(io.BytesIO(payload)) as archive:
        for name in archive.namelist():
            if not name.endswith(".class"):
                continue
            if name.endswith("module-info.class"):
                continue  # compile-time metadata, never loaded at runtime

            multi_release = MULTI_RELEASE_RE.match(name)
            if multi_release:
                gate = int(multi_release.group(1))
                # Below the gate version the JVM uses the base entry instead,
                # so this copy imposes no requirement on a Java 17 runtime.
                if runtime_java is not None and gate > runtime_java:
                    continue

            with archive.open(name) as handle:
                head = handle.read(8)
            if head[:4] != CLASS_MAGIC:
                continue
            major = int.from_bytes(head[6:8], "big")
            versions[major] += 1
            example.setdefault(major, name)

    if not versions:
        return versions, 0, None
    highest = max(versions)
    return versions, highest - 44, example[highest]


def base_image_java(path: str) -> int | None:
    if not os.path.isfile(path):
        return None
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    match = FROM_RE.search(text)
    return int(match.group(1)) if match else None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--lock", default=DEFAULT_LOCK)
    parser.add_argument("--base-image-java", type=int, default=None,
                        help=f"runtime to compare against (default: read from {DOCKERFILE})")
    args = parser.parse_args()

    if not os.path.isfile(args.lock):
        print(f"ERROR lock file not found: {args.lock}")
        return 1

    runtime = args.base_image_java
    detected = base_image_java(DOCKERFILE)
    if runtime is None:
        runtime = detected
    if runtime:
        print(f"Runtime declared by {DOCKERFILE}: Java {runtime}")
    else:
        print("Could not determine the runtime Java version from the Dockerfile.")
    print()

    failures: list[str] = []

    for target, url in parse_lock(args.lock):
        try:
            payload = load_jar(target, url)
        except Exception as exc:  # noqa: BLE001
            failures.append(f"{target}: could not be read or downloaded: {exc}")
            continue

        versions, required, example = scan(payload, runtime)
        size_mb = len(payload) / 1e6
        histogram = ", ".join(f"{v - 44}:{c}" for v, c in sorted(versions.items()))
        print(f"{os.path.basename(target)}  ({size_mb:.1f} MB)")
        print(f"    class file versions -> Java level: {histogram}")
        print(f"    requires Java {required}")
        if example:
            print(f"    highest example: {example}")

        if runtime and required > runtime:
            failures.append(
                f"{target} needs Java {required} but the image runs Java {runtime}"
            )
        print()

    if failures:
        for failure in failures:
            print(f"ERROR {failure}")
        print("\nRaise the base image Java version or pin an older artifact.")
        return 1

    print("Every pinned library is loadable by the declared runtime.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
