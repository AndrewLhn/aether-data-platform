#!/usr/bin/env python3
"""Check the Markdown rules that .github/workflows/docs.yml enforces in CI.

markdownlint-cli2 runs only in CI, so a documentation defect is discovered after
a push. That is a slow place to learn it, and it happened: two placeholder
READMEs were written with shell-style `#` comments, which Markdown reads as
level-one headings, and nothing locally objected.

This checks the subset of rules that .markdownlint.json leaves enabled and that
plain text can violate without help from a full parser. It mirrors the
configured behaviour rather than markdownlint's defaults where they differ —
notably MD009, whose default br_spaces is 2, meaning up to two trailing spaces
are a legitimate hard line break and must not be reported.

Usage:
    scripts/check-markdown.py [path ...]
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys

DEFAULT_CONFIG = ".markdownlint.json"
HEADING_RE = re.compile(r"^(#{1,6})(?:\s|$)")
ATX_NO_SPACE_RE = re.compile(r"^#{1,6}[^#\s]")
LIST_RE = re.compile(r"^\s*([-*+]|\d+\.)\s")
BLOCKQUOTE_RE = re.compile(r"^\s*>")
FENCE_RE = re.compile(r"^(`{3,}|~{3,})")


def load_disabled_rules(config_path: str) -> set[str]:
    """Return rule ids explicitly turned off in the markdownlint config."""
    if not os.path.isfile(config_path):
        return set()
    try:
        with open(config_path, encoding="utf-8") as handle:
            config = json.load(handle)
    except (OSError, json.JSONDecodeError) as exc:
        print(f"WARN  could not read {config_path}: {exc}")
        return set()

    disabled = set()
    for key, value in config.items():
        # Rules appear as "MD013" or "no-hard-tabs"; only the numeric form matters here.
        if re.fullmatch(r"MD\d+", key) and value is False:
            disabled.add(key)
    return disabled


def markdown_files(paths: list[str], repo_root: str) -> list[str]:
    found: list[str] = []
    for path in paths:
        if os.path.isfile(path) and path.endswith(".md"):
            found.append(path)
        elif os.path.isdir(path):
            for root, dirs, files in os.walk(path):
                dirs[:] = [d for d in dirs if d not in {".git", "node_modules"}]
                for name in sorted(files):
                    if name.endswith(".md"):
                        found.append(os.path.join(root, name))
    if not paths:
        out = subprocess.run(
            ["git", "ls-files", "*.md"], cwd=repo_root, capture_output=True, text=True, check=False
        ).stdout
        found.extend(line for line in out.splitlines() if line)
    return sorted(set(found))


def check_file(path: str, disabled: set[str], br_spaces: int = 2) -> list[str]:
    issues: list[str] = []

    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    lines = text.split("\n")

    def rule(name: str) -> bool:
        return name not in disabled

    if rule("MD041") and lines and lines[0].strip() and not lines[0].startswith("# "):
        issues.append(f"{path}:1 MD041 first line should be a top-level heading")

    in_fence = False
    fence_marker = ""
    blank_run = 0
    h1_lines: list[int] = []

    for index, line in enumerate(lines):
        number = index + 1
        previous = lines[index - 1] if index else ""

        if not line.strip():
            blank_run += 1
            if rule("MD012") and blank_run > 1:
                issues.append(f"{path}:{number} MD012 multiple consecutive blank lines")
            continue
        blank_run = 0

        fence = FENCE_RE.match(line)
        if fence:
            if not in_fence:
                in_fence, fence_marker = True, fence.group(1)[0]
                if rule("MD031") and previous.strip():
                    issues.append(f"{path}:{number} MD031 fenced code block needs a blank line above")
            elif line.strip().startswith(fence_marker * 3):
                if rule("MD031") and index + 1 < len(lines) and lines[index + 1].strip():
                    issues.append(f"{path}:{number} MD031 fenced code block needs a blank line below")
                in_fence = False
            continue

        if in_fence:
            continue

        if rule("MD009"):
            trailing = len(line) - len(line.rstrip())
            if trailing > br_spaces:
                issues.append(f"{path}:{number} MD009 {trailing} trailing spaces (limit {br_spaces})")

        if rule("MD010") and "\t" in line:
            issues.append(f"{path}:{number} MD010 hard tab")

        if rule("MD018") and ATX_NO_SPACE_RE.match(line):
            issues.append(f"{path}:{number} MD018 no space after hashes in heading")

        if rule("MD040") and fence and not line.strip().strip("`~"):
            issues.append(f"{path}:{number} MD040 fenced code block should have a language")

        if HEADING_RE.match(line):
            if line.startswith("# "):
                h1_lines.append(number)
            if rule("MD022") and previous.strip():
                issues.append(f"{path}:{number} MD022 heading should be surrounded by blank lines")

        # markdownlint treats a heading, another list item, or the wrapped
        # continuation of a list item as a sufficient boundary for MD032. Only a
        # paragraph line directly above a list's first item is a violation.
        #
        # Both simplifications were tried and both were wrong. Requiring a literal
        # blank line reported every list that follows a heading. Ignoring only
        # list markers and headings then reported every list item that follows a
        # wrapped item, because an indented continuation line looks like a
        # paragraph. Detecting the continuation needs the list state carried
        # across the previous line, hence prev_was_list.
        # A line above a list item is an acceptable boundary if it is blank, a
        # heading, another list item, or indented. Indentation covers both a
        # wrapped continuation of the previous item and a nested list, which are
        # the two shapes that a plain "was the previous line a marker" test gets
        # wrong. Only an unindented paragraph line directly above a list's first
        # item is reported.
        if rule("MD032") and LIST_RE.match(line) and previous.strip() \
                and not LIST_RE.match(previous) and not HEADING_RE.match(previous) \
                and not previous.startswith((" ", "\t")):
            issues.append(f"{path}:{number} MD032 list should be surrounded by blank lines")

        if rule("MD027") and re.match(r"^\s+>", line):
            issues.append(f"{path}:{number} MD027 multiple spaces after blockquote symbol")

        if rule("MD047") and index == len(lines) - 1:
            pass

    if in_fence:
        issues.append(f"{path}: unclosed fenced code block")

    if rule("MD025") and len(h1_lines) > 1:
        issues.append(f"{path}: MD025 multiple top-level headings at lines {h1_lines}")

    if rule("MD047") and text and not text.endswith("\n"):
        issues.append(f"{path}: MD047 file should end with a single newline")

    return issues


def main() -> int:
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    disabled = load_disabled_rules(os.path.join(repo_root, DEFAULT_CONFIG))
    targets = markdown_files(sys.argv[1:], repo_root)

    if not targets:
        print("No Markdown files found.")
        return 0

    all_issues: list[str] = []
    for path in targets:
        full = path if os.path.isabs(path) else os.path.join(repo_root, path)
        if os.path.isfile(full):
            all_issues.extend(check_file(os.path.relpath(full, repo_root), disabled))

    for issue in all_issues:
        print(f"ERROR {issue}")

    if all_issues:
        print(f"\nMarkdown check failed: {len(all_issues)} issue(s) in {len(targets)} file(s).")
        return 1

    print(f"Markdown check passed for {len(targets)} file(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
