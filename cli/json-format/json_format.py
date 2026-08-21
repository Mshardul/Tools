#!/usr/bin/env python3
"""Pretty-print or minify JSON."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def format_json(text: str, mode: str = "pretty") -> str:
    try:
        data = json.loads(text)
    except json.JSONDecodeError as exc:
        raise ValueError(f"invalid JSON: {exc}") from exc
    if mode == "pretty":
        return json.dumps(data, indent=2, ensure_ascii=False) + "\n"
    if mode == "minify":
        return json.dumps(data, separators=(",", ":"), ensure_ascii=False)
    raise ValueError(f"unknown mode: {mode!r}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Pretty-print or minify JSON.")
    parser.add_argument(
        "-m",
        "--mode",
        choices=("pretty", "minify"),
        default="pretty",
        help="pretty or minify (default: pretty)",
    )
    parser.add_argument(
        "path",
        nargs="?",
        help="JSON file (default: stdin)",
    )
    args = parser.parse_args(argv)

    try:
        if args.path is not None:
            text = Path(args.path).read_text(encoding="utf-8")
        else:
            text = sys.stdin.read()
        if not text.strip():
            raise ValueError("no input (pass a file or pipe stdin)")
        out = format_json(text, mode=args.mode)
    except (OSError, ValueError) as exc:
        print(f"json-format: {exc}", file=sys.stderr)
        return 2

    if args.mode == "minify":
        print(out)
    else:
        sys.stdout.write(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
