#!/usr/bin/env python3
"""List or cancel jobs on the local Flink session cluster.

`make pipeline` submits a detached job and exits 0, so submitting a second one
goes unnoticed. An earlier compose file did exactly that on every `up`, because
the one-shot submitter was a regular service. Two writers into the same Iceberg
table do not fail loudly, they both commit, so duplicates have to be visible and
clearable.

Parsing the REST response with shell text tools was tried first and got two
things wrong on a two-job payload: the final record was dropped by the record
splitting, and the timestamp used `date -u -r`, which is BSD-only and fails on
Linux and in CI. The standard library does both correctly.

Usage:
    scripts/flink-jobs.py [--cancel-all] [--port N]
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import sys
import urllib.error
import urllib.request

DEFAULT_ENV_FILE = ".env"


def read_port(env_file: str) -> int:
    """Prefer the host-published UI port; FLINK_REST_PORT is in-network only."""
    fallback = 8081
    if not os.path.isfile(env_file):
        return fallback
    published = None
    with open(env_file, encoding="utf-8") as handle:
        for line in handle:
            if line.startswith("FLINK_UI_PORT="):
                published = line.split("=", 1)[1].strip()
    try:
        return int(published) if published else fallback
    except ValueError:
        return fallback


def fetch(url: str) -> dict:
    try:
        with urllib.request.urlopen(url, timeout=30) as response:
            return json.load(response)
    except urllib.error.URLError as exc:
        print(f"ERROR cannot reach {url}: {exc}", file=sys.stderr)
        raise SystemExit(1)
    except json.JSONDecodeError as exc:
        print(f"ERROR {url} did not return JSON: {exc}", file=sys.stderr)
        raise SystemExit(1)


def cancel(url: str, job_id: str) -> None:
    request = urllib.request.Request(f"{url}?mode=cancel", method="PATCH")
    try:
        with urllib.request.urlopen(request, timeout=30):
            print(f"cancelling {job_id} ... requested")
    except (urllib.error.URLError, urllib.error.HTTPError) as exc:
        print(f"cancelling {job_id} ... FAILED ({exc})")


def format_start(epoch_ms: int) -> str:
    if not epoch_ms or epoch_ms < 0:
        return "-"
    moment = datetime.datetime.fromtimestamp(epoch_ms / 1000, datetime.timezone.utc)
    return moment.strftime("%Y-%m-%dT%H:%M:%SZ")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--cancel-all", action="store_true",
                        help="cancel every job on the cluster")
    parser.add_argument("--port", type=int, default=None,
                        help="JobManager REST port on the host (default: from .env)")
    parser.add_argument("--env-file", default=DEFAULT_ENV_FILE)
    args = parser.parse_args()

    port = args.port if args.port else read_port(args.env_file)
    rest = f"http://localhost:{port}"
    jobs = fetch(f"{rest}/jobs/overview").get("jobs", [])

    if args.cancel_all:
        if not jobs:
            print("No jobs to cancel.")
            return 0
        for job in jobs:
            cancel(f"{rest}/jobs/{job['jid']}", job["jid"])
        print("\nCancellation is asynchronous; re-run without --cancel-all to confirm.")
        return 0

    print(f"{'JOB ID':<34} {'STATE':<10} {'TASKS':<8} STARTED (UTC)")
    for job in sorted(jobs, key=lambda j: j.get("start-time", 0)):
        tasks = job.get("tasks", {})
        running = tasks.get("running", 0)
        total = tasks.get("total", 0)
        print(f"{job.get('jid', '-'):<34} {job.get('state', '-'):<10} "
              f"{running}/{total:<6} {format_start(job.get('start-time', 0))}")

    active = [j for j in jobs if j.get("state") == "RUNNING"]
    print()
    if len(active) > 1:
        print(f"WARNING {len(active)} jobs are RUNNING. The pipeline was submitted more")
        print("        than once and every writer commits to the same Iceberg table.")
        print("        Clear them with: scripts/flink-jobs.py --cancel-all")
    elif not jobs:
        print("No jobs on the cluster. Submit one with: make pipeline")
    else:
        print(f"{len(active)} job RUNNING.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
