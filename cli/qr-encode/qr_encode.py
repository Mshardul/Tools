#!/usr/bin/env python3
"""Encode text as a QR code (ASCII terminal art or PNG)."""

from __future__ import annotations

import argparse
import sys
from io import StringIO
from pathlib import Path
from typing import TextIO

import qrcode


def ascii_qr(text: str) -> str:
    """Return terminal ASCII art for *text* (no display / TTY required)."""
    if not text or not text.strip():
        raise ValueError("empty text")
    qr = qrcode.QRCode()
    qr.add_data(text)
    qr.make(fit=True)
    buf = StringIO()
    qr.print_ascii(out=buf)
    return buf.getvalue()


def write_png(text: str, path: Path | str) -> None:
    """Write a PNG QR code for *text* to *path* (requires pillow)."""
    if not text or not text.strip():
        raise ValueError("empty text")
    img = qrcode.make(text)
    img.save(str(path))


def resolve_text(arg: str | None, stdin: TextIO | None = None) -> str:
    """Resolve CLI text from argv or stdin (`-` / missing arg)."""
    stream = stdin if stdin is not None else sys.stdin
    if arg is None or arg == "-":
        data = stream.read()
        if not data or not data.strip():
            raise ValueError("empty text")
        return data.rstrip("\n")
    if not arg.strip():
        raise ValueError("empty text")
    return arg


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Encode text as a QR code (ASCII or PNG).",
    )
    parser.add_argument(
        "text",
        nargs="?",
        help="text to encode (use - or omit to read stdin)",
    )
    parser.add_argument(
        "-a",
        "--ascii",
        action="store_true",
        help="print ASCII QR to stdout (default when -o is omitted)",
    )
    parser.add_argument(
        "-o",
        "--output",
        metavar="PATH.png",
        help="write PNG to PATH (requires pillow via qrcode[pil])",
    )
    args = parser.parse_args(argv)

    try:
        text = resolve_text(args.text)
        if args.output:
            write_png(text, args.output)
        else:
            # Default and --ascii: terminal-friendly ASCII (no file required).
            print(ascii_qr(text), end="")
    except ValueError as exc:
        print(f"qr-encode: {exc}", file=sys.stderr)
        return 2
    except OSError as exc:
        print(f"qr-encode: {exc}", file=sys.stderr)
        return 2
    except ImportError as exc:
        # pillow missing when saving PNG
        print(f"qr-encode: {exc}", file=sys.stderr)
        return 2

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
