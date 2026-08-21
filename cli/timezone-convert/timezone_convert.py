#!/usr/bin/env python3
"""Convert a datetime across IANA timezones."""

from __future__ import annotations

import argparse
import subprocess
import sys
from datetime import datetime
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError


def parse_datetime(value: str) -> datetime:
    text = value.strip()
    if text.lower() == "now":
        return datetime.now(tz=ZoneInfo("UTC")).replace(tzinfo=None)
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        dt = datetime.fromisoformat(text)
    except ValueError:
        pass
    else:
        return dt
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M"):
        try:
            return datetime.strptime(text, fmt)
        except ValueError:
            continue
    raise ValueError(f"invalid datetime: {value!r}")


def _zone(name: str) -> ZoneInfo:
    try:
        return ZoneInfo(name)
    except ZoneInfoNotFoundError as exc:
        raise ValueError(f"unknown timezone: {name!r}") from exc


def convert_timezone(value: str, *, from_tz: str, to_tz: str) -> str:
    text = value.strip()
    if text.lower() == "now":
        dt = datetime.now(_zone(from_tz))
    else:
        dt = parse_datetime(text)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=_zone(from_tz))
    target = _zone(to_tz)
    return dt.astimezone(target).isoformat(timespec="seconds")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Convert a time across IANA timezones.")
    parser.add_argument(
        "--from",
        dest="from_tz",
        default="UTC",
        help="source timezone for naive datetimes (default: UTC)",
    )
    parser.add_argument(
        "--to",
        dest="to_tz",
        required=True,
        help="target timezone (IANA name)",
    )
    parser.add_argument("value", nargs="?", help="datetime or 'now' (default: stdin)")
    parser.add_argument(
        "-c",
        "--copy",
        action="store_true",
        help="copy result to the clipboard (macOS pbcopy)",
    )
    args = parser.parse_args(argv)

    value = args.value if args.value is not None else sys.stdin.read()
    if args.value is None and value.endswith("\n"):
        value = value[:-1]
    if value.strip() == "":
        print("timezone-convert: no input (pass a datetime or pipe stdin)", file=sys.stderr)
        return 2

    try:
        out = convert_timezone(value, from_tz=args.from_tz, to_tz=args.to_tz)
    except ValueError as exc:
        print(f"timezone-convert: {exc}", file=sys.stderr)
        return 2

    print(out)
    if args.copy:
        try:
            subprocess.run(["pbcopy"], input=out.encode("utf-8"), check=True)
        except (FileNotFoundError, subprocess.CalledProcessError) as exc:
            print(f"timezone-convert: could not copy to clipboard: {exc}", file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
