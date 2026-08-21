#!/usr/bin/env python3
"""Sort, dedupe, or reverse lines from stdin or a file."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


def process_lines(
    lines: list[str], *, unique: bool = False, reverse: bool = False
) -> list[str]:
    if unique:
        result = sorted(set(lines))
    else:
        result = sorted(lines)
    if reverse:
        result = list(reversed(result))
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Sort, dedupe, or reverse lines from stdin or a file."
    )
    parser.add_argument("file", nargs="?", help="input file (default: stdin)")
    parser.add_argument(
        "-u",
        "--unique",
        action="store_true",
        help="keep sorted unique lines only",
    )
    parser.add_argument(
        "-r",
        "--reverse",
        action="store_true",
        help="reverse the final line order",
    )
    args = parser.parse_args(argv)

    if args.file is not None:
        path = Path(args.file)
        if not path.is_file():
            print(f"line-sort: not a file: {args.file}", file=sys.stderr)
            return 2
        text = path.read_text(encoding="utf-8")
    else:
        if sys.stdin.isatty():
            print("line-sort: no input (pass a file or pipe stdin)", file=sys.stderr)
            return 2
        text = sys.stdin.read()

    lines = text.splitlines()
    result = process_lines(lines, unique=args.unique, reverse=args.reverse)
    sys.stdout.write("\n".join(result))
    if result or text.endswith("\n"):
        sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
