#!/usr/bin/env python3
"""Scan files or directories for likely secrets (heuristic regex)."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Any

SKIP_DIR_NAMES = frozenset({".git", "node_modules", "__pycache__", ".venv"})
SNIPPET_MAX = 80
BINARY_PROBE = 8192

RULES: list[dict[str, Any]] = [
    {
        "id": "aws-access-key",
        "pattern": re.compile(r"AKIA[0-9A-Z]{16}"),
    },
    {
        "id": "github-pat",
        "pattern": re.compile(r"ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]+"),
    },
    {
        "id": "slack-token",
        "pattern": re.compile(r"xox[baprs]-"),
    },
    {
        "id": "private-key",
        "pattern": re.compile(r"-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----"),
    },
    {
        "id": "google-api-key",
        "pattern": re.compile(r"AIza[0-9A-Za-z_-]{35}"),
    },
]


def is_binary(path: Path) -> bool:
    """True if the first 8 KiB contains a null byte."""
    try:
        with path.open("rb") as fh:
            chunk = fh.read(BINARY_PROBE)
    except OSError:
        return True
    return b"\x00" in chunk


def scan_text(text: str, path: str = "") -> list[dict[str, Any]]:
    """Return findings for text content. Each finding: path, line, rule, match."""
    findings: list[dict[str, Any]] = []
    for line_no, line in enumerate(text.splitlines(), start=1):
        for rule in RULES:
            for m in rule["pattern"].finditer(line):
                findings.append(
                    {
                        "path": path,
                        "line": line_no,
                        "rule": rule["id"],
                        "match": m.group(0),
                    }
                )
    return findings


def _iter_files(root: Path) -> list[Path]:
    if root.is_file():
        return [root]
    files: list[Path] = []
    for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIR_NAMES]
        for name in filenames:
            fp = Path(dirpath) / name
            if fp.is_symlink():
                continue
            files.append(fp)
    return files


def scan_path(path: Path | str) -> list[dict[str, Any]]:
    """Scan a file or directory; skip binary and junk dirs."""
    root = Path(path)
    if not root.exists():
        raise FileNotFoundError(f"No such file or directory: {root}")

    findings: list[dict[str, Any]] = []
    for fp in _iter_files(root):
        if not fp.is_file():
            continue
        if is_binary(fp):
            continue
        try:
            text = fp.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        findings.extend(scan_text(text, path=str(fp)))
    return findings


def _format_snippet(match: str) -> str:
    if len(match) <= SNIPPET_MAX:
        return match
    return match[: SNIPPET_MAX - 3] + "..."


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Scan files or directories for likely secrets (heuristic)."
    )
    parser.add_argument(
        "paths",
        nargs="*",
        help="file or directory paths to scan",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help='print JSON array of {path,line,rule,match}',
    )
    args = parser.parse_args(argv)

    if not args.paths:
        print("secret-scan: pass one or more file or directory paths", file=sys.stderr)
        return 2

    all_findings: list[dict[str, Any]] = []
    try:
        for p in args.paths:
            all_findings.extend(scan_path(p))
    except OSError as exc:
        print(f"secret-scan: {exc}", file=sys.stderr)
        return 2

    if args.json:
        print(json.dumps(all_findings, ensure_ascii=False))
    else:
        for f in all_findings:
            snippet = _format_snippet(f["match"])
            print(f"{f['path']}:{f['line']}: {f['rule']}: {snippet}")

    return 1 if all_findings else 0


if __name__ == "__main__":
    raise SystemExit(main())
