#!/usr/bin/env python3
"""Human-readable size of a file or directory tree."""

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


def path_size_bytes(path: Path | str) -> int:
    path = Path(path)
    if path.is_symlink() and path.is_file():
        return path.stat().st_size
    if path.is_file():
        return path.stat().st_size
    if not path.is_dir():
        raise FileNotFoundError(f"No such file or directory: {path}")

    total = 0
    for dirpath, _dirnames, filenames in os.walk(path, followlinks=False):
        for name in filenames:
            fp = Path(dirpath) / name
            if fp.is_symlink():
                continue
            try:
                if fp.is_file():
                    total += fp.stat().st_size
            except OSError:
                continue
    return total


def format_path_size(path: Path | str) -> str:
    path = Path(path)
    size = path_size_bytes(path)
    return f"{human_bytes(size)}\t{path}"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Human-readable size of a path.")
    parser.add_argument("path", help="file or directory to measure")
    parser.add_argument(
        "-b",
        "--bytes",
        action="store_true",
        help="print raw byte count only",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help='print {"path","bytes","human"} JSON',
    )
    args = parser.parse_args(argv)

    try:
        path = Path(args.path)
        size = path_size_bytes(path)
    except OSError as exc:
        print(f"file-size: {exc}", file=sys.stderr)
        return 2

    if args.json:
        print(
            json.dumps(
                {"path": str(path), "bytes": size, "human": human_bytes(size)},
                ensure_ascii=False,
            )
        )
    elif args.bytes:
        print(size)
    else:
        print(format_path_size(path))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
