#!/usr/bin/env python3
"""Generate ids (uuid, nanoid)."""

from __future__ import annotations

import argparse
import secrets
import sys
import uuid

NANOID_ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz-"
DEFAULT_NANOID_LENGTH = 21


def generate_id(kind: str, length: int = DEFAULT_NANOID_LENGTH) -> str:
    kind = kind.lower()
    if kind == "uuid":
        return str(uuid.uuid4())
    if kind == "nanoid":
        if length < 1:
            raise ValueError("nanoid length must be >= 1")
        return "".join(secrets.choice(NANOID_ALPHABET) for _ in range(length))
    raise ValueError(f"unknown id type: {kind!r} (use uuid or nanoid)")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Generate an id (uuid or nanoid).")
    parser.add_argument(
        "-t",
        "--type",
        choices=("uuid", "nanoid"),
        default="uuid",
        help="id type (default: uuid)",
    )
    parser.add_argument(
        "-n",
        "--count",
        type=int,
        default=1,
        help="how many ids to print (default: 1)",
    )
    parser.add_argument(
        "-l",
        "--length",
        type=int,
        default=DEFAULT_NANOID_LENGTH,
        help=f"nanoid length (default: {DEFAULT_NANOID_LENGTH})",
    )
    parser.add_argument(
        "-c",
        "--copy",
        action="store_true",
        help="copy the last id to the clipboard (macOS pbcopy)",
    )
    args = parser.parse_args(argv)

    if args.count < 1:
        parser.error("--count must be >= 1")

    values = [generate_id(args.type, length=args.length) for _ in range(args.count)]
    for value in values:
        print(value)

    if args.copy:
        text = values[-1]
        try:
            import subprocess

            subprocess.run(["pbcopy"], input=text.encode(), check=True)
        except (FileNotFoundError, subprocess.CalledProcessError) as exc:
            print(f"id-gen: could not copy to clipboard: {exc}", file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
