#!/usr/bin/env python3
"""Hash a file or string (SHA-256 and friends)."""

from __future__ import annotations

import argparse
import hashlib
import subprocess
import sys
from pathlib import Path

ALGORITHMS = ("md5", "sha1", "sha256", "sha512")


def hash_bytes(data: bytes, algorithm: str) -> str:
    algo = algorithm.lower()
    if algo not in ALGORITHMS:
        raise ValueError(f"unknown algorithm: {algorithm!r} (use {', '.join(ALGORITHMS)})")
    return hashlib.new(algo, data).hexdigest()


def hash_file(path: Path | str, algorithm: str) -> str:
    path = Path(path)
    algo = algorithm.lower()
    if algo not in ALGORITHMS:
        raise ValueError(f"unknown algorithm: {algorithm!r} (use {', '.join(ALGORITHMS)})")
    h = hashlib.new(algo)
    with path.open("rb") as fh:
        while True:
            chunk = fh.read(1024 * 1024)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="SHA-256 (and friends) of a file or string.")
    parser.add_argument(
        "-a",
        "--algorithm",
        choices=ALGORITHMS,
        default="sha256",
        help="hash algorithm (default: sha256)",
    )
    parser.add_argument(
        "-s",
        "--string",
        help="hash this string instead of a file",
    )
    parser.add_argument(
        "path",
        nargs="?",
        help="file to hash (or omit with --string / stdin)",
    )
    parser.add_argument(
        "-c",
        "--copy",
        action="store_true",
        help="copy digest to the clipboard (macOS pbcopy)",
    )
    args = parser.parse_args(argv)

    try:
        if args.string is not None:
            digest = hash_bytes(args.string.encode("utf-8"), args.algorithm)
        elif args.path is not None:
            digest = hash_file(args.path, args.algorithm)
        else:
            data = sys.stdin.buffer.read()
            if not data:
                raise ValueError("no input (pass a path, --string, or pipe stdin)")
            digest = hash_bytes(data, args.algorithm)
    except (OSError, ValueError) as exc:
        print(f"file-hash: {exc}", file=sys.stderr)
        return 2

    print(digest)
    if args.copy:
        try:
            subprocess.run(["pbcopy"], input=digest.encode("utf-8"), check=True)
        except (FileNotFoundError, subprocess.CalledProcessError) as exc:
            print(f"file-hash: could not copy to clipboard: {exc}", file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
