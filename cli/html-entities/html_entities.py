#!/usr/bin/env python3
"""Encode or decode HTML entities."""

from __future__ import annotations

import argparse
import html
import subprocess
import sys


def encode_entities(text: str) -> str:
    return html.escape(text, quote=True)


def decode_entities(text: str) -> str:
    return html.unescape(text)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Encode or decode HTML entities.")
    parser.add_argument(
        "-m",
        "--mode",
        choices=("encode", "decode"),
        default="encode",
        help="encode or decode (default: encode)",
    )
    parser.add_argument("text", nargs="?", help="input text (default: stdin)")
    parser.add_argument(
        "-c",
        "--copy",
        action="store_true",
        help="copy result to the clipboard (macOS pbcopy)",
    )
    args = parser.parse_args(argv)

    text = args.text if args.text is not None else sys.stdin.read()
    if text == "":
        print("html-entities: no input (pass a string or pipe stdin)", file=sys.stderr)
        return 2

    if args.text is None and text.endswith("\n"):
        text = text[:-1]

    out = encode_entities(text) if args.mode == "encode" else decode_entities(text)
    print(out)

    if args.copy:
        try:
            subprocess.run(["pbcopy"], input=out.encode("utf-8"), check=True)
        except (FileNotFoundError, subprocess.CalledProcessError) as exc:
            print(f"html-entities: could not copy to clipboard: {exc}", file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
