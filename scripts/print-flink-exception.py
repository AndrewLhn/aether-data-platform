#!/usr/bin/env python3
"""Print a Flink job's exceptions in full, with the stack unwrapped.

The REST API returns the failure as one JSON string with embedded newlines and
tab-indented frames. Truncating it hides the frames that actually matter, which
is how "Caused by: NullPointerException" ends up being the last visible line and
the real throw site stays unknown.

Reads the JSON on stdin and prints:

* the root exception with every frame on its own line;
* the exception history entries, newest first, each with its full stack.

Usage:
    curl -s http://localhost:8081/jobs/<jid>/exceptions | scripts/print-flink-exception.py
"""

from __future__ import annotations

import json
import sys


def print_stack(text: str, indent: str = "  ") -> None:
    for line in (text or "").split("\n"):
        line = line.rstrip()
        if line:
            print(f"{indent}{line}")


def main() -> int:
    raw = sys.stdin.read()
    if not raw.strip():
        print("  (empty response)")
        return 0

    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        # Not JSON; print it verbatim rather than losing it.
        print_stack(raw)
        return 0

    root = payload.get("root-exception")
    timestamp = payload.get("timestamp")
    if root:
        print(f"  root exception (timestamp {timestamp}):")
        print_stack(root)
    elif timestamp:
        print(f"  no root exception recorded (timestamp {timestamp})")

    history = payload.get("exception-history", {}).get("entries", [])
    if history:
        print()
        print(f"  exception history: {len(history)} entr(ies), newest first")
        for index, entry in enumerate(history):
            print()
            print(f"  --- entry {index}: {entry.get('exception-name', '?')} "
                  f"at {entry.get('timestamp')} task={entry.get('taskName', '?')}")
            print_stack(entry.get("stacktrace", ""))
    elif not root:
        print("  no exceptions recorded for this job")

    return 0


if __name__ == "__main__":
    sys.exit(main())
