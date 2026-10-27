#!/usr/bin/env bash
#
# Fetch the pinned Flink libraries declared in infra/docker/flink/libs.lock and
# verify each one against its SHA-512 digest before it can be used.
#
# The script is idempotent: artifacts that are already present and correct are
# skipped, so it is safe to call from `make up`, CI, and the Docker build.
# A digest mismatch is fatal — the corrupt file is removed so the next run
# re-downloads it instead of silently keeping a poisoned artifact.

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
libs_dir="${repository_root}/infra/docker/flink"
lock_file="${libs_dir}/libs.lock"
force=0

if [[ "${1:-}" == "--force" ]]; then
  force=1
fi

if [[ ! -f "${lock_file}" ]]; then
  echo "Missing lock file: ${lock_file}" >&2
  exit 1
fi

sha512_of() {
  if command -v sha512sum >/dev/null 2>&1; then
    sha512sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 512 "$1" | awk '{print $1}'
  else
    echo "Neither sha512sum nor shasum is available." >&2
    exit 1
  fi
}

failures=0
verified=0
downloaded=0
cached=0

# Validate the lock file structurally before spending any bandwidth. This is
# what turns a mistyped digest into an immediate, named error instead of a
# 5.6 MB download that ends in a generic mismatch.
if [[ -f "${repository_root}/scripts/check-flink-libs-lock.py" ]] &&
   command -v python3 >/dev/null 2>&1; then
  python3 "${repository_root}/scripts/check-flink-libs-lock.py" "${lock_file}" || exit 1
fi

while read -r expected_sha target url; do
  # Skip blank lines and comments.
  [[ -z "${expected_sha}" || "${expected_sha}" == \#* ]] && continue

  # Defence in depth for the case where python3 is unavailable: a SHA-512 is
  # exactly 128 lowercase hex characters, so anything else cannot match.
  if [[ ! "${expected_sha}" =~ ^[0-9a-f]{128}$ ]]; then
    echo "Malformed digest for ${target}: expected 128 lowercase hex characters, got ${#expected_sha}." >&2
    failures=$((failures + 1))
    continue
  fi

  path="${libs_dir}/${target}"

  if [[ "${force}" -eq 0 && -f "${path}" ]] &&
     [[ "$(sha512_of "${path}")" == "${expected_sha}" ]]; then
    cached=$((cached + 1))
    continue
  fi

  mkdir -p "$(dirname "${path}")"
  echo "Downloading ${target}"

  if command -v curl >/dev/null 2>&1; then
    curl --fail --location --silent --show-error --output "${path}.part" "${url}"
  elif command -v wget >/dev/null 2>&1; then
    wget --quiet --output-document="${path}.part" "${url}"
  else
    echo "Neither curl nor wget is available." >&2
    exit 1
  fi

  actual_sha="$(sha512_of "${path}.part")"
  if [[ "${actual_sha}" != "${expected_sha}" ]]; then
    rm -f "${path}.part"
    echo "SHA-512 mismatch for ${target}" >&2
    echo "  expected: ${expected_sha}" >&2
    echo "  actual:   ${actual_sha}" >&2
    failures=$((failures + 1))
    continue
  fi

  mv "${path}.part" "${path}"
  downloaded=$((downloaded + 1))
  verified=$((verified + 1))
done < <(grep -Ev '^[[:space:]]*(#|$)' "${lock_file}")

if [[ "${failures}" -gt 0 ]]; then
  echo "Refusing to continue: ${failures} artifact(s) failed verification." >&2
  exit 1
fi

echo "Flink libraries ready: ${downloaded} downloaded, ${cached} already cached (${verified} verified this run)."
