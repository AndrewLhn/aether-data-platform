#!/usr/bin/env python3
"""Fail when the Docker Compose stack cannot run on someone else's machine.

`docker compose config` happily resolves an absolute build context or bind
mount that only exists on the author's laptop, so it cannot catch the failure
mode that actually breaks a fresh clone. This check parses the compose file
and rejects host paths that are not repository-relative.

Checks, in order of severity:

* ERROR  an absolute host path (``/Users/...``, ``/home/...``, ``C:\\...``) in a
  build context or bind mount source;
* ERROR  a home-relative path (``~/...``) in the same positions;
* ERROR  (``--strict`` only) a relative path that git does not track, meaning a
  fresh clone would not have it;
* WARN   a relative path that does not exist on disk right now.

Usage:
    scripts/check-compose-portability.sh [--strict] [compose-file ...]
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys

try:
    import yaml
except ImportError:  # pragma: no cover - guidance beats a traceback
    sys.stderr.write(
        "PyYAML is required: python3 -m pip install pyyaml\n"
    )
    sys.exit(2)

DEFAULT_TARGETS = ("infra/docker/docker-compose.yml",)
DEFAULT_ENV_TEMPLATE = ".env.example"
# ${VAR}, ${VAR:-default}, ${VAR:?error} — the forms compose interpolates.
INTERPOLATION_RE = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)(?::?[-?][^}]*)?\}")
VOLUME_FLAGS = {"ro", "rw", "z", "Z"}
# Host paths that are legitimately outside the repository. They still have to
# exist, but they are not a portability defect.
ALLOWED_ABSOLUTE_SOURCES = {
    "/var/run/docker.sock",
    "/tmp",
}
NAMED_VOLUME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
ABSOLUTE_PATH = re.compile(r"^(?:/|[A-Za-z]:[\\/])")


def git_tracked(repo_root: str, path: str) -> bool:
    """Return True when git has the path under version control."""
    result = subprocess.run(
        ["git", "ls-files", "--error-unmatch", "--", path],
        cwd=repo_root,
        capture_output=True,
        check=False,
    )
    return result.returncode == 0


def inspect_source(source: str, where: str, compose_dir: str, repo_root: str,
                   strict: bool, errors: list[str], warnings: list[str]) -> None:
    """Validate a single host path used as a build context or bind source."""
    if ABSOLUTE_PATH.match(source) or source.startswith("~"):
        if source in ALLOWED_ABSOLUTE_SOURCES:
            warnings.append(
                f"{where}: host path {source!r} is outside the repository; "
                f"intentional, but it will not exist in every environment"
            )
            return
        errors.append(
            f"{where}: host path {source!r} is not repository-relative; "
            f"a fresh clone cannot build or mount it"
        )
        return

    resolved = os.path.normpath(os.path.join(compose_dir, source))
    try:
        display = os.path.relpath(resolved, repo_root)
    except ValueError:  # different drive on Windows
        display = resolved

    if not os.path.exists(resolved):
        warnings.append(f"{where}: {source!r} does not exist on disk")

    if strict and not git_tracked(repo_root, resolved):
        errors.append(
            f"{where}: {source!r} resolves to {display}, which git does not "
            f"track; a fresh clone would not have it"
        )


def check_volumes(service: str, volumes: object, compose_dir: str,
                  repo_root: str, strict: bool, errors: list[str],
                  warnings: list[str]) -> None:
    if not isinstance(volumes, list):
        errors.append(f"{service}.volumes must be a list")
        return

    for entry in volumes:
        if isinstance(entry, dict):
            source = entry.get("source")
            if entry.get("type") != "bind" or not isinstance(source, str):
                continue
                where = f"{service}.volumes[{entry.get('target', '?')}]"
        elif isinstance(entry, str):
            parts = entry.split(":")
            if len(parts) < 2:
                continue
            if len(parts) >= 3 and parts[-1] not in VOLUME_FLAGS:
                # Windows-style drive letter inside the source, e.g. C:\x:y:ro
                continue
            source = parts[0]
            if NAMED_VOLUME.match(source):
                continue  # named volume, not a host path
            where = f"{service}.volumes[{parts[1]}]"
        else:
            errors.append(f"{service}.volumes: unsupported entry {entry!r}")
            continue

        inspect_source(source, where, compose_dir, repo_root, strict,
                       errors, warnings)


def check_build(service: str, build: object, compose_dir: str, repo_root: str,
                strict: bool, errors: list[str], warnings: list[str]) -> None:
    if isinstance(build, str):
        context, dockerfile = build, None
    elif isinstance(build, dict):
        context = build.get("context", ".")
        dockerfile = build.get("dockerfile")
    else:
        errors.append(f"{service}.build must be a string or mapping")
        return

    if isinstance(context, str):
        inspect_source(context, f"{service}.build.context", compose_dir,
                       repo_root, strict, errors, warnings)

    if isinstance(dockerfile, str) and isinstance(context, str) \
            and not ABSOLUTE_PATH.match(context) and not context.startswith("~"):
        candidate = os.path.normpath(os.path.join(compose_dir, context, dockerfile))
        if not os.path.exists(candidate):
            errors.append(
                f"{service}.build.dockerfile: {dockerfile!r} not found "
                f"inside the build context"
            )


def interpolated_variables(raw_text: str) -> set[str]:
    """Return every variable the compose file asks the environment for."""
    return set(INTERPOLATION_RE.findall(raw_text))


def template_keys(path: str) -> set[str]:
    """Return the keys an .env-style template declares."""
    keys: set[str] = set()
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            match = re.match(r"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=", line)
            if match:
                keys.add(match.group(1))
    return keys


def check_env_template(compose_paths: list[str], template: str,
                       repo_root: str) -> list[str]:
    """Fail when compose interpolates a variable the template never declares.

    This is the defect class behind the stale-.env start-up failure: a required
    variable existed only in someone's local .env, so a fresh environment had no
    way to learn it was needed.
    """
    errors: list[str] = []
    template_path = os.path.join(repo_root, template)

    if not os.path.isfile(template_path):
        return [f"{template}: template not found, cannot verify variable coverage"]

    declared = template_keys(template_path)
    required: set[str] = set()

    for compose_path in compose_paths:
        if os.path.isfile(compose_path):
            with open(compose_path, encoding="utf-8") as handle:
                required |= interpolated_variables(handle.read())

    missing = sorted(required - declared)
    if missing:
        errors.append(
            f"{template} does not declare variable(s) the compose file "
            f"interpolates: {', '.join(missing)}"
        )

    return errors


def check_file(path: str, repo_root: str, strict: bool) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    warnings: list[str] = []
    compose_dir = os.path.dirname(os.path.abspath(path))

    with open(path, encoding="utf-8") as handle:
        document = yaml.safe_load(handle)

    if not isinstance(document, dict):
        return [f"{path}: not a mapping"], warnings

    services = document.get("services") or {}
    if not isinstance(services, dict):
        return [f"{path}: 'services' must be a mapping"], warnings

    for name, service in services.items():
        if not isinstance(service, dict):
            errors.append(f"{path}: services.{name} must be a mapping")
            continue

        where = f"{path} -> services.{name}"
        if "build" in service:
            check_build(f"{where}", service["build"], compose_dir, repo_root,
                        strict, errors, warnings)
        if "volumes" in service:
            check_volumes(f"{where}", service["volumes"], compose_dir, repo_root,
                          strict, errors, warnings)

    return errors, warnings


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("compose_files", nargs="*", default=None,
                        help="compose files to inspect (default: %(default)s)")
    parser.add_argument("--strict", action="store_true",
                        help="also fail on relative paths that git does not track")
    parser.add_argument("--env-template", default=DEFAULT_ENV_TEMPLATE,
                        help="dotenv template that must cover every interpolated "
                             "variable (default: %(default)s)")
    parser.add_argument("--skip-env-template", action="store_true",
                        help="only check host paths")
    args = parser.parse_args()

    targets = args.compose_files or list(DEFAULT_TARGETS)
    repo_root = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True, text=True, check=True,
    ).stdout.strip()

    all_errors: list[str] = []
    all_warnings: list[str] = []

    for target in targets:
        if not os.path.isfile(target):
            all_errors.append(f"{target}: file not found")
            continue
        errors, warnings = check_file(target, repo_root, args.strict)
        all_errors.extend(errors)
        all_warnings.extend(warnings)

    if not args.skip_env_template:
        all_errors.extend(check_env_template(targets, args.env_template, repo_root))

    for warning in all_warnings:
        print(f"WARN  {warning}")
    for error in all_errors:
        print(f"ERROR {error}")

    if all_errors:
        print(f"\nCompose portability check failed: {len(all_errors)} error(s).")
        return 1

    print(f"Compose portability check passed for {len(targets)} file(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
