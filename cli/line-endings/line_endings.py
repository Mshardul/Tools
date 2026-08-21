#!/usr/bin/env python3
"""Convert CRLF and LF line endings in text."""

from __future__ import annotations

import argparse
import sys


def detect_endings(text: str) -> str:
    if "\n" not in text and "\r" not in text:
        return "none"
    has_lf = False
    has_crlf = False
    i = 0
    while i < len(text):
        if text[i] == "\r" and i + 1 < len(text) and text[i + 1] == "\n":
            has_crlf = True
            i += 2
            continue
        if text[i] == "\n":
            has_lf = True
        elif text[i] == "\r":
            has_lf = True
        i += 1
    if has_lf and has_crlf:
        return "mixed"
    if has_crlf:
        return "crlf"
    if has_lf:
        return "lf"
    return "none"


def convert_endings(text: str, mode: str) -> str:
    if mode == "check":
        return text
    if mode == "to-lf":
        text = text.replace("\r\n", "\n")
        return text.replace("\r", "\n")
    if mode == "to-crlf":
        text = text.replace("\r\n", "\n")
        text = text.replace("\r", "\n")
        return text.replace("\n", "\r\n")
    raise ValueError(f"unknown mode: {mode!r} (use to-lf, to-crlf, check)")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Convert CRLF and LF line endings.")
    parser.add_argument(
        "-m",
        "--mode",
        choices=("to-lf", "to-crlf", "check"),
        default="to-lf",
        help="conversion mode (default: to-lf)",
    )
    parser.add_argument("path", nargs="?", help="file path (default: stdin/stdout)")
    parser.add_argument(
        "--stdout",
        action="store_true",
        help="print converted output instead of writing in place",
    )
    args = parser.parse_args(argv)

    if args.path is None:
        text = sys.stdin.read()
        if args.mode == "check":
            print(detect_endings(text))
            return 0
        out = convert_endings(text, args.mode)
        sys.stdout.write(out)
        return 0

    try:
        with open(args.path, encoding="utf-8") as fh:
            text = fh.read()
    except OSError as exc:
        print(f"line-endings: could not read {args.path!r}: {exc}", file=sys.stderr)
        return 2

    if args.mode == "check":
        print(detect_endings(text))
        return 0

    out = convert_endings(text, args.mode)
    if args.stdout:
        sys.stdout.write(out)
        return 0

    try:
        with open(args.path, "w", encoding="utf-8", newline="") as fh:
            fh.write(out)
    except OSError as exc:
        print(f"line-endings: could not write {args.path!r}: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
