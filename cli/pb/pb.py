#!/usr/bin/env python3
"""Read or write the macOS clipboard."""

from __future__ import annotations

import argparse
import subprocess
import sys


def clipboard_read() -> str:
    result = subprocess.run(["pbpaste"], check=True, capture_output=True)
    return result.stdout.decode()


def clipboard_write(text: str) -> None:
    subprocess.run(["pbcopy"], input=text.encode(), check=True)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Read or write the macOS clipboard (pbpaste / pbcopy)."
    )
    parser.add_argument(
        "-r",
        "--read",
        action="store_true",
        help="print clipboard contents",
    )
    parser.add_argument(
        "-w",
        "--write",
        metavar="TEXT",
        nargs="?",
        const=None,
        default=argparse.SUPPRESS,
        help="write TEXT, or stdin when TEXT is omitted",
    )
    args = parser.parse_args(argv)

    writing = hasattr(args, "write")
    try:
        if writing:
            if args.write is not None:
                text = args.write
            else:
                text = sys.stdin.read()
            clipboard_write(text)
            return 0

        if args.read or sys.stdin.isatty():
            sys.stdout.write(clipboard_read())
            return 0

        # Piped input without -w: treat as write
        clipboard_write(sys.stdin.read())
        return 0
    except FileNotFoundError:
        print("pb: pbcopy/pbpaste not found (macOS only)", file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as exc:
        print(f"pb: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
