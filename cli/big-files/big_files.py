#!/usr/bin/env python3
"""Find the largest files under a path."""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

UNITS = ("B", "KB", "MB", "GB", "TB")


def human_bytes(n: int) -> str:
    if n < 0:
        raise ValueError(f"size must be non-negative, got {n}")
    value = float(n)
    for i, unit in enumerate(UNITS):
        if value < 1024.0 or i == len(UNITS) - 1:
            if unit == "B":
                return f"{int(value)} B"
            return f"{value:.1f} {unit}"
        value /= 1024.0
    return f"{value:.1f} TB"  # pragma: no cover


def find_big_files(root: Path | str, n: int = 10) -> list[tuple[Path, int]]:
    root = Path(root)
    if n < 0:
        raise ValueError(f"n must be non-negative, got {n}")
    if n == 0:
        return []
    if not root.exists():
        raise FileNotFoundError(f"No such file or directory: {root}")

    found: list[tuple[Path, int]] = []

    def consider(path: Path, size: int) -> None:
        found.append((path, size))

    if root.is_file() and not root.is_symlink():
        consider(root, root.stat().st_size)
    elif root.is_dir():
        for dirpath, _dirnames, filenames in os.walk(root, followlinks=False):
            for name in filenames:
                fp = Path(dirpath) / name
                if fp.is_symlink():
                    continue
                try:
                    if fp.is_file():
                        consider(fp, fp.stat().st_size)
                except OSError:
                    continue

    found.sort(key=lambda item: (-item[1], str(item[0])))
    return found[:n]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Largest N files under a path.")
    parser.add_argument(
        "path",
        nargs="?",
        default=".",
        help="root path to search (default: .)",
    )
    parser.add_argument(
        "-n",
        "--count",
        type=int,
        default=10,
        metavar="N",
        help="number of files to show (default: 10)",
    )
    parser.add_argument(
        "-b",
        "--bytes",
        action="store_true",
        help="print raw byte counts",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="print JSON array of matches",
    )
    args = parser.parse_args(argv)

    try:
        root = Path(args.path)
        results = find_big_files(root, n=args.count)
    except (OSError, ValueError) as exc:
        print(f"big-files: {exc}", file=sys.stderr)
        return 2

    if args.json:
        payload = [
            {"path": str(path), "bytes": size, "human": human_bytes(size)}
            for path, size in results
        ]
        print(json.dumps(payload, ensure_ascii=False))
        return 0

    for path, size in results:
        shown = str(size) if args.bytes else human_bytes(size)
        print(f"{shown}\t{path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
