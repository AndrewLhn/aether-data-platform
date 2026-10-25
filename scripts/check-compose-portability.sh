#!/usr/bin/env bash
#
# Thin wrapper so that `make lint`, CI and humans all call the same entry point
# regardless of whether they prefer a shell or a Python path.
#
# Usage: scripts/check-compose-portability.sh [--strict] [compose-file ...]

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "${script_dir}/.." && pwd)"

python="${PYTHON:-}"
if [[ -z "${python}" ]]; then
  for candidate in python3 python; do
    if command -v "${candidate}" >/dev/null 2>&1; then
      python="${candidate}"
      break
    fi
  done
fi

if [[ -z "${python}" ]]; then
  echo "python3 is required to run the compose portability check." >&2
  exit 2
fi

cd "${repository_root}"
exec "${python}" "${script_dir}/check-compose-portability.py" "$@"
