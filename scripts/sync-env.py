#!/usr/bin/env python3
"""Keep .env aligned with .env.example without discarding local values.

A stale .env is the most common reason a freshly cloned stack fails to start:
the template gains a variable, the operator's .env predates it, and compose
either interpolates an empty string or refuses to start. The previous `make env`
only copied the template when .env was absent, so it printed ".env is present."
for a file that was missing every new key — confidently reporting success right
before a guaranteed failure.

Behaviour:

* no .env       -> create it from the template;
* .env present  -> rewrite it from the template, keeping every value the
                   operator already had, adding keys the template introduced,
                   and re-emitting local-only keys in a marked section at the
                   end so nothing is silently destroyed;
* --check       -> change nothing and exit non-zero if .env differs, for CI.

.env is a generated file. Edit .env.example to change a default; a hand edit to
.env survives the next sync only as a value, not as structure. When the first
assignment wins on a duplicated key, which matches most dotenv loaders.

Usage:
    scripts/sync-env.py [--check] [--env-file PATH] [--template PATH]
"""

from __future__ import annotations

import argparse
import os
import re
import sys

KEY_RE = re.compile(r"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$")


def parse_env(path: str) -> tuple[list[str], dict[str, str]]:
    """Return keys in file order and a key -> value map (first assignment wins)."""
    keys: list[str] = []
    values: dict[str, str] = {}

    with open(path, encoding="utf-8") as handle:
        for raw in handle.read().splitlines():
            match = KEY_RE.match(raw)
            if not match:
                continue
            key = match.group(1)
            if key in values:
                continue
            value = match.group(2).strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                value = value[1:-1]
            keys.append(key)
            values[key] = value

    return keys, values


def read_template(path: str) -> tuple[list[str], list[str], dict[str, str]]:
    """Return template lines, template keys in order, and template defaults."""
    with open(path, encoding="utf-8") as handle:
        lines = handle.read().splitlines()

    keys: list[str] = []
    defaults: dict[str, str] = {}
    for line in lines:
        match = KEY_RE.match(line)
        if match and match.group(1) not in defaults:
            keys.append(match.group(1))
            defaults[match.group(1)] = match.group(2).strip()

    return lines, keys, defaults


def build_output(template_lines: list[str], template_keys: list[str],
                 defaults: dict[str, str], current: dict[str, str],
                 local_only: list[str]) -> str:
    """Rebuild .env from the template, preferring values already present."""
    out: list[str] = [
        "# Generated from .env.example by scripts/sync-env.py.",
        "# Existing values are preserved; new keys take the template default.",
        "# To change a default, edit .env.example rather than this file.",
        "",
    ]

    for line in template_lines:
        match = KEY_RE.match(line)
        if not match:
            out.append(line)  # keep comments, section headers and blank lines
            continue
        key = match.group(1)
        out.append(f"{key}={current.get(key, defaults.get(key, match.group(2).strip()))}")

    if local_only:
        out.append("")
        out.append("# Keys present in your .env but not in .env.example.")
        out.append("# Kept so nothing is lost; delete them if they are unused.")
        for key in local_only:
            out.append(f"{key}={current[key]}")

    return "\n".join(out) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--env-file", default=".env")
    parser.add_argument("--template", default=".env.example")
    parser.add_argument("--check", action="store_true",
                        help="report drift and exit non-zero without writing")
    args = parser.parse_args()

    if not os.path.isfile(args.template):
        print(f"ERROR template not found: {args.template}")
        return 1

    template_lines, template_keys, defaults = read_template(args.template)

    if not os.path.isfile(args.env_file):
        if args.check:
            print(f"ERROR {args.env_file} is missing; run scripts/sync-env.py to create it")
            return 1
        # Generated through the same code path as an update, so a second run
        # finds the file already in sync instead of reporting a formatting
        # difference between a raw copy and the generated layout.
        output = build_output(template_lines, template_keys, defaults, {}, [])
        with open(args.env_file, "w", encoding="utf-8") as handle:
            handle.write(output)
        print(f"Created {args.env_file} from {args.template} ({len(template_keys)} keys).")
        return 0

    current_keys, current = parse_env(args.env_file)
    missing = [k for k in template_keys if k not in current]
    local_only = [k for k in current_keys if k not in defaults]

    expected = build_output(template_lines, template_keys, defaults, current, local_only)
    with open(args.env_file, encoding="utf-8") as handle:
        actual = handle.read()

    # Drift is defined by content, not by the presence of local-only keys: those
    # can never appear in the template, so treating them as drift would make the
    # check fail forever and rewrite the file on every run.
    if actual == expected:
        print(f"{args.env_file} is in sync with {args.template} ({len(current_keys)} keys).")
        if local_only:
            print(f"  ({len(local_only)} local-only key(s) preserved, not required by the template)")
        return 0

    print(f"{args.env_file} has drifted from {args.template}:")
    for key in missing:
        print(f"  + {key}   new in template, will be set to the template default")
    for key in local_only:
        print(f"  ! {key}   local only, will be preserved at the end of the file")
    if not missing and not local_only:
        print("  ~ formatting or ordering differs from the generated layout")

    if args.check:
        print("\n--check was given, so nothing was written. Run scripts/sync-env.py to fix.")
        return 1

    with open(args.env_file, "w", encoding="utf-8") as handle:
        handle.write(expected)

    print(f"\nRewrote {args.env_file}: {len(template_keys)} key(s) from the template, "
          f"{len(local_only)} local key(s) preserved.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
