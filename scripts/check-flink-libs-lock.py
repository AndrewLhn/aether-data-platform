#!/usr/bin/env python3
"""Validate infra/docker/flink/libs.lock before anything downloads it.

A mistyped digest is not a hypothetical: this file was committed once with a
129-character SHA-512, transcribed by hand with a spurious leading zero. The
download script caught it, but only after fetching 5.6 MB and only as a generic
mismatch. These checks reject the mistake statically, in milliseconds, without
network access, and name the offending line.

Structural rules:

* exactly three whitespace-separated fields per entry;
* digest is 128 lowercase hexadecimal characters, which is the only shape a
  SHA-512 can have;
* target is a relative path with no '..' component, under lib/ or plugins/,
  ending in .jar;
* URL is HTTPS, ends in .jar, and its basename equals the target basename, so a
  digest cannot be paired with the wrong artifact.

Pass --verify-downloads to additionally fetch every artifact and compare its
real digest. That is slow, so it belongs in CI on a schedule or in a release
check, not in the default lint path.

Usage:
    scripts/check-flink-libs-lock.py [--verify-downloads] [lock-file]
"""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import sys
import urllib.request

DEFAULT_LOCK = "infra/docker/flink/libs.lock"
SHA512_RE = re.compile(r"^[0-9a-f]{128}$")
ALLOWED_PREFIXES = ("lib/", "plugins/")
EXPECTED_FIELDS = 3


def validate_entry(lineno: int, line: str, errors: list[str]) -> tuple[str, str, str] | None:
    fields = line.split()

    if len(fields) != EXPECTED_FIELDS:
        errors.append(
            f"line {lineno}: expected {EXPECTED_FIELDS} whitespace-separated fields "
            f"(digest, target, url), found {len(fields)}"
        )
        return None

    digest, target, url = fields

    if not SHA512_RE.match(digest):
        hint = ""
        if re.fullmatch(r"[0-9a-fA-F]+", digest):
            hint = f" (got {len(digest)} hex characters, SHA-512 is exactly 128)"
        errors.append(f"line {lineno}: digest is not 128 lowercase hex characters{hint}")

    if target.startswith("/") or target.startswith("~"):
        errors.append(f"line {lineno}: target {target!r} must be relative to the lock file")
    if ".." in target.split("/"):
        errors.append(f"line {lineno}: target {target!r} must not escape the directory")
    if not target.startswith(ALLOWED_PREFIXES):
        errors.append(
            f"line {lineno}: target {target!r} must live under one of "
            f"{', '.join(ALLOWED_PREFIXES)}"
        )
    if not target.endswith(".jar"):
        errors.append(f"line {lineno}: target {target!r} must end in .jar")

    if not url.startswith("https://"):
        errors.append(f"line {lineno}: url must use https, got {url!r}")
    if not url.endswith(".jar"):
        errors.append(f"line {lineno}: url {url!r} does not point at a .jar")

    url_base, target_base = os.path.basename(url), os.path.basename(target)
    if url_base != target_base:
        errors.append(
            f"line {lineno}: url basename {url_base!r} does not match target "
            f"basename {target_base!r}; a digest may be paired with the wrong artifact"
        )

    return digest, target, url


def verify_download(digest: str, target: str, url: str, errors: list[str]) -> None:
    try:
        with urllib.request.urlopen(url, timeout=300) as response:
            payload = response.read()
    except Exception as exc:  # noqa: BLE001 - any fetch failure is a finding
        errors.append(f"{target}: download failed: {exc}")
        return

    actual = hashlib.sha512(payload).hexdigest()
    if actual != digest:
        errors.append(
            f"{target}: digest mismatch\n"
            f"    declared: {digest}\n"
            f"    actual:   {actual}"
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("lock_file", nargs="?", default=DEFAULT_LOCK)
    parser.add_argument("--verify-downloads", action="store_true",
                        help="fetch each artifact and compare its real digest (slow)")
    args = parser.parse_args()

    if not os.path.isfile(args.lock_file):
        print(f"ERROR lock file not found: {args.lock_file}")
        return 1

    errors: list[str] = []
    entries: list[tuple[str, str, str]] = []

    with open(args.lock_file, encoding="utf-8") as handle:
        for lineno, raw in enumerate(handle, start=1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            parsed = validate_entry(lineno, line, errors)
            if parsed:
                entries.append(parsed)

    if not entries:
        errors.append("lock file declares no artifacts")

    if args.verify_downloads and not errors:
        print(f"Verifying {len(entries)} artifact(s) against their digests...")
        for digest, target, url in entries:
            verify_download(digest, target, url, errors)

    for error in errors:
        print(f"ERROR {error}")

    if errors:
        print(f"\nlibs.lock validation failed: {len(errors)} error(s).")
        return 1

    scope = "and digests verified" if args.verify_downloads else "structure only"
    print(f"libs.lock is valid: {len(entries)} artifact(s), {scope}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
