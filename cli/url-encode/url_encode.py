#!/usr/bin/env python3
"""Percent-encode or decode a string."""

from __future__ import annotations

import argparse
import subprocess
import sys
from urllib.parse import quote, unquote


def url_encode(text: str) -> str:
    return quote(text, safe="")


def url_decode(text: str) -> str:
    return unquote(text.replace("+", " "))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Percent-encode or decode a string.")
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
        print("url-encode: no input (pass a string or pipe stdin)", file=sys.stderr)
        return 2

    # Drop a single trailing newline from stdin so piping feels natural
    if args.text is None and text.endswith("\n"):
        text = text[:-1]

    out = url_encode(text) if args.mode == "encode" else url_decode(text)
    print(out)

    if args.copy:
        try:
            subprocess.run(["pbcopy"], input=out.encode("utf-8"), check=True)
        except (FileNotFoundError, subprocess.CalledProcessError) as exc:
            print(f"url-encode: could not copy to clipboard: {exc}", file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
