#!/usr/bin/env bash
#
# Collect everything needed to diagnose a local stack that will not come up,
# in one pass and without interactive guessing.
#
# Usage: scripts/diagnose-stack.sh
#
# Exit status is always 0: this is a reporting tool, and failing it would hide
# the rest of the report behind the first problem.

set -uo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
environment_file="${AETHER_ENV_FILE:-${repository_root}/.env}"
compose_file="${repository_root}/infra/docker/docker-compose.yml"

if [[ ! -f "${environment_file}" ]]; then
  echo "Missing ${environment_file}. Run 'make env' first." >&2
  exit 1
fi

compose=(docker compose --env-file "${environment_file}" -f "${compose_file}")

section() {
  echo
  echo "=================================================================="
  echo "== $*"
  echo "=================================================================="
}

section "1. docker compose ps"
"${compose[@]}" ps -a

section "2. Container health, with the last probe output and exit code"
# `docker inspect` on the whole project at once, so a service that is restarting
# in a loop still reports its last known state.
for name in $("${compose[@]}" ps -aq); do
  service="$(docker inspect --format '{{ index .Config.Labels "com.docker.compose.service" }}' "${name}" 2>/dev/null)"
  state="$(docker inspect --format '{{.State.Status}}' "${name}" 2>/dev/null)"
  health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}no healthcheck{{end}}' "${name}" 2>/dev/null)"
  echo
  echo "--- ${service:-unknown} (${name}) state=${state} health=${health}"
  docker inspect --format '{{range .State.Health.Log}}    exit={{.ExitCode}} out={{.Output}}{{end}}' "${name}" 2>/dev/null | tail -6
done

section "3. JobManager: rendered Flink configuration"
# Shows what FLINK_PROPERTIES actually produced, which is where a bad key or an
# unsubstituted variable becomes visible.
"${compose[@]}" exec -T flink-jobmanager sh -c 'cat /opt/flink/conf/config.yaml 2>/dev/null || cat /opt/flink/conf/flink-conf.yaml 2>/dev/null' \
  | sed -E -e 's/^([A-Za-z0-9._-]*(access[.-]key|secret[.-]key|password)[A-Za-z0-9._-]*[[:space:]]*):.*/\1: ***REDACTED***/I' \
  || echo "  (jobmanager is not running, cannot read its config)"

section "4. JobManager: enabled plugins and mounted libraries"
"${compose[@]}" exec -T flink-jobmanager sh -c 'ls -1 /opt/flink/plugins/*/ 2>/dev/null; echo "--- usrlib ---"; ls -1 /opt/flink/usrlib 2>/dev/null; echo "--- opt ---"; ls -1 /opt/flink/opt 2>/dev/null' \
  || echo "  (jobmanager is not running)"

section "5. JobManager: is the REST endpoint actually listening?"
"${compose[@]}" exec -T flink-jobmanager sh -c 'command -v wget >/dev/null && wget -q -O- http://localhost:8081/overview || echo "wget missing or request failed"' \
  || echo "  (jobmanager is not running)"

section "6. Last 150 log lines from every unhealthy or exited container"
for name in $("${compose[@]}" ps -aq); do
  service="$(docker inspect --format '{{ index .Config.Labels "com.docker.compose.service" }}' "${name}" 2>/dev/null)"
  health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${name}" 2>/dev/null)"
  state="$(docker inspect --format '{{.State.Status}}' "${name}" 2>/dev/null)"
  if [[ "${health}" == "unhealthy" || "${state}" == "exited" || "${state}" == "dead" ]]; then
    echo
    echo "--- ${service} (${state}/${health}) ---"
    docker logs --tail 150 "${name}" 2>&1 \
      | sed -E -e 's/(access[.-]key[a-z.-]*|secret[.-]key[a-z.-]*|password)([=:])[[:space:]]*[^[:space:],}]+/\1\2***REDACTED***/Ig'
  fi
done

section "7. Orphan containers left over from an earlier compose file"
docker ps -a --filter "label=com.docker.compose.project" \
  --format '{{.Names}}\t{{.Image}}\t{{.Status}}' \
  | grep -Ei 'localstack|minio' || echo "  none"

echo
echo "Done. Paste everything above; secrets have been redacted."
