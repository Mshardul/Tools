#!/usr/bin/env python3
"""Encode or decode Base64."""

from __future__ import annotations

import argparse
import base64
import subprocess
import sys


def b64_encode(data: bytes) -> str:
    return base64.b64encode(data).decode("ascii")


def b64_decode(text: str) -> bytes:
    try:
        return base64.b64decode(text.strip(), validate=True)
    except Exception as exc:
        raise ValueError(f"invalid base64: {exc}") from exc


def _read_input(text: str | None) -> bytes:
    if text is not None:
        return text.encode("utf-8")
    data = sys.stdin.buffer.read()
    if not data:
        raise ValueError("no input (pass a string or pipe stdin)")
    return data


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Encode or decode Base64.")
    parser.add_argument(
        "-m",
        "--mode",
        choices=("encode", "decode"),
        default="encode",
        help="encode or decode (default: encode)",
    )
    parser.add_argument(
        "text",
        nargs="?",
        help="input text (default: stdin)",
    )
    parser.add_argument(
        "-c",
        "--copy",
        action="store_true",
        help="copy result to the clipboard (macOS pbcopy)",
    )
    args = parser.parse_args(argv)

    try:
        if args.mode == "encode":
            raw = _read_input(args.text)
            out = b64_encode(raw)
            print(out)
        else:
            if args.text is not None:
                encoded = args.text
            else:
                encoded = sys.stdin.read()
            if not encoded.strip():
                raise ValueError("no input (pass a string or pipe stdin)")
            decoded = b64_decode(encoded)
            sys.stdout.buffer.write(decoded)
            if not decoded.endswith(b"\n") and sys.stdout.isatty():
                sys.stdout.buffer.write(b"\n")
            out = decoded.decode("utf-8", errors="replace")
    except ValueError as exc:
        print(f"base64-tool: {exc}", file=sys.stderr)
        return 2

    if args.copy:
        try:
            subprocess.run(["pbcopy"], input=out.encode("utf-8"), check=True)
        except (FileNotFoundError, subprocess.CalledProcessError) as exc:
            print(f"base64-tool: could not copy to clipboard: {exc}", file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
