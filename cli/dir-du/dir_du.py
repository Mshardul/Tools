#!/usr/bin/env python3
"""Disk usage summary for immediate children of a directory."""

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


def _tree_size_bytes(path: Path) -> int:
    """Size of a file, or recursive sum under a directory (no symlink follow)."""
    if path.is_symlink():
        # Do not follow: directory symlinks contribute 0; file symlinks skipped.
        return 0
    if path.is_file():
        return path.stat().st_size
    if not path.is_dir():
        return 0

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


def dir_usage(path: Path | str) -> list[tuple[str, int]]:
    path = Path(path)
    if not path.is_dir():
        raise NotADirectoryError(f"Not a directory: {path}")

    rows: list[tuple[str, int]] = []
    for child in path.iterdir():
        rows.append((child.name, _tree_size_bytes(child)))
    rows.sort(key=lambda item: (-item[1], item[0]))
    return rows


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Disk usage of immediate children of a directory."
    )
    parser.add_argument(
        "dir",
        nargs="?",
        default=".",
        help="directory to summarize (default: .)",
    )
    parser.add_argument(
        "-n",
        "--max",
        type=int,
        default=None,
        metavar="N",
        help="limit number of child rows shown",
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
        help="print JSON summary",
    )
    args = parser.parse_args(argv)

    try:
        root = Path(args.dir)
        rows = dir_usage(root)
    except OSError as exc:
        print(f"dir-du: {exc}", file=sys.stderr)
        return 2

    total = sum(size for _, size in rows)
    display = rows if args.max is None else rows[: max(0, args.max)]

    if args.json:
        payload = {
            "path": str(root),
            "entries": [
                {"name": name, "bytes": size, "human": human_bytes(size)}
                for name, size in display
            ],
            "total": {"bytes": total, "human": human_bytes(total)},
        }
        print(json.dumps(payload, ensure_ascii=False))
        return 0

    for name, size in display:
        shown = str(size) if args.bytes else human_bytes(size)
        print(f"{shown}\t{name}")
    total_shown = str(total) if args.bytes else human_bytes(total)
    print(f"{total_shown}\tTOTAL")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
