#!/usr/bin/env python3
"""Convert identifier case (camel / snake / kebab / Pascal)."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys


def _split_words(text: str) -> list[str]:
    text = text.strip()
    if not text:
        return []
    # Replace separators with space, then split CamelCase / PascalCase
    text = re.sub(r"[_\-\s]+", " ", text)
    text = re.sub(r"([a-z0-9])([A-Z])", r"\1 \2", text)
    text = re.sub(r"([A-Z]+)([A-Z][a-z])", r"\1 \2", text)
    return [w.lower() for w in text.split() if w]


def transform_case(text: str, target: str) -> str:
    words = _split_words(text)
    if not words:
        return ""
    target = target.lower()
    if target == "snake":
        return "_".join(words)
    if target == "kebab":
        return "-".join(words)
    if target == "camel":
        return words[0] + "".join(w.capitalize() for w in words[1:])
    if target == "pascal":
        return "".join(w.capitalize() for w in words)
    raise ValueError(f"unknown target case: {target!r} (use camel, snake, kebab, pascal)")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Convert text among camel, snake, kebab, and Pascal case."
    )
    parser.add_argument(
        "-t",
        "--to",
        choices=("camel", "snake", "kebab", "pascal"),
        required=True,
        help="target case",
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
    if args.text is None and text.endswith("\n"):
        text = text[:-1]
    if text == "":
        print("case-transform: no input (pass a string or pipe stdin)", file=sys.stderr)
        return 2

    try:
        out = transform_case(text, args.to)
    except ValueError as exc:
        print(f"case-transform: {exc}", file=sys.stderr)
        return 2

    print(out)
    if args.copy:
        try:
            subprocess.run(["pbcopy"], input=out.encode("utf-8"), check=True)
        except (FileNotFoundError, subprocess.CalledProcessError) as exc:
            print(f"case-transform: could not copy to clipboard: {exc}", file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
