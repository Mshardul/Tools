#!/usr/bin/env python3
"""Generate a random password."""

from __future__ import annotations

import argparse
import secrets
import string
import subprocess
import sys

DEFAULT_SYMBOLS = "!@#$%^&*()-_=+[]{}:,.?/"


def generate_password(
    length: int = 20,
    *,
    letters: bool = True,
    digits: bool = True,
    symbols: bool = True,
) -> str:
    if length < 1:
        raise ValueError("length must be >= 1")
    alphabet = ""
    if letters:
        alphabet += string.ascii_letters
    if digits:
        alphabet += string.digits
    if symbols:
        alphabet += DEFAULT_SYMBOLS
    if not alphabet:
        raise ValueError("at least one of letters/digits/symbols must be enabled")
    return "".join(secrets.choice(alphabet) for _ in range(length))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Generate a random password.")
    parser.add_argument("-l", "--length", type=int, default=20, help="password length (default: 20)")
    parser.add_argument("--no-letters", action="store_true", help="exclude letters")
    parser.add_argument("--no-digits", action="store_true", help="exclude digits")
    parser.add_argument("--no-symbols", action="store_true", help="exclude symbols")
    parser.add_argument(
        "-c",
        "--copy",
        action="store_true",
        help="copy password to the clipboard (macOS pbcopy)",
    )
    args = parser.parse_args(argv)

    try:
        password = generate_password(
            length=args.length,
            letters=not args.no_letters,
            digits=not args.no_digits,
            symbols=not args.no_symbols,
        )
    except ValueError as exc:
        print(f"password-gen: {exc}", file=sys.stderr)
        return 2

    print(password)
    if args.copy:
        try:
            subprocess.run(["pbcopy"], input=password.encode(), check=True)
        except (FileNotFoundError, subprocess.CalledProcessError) as exc:
            print(f"password-gen: could not copy to clipboard: {exc}", file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
