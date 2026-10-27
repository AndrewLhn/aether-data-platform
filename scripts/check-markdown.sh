#!/usr/bin/env bash
# Run the real markdownlint, same tool and version CI runs.
# Pinned to the CLI version that DavidAnson/markdownlint-cli2-action@v20 uses,
# so local and CI results cannot drift.
set -euo pipefail
MARKDOWNLINT_CLI2_VERSION="${MARKDOWNLINT_CLI2_VERSION:-0.18.1}"
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v npx >/dev/null 2>&1; then
  echo "ERROR: npx is required to run markdownlint-cli2." >&2
  echo "       Install Node.js, or let CI run this check." >&2
  exit 2
fi
exec npx --yes "markdownlint-cli2@${MARKDOWNLINT_CLI2_VERSION}" "**/*.md"
