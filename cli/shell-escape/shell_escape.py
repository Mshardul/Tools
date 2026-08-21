#!/usr/bin/env python3
"""Escape a string for safe shell use."""

from __future__ import annotations

import argparse
import shlex
import subprocess
import sys


def escape(text: str) -> str:
    return shlex.quote(text)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Escape a string for safe shell use.")
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
        print("shell-escape: no input (pass a string or pipe stdin)", file=sys.stderr)
        return 2

    if args.text is None and text.endswith("\n"):
        text = text[:-1]

    out = escape(text)
    print(out)

    if args.copy:
        try:
            subprocess.run(["pbcopy"], input=out.encode("utf-8"), check=True)
        except (FileNotFoundError, subprocess.CalledProcessError) as exc:
            print(f"shell-escape: could not copy to clipboard: {exc}", file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
