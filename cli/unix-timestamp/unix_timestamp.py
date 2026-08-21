#!/usr/bin/env python3
"""Convert between unix timestamps and human-readable dates."""

from __future__ import annotations

import argparse
import sys
from datetime import datetime, timezone


def from_unix(ts: int | float) -> str:
    return datetime.fromtimestamp(float(ts), tz=timezone.utc).isoformat()


def to_unix(text: str) -> int:
    raw = text.strip()
    if not raw:
        raise ValueError("empty date string")
    # Accept trailing Z
    if raw.endswith("Z"):
        raw = raw[:-1] + "+00:00"
    try:
        dt = datetime.fromisoformat(raw)
    except ValueError as exc:
        raise ValueError(f"invalid date: {text!r}") from exc
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return int(dt.timestamp())


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Convert between unix time and ISO-8601 dates (UTC)."
    )
    parser.add_argument(
        "-m",
        "--mode",
        choices=("from-unix", "to-unix", "auto"),
        default="auto",
        help="conversion direction (default: auto)",
    )
    parser.add_argument(
        "value",
        nargs="?",
        help="timestamp or date string (default: stdin)",
    )
    args = parser.parse_args(argv)

    value = args.value if args.value is not None else sys.stdin.read()
    value = value.strip()
    if not value:
        print("unix-timestamp: no input (pass a value or pipe stdin)", file=sys.stderr)
        return 2

    mode = args.mode
    if mode == "auto":
        try:
            float(value)
            mode = "from-unix"
        except ValueError:
            mode = "to-unix"

    try:
        if mode == "from-unix":
            print(from_unix(float(value)))
        else:
            print(to_unix(value))
    except ValueError as exc:
        print(f"unix-timestamp: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
