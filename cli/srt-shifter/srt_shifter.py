#!/usr/bin/env python3
"""Shift SRT / WebVTT subtitle timings by milliseconds."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

# HH:MM:SS,mmm or HH:MM:SS.mmm, and short MM:SS.mmm / MM:SS,mmm
_TIME_RE = re.compile(r"(?:(\d{2,}):)?(\d{2}):(\d{2})([.,])(\d{3})")
_ARROW_RE = re.compile(r"\s*-->\s*")


def _parse_time(match: re.Match[str]) -> int:
    hours = int(match.group(1) or 0)
    minutes = int(match.group(2))
    seconds = int(match.group(3))
    millis = int(match.group(5))
    return ((hours * 60 + minutes) * 60 + seconds) * 1000 + millis


def _format_time(total_ms: int, sep: str, *, short: bool) -> str:
    if total_ms < 0:
        total_ms = 0
    hours, rem = divmod(total_ms, 3_600_000)
    minutes, rem = divmod(rem, 60_000)
    seconds, millis = divmod(rem, 1000)
    if short and hours == 0:
        return f"{minutes:02d}:{seconds:02d}{sep}{millis:03d}"
    return f"{hours:02d}:{minutes:02d}:{seconds:02d}{sep}{millis:03d}"


def _shift_timestamp_line(line: str, offset_ms: int, fmt: str) -> str:
    if "-->" not in line:
        return line

    parts = _ARROW_RE.split(line, maxsplit=1)
    if len(parts) != 2:
        return line

    left, right = parts
    # Right may have cue settings after the end timestamp (VTT).
    end_match = _TIME_RE.match(right.lstrip())
    start_match = _TIME_RE.search(left)
    if not start_match or not end_match:
        return line

    # Detect short form from original start (no hours group).
    start_short = start_match.group(1) is None
    end_short = end_match.group(1) is None
    sep = "," if fmt == "srt" else "."

    start_ms = max(0, _parse_time(start_match) + offset_ms)
    end_ms = max(0, _parse_time(end_match) + offset_ms)

    prefix = left[: start_match.start()]
    # Preserve anything after the end timestamp (settings / trailing text).
    end_span_start = right.find(end_match.group(0))
    suffix = right[end_span_start + len(end_match.group(0)) :]

    new_start = _format_time(start_ms, sep, short=start_short and fmt == "vtt")
    new_end = _format_time(end_ms, sep, short=end_short and fmt == "vtt")
    return f"{prefix}{new_start} --> {new_end}{suffix}"


def detect_format(path: str | Path, text: str) -> str:
    """Detect subtitle format from path extension or content."""
    suffix = Path(path).suffix.lower()
    if suffix == ".srt":
        return "srt"
    if suffix == ".vtt":
        return "vtt"
    stripped = text.lstrip("\ufeff").lstrip()
    if stripped.upper().startswith("WEBVTT"):
        return "vtt"
    if re.search(r"\d{2}:\d{2}:\d{2},\d{3}\s*-->", text):
        return "srt"
    if re.search(r"(?:\d{2}:)?\d{2}:\d{2}\.\d{3}\s*-->", text):
        return "vtt"
    raise ValueError("cannot detect format (use a .srt/.vtt path or WEBVTT content)")


def shift_text(text: str, offset_ms: int, fmt: str) -> str:
    """Shift all cue timestamps in *text* by *offset_ms*. fmt is 'srt' or 'vtt'."""
    fmt = fmt.lower().strip()
    if fmt not in ("srt", "vtt"):
        raise ValueError(f"unknown format: {fmt!r} (use srt or vtt)")

    lines = text.splitlines(keepends=True)
    out: list[str] = []
    for line in lines:
        # Split keepends so we can rewrite the body without the newline.
        if line.endswith("\r\n"):
            body, nl = line[:-2], "\r\n"
        elif line.endswith("\n"):
            body, nl = line[:-1], "\n"
        elif line.endswith("\r"):
            body, nl = line[:-1], "\r"
        else:
            body, nl = line, ""
        if "-->" in body:
            body = _shift_timestamp_line(body, offset_ms, fmt)
        out.append(body + nl)
    return "".join(out)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Shift SRT or WebVTT timings by milliseconds.",
    )
    parser.add_argument("path", help="subtitle file (.srt or .vtt)")
    parser.add_argument(
        "--by",
        type=int,
        required=True,
        metavar="MS",
        help="offset in milliseconds (positive or negative)",
    )
    parser.add_argument(
        "-o",
        "--output",
        metavar="OUT",
        help="write result to OUT (default: overwrite PATH; use - for stdout)",
    )
    args = parser.parse_args(argv)

    path = Path(args.path)
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        print(f"srt-shifter: could not read {args.path!r}: {exc}", file=sys.stderr)
        return 2

    try:
        fmt = detect_format(path, text)
        out = shift_text(text, args.by, fmt)
    except ValueError as exc:
        print(f"srt-shifter: {exc}", file=sys.stderr)
        return 2

    if args.output == "-":
        sys.stdout.write(out)
        return 0

    dest = Path(args.output) if args.output else path
    try:
        dest.write_text(out, encoding="utf-8", newline="")
    except OSError as exc:
        print(f"srt-shifter: could not write {str(dest)!r}: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
