#!/usr/bin/env python3
"""Turn a title into a kebab-case slug."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import unicodedata


def slugify(text: str) -> str:
    text = unicodedata.normalize("NFKD", text)
    text = text.encode("ascii", "ignore").decode("ascii")
    text = text.lower()
    text = re.sub(r"[^a-z0-9]+", "-", text)
    return text.strip("-")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Turn a title into a kebab-case slug.")
    parser.add_argument("text", nargs="?", help="input title (default: stdin)")
    parser.add_argument(
        "-c",
        "--copy",
        action="store_true",
        help="copy result to the clipboard (macOS pbcopy)",
    )
    args = parser.parse_args(argv)

    text = args.text if args.text is not None else sys.stdin.read()
    if args.text is None and text.endswith("\n"):
        text = text[:-1]
    if text == "":
        print("slugify: no input (pass a string or pipe stdin)", file=sys.stderr)
        return 2

    out = slugify(text)
    print(out)
    if args.copy:
        try:
            subprocess.run(["pbcopy"], input=out.encode("utf-8"), check=True)
        except (FileNotFoundError, subprocess.CalledProcessError) as exc:
            print(f"slugify: could not copy to clipboard: {exc}", file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
